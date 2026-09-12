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
    private var codecCache: [String: (codecType: Int, displayName: String)] = [:]
    private var firstTagsCache: [String: [HuyaFlvTag]] = [:]

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
        firstTagsCache.removeAll()
        return info
    }

    func getCodecType(roomId: String, rate: Int? = nil) async throws -> (codecType: Int, displayName: String) {
        // nil = auto, kept distinct from explicit 0 in the key
        let cacheKey = "\(roomId)#\(rate.map { String($0) } ?? "auto")"
        if let cached = codecCache[cacheKey] {
            return cached
        }
        let info = try await getStreamInfo(roomId: roomId)
        let result: (codecType: Int, displayName: String)
        // any explicit rate, incl. 0, takes the exact-match path
        if let rate {
            result = Self.selectCodecType(
                forRate: rate,
                vMultiStreamInfo: info.vMultiStreamInfo,
                srcBitrate: info.bitRate
            )
        } else {
            // codec comes from the site data; handle whatever format is given
            let r = try HuyaUrl.buildSliceUrl(stream: info)
            result = (r.codecType, r.displayName)
        }
        codecCache[cacheKey] = result
        return result
    }

    /// Pick the codecType for the user-selected quality (iBitRate)
    ///
    /// Match iBitRate in vMultiStreamInfo and compute codecType from that
    /// entry's iCodecType family (0=H.264, else H.265, official _getCodec);
    /// prefer H.265 when both exist at the same rate; fall back to
    /// auto-select if no matching entry
    nonisolated static func selectCodecType(
        forRate rate: Int,
        vMultiStreamInfo: [HuyaStream.StreamInfo],
        srcBitrate: Int
    ) -> (codecType: Int, displayName: String) {
        let candidates = vMultiStreamInfo.filter { v in
            v.iBitRate == rate
                // Skip HDR (iCompatibleFlag=16384, official ie() L48672)
                && v.iCompatibleFlag != 16384
        }
        if let v = candidates.first(where: { $0.iCodecType != 0 })
            ?? candidates.first {
            let iCodecType = v.iCodecType
            let family = iCodecType == 0 ? CODEC_FAMILY_H264 : CODEC_FAMILY_H265
            let displayName = v.sDisplayName
            let codecType = HuyaUrl.getCodec(codecFamily: family, bitrate: rate)
            HuyaLogger.log("HuyaProxy: selectCodecType rate=\(rate) (\(displayName), \(iCodecType == 0 ? "H.264" : "H.265")) codecType=\(codecType)", level: .debug)
            return (codecType, displayName)
        }
        let r = HuyaUrl.selectBestCodecType(
            vMultiStreamInfo: vMultiStreamInfo,
            srcBitrate: srcBitrate
        )
        HuyaLogger.log("HuyaProxy: no entry for rate=\(rate), fallback auto-select (\(r.displayName))", level: .debug)
        return (r.codecType, r.displayName)
    }

    /// Download the first slice, sniff the actual codec (hvcC vs avcC) and
    /// correct codecType if needed: don't trust the codecType marker, and
    /// re-download at the correct family's top bitrate on mismatch.
    ///
    /// Cached under a fresh UUID key per connection so 264/265 first slices
    /// are never mixed across connections
    func getFirstTagsVerified(
        roomId: String,
        codecType: Int,
        expectedIsH265: Bool
    ) async throws -> (codecType: Int, tags: [HuyaFlvTag]) {
        let info = try await getStreamInfo(roomId: roomId)
        var current = codecType
        var tags: [HuyaFlvTag] = []

        for attempt in 0..<2 {
            let (url, _, _) = try HuyaUrl.buildSliceUrl(stream: info, codecType: current)
            do {
                // Adaptive early stop: CDN serves history at the live bitrate
                // (1MB ≈ 12s of history, ~9.6s measured); playback only needs
                // seq header + first keyframe, so stop once the header-level
                // check passes. streamLoop resumes from the live edge and
                // proxyState dedups by fid, so a short first slice doesn't
                // break continuity. Hard cap at 1MB as a fallback.
                let data = try await Self.downloadSlice(url: url, maxSize: 1_000_000)
                tags = HuyaSliceDecoder.decode(sliceData: data)
            } catch {
                HuyaLogger.log("HuyaProxy:\(roomId) first-slice download failed: \(error)", level: .error)
                return (current, [])
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
                // Marker disagrees with the sniffed codec -> switch family and re-download
                HuyaLogger.log("HuyaProxy:\(roomId) codec mismatch, switching to "
                    + "\(actualIsH265 ? "H.265" : "H.264")")
                current = Self.fallbackCodecType(
                    vMultiStreamInfo: info.vMultiStreamInfo,
                    actualIsH265: actualIsH265,
                    srcBitrate: info.bitRate
                )
                continue
            }
            break
        }

        if firstTagsCache.count > 4 {
            firstTagsCache.removeAll()
        }
        firstTagsCache[UUID().uuidString] = tags
        return (current, tags)
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

    /// Highest codecType of the sniffed family from vMultiStreamInfo
    nonisolated static func fallbackCodecType(
        vMultiStreamInfo: [HuyaStream.StreamInfo],
        actualIsH265: Bool,
        srcBitrate: Int
    ) -> Int {
        var bestBitrate = 0
        for v in vMultiStreamInfo {
            let iCodecType = v.iCodecType
            if HuyaUrl.isH265CodecType(iCodecType) != actualIsH265 { continue }
            // Skip HDR (iCompatibleFlag=16384, official ie() L48672)
            if v.iCompatibleFlag == 16384 { continue }
            let iBitRate = v.iBitRate
            let eff = iBitRate > 0 ? iBitRate : srcBitrate
            if eff > bestBitrate { bestBitrate = eff }
        }
        let bitrate = bestBitrate > 0 ? bestBitrate : 4000
        let family = actualIsH265 ? CODEC_FAMILY_H265 : CODEC_FAMILY_H264
        return HuyaUrl.getCodec(codecFamily: family, bitrate: bitrate)
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
            let expectedIsH265 = HuyaUrl.isH265CodecType(streamInfo.codecType)
            let verified = try await self.getFirstTagsVerified(
                roomId: roomId,
                codecType: codecResult.codecType,
                expectedIsH265: expectedIsH265
            )
            return HuyaPrewarmSession(
                roomId: roomId,
                codecType: verified.codecType,
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
    ///
    /// token first matches a prewarm session uuid -> skip the serial prep
    /// (streamInfo/codecType/firstTags already prefetched); otherwise treat
    /// it as a roomId and go through the cold path
    public func handleHuyaRequest(
        roomId: String,
        outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>
    ) async throws {
        let streamInfo: HuyaStream
        let codecType: Int
        let displayName: String
        let firstTags: [HuyaFlvTag]
        let effectiveRoomId: String

        if case let .prewarm(task, _)? = tasks[roomId] {
            // Task stays cached until cleanupExpiredPrewarms, so reconnects on
            // the same /huya/{uuid}.flv URL hit it again
            do {
                let session = try await task.value
                effectiveRoomId = session.roomId
                streamInfo = session.streamInfo
                codecType = session.codecType
                displayName = session.displayName
                firstTags = session.firstTags
                HuyaLogger.log("HuyaProxy:\(session.roomId) prewarm hit uuid=\(roomId.prefix(8))… "
                    + "\(session.displayName) (codecType=\(session.codecType))", level: .debug)
            } catch {
                try await Self.sendError(outbound: outbound, message: "room \(roomId) prewarm failed: \(error)")
                return
            }
        } else if roomId.contains("-") {
            // Opaque session id with no session: don't treat it as a roomId
            try await Self.sendError(outbound: outbound, message: "room \(roomId) prewarm session not found")
            return
        } else {
            effectiveRoomId = roomId
            do {
                streamInfo = try await getStreamInfo(roomId: roomId)
                let initialCodec = try await getCodecType(roomId: roomId)
                // Download first slice + sniff the actual codec; re-download
                // at the correct codecType if the marker disagrees
                let expectedIsH265 = HuyaUrl.isH265CodecType(streamInfo.codecType)
                let verified = try await getFirstTagsVerified(
                    roomId: roomId,
                    codecType: initialCodec.codecType,
                    expectedIsH265: expectedIsH265
                )
                firstTags = verified.tags
                codecType = verified.codecType
                displayName = initialCodec.displayName
            } catch {
                try await Self.sendError(outbound: outbound, message: "room \(roomId) fetch failed: \(error)")
                return
            }
            HuyaLogger.log("HuyaProxy:\(roomId) \(displayName) (codecType=\(codecType))", level: .debug)
        }

        var headers = NIOHTTP1.HTTPHeaders()
        headers.add(name: "Content-Type", value: "video/x-flv")
        headers.add(name: "Cache-Control", value: "no-cache")
        headers.add(name: "Connection", value: "close")
        let responseHead = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
        try await outbound.write(.head(responseHead))

        try await outbound.write(.body(HuyaFlvBuilder.flvHeader))

        // Register the pull in tasks; withTaskCancellationHandler keeps the
        // "client disconnect -> cancel pull" semantics
        let sessionKey = "\(effectiveRoomId)#\(UUID().uuidString)"
        let pull = Task { () throws in
            try await streamLoop(
                outbound: outbound,
                roomId: effectiveRoomId,
                streamInfo: streamInfo,
                codecType: codecType,
                firstTags: firstTags
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
    /// local, processed sequentially in a single Task, no actor isolation needed
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

        // 1. send pre-cached first_tags
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
                                proxyState: &proxyState, outbound: outbound, roomId: roomId
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
                                proxyState: &proxyState, outbound: outbound, roomId: roomId
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
    /// Adaptive early stop: the CDN serves history at the live bitrate
    /// (1MB ≈ 12s of history, ~9.6s measured); playback only needs the seq
    /// header + first complete keyframe (~100-400KB). HuyaFirstKeyframeTracker
    /// inspects slice headers chunk by chunk and cancels as soon as the first
    /// complete keyframe arrives; maxSize is the hard fallback
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
struct HuyaPrewarmSession: Sendable {
    let roomId: String
    let codecType: Int
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

    // Gap-skip state: on a fid jump, drop broken video frames until the next
    // keyframe while keeping audio continuous (matches official behavior).
    // Recovery follows official setNextIFrame: video jumps forward on its own
    // source dts (forward PTS jumps allowed), player (mpv) resyncs A/V;
    // audio stays continuous on its own timeline
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

        let newData = HuyaFlvBuilder.rewriteFlvTagTs(tagData, newTs: newTs)

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
