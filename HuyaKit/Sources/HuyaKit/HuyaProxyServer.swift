//
//  HuyaProxyServer.swift
//  IINA+
//
//  Huya .slice proxy - FLV stream relay + ts dedup
//
//  URL route: GET /huya/{roomId}.flv -> stream proxy for that room
//

import Foundation

import NIOCore
import NIOHTTP1

import Alamofire

// MARK: - HuyaProxyServer

/// Huya .slice proxy server, called from HTTPHandler on the
/// `/huya/{roomId}.flv` route via `handleHuyaRequest(outbound:)`
public actor HuyaProxyServer {
    public static let shared = HuyaProxyServer()

    private var streamInfoCache: [String: (HuyaStream, Date)] = [:]
    private var codecCache: [String: (codecType: Int, displayName: String, isH265: Bool)] = [:]
    /// Sniffed first-slice tags per requested codecType（参数集不常变，短期复用省一次首片下载）；
    /// 连同嗅探**修正后**的 codecType 一起存，命中时一并返回，避免 tags 与拉流档位不一致
    private var firstTagsByCodec: [String: (codecType: Int, isH265: Bool, tags: [HuyaFlvTag], date: Date)] = [:]
    private let firstTagsTTL: TimeInterval = 120

    // Unified registry for all huya background tasks (key -> HuyaTask)
    // - .prewarm:  key = uuid (= /huya/{uuid}.flv path token), background prefetch;
    //   playback starts immediately; handleHuyaRequest awaits task.value on hit
    // - .livePull:  key = sessionKey (room#uuid), the running streamLoop Task
    private var tasks: [String: HuyaTask] = [:]

    /// Cancel and clear all huya tasks
    public func cancelAll() {
        tasks.forEach { $0.value.cancel() }
        tasks.removeAll()
    }

    /// Active live pull session keys (diagnostics)
    public func activePulls() -> [String] {
        tasks.filter { _, entry in
            if case .livePull = entry { return true }
            return false
        }.keys.sorted()
    }

    /// (live pulls, prewarms) currently active (diagnostics)
    public func activeTaskCount() -> (livePulls: Int, prewarms: Int) {
        var livePulls = 0
        var prewarms = 0
        for (_, entry) in tasks {
            switch entry {
            case .livePull: livePulls += 1
            case .prewarm: prewarms += 1
            }
        }
        return (livePulls, prewarms)
    }

    private let cacheTTL: TimeInterval = 60
    /// Prewarm session TTL (2 min, matches slice signature wsTime ~110s validity)
    private let prewarmTTL: TimeInterval = 120

    private init() {}

    // MARK: - Caching

    func getStreamInfo(roomId: String, forceRefresh: Bool = false) async throws -> HuyaStream {
        if !forceRefresh, let (info, time) = streamInfoCache[roomId],
           Date().timeIntervalSince(time) < cacheTTL {
            return info
        }
        let info = try await HuyaStream.fetch(roomId: roomId)
        streamInfoCache[roomId] = (info, Date())
        // Invalidate caches tied to the old streamInfo
        codecCache = codecCache.filter { !$0.key.hasPrefix("\(roomId)#") }
        firstTagsByCodec = firstTagsByCodec.filter { !$0.key.hasPrefix("\(roomId)#") }
        return info
    }

    func getCodecType(roomId: String, rate: Int? = nil) async throws -> (codecType: Int, displayName: String, isH265: Bool) {
        // nil = auto, kept distinct from explicit 0 in the key
        let cacheKey = "\(roomId)#\(rate.map { String($0) } ?? "auto")"
        if let cached = codecCache[cacheKey] {
            return cached
        }
        let info = try await getStreamInfo(roomId: roomId)
        let result: (codecType: Int, displayName: String, isH265: Bool)
        if let rate {
            // 选档走官方口径的翻译（与冷路径 codecType(forRate:) 同源）
            let mapped = Self.codecType(forRate: rate, stream: info)
            guard mapped.codecType >= 0 else {
                throw HuyaError.parseError("rate=\(rate) has no third-party-decodable variant")
            }
            let displayName = info.playableStreamInfo.first {
                $0.iBitRate == rate
            }?.sDisplayName ?? "蓝光"
            result = (mapped.codecType, displayName, mapped.isH265)
        } else {
            // 自动档：以 API 档位列表为准取最高的一条可解档（不硬编码兜底）
            guard let best = HuyaUrl.selectBestCodecType(stream: info) else {
                throw HuyaError.parseError("room \(roomId): no playable gear in vMultiStreamInfo")
            }
            result = (best.codecType, best.displayName, best.codecFamily == HuyaOfficialCodec.familyH265)
        }
        codecCache[cacheKey] = result
        return result
    }

    /// 下载首片、嗅探实际编码族（hvcC vs avcC）并按需纠正 codecType；结果按
    /// `roomId#codecType` 缓存 120s（参数集不常变，重连/重复播放可跳过首片下载）
    func getFirstTagsVerified(
        roomId: String,
        codecType: Int,
        expectedIsH265: Bool
    ) async throws -> (codecType: Int, isH265: Bool, tags: [HuyaFlvTag]) {
        let cacheKey = "\(roomId)#\(codecType)"
        if let cached = firstTagsByCodec[cacheKey],
           Date().timeIntervalSince(cached.date) < firstTagsTTL {
            HuyaLogger.log("HuyaProxy:\(roomId) first-tags cache hit ct=\(codecType)→\(cached.codecType)", level: .debug)
            // 返回嗅探修正后的 codecType + 编码族，与缓存里的 tags 同源
            return (cached.codecType, cached.isH265, cached.tags)
        }

        let info = try await getStreamInfo(roomId: roomId)
        var current = codecType
        var currentIsH265 = expectedIsH265
        var tags: [HuyaFlvTag] = []

        for attempt in 0..<2 {
            let (url, _, _) = try HuyaUrl.buildSliceUrl(stream: info, codecType: current)
            do {
                // 自适应提前停止（见 downloadSlice）；1MB 是这里的兜底上限
                let data = try await Self.downloadSlice(url: url, maxSize: 1_000_000)
                tags = HuyaSliceDecoder.decode(sliceData: data)
            } catch {
                HuyaLogger.log("HuyaProxy:\(roomId) first-slice download failed: \(error)", level: .error)
                return (current, currentIsH265, [])
            }

            guard let actualIsH265 = Self.sniffIsH265(tags) else {
                // No seq header in the first slice, trust the marker
                HuyaLogger.log("HuyaProxy:\(roomId) no seq header in first slice, trust codecType=\(current)")
                break
            }
            HuyaLogger.log("HuyaProxy:\(roomId) sniffed \(actualIsH265 ? "H.265" : "H.264")"
                + " (codecType=\(current), expected \(expectedIsH265 ? "H.265" : "H.264"), "
                + "\(tags.count) tags)")

            if attempt == 0 && actualIsH265 != expectedIsH265 {
                // 只换编码族、不换档：反查该 codecType 对应的档位后换族重下；
                // 反查不到就保持原 codecType（宁可让上层报错，也不跨档兜底）
                guard let switched = Self.switchFamilyCodecType(
                    codecType: current,
                    actualIsH265: actualIsH265,
                    stream: info
                ) else {
                    HuyaLogger.log("HuyaProxy:\(roomId) codec mismatch but no same-gear "
                        + "\(actualIsH265 ? "H.265" : "H.264") variant, keeping codecType=\(current)",
                        level: .error)
                    break
                }
                HuyaLogger.log("HuyaProxy:\(roomId) codec mismatch, same-gear switch to "
                    + "\(actualIsH265 ? "H.265" : "H.264") codecType=\(switched)")
                current = switched
                currentIsH265 = actualIsH265
                continue
            }
            break
        }

        firstTagsByCodec = firstTagsByCodec.filter { _, entry in
            Date().timeIntervalSince(entry.date) < firstTagsTTL
        }
        firstTagsByCodec[cacheKey] = (current, currentIsH265, tags, Date())
        return (current, currentIsH265, tags)
    }

    /// 用户选择档位（`iBitRate`）→ slice URL 的 codecType + 是否 HEVC。
    ///
    /// 官方 `createStreamId`：`codecType = _getCodec(族, 该档自己的 iBitRate)`（族 2=H265 / 3=H264）。
    /// **族逐档判定**（`HuyaOfficialCodec.isH265Gear`），不可用房间顶层 `codecType` 覆盖。
    /// 档位来源恒为 `stream.playableStreamInfo`；不硬编码、不跨档兜底。
    ///
    /// 唯一偏离官方：官方能解 0 码率 HEVC 档（`getCodec(H265,0)` = 私有胶囊），我们解不了 →
    /// 退到**同名档**的 H.264 变体；没有就返回 -1 交上层报错。
    /// 细节与踩坑：MEMORY.md §3.3 / §4.2 / §5.1
    nonisolated static func codecType(
        forRate rate: Int,
        stream: HuyaStream
    ) -> (codecType: Int, isH265: Bool) {
        let gears = stream.playableStreamInfo
        guard let entry = gears.first(where: { $0.iBitRate == rate }) else {
            // 区分"API 里根本没这个档"与"有但被 HDR 策略丢掉了"，便于排查
            if stream.vMultiStreamInfo.contains(where: { $0.iBitRate == rate }) {
                HuyaLogger.log("HuyaProxy: rate=\(rate) 只存在于 HDR 档，已按策略丢弃", level: .error)
            } else {
                HuyaLogger.log("HuyaProxy: rate=\(rate) not found in vMultiStreamInfo", level: .error)
            }
            return (-1, false)
        }
        let isH265 = HuyaOfficialCodec.isH265Gear(
            iBitRate: entry.iBitRate,
            iCodecType: entry.iCodecType,
            iHEVCBitRate: entry.iHEVCBitRate,
            isHEVCSupport: stream.primaryStream?.iIsHEVCSupport ?? 0
        )
        let family = isH265 ? HuyaOfficialCodec.familyH265 : HuyaOfficialCodec.familyH264
        let ct = HuyaOfficialCodec.getCodec(codecFamily: family, bitrate: entry.iBitRate)
        guard ct == HuyaOfficialCodec.h265Capsule else {
            return (ct, isH265)
        }
        // 0 码率 HEVC 档 → 私有胶囊，第三方解码器拉不到可解流；退到同名档的 H.264 变体
        if let sameName = gears.first(where: {
            $0.sDisplayName == entry.sDisplayName && $0.iCodecType == 0
        }) {
            HuyaLogger.log("HuyaProxy: rate=\(rate) (\(entry.sDisplayName)) HEVC 变体为私有胶囊，"
                + "改用同名 H.264 档 iBitRate=\(sameName.iBitRate)", level: .debug)
            return (HuyaOfficialCodec.getCodec(codecFamily: HuyaOfficialCodec.familyH264, bitrate: sameName.iBitRate), false)
        }
        HuyaLogger.log("HuyaProxy: rate=\(rate) (\(entry.sDisplayName)) 无第三方可解变体", level: .error)
        return (-1, false)
    }

    /// Sniff the actual codec (hvcC vs avcC) from decoded first-slice tags
    ///
    /// seq tag layout: FLV tag header(11) + body
    /// - H.265: body[0]=0x90 (Enhanced FLV 4CC 'hvc1') or standard codecId=12
    /// - H.264: body[0]=0x17/0x27 (codecId=7)
    /// - nil when no seq header found
    nonisolated static func sniffIsH265(_ tags: [HuyaFlvTag]) -> Bool? {
        for tag in tags where tag.type == 9 && tag.isSeqHeader {
            guard tag.data.readableBytes >= 16 else { continue }
            let bytes = tag.data.readableBytesView
            let b0 = bytes[11]
            // Enhanced FLV 4CC 'hvc1'
            if (b0 & 0x80) != 0 && bytes[12] == 0x68 && bytes[13] == 0x76
                && bytes[14] == 0x63 && bytes[15] == 0x31 {
                return true
            }
            // standard FLV codecId: 12=HEVC, 7=AVC
            let codecId = b0 & 0x0F
            if codecId == 12 { return true }
            if codecId == 7 { return false }
        }
        return nil
    }

    /// 嗅探到实际编码族与预期不符时的纠错：只允许**换编码族、不换清晰度档**。
    ///
    /// 反查 codecType 属于哪一档的 iBitRate（getCodec 对固定族单射、两族区间不重叠 ⇒ 唯一），
    /// 再用同一 iBitRate 换族。反查不到或结果是私有胶囊 → nil，调用方保持原 codecType。
    /// 官方无此步（直接信任自己算出的 codecType）。
    nonisolated static func switchFamilyCodecType(
        codecType: Int,
        actualIsH265: Bool,
        stream: HuyaStream
    ) -> Int? {
        guard let gear = stream.playableStreamInfo.first(where: { v in
            HuyaOfficialCodec.getCodec(codecFamily: HuyaOfficialCodec.familyH265, bitrate: v.iBitRate) == codecType
                || HuyaOfficialCodec.getCodec(codecFamily: HuyaOfficialCodec.familyH264, bitrate: v.iBitRate) == codecType
        }) else { return nil }
        let family = actualIsH265 ? HuyaOfficialCodec.familyH265 : HuyaOfficialCodec.familyH264
        let switched = HuyaOfficialCodec.getCodec(codecFamily: family, bitrate: gear.iBitRate)
        return switched == HuyaOfficialCodec.h265Capsule ? nil : switched
    }

    // MARK: - Prewarm

    /// Non-blocking prewarm; handleHuyaRequest awaits the task on a
    /// /huya/{uuid}.flv hit.
    ///
    /// - Parameter uuid: caller-supplied session id (e.g. YouGetJSON.uuid),
    ///   must match the /huya/{uuid}.flv path token; defaults to a fresh UUID
    /// - Parameter rate: user-selected quality (vMultiStreamInfo iBitRate); nil = auto
    /// - Returns: session uuid (path token of /huya/{uuid}.flv)
    public func startPrewarm(uuid: String = UUID().uuidString, roomId: String, rate: Int? = nil) -> String {
        cleanupExpiredPrewarms()

        let task = Task { () throws -> HuyaPrewarmSession in
            let streamInfo = try await self.getStreamInfo(roomId: roomId)
            let codecResult = try await self.getCodecType(roomId: roomId, rate: rate)
            let verified = try await self.getFirstTagsVerified(
                roomId: roomId,
                codecType: codecResult.codecType,
                expectedIsH265: codecResult.isH265
            )
            return HuyaPrewarmSession(
                roomId: roomId,
                codecType: verified.codecType,
                isH265: verified.isH265,
                displayName: codecResult.displayName,
                streamInfo: streamInfo,
                firstTags: verified.tags,
                createdAt: Date()
            )
        }

        tasks[uuid] = .prewarm(task: task, createdAt: Date())
        HuyaLogger.log("HuyaProxy:prewarm room \(roomId) uuid=\(uuid.prefix(8))… (background)", level: .debug)
        return uuid
    }

    /// Drop prewarm tasks older than prewarmTTL (live pulls untouched)
    private func cleanupExpiredPrewarms() {
        let now = Date()
        if tasks.isEmpty { return }
        tasks = tasks.filter { _, entry in
            guard case let .prewarm(_, createdAt) = entry else { return true }
            return now.timeIntervalSince(createdAt) < prewarmTTL
        }
    }

    // MARK: - HTTP request handling

    /// Handle /huya/{token}.flv (called by HTTPHandler).
    /// token 先按 prewarm 会话 uuid 匹配（命中则跳过串行准备）；否则当 roomId 走冷路径
    public func handleHuyaRequest(
        roomId: String,
        outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>,
        rate: Int? = nil
    ) async throws {
        // Slice -> FLV：官方增强 FLV('hvc1') 标准 HEVC 流，mpv/ffmpeg 直接可解。
        // 清晰度由调用方给定：prewarm 会话里存着用户选定的 codecType，只有冷路径才需要 rate / 默认值。
        let streamInfo: HuyaStream
        let effectiveRoomId: String
        var prewarmed: HuyaPrewarmSession?

        if case let .prewarm(task, _)? = tasks[roomId] {
            do {
                let session = try await task.value
                effectiveRoomId = session.roomId
                streamInfo = session.streamInfo
                prewarmed = session
                HuyaLogger.log("HuyaProxy:\(session.roomId) prewarm hit uuid=\(roomId.prefix(8))… "
                    + "\(session.displayName) (codecType=\(session.codecType))", level: .debug)
            } catch {
                // 记日志：这类失败（页面抓取瞬时失败/限流）只回客户端的话无从排查
                HuyaLogger.log("HuyaProxy:\(roomId) prewarm failed: \(error)", level: .error)
                try await Self.sendError(outbound: outbound, message: "room \(roomId) prewarm failed: \(error)")
                return
            }
        } else if roomId.contains("-") {
            try await Self.sendError(outbound: outbound, message: "room \(roomId) prewarm session not found")
            return
        } else {
            effectiveRoomId = roomId
            do {
                streamInfo = try await getStreamInfo(roomId: roomId)
            } catch {
                HuyaLogger.log("HuyaProxy:\(roomId) stream info fetch failed: \(error)", level: .error)
                try await Self.sendError(outbound: outbound, message: "room \(roomId) fetch failed: \(error)")
                return
            }
            HuyaLogger.log("HuyaProxy:\(roomId) slice->FLV", level: .debug)
        }

        // 档位 → codecType 与首片，全部在写响应头之前完成：
        // 失败时还能回 500（写过头之后再 sendError 会发出第二个 head）
        let verified: (codecType: Int, isH265: Bool, tags: [HuyaFlvTag])
        do {
            if let session = prewarmed {
                // prewarm 已完成档位翻译 + 首片嗅探校验，直接复用：用户选的是哪一档，拉的就是哪一档
                if session.firstTags.isEmpty {
                    // prewarm 时首片下载失败 → 用同一 codecType 重试（不重算档位）
                    verified = try await self.getFirstTagsVerified(
                        roomId: effectiveRoomId,
                        codecType: session.codecType,
                        expectedIsH265: session.isH265
                    )
                } else {
                    verified = (session.codecType, session.isH265, session.firstTags)
                }
            } else {
                let sliceCT: Int
                let expectedIsH265: Bool
                if let rate {
                    let mapped = Self.codecType(forRate: rate, stream: streamInfo)
                    guard mapped.codecType >= 0 else {
                        try await Self.sendError(outbound: outbound, message: "room \(effectiveRoomId) rate=\(rate) has no third-party-decodable variant")
                        return
                    }
                    sliceCT = mapped.codecType
                    expectedIsH265 = mapped.isH265
                } else {
                    // 无会话、无档位的冷路径（CLI / 直连 roomId）：以 API 档位列表为准，
                    // 取该房间最高的一条可解档。列表里挑不出来就报错，不硬编码兜底。
                    guard let auto = HuyaUrl.selectBestCodecType(stream: streamInfo) else {
                        try await Self.sendError(outbound: outbound, message: "room \(effectiveRoomId) has no playable gear in vMultiStreamInfo")
                        return
                    }
                    sliceCT = auto.codecType
                    expectedIsH265 = auto.codecFamily == HuyaOfficialCodec.familyH265
                }
                verified = try await self.getFirstTagsVerified(
                    roomId: effectiveRoomId,
                    codecType: sliceCT,
                    expectedIsH265: expectedIsH265
                )
            }
        } catch {
            // buildSliceUrl 失败（如房间无 gameStreamInfo）等：头还没写，干净回 500，
            // 不能让错误逃出去导致客户端拿到一个被掐断的连接
            HuyaLogger.log("HuyaProxy:\(effectiveRoomId) stream setup failed: \(error)", level: .error)
            try await Self.sendError(outbound: outbound, message: "room \(effectiveRoomId) stream setup failed: \(error)")
            return
        }

        var headers = NIOHTTP1.HTTPHeaders()
        headers.add(name: "Content-Type", value: "video/x-flv")
        headers.add(name: "Cache-Control", value: "no-cache")
        headers.add(name: "Connection", value: "close")
        let responseHead = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
        try await outbound.write(.head(responseHead))

        // Register the pull in tasks; withTaskCancellationHandler keeps the
        // "client disconnect -> cancel pull" semantics
        let sessionKey = "\(effectiveRoomId)#\(UUID().uuidString)"
        let pull = Task { () throws in
            try await self.streamLoop(
                outbound: outbound,
                roomId: effectiveRoomId,
                streamInfo: streamInfo,
                codecType: verified.codecType,
                firstTags: verified.tags
            )
        }
        tasks[sessionKey] = .livePull(task: pull)
        HuyaLogger.log("HuyaProxy:\(effectiveRoomId) pull registered (\(activeTaskCount().livePulls) active)", level: .debug)
        do {
            try await withTaskCancellationHandler {
                try await pull.value
            } onCancel: {
                pull.cancel()
            }
            tasks[sessionKey] = nil
            HuyaLogger.log("HuyaProxy:\(effectiveRoomId) pull ended (\(activeTaskCount().livePulls) active)")
        } catch {
            tasks[sessionKey] = nil
            HuyaLogger.log("HuyaProxy:\(effectiveRoomId) pull ended (\(activeTaskCount().livePulls) active): \(error)", level: .error)
            throw error
        }

        try? await outbound.write(.end(nil))
    }

    // MARK: - Stream loop

    /// Long-lived stream loop; all state (tupParser, decoder, proxyState) is
    /// local, processed sequentially in a single Task, no actor isolation needed.
    /// Pulls the official .slice stream (Enhanced-FLV 'hvc1' HEVC) and forwards
    /// FLV tags to the client.
    nonisolated private func streamLoop(
        outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>,
        roomId: String,
        streamInfo initialStreamInfo: HuyaStream,
        codecType: Int,
        firstTags: [HuyaFlvTag]
    ) async throws {
        var streamInfo = initialStreamInfo
        var lastRefresh = Date()
        var connectCount = 0
        var consecutiveErrors = 0
        let maxConsecutiveErrors = 10

        // streaming parser (local struct)
        var tupParser = HuyaTupStreamParser()
        var decoder = HuyaSliceStreamDecoder()

        // per-connection proxy state (dedup + ts rewrite)
        var proxyState = HuyaFlvProxyState()

        // 1. FLV file header (9) + PrevTagSize0(4)
        var head = ByteBufferAllocator().buffer(capacity: 13)
        head.writeBytes([0x46, 0x4C, 0x56, 0x01, 0x05, 0x00, 0x00, 0x00, 0x09])
        head.writeInteger(UInt32(0), endianness: .big)
        try await Self.writeData(outbound: outbound, data: head)

        // 2. send pre-cached first_tags
        let firstTagsData = proxyState.processFirstTags(firstTags)
        for data in firstTagsData {
            try await Self.writeData(outbound: outbound, data: data)
        }
        if !firstTags.isEmpty {
            HuyaLogger.log("HuyaProxy:\(roomId) sent \(firstTags.count) first tags "
                + "(v_fid<=\(proxyState.baseFrameId), a_fid<=\(proxyState.baseAudioFrameId), "
                + "last_ts_v=\(proxyState.lastTsV), last_ts_a=\(proxyState.lastTsA))")
        }

        // 2. main loop
        while proxyState.clientAlive && !Task.isCancelled {
            // wsTime is valid ~110s, refresh stream_info every 60s
            if Date().timeIntervalSince(lastRefresh) > 60 {
                do {
                    streamInfo = try await self.getStreamInfo(roomId: roomId, forceRefresh: true)
                    HuyaLogger.log("HuyaProxy:\(roomId) stream_info refreshed")
                } catch {
                    HuyaLogger.log("HuyaProxy:\(roomId) refresh failed: \(error)", level: .error)
                }
                lastRefresh = Date()
            }

            do {
                let (url, _, _) = try HuyaUrl.buildSliceUrl(stream: streamInfo, codecType: codecType)
                connectCount += 1

                // Reset parser state (dedup cursors survive reconnects)
                tupParser.reset()
                decoder.flush()

                // URLRequest with timeout + headers
                var request = URLRequest(url: URL(string: url)!)
                request.timeoutInterval = 30
                for header in Self.sliceHeaders {
                    request.setValue(header.value, forHTTPHeaderField: header.name)
                }

                // Alamofire DataStreamRequest
                let dataStreamRequest = AF.streamRequest(request)
                    .validate(statusCode: 200..<300)
                let streamTask = dataStreamRequest.streamTask()

                var total = 0
                var buffer = ByteBuffer()
                var lastDiag = Date()
                var clientGone = false

                downloadStream: for try await streamEvent in streamTask.streamingData() {
                    if Task.isCancelled || !proxyState.clientAlive {
                        dataStreamRequest.cancel()
                        break downloadStream
                    }
                    // Periodic diagnostics (30s), visible mid-connection
                    if Date().timeIntervalSince(lastDiag) > 30 {
                        lastDiag = Date()
                        HuyaLogger.log("HuyaProxy:\(roomId) [diag] mid-connection sent(v=\(proxyState.sentV),a=\(proxyState.sentA)) "
                            + "skip(v=\(proxyState.skipV),a=\(proxyState.skipA)) "
                            + "ts_reset(v=\(proxyState.tsResetV),a=\(proxyState.tsResetA)) "
                            + "dec(v=\(decoder.completedFrames),drop=\(decoder.droppedIncomplete),"
                            + "back=\(decoder.skippedBackward),gap=\(decoder.maxFidGap),"
                            + "skipDrop=\(proxyState.skipDropCount))", level: .debug)
                    }
                    switch streamEvent.event {
                    case .stream(.success(let data)):
                        // Accumulate, process in 64KB chunks
                        buffer.writeBytes(data)
                        while buffer.readableBytes >= 65536 {
                            let chunk = buffer.readSlice(length: 65536)!
                            total += chunk.readableBytes
                            if try await !Self.processChunk(
                                chunk, tupParser: &tupParser, decoder: &decoder,
                                proxyState: &proxyState,
                                outbound: outbound, roomId: roomId
                            ) {
                                clientGone = true
                                break
                            }
                        }
                        if clientGone {
                            dataStreamRequest.cancel()
                            break downloadStream
                        }

                    case .stream(.failure):
                        break

                    case .complete(let completion):
                        if !proxyState.clientAlive {
                            break downloadStream
                        }
                        if let response = completion.response, response.statusCode != 200 {
                            throw HuyaError.httpError(response.statusCode)
                        }
                        if let error = completion.error {
                            throw HuyaError.streamError(error.localizedDescription)
                        }
                        // flush remaining data (normal end)
                        if buffer.readableBytes > 0 {
                            total += buffer.readableBytes
                            if try await !Self.processChunk(
                                buffer, tupParser: &tupParser, decoder: &decoder,
                                proxyState: &proxyState,
                                outbound: outbound, roomId: roomId
                            ) {
                                dataStreamRequest.cancel()
                                break downloadStream
                            }
                        }
                    }
                }

                let totalPackets = tupParser.totalPackets
                HuyaLogger.log("HuyaProxy:\(roomId) #\(connectCount) connection ended bytes=\(total) pkts=\(totalPackets) "
                    + "sent(v=\(proxyState.sentV),a=\(proxyState.sentA)) "
                    + "skip(v=\(proxyState.skipV),a=\(proxyState.skipA)) "
                    + "ts_reset(v=\(proxyState.tsResetV),a=\(proxyState.tsResetA)) "
                    + "dec(v=\(decoder.completedFrames),drop=\(decoder.droppedIncomplete),"
                    + "back=\(decoder.skippedBackward),gap=\(decoder.maxFidGap),"
                    + "skipDrop=\(proxyState.skipDropCount))")

                // Reset per-connection stats (dedup + ts cursors kept)
                proxyState.resetStats()

                // Reconnect after a brief wait
                consecutiveErrors = 0
                try await Task.sleep(nanoseconds: 300_000_000)

            } catch HuyaError.httpError(let code) {
                // Unrecoverable (e.g. 404): give up
                HuyaLogger.log("HuyaProxy:\(roomId) #\(connectCount) HTTP \(code), giving up", level: .error)
                break
            } catch is ClientDisconnectedError {
                HuyaLogger.log("HuyaProxy:\(roomId) client disconnected")
                break
            } catch is CancellationError {
                // External cancel (client disconnect / monitor task): stop
                break
            } catch {
                if Task.isCancelled {
                    HuyaLogger.log("HuyaProxy:\(roomId) task cancelled, stop reconnecting")
                    break
                }
                consecutiveErrors += 1
                if consecutiveErrors >= maxConsecutiveErrors {
                    HuyaLogger.log("HuyaProxy:\(roomId) \(consecutiveErrors) consecutive failures, giving up: \(error)", level: .error)
                    break
                }
                let backoff = min(1 << (consecutiveErrors - 1), 30)
                HuyaLogger.log("HuyaProxy:\(roomId) #\(connectCount) connection error (\(consecutiveErrors)/\(maxConsecutiveErrors)): \(error), retry in \(backoff)s", level: .error)
                try? await Task.sleep(nanoseconds: UInt64(backoff) * 1_000_000_000)
            }
        }
    }

    // MARK: - Static Helpers

    /// Feed a chunk through tupParser -> decoder -> proxyState -> writeData.
    /// Returns false when the client has disconnected and processing should stop
    nonisolated static func processChunk(
        _ chunk: ByteBuffer,
        tupParser: inout HuyaTupStreamParser,
        decoder: inout HuyaSliceStreamDecoder,
        proxyState: inout HuyaFlvProxyState,
        outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>,
        roomId: String
    ) async throws -> Bool {
        let packets = tupParser.feed(chunk)
        guard !packets.isEmpty else { return true }
        let tags = decoder.feed(packets)
        for tag in tags {
            if let data = proxyState.processTag(tag) {
                do {
                    try await writeData(outbound: outbound, data: data)
                } catch {
                    // NIO write failure = client (mpv) disconnected
                    proxyState.clientAlive = false
                    throw ClientDisconnectedError()
                }
            }
            if !proxyState.clientAlive { return false }
        }
        return true
    }

    /// Write a ByteBuffer to the NIO outbound
    nonisolated static func writeData(
        outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>,
        data: ByteBuffer
    ) async throws {
        try await outbound.write(.body(data))
    }

    /// Download .slice data (first-slice pre-cache)
    ///
    /// 自适应提前停止：播放只需 seq header + 首个完整关键帧，`HuyaFirstKeyframeTracker`
    /// 逐块查 slice 头、凑齐即取消；`maxSize` 只是兜底上限。实测数据见 doc/03 §4
    nonisolated static func downloadSlice(
        url: String,
        maxSize: Int = 2_000_000
    ) async throws -> ByteBuffer {
        var request = URLRequest(url: URL(string: url)!)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for header in sliceHeaders {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }

        var result = ByteBuffer()
        var reachedMax = false
        var stopped = false
        var tracker = HuyaFirstKeyframeTracker()
        let dataStreamRequest = AF.streamRequest(request).validate(statusCode: 200..<300)
        let streamTask = dataStreamRequest.streamTask()

        for try await streamEvent in streamTask.streamingData() {
            switch streamEvent.event {
            case .stream(.success(let data)):
                if stopped {
                    // In-flight data after cancel: discard
                    continue
                }
                result.writeBytes(data)
                // Header-level check: stop on the first complete keyframe
                var chunk = ByteBufferAllocator().buffer(capacity: data.count)
                chunk.writeBytes(data)
                if tracker.feed(chunk) {
                    stopped = true
                    reachedMax = true
                    dataStreamRequest.cancel()
                }
                if result.readableBytes >= maxSize {
                    reachedMax = true
                    dataStreamRequest.cancel()
                    break
                }
            case .stream(.failure):
                break
            case .complete(let completion):
                if reachedMax { break }
                if let response = completion.response, response.statusCode != 200 {
                    throw HuyaError.httpError(response.statusCode)
                }
                if let error = completion.error {
                    throw HuyaError.streamError(error.localizedDescription)
                }
            }
        }

        return result
    }

    /// Send an error response
    nonisolated static func sendError(
        outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>,
        message: String
    ) async throws {
        let data = Data(message.utf8)

        var headers = NIOHTTP1.HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
        headers.add(name: "Content-Length", value: "\(data.count)")
        headers.add(name: "Connection", value: "close")

        let head = HTTPResponseHead(version: .http1_1, status: .internalServerError, headers: headers)
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)

        try await outbound.write(contentsOf: [
            .head(head),
            .body(buffer),
            .end(nil),
        ])
    }

    /// .slice request headers
    nonisolated static let sliceHeaders: Alamofire.HTTPHeaders = [
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            + "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36",
        "Referer": "https://www.huya.com/",
        "Accept": "*/*",
    ]
}

// MARK: - HuyaTask

/// Registry entry in `HuyaProxyServer.tasks`
///
/// - `.prewarm`: prefetch task (key = uuid, the /huya/{uuid}.flv path token)
/// - `.livePull`: active streamLoop task (key = sessionKey "room#uuid")
enum HuyaTask {
    case prewarm(task: Task<HuyaPrewarmSession, any Error>, createdAt: Date)
    case livePull(task: Task<Void, any Error>)

    func cancel() {
        switch self {
        case .prewarm(let task, _):
            task.cancel()
        case .livePull(let task):
            task.cancel()
        }
    }
}

// MARK: - HuyaPrewarmSession

/// Prefetched data enabling /huya/{uuid}.flv to skip the serial prep path
///
/// `codecType`/`isH265`/`firstTags` 存的都是**嗅探校验后**的结果，handleHuyaRequest 直接复用，
/// 不再重算档位、不再重下首片（重算会换档，重下会白拉 1MB）
struct HuyaPrewarmSession: Sendable {
    let roomId: String
    let codecType: Int
    let isH265: Bool
    let displayName: String
    let streamInfo: HuyaStream
    let firstTags: [HuyaFlvTag]
    let createdAt: Date
}

// MARK: - ClientDisconnectedError

/// Client (mpv) disconnected
public struct ClientDisconnectedError: Error {
    public init() {}
}

// MARK: - HuyaFlvProxyState

/// Per-connection proxy state (dedup + ts rewrite); a value type accessed
/// sequentially within a single Task, no concurrency issues
struct HuyaFlvProxyState: Sendable {
    // Seq header is sent once, but must be resent when the stream switches
    // codec params mid-stream (SPS/PPS change), or mpv decodes new frames
    // with stale params -> hardware decode failure
    var avcSeqSent = false
    var aacSeqSent = false
    var lastAvcSeqData: ByteBuffer?
    var lastAacSeqData: ByteBuffer?
    var firstIFrameSent = false

    // Gap-skip：fid 跳变时丢到下一个关键帧，音频保持连续（与官方一致）。
    // 恢复走官方 setNextIFrame —— 视频按自身 dts 前跳，mpv 自行重同步 A/V。
    var skipUntilKeyframe = false
    var skipDropCount = 0       // frames dropped (diagnostics)

    // frameId dedup cursors (kept across reconnects);
    // official vplayer.js lastPlayFrameId starts at 0
    var baseFrameId: Int32 = 0
    var baseAudioFrameId: Int32 = 0

    // ts rewrite (kept across reconnects, proxy needs a continuous timeline)
    var baseTsV: Int?
    var baseTsA: Int?
    var lastTsV: Int = -1
    var lastTsA: Int = -1

    // per-connection stats
    var sentV = 0
    var sentA = 0
    var skipV = 0
    var skipA = 0
    var tsResetV = 0
    var tsResetA = 0
    var firstVFid: Int32?
    var lastVFid: Int32 = -1
    var firstAFid: Int32?
    var lastAFid: Int32 = -1

    // whether the client is still alive
    var clientAlive = true

    /// Process pre-cached first_tags; returns buffers to write, updating
    /// the dedup cursors. AVC/AAC seq headers are sent first, resent on
    /// change (through the processTag path)
    mutating func processFirstTags(_ tags: [HuyaFlvTag]) -> [ByteBuffer] {
        var result: [ByteBuffer] = []

        for tag in tags {
            if tag.isSeqHeader {
                if let data = processTag(tag) {
                    result.append(data)
                }
                continue
            }
            if tag.type == 8, tag.data.readableBytes >= 13 {
                let bytes = tag.data.readableBytesView
                if (bytes[11] >> 4) == 10 && bytes[12] == 0 {
                    if let data = processTag(tag) {
                        result.append(data)
                    }
                    continue
                }
            }
            if let data = processTag(tag) {
                result.append(data)
            }
        }
        return result
    }

    /// Process a single FLV tag; returns the bytes to write
    /// (deduped + ts-rewritten) or nil to skip
    mutating func processTag(_ tag: HuyaFlvTag) -> ByteBuffer? {
        let tagData = tag.data
        let tagType = tag.type
        let fid = tag.frameId
        let origTs = tag.timestamp

        // Video seq header: first one always sent; resent when content
        // changes (live streams may switch codec params mid-stream)
        if tag.isSeqHeader {
            if !avcSeqSent {
                avcSeqSent = true
                lastAvcSeqData = tagData
                return tagData
            }
            if let last = lastAvcSeqData {
                if tagData.readableBytes == last.readableBytes,
                   tagData.readableBytesView.elementsEqual(last.readableBytesView) {
                    return nil // same seq header, skip
                }
                // Codec params changed -> resend so mpv reinitializes the decoder
                HuyaLogger.log("HuyaProxy video seq header changed, resending (SPS/PPS update)")
                lastAvcSeqData = tagData
                return tagData
            }
            return nil
        }

        // AAC seq header (type=8, aacPacketType=0): same resend-on-change logic
        if tagType == 8, tagData.readableBytes >= 13 {
            let bytes = tagData.readableBytesView
            if (bytes[11] >> 4) == 10 && bytes[12] == 0 {
                if !aacSeqSent {
                    aacSeqSent = true
                    lastAacSeqData = tagData
                    return tagData
                }
                if let last = lastAacSeqData {
                    if tagData.readableBytes == last.readableBytes,
                       tagData.readableBytesView.elementsEqual(last.readableBytesView) {
                        return nil
                    }
                    HuyaLogger.log("HuyaProxy AAC seq header changed, resending (audio config update)")
                    lastAacSeqData = tagData
                    return tagData
                }
                return nil
            }
        }

        // video: drop P/B frames before the first I frame
        // keyframe detection covers both formats:
        // - standard H.264: top 4 bits of b0 = 1 (0x17/0x27)
        // - Enhanced FLV 4CC H.265: IsEx(bit7) + FrameType=key (0x91)
        if tagType == 9 {
            if !firstIFrameSent {
                if tagData.readableBytes >= 12 {
                    let bytes = tagData.readableBytesView
                    let b0 = bytes[11]
                    let isKey = (b0 >> 4) == 1 || ((b0 & 0x80) != 0 && (b0 & 0x70) == 0x10)
                    if isKey {
                        firstIFrameSent = true
                    } else {
                        return nil
                    }
                } else {
                    return nil
                }
            }
        }

        // dedup: skip already-sent frameIds
        if fid >= 0 {
            if tagType == 9 && fid <= baseFrameId {
                skipV += 1
                return nil
            }
            if tagType == 8 && fid <= baseAudioFrameId {
                skipA += 1
                return nil
            }
        }

        // Gap skip: a video fid jump means the reference frame is missing;
        // drop video frames until the keyframe, keep audio continuous
        // (audio frames are never dropped, the player resyncs)
        if tagType == 9, fid >= 0, lastVFid >= 0, !skipUntilKeyframe {
            if fid > lastVFid + 1 {
                skipUntilKeyframe = true
                skipDropCount = 0
                HuyaLogger.log("HuyaProxy:\(fid) video frame gap fid=\(lastVFid)->\(fid), skip until keyframe (audio continuous)")
            }
        }

        if skipUntilKeyframe {
            if tagType == 9 {
                if !Self.isKeyframeTag(tagData) {
                    // non-keyframe: broken frame, don't display
                    skipDropCount += 1
                    return nil
                }
                // Keyframe: resume video output (official setNextIFrame) -
                // no timeline special-casing, video jumps forward on its own
                // source dts, mpv resyncs A/V; audio stays continuous
                skipUntilKeyframe = false
                HuyaLogger.log("HuyaProxy keyframe fid=\(fid) resume (skipped \(skipDropCount) frames, video jumps forward)")
            }
            // tagType == 8 (audio): pass through
        }

        // ts handling
        let newTs: Int
        if tagType == 9 {
            if baseTsV == nil { baseTsV = origTs }
            var ts = origTs - (baseTsV ?? 0)
            if ts <= lastTsV {
                // Timestamp went backwards (new stream/reconnect): re-anchor
                // to stay monotonic. Forward jumps (ts > lastTsV) are the
                // natural result of frame recovery; not clamped, the player
                // resyncs
                baseTsV = origTs - (lastTsV + 1)
                ts = lastTsV + 1
                tsResetV += 1
            }
            lastTsV = ts
            newTs = ts
        } else {
            if baseTsA == nil { baseTsA = origTs }
            var ts = origTs - (baseTsA ?? 0)
            if ts <= lastTsA {
                baseTsA = origTs - (lastTsA + 1)
                ts = lastTsA + 1
                tsResetA += 1
            }
            lastTsA = ts
            newTs = ts
        }

        let newData = HuyaFlvTimestamp.rewrite(tagData, newTs: newTs)

        // Advance frameId cursors
        if fid >= 0 {
            if tagType == 9 && fid > baseFrameId {
                baseFrameId = fid
            } else if tagType == 8 && fid > baseAudioFrameId {
                baseAudioFrameId = fid
            }
        }

        // Update stats
        if tagType == 9 {
            sentV += 1
            if firstVFid == nil { firstVFid = fid }
            if fid > lastVFid { lastVFid = fid }
        } else if tagType == 8 {
            sentA += 1
            if firstAFid == nil { firstAFid = fid }
            if fid > lastAFid { lastAFid = fid }
        }

        return newData
    }

    /// Reset per-connection stats (dedup + ts cursors kept)
    mutating func resetStats() {
        sentV = 0; sentA = 0
        skipV = 0; skipA = 0
        tsResetV = 0; tsResetA = 0
        skipUntilKeyframe = false
        skipDropCount = 0
        firstVFid = nil; firstAFid = nil
        lastVFid = -1; lastAFid = -1
    }

    /// Keyframe detection for both standard H.264 and Enhanced FLV 4CC H.265
    static func isKeyframeTag(_ tagData: ByteBuffer) -> Bool {
        guard tagData.readableBytes >= 12 else { return false }
        let bytes = tagData.readableBytesView
        let b0 = bytes[11]
        return (b0 >> 4) == 1 || ((b0 & 0x80) != 0 && (b0 & 0x70) == 0x10)
    }
}
