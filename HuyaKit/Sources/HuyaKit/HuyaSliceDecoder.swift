//
//  HuyaSliceDecoder.swift
//  HuyaProxy
//
//  streamData → FLV tag extraction + .slice decode
//
//  SwiftNIO ByteBuffer based binary parsing
//

import Foundation
import NIOCore

// MARK: - HuyaFlvTag

struct HuyaFlvTag: Sendable {
    let type: UInt8       // 8=audio, 9=video, 18=script
    let timestamp: Int    // original DTS (read from inside the FLV tag)
    let data: ByteBuffer  // complete FLV tag (header + data + prevTagSize)
    let seq: UInt16       // seqNum (video) or 0 (audio)
    let frameId: Int32    // for dedup (-1 = seq header)
    let isSeqHeader: Bool
    /// 关键帧的原始 AnnexB VPS/SPS/PPS（非关键帧为 nil）。当前**无读取点**，
    /// 保留作超分私有档（codecType=2）逆向的原始素材（见 MEMORY.md §4.3 / doc/05）。
    let annexHeader: ByteBuffer?

    init(type: UInt8, timestamp: Int, data: ByteBuffer, seq: UInt16 = 0, frameId: Int32 = -1, isSeqHeader: Bool = false, annexHeader: ByteBuffer? = nil) {
        self.type = type
        self.timestamp = timestamp
        self.data = data
        self.seq = seq
        self.frameId = frameId
        self.isSeqHeader = isSeqHeader
        self.annexHeader = annexHeader
    }
}

// MARK: - HuyaFrameExtractor

enum HuyaFrameExtractor {
    /// Extract a single FLV tag from merged streamData
    ///
    /// - H.264 keyframe: `[size_prefix(4)] + [AVCDecoderConfigurationRecord] + [FLV tag]`
    /// - H.265 keyframe: `[size_prefix(4)] + [AnnexB VPS+SPS+PPS] + [FLV tag (AnnexB payload)]`
    /// - non-keyframe: `[FLV tag]`
    static func extract(merged: ByteBuffer, isKeyframe: Bool) -> (seqTag: ByteBuffer?, annexHeader: ByteBuffer?, flvTag: HuyaFlvTag?) {
        let bytes = merged.readableBytesView
        var pos = 0
        var seqTag: ByteBuffer? = nil
        var annexHeader: ByteBuffer? = nil

        if isKeyframe {
            guard bytes.count >= 4 else { return (nil, nil, nil) }
            let sizePrefix = merged.getInteger(at: 0, endianness: .little, as: UInt32.self) ?? 0
            let seqHeaderEnd = 4 + Int(sizePrefix)
            guard seqHeaderEnd <= bytes.count else { return (nil, nil, nil) }
            let seqHeader = merged.getSlice(at: 4, length: Int(sizePrefix))!

            if seqHeader.readableBytes > 4 {
                let shBytes = seqHeader.readableBytesView
                // AnnexB start code?
                let isAnnexB3 = shBytes[0] == 0 && shBytes[1] == 0 && shBytes[2] == 1
                let isAnnexB4 = shBytes.count >= 4 && shBytes[0] == 0 && shBytes[1] == 0 && shBytes[2] == 0 && shBytes[3] == 1

                if isAnnexB3 || isAnnexB4 {
                    // H.265: AnnexB → hvcC（另存原始 AnnexB 头，见 HuyaFlvTag.annexHeader）
                    annexHeader = seqHeader
                    let nalus = HuyaOfficialFlv.parseHevcAnnexB(seqHeader)
                    let vps = nalus.filter { $0.naluType == HuyaOfficialFlv.nalVPS }.map { $0.naluData }
                    let sps = nalus.filter { $0.naluType == HuyaOfficialFlv.nalSPS }.map { $0.naluData }
                    let pps = nalus.filter { $0.naluType == HuyaOfficialFlv.nalPPS }.map { $0.naluData }
                    if !vps.isEmpty && !sps.isEmpty && !pps.isEmpty {
                        if let hvcc = HuyaOfficialFlv.buildHvcc(vps: vps, sps: sps, pps: pps) {
                            seqTag = HuyaOfficialFlv.buildHevcSeqTag(hvccData: hvcc)
                        }
                    }
                } else if shBytes[0] == 0x01 {
                    // H.264: AVCDecoderConfigurationRecord
                    seqTag = HuyaOfficialFlv.buildAvcSeqTag(seqHeaderData: seqHeader)
                }
            }
            pos = seqHeaderEnd
        }

        // read the FLV tag from pos
        guard pos + 11 <= bytes.count else { return (seqTag, annexHeader, nil) }

        let tagType = bytes[pos]
        guard tagType == 8 || tagType == 9 || tagType == 18 else { return (seqTag, annexHeader, nil) }

        let dataSize = (Int(bytes[pos+1]) << 16) | (Int(bytes[pos+2]) << 8) | Int(bytes[pos+3])
        let timestampLow = (Int(bytes[pos+4]) << 16) | (Int(bytes[pos+5]) << 8) | Int(bytes[pos+6])
        let tsExt = Int(bytes[pos+7])

        var tagTotal = 11 + dataSize + 4
        if pos + tagTotal > bytes.count {
            tagTotal = 11 + dataSize
            if pos + tagTotal > bytes.count {
                return (seqTag, annexHeader, nil)
            }
        }

        var flvTagData = merged.getSlice(at: pos, length: tagTotal)!

        // H.265: convert the FLV video tag's AnnexB payload to length-prefixed
        if tagType == 9 && dataSize > 5 {
            let codecId = bytes[pos + 11] & 0x0F
            let packetType = bytes[pos + 12]
            if codecId == 12 && packetType == 1 {
                let oldPayloadStart = pos + 16
                let oldPayloadEnd = pos + 11 + dataSize
                if oldPayloadEnd <= bytes.count {
                    let oldPayload = merged.getSlice(at: oldPayloadStart, length: dataSize - 5)!
                    let plBytes = oldPayload.readableBytesView
                    let needsConvert: Bool
                    if plBytes.count >= 4 {
                        needsConvert = plBytes[0] == 0 && plBytes[1] == 0 && plBytes[2] == 0 && plBytes[3] == 1
                    } else if plBytes.count >= 3 {
                        needsConvert = plBytes[0] == 0 && plBytes[1] == 0 && plBytes[2] == 1
                    } else {
                        needsConvert = false
                    }
                    if needsConvert {
                        let newPayload = HuyaOfficialFlv.annexBToLengthPrefixed(oldPayload)
                        // Enhanced FLV 4CC: b0(1) + 'hvc1'(4) + cts(3)
                        let newDataSize = 8 + newPayload.readableBytes
                        var newTag = ByteBufferAllocator().buffer(capacity: 11 + newDataSize + 4)
                        newTag.writeInteger(UInt8(0x09)) // tagType = 9
                        // dataSize (3 bytes BE)
                        newTag.writeInteger(UInt8((newDataSize >> 16) & 0xFF))
                        newTag.writeInteger(UInt8((newDataSize >> 8) & 0xFF))
                        newTag.writeInteger(UInt8(newDataSize & 0xFF))
                        // keep original timestamp + tsExt
                        newTag.writeBytes(bytes[pos+4..<pos+8])
                        // streamId
                        newTag.writeBytes([0x00, 0x00, 0x00])
                        // Enhanced FLV byte0: IsEx(bit7=1) | FrameType(bit6-4) | PacketType(1).
                        // FrameType sits in bit4-5 in both standard and 4CC
                        // formats (key=0x10/inter=0x20); keep the original
                        // FrameType bits, do not shift
                        newTag.writeInteger(UInt8(0x80 | (bytes[pos + 11] & 0xF0) | 0x01))
                        // 4CC 'hvc1'
                        newTag.writeBytes([0x68, 0x76, 0x63, 0x31])
                        // cts：保留原值（B 帧重排需要；与官方一致）
                        newTag.writeBytes(bytes[pos + 13..<pos + 16])
                        // payload
                        newTag.writeImmutableBuffer(newPayload)
                        // prevTagSize
                        newTag.writeInteger(UInt32(11 + newDataSize), endianness: .big)
                        flvTagData = newTag
                        tagTotal = newTag.readableBytes
                    }
                }
            }
        }

        let fullTs = (tsExt << 24) | timestampLow
        let flvTag = HuyaFlvTag(
            type: tagType,
            timestamp: fullTs,
            data: flvTagData
        )
        return (seqTag, annexHeader, flvTag)
    }
}

// MARK: - HuyaSliceDecoder (one-shot decode)

enum HuyaSliceDecoder {
    /// Decode .slice data into a list of FLV tags
    static func decode(sliceData: ByteBuffer) -> [HuyaFlvTag] {
        let packets = HuyaTupParser.parse(data: sliceData)

        var videoFrames: [UInt32: [HuyaVideoSlice]] = [:]
        var audioSlices: [HuyaAudioSlice] = []

        for pkt in packets {
            if pkt.uri == UInt32(HuyaProtoUri.video) {
                if let v = HuyaSliceParser.parseVideo(payload: pkt.payload) {
                    videoFrames[v.frameId, default: []].append(v)
                }
            } else if pkt.uri == UInt32(HuyaProtoUri.audio) {
                if let a = HuyaSliceParser.parseAudio(payload: pkt.payload) {
                    audioSlices.append(a)
                }
            }
        }

        var allTags: [HuyaFlvTag] = []

        // video frames in frameId order
        let sortedFids = videoFrames.keys.sorted()
        for fid in sortedFids {
            guard var slices = videoFrames[fid] else { continue }
            slices.sort { $0.seqNum < $1.seqNum }

            guard let first = slices.first else { continue }
            let isKeyframe = first.isKeyframe
            let pktNum = first.frameNum
            if slices.count != Int(pktNum) { continue }

            // merge streamData
            let totalSize = slices.reduce(0) { $0 + $1.streamData.readableBytes }
            var merged = ByteBufferAllocator().buffer(capacity: totalSize)
            for s in slices { merged.writeImmutableBuffer(s.streamData) }

            let (seqTag, annexHeader, flvTag) = HuyaFrameExtractor.extract(merged: merged, isKeyframe: isKeyframe)

            if let st = seqTag {
                allTags.append(HuyaFlvTag(
                    type: 9, timestamp: 0, data: st,
                    seq: first.seqNum, frameId: -1, isSeqHeader: true
                ))
            }
            if let ft = flvTag {
                allTags.append(HuyaFlvTag(
                    type: ft.type, timestamp: ft.timestamp, data: ft.data,
                    seq: first.seqNum, frameId: Int32(fid),
                    annexHeader: annexHeader
                ))
            }
        }

        // 音频（官方 `readAacTag`，vplayer 搜 `readAacTag`）
        for audio in audioSlices {
            let sd = audio.streamData
            let sdBytes = sd.readableBytesView
            var pos = 0

            // AAC seq header
            if sdBytes.count >= 19 && sdBytes[0] == 0x08 {
                let seqDataSize = (Int(sdBytes[1]) << 16) | (Int(sdBytes[2]) << 8) | Int(sdBytes[3])
                let seqTagTotal = 11 + seqDataSize + 4
                if seqTagTotal <= sdBytes.count {
                    let seqTag = sd.getSlice(at: 0, length: seqTagTotal)!
                    allTags.append(HuyaFlvTag(type: 8, timestamp: 0, data: seqTag))
                    pos = seqTagTotal
                }
            }

            // records: [4B LE total_size][4B LE frameId][FLV audio tag]
            while pos + 8 <= sdBytes.count {
                let totalSize = Int(sd.getInteger(at: pos, endianness: .little, as: UInt32.self) ?? 0)
                let audioFrameId = sd.getInteger(at: pos + 4, endianness: .little, as: UInt32.self) ?? 0
                if totalSize < 8 || pos + totalSize > sdBytes.count { break }
                let flvTagData = sd.getSlice(at: pos + 8, length: totalSize - 8)!
                var flvTs = 0
                if totalSize - 8 >= 8 {
                    let tagStart = pos + 8
                    let tsLow = (Int(sdBytes[tagStart + 4]) << 16) | (Int(sdBytes[tagStart + 5]) << 8) | Int(sdBytes[tagStart + 6])
                    let tsExt = Int(sdBytes[tagStart + 7])
                    flvTs = (tsExt << 24) | tsLow
                }
                allTags.append(HuyaFlvTag(
                    type: 8, timestamp: flvTs, data: flvTagData,
                    frameId: Int32(bitPattern: audioFrameId)
                ))
                pos += totalSize
            }
        }

        // interleave: video by frameId, audio by internal FLV ts
        let videoTags = allTags.filter { $0.type == 9 }
        let audioTags = allTags.filter { $0.type == 8 }.sorted { $0.timestamp < $1.timestamp }

        var mergedTags: [HuyaFlvTag] = []
        var vi = 0
        var ai = 0
        while vi < videoTags.count && ai < audioTags.count {
            if videoTags[vi].timestamp <= audioTags[ai].timestamp {
                mergedTags.append(videoTags[vi]); vi += 1
            } else {
                mergedTags.append(audioTags[ai]); ai += 1
            }
        }
        mergedTags.append(contentsOf: videoTags[vi...])
        mergedTags.append(contentsOf: audioTags[ai...])
        return mergedTags
    }
}

// MARK: - HuyaSliceStreamDecoder (streaming decode)

/// Streaming .slice decoder (official vplayer.js VideoRecver + AudioRecver)
///
/// Keeps video_frames state across chunks, emits a frame as soon as it's
/// complete; audio slices are streamed directly, one record at a time
struct HuyaSliceStreamDecoder: Sendable {
    /// Pending video frames (cached by fid); first-slice arrival time for
    /// the loss timeout
    private struct PendingFrame {
        var slices: [HuyaVideoSlice]
        /// 该帧首个分片到达时的视频包计数（用于下面的包数预算判据）
        let firstSlicePacketIndex: Int
        let receivedAtNanos: UInt64
    }

    private var videoFrames: [UInt32: PendingFrame] = [:]
    private var audioSeqSent = false
    /// Next video fid to emit (play cursor, matches official lastPlayFrameId)
    private var nextPlayFid: Int32 = -1
    /// Highest fid actually emitted (for dropping late slices of emitted frames)
    private(set) var lastEmittedFid: Int32 = -1
    /// 收到的视频分片计数（单调递增）
    private var videoPacketCount = 0
    /// 「等齐」预算：以**视频包数**计，与码率/包率无关（256 对实测最大跨度 86 包留约 3 倍余量）。
    /// 原为固定 400ms 墙钟 —— 预算单位是时间、跨度是包数，低码率（低包率）下同样的包跨度会超时，
    /// 把**还在路上**的帧误判成丢失 → fid 空洞 → 卡顿。成因与实测：MEMORY.md §5.4 / §5.5
    private let sliceSpanBudget = 256
    /// 墙钟兜底：流卡住（不再来包）时包数判据永不触发
    private let dropTimeoutNanos: UInt64 = 3_000_000_000   // 3s

    // ---- per-connection diagnostics ----
    private(set) var completedFrames = 0       // frames completed and emitted
    private(set) var droppedIncomplete = 0     // frames truly lost (timeout/gap)
    private(set) var skippedBackward = 0       // late slices of emitted frames dropped
    private(set) var lateCompletedFrames = 0   // frames completed only after late slices arrived
    private(set) var maxFidGap = 0             // largest gap between consecutive emitted fids

    /// Feed a list of TUP packets (from HuyaTupStreamParser.feed)
    ///
    /// - Returns: FLV tags (ordered by fid, interleaved with audio)
    mutating func feed(_ packets: [HuyaTupPacket]) -> [HuyaFlvTag] {
        var tags: [HuyaFlvTag] = []
        // Append all video slices of this batch first, then emit in order,
        // so the last slice of a frame arriving late (within the batch)
        // can still complete it
        for pkt in packets {
            if pkt.uri == UInt32(HuyaProtoUri.video) {
                appendVideoSlice(pkt)
            } else if pkt.uri == UInt32(HuyaProtoUri.audio) {
                tags.append(contentsOf: handleAudio(pkt))
            }
        }
        emitReady(&tags)
        return tags
    }

    /// Called on disconnect; clears incomplete frame state and resets
    /// per-connection stats
    mutating func flush() {
        videoFrames.removeAll()
        nextPlayFid = -1
        // 重连后重置 AAC 配置头发送标记：新连接首包带配置，客户端重初始化安心
        audioSeqSent = false
        completedFrames = 0
        droppedIncomplete = 0
        skippedBackward = 0
        lateCompletedFrames = 0
        lastEmittedFid = -1
        maxFidGap = 0
    }

    // MARK: - Private (video)

    private mutating func appendVideoSlice(_ pkt: HuyaTupPacket) {
        guard let parsed = HuyaSliceParser.parseVideo(payload: pkt.payload) else { return }
        let fid = parsed.frameId
        videoPacketCount += 1
        // Late slice of an already-emitted frame: drop (matches official
        // recvData's frameId <= lastPlayFrameId branch)
        if Int32(fid) <= lastEmittedFid {
            skippedBackward += 1
            return
        }
        if videoFrames[fid] == nil {
            videoFrames[fid] = PendingFrame(
                slices: [],
                firstSlicePacketIndex: videoPacketCount,
                receivedAtNanos: DispatchTime.now().uptimeNanoseconds
            )
        }
        videoFrames[fid]?.slices.append(parsed)
    }

    /// Try to emit pending frames in fid order (wait on incomplete frames,
    /// treat them as lost past the timeout)
    private mutating func emitReady(_ tags: inout [HuyaFlvTag]) {
        if nextPlayFid < 0 {
            guard let lo = videoFrames.keys.min() else { return }
            nextPlayFid = Int32(lo)
        }
        let now = DispatchTime.now().uptimeNanoseconds
        while true {
            guard let frame = videoFrames[UInt32(nextPlayFid)] else {
                // fid missing (cursor hole): frames behind the cursor that
                // never completed are truly lost
                let stale = videoFrames.keys.filter { $0 < UInt32(nextPlayFid) }
                for s in stale {
                    if let f = videoFrames[s] {
                        HuyaLogger.log("HuyaProxy frame gap fid=\(s) expected \(Int(f.slices[0].frameNum)) slices "
                            + "got \(f.slices.count) \(f.slices[0].isKeyframe ? "KEY" : "P/B")")
                        droppedIncomplete += 1
                    }
                    videoFrames[s] = nil
                }
                guard let nxt = videoFrames.keys.filter({ $0 > UInt32(nextPlayFid) }).min() else {
                    return
                }
                nextPlayFid = Int32(nxt)
                continue
            }

            let pktNum = Int(frame.slices[0].frameNum)
            if frame.slices.count >= pktNum {
                // complete: emit
                appendEmittedFrame(for: nextPlayFid, frame: frame, to: &tags)
                videoFrames.removeValue(forKey: UInt32(nextPlayFid))
                let emitted = nextPlayFid
                nextPlayFid += 1
                if emitted > lastEmittedFid { lastEmittedFid = emitted }
                continue
            }

            // incomplete: wait (don't emit later frames).
            // 两种判据任一满足即认定它真的丢了：
            //   ① 之后又来了 sliceSpanBudget 个视频包 → 它的分片早该到了（与码率无关，见属性注释）
            //   ② 墙钟兜底（流卡住、不再来包时 ① 永不触发）
            let packetsSince = videoPacketCount - frame.firstSlicePacketIndex
            let elapsedMs = Int((now - frame.receivedAtNanos) / 1_000_000)
            if packetsSince > sliceSpanBudget || now - frame.receivedAtNanos > dropTimeoutNanos {
                HuyaLogger.log("HuyaProxy frame gap fid=\(nextPlayFid) expected \(pktNum) slices got \(frame.slices.count) "
                    + "\(frame.slices[0].isKeyframe ? "KEY" : "P/B")"
                    + " after \(packetsSince) pkts / \(elapsedMs)ms")
                videoFrames.removeValue(forKey: UInt32(nextPlayFid))
                droppedIncomplete += 1
                nextPlayFid += 1
                continue
            }
            break
        }
    }

    /// Emit one complete video frame (sort-merge + seq/FLV tag extraction + stats)
    private mutating func appendEmittedFrame(for fid: Int32, frame: PendingFrame, to tags: inout [HuyaFlvTag]) {
        let first = frame.slices[0]
        var sortedSlices = frame.slices
        sortedSlices.sort { $0.seqNum < $1.seqNum }
        let totalSize = sortedSlices.reduce(0) { $0 + $1.streamData.readableBytes }
        var merged = ByteBufferAllocator().buffer(capacity: totalSize)
        for s in sortedSlices { merged.writeImmutableBuffer(s.streamData) }

        let isKeyframe = first.isKeyframe
        let (seqTag, annexHeader, flvTag) = HuyaFrameExtractor.extract(merged: merged, isKeyframe: isKeyframe)

        if let st = seqTag {
            tags.append(HuyaFlvTag(
                type: 9, timestamp: 0, data: st,
                seq: first.seqNum, frameId: -1, isSeqHeader: true
            ))
        }
        if let ft = flvTag {
            tags.append(HuyaFlvTag(
                type: ft.type, timestamp: ft.timestamp, data: ft.data,
                seq: first.seqNum, frameId: Int32(fid),
                annexHeader: annexHeader
            ))
        }

        completedFrames += 1
        if lastEmittedFid >= 0 && fid > lastEmittedFid + 1 {
            let gap = fid - lastEmittedFid - 1
            if Int(gap) > maxFidGap { maxFidGap = Int(gap) }
        }
        // If a larger fid was still waiting when this one was emitted, it was
        // held up by its missing last slice (out-of-order/late)
        if videoFrames.keys.contains(where: { $0 > UInt32(fid) }) {
            lateCompletedFrames += 1
        }
    }

    private mutating func handleAudio(_ pkt: HuyaTupPacket) -> [HuyaFlvTag] {
        guard let parsed = HuyaSliceParser.parseAudio(payload: pkt.payload) else { return [] }
        let sd = parsed.streamData
        let sdBytes = sd.readableBytesView

        // 每个音频 slice 开头都带 AAC seq header，读记录前先跳过它
        // （官方 `readAacConfig`，vplayer 搜 `readAacConfig`）；seq header 只发一次
        var tags: [HuyaFlvTag] = []
        var pos = 0
        if sdBytes.count >= 19 && sdBytes[0] == 0x08 {
            let seqDataSize = (Int(sdBytes[1]) << 16) | (Int(sdBytes[2]) << 8) | Int(sdBytes[3])
            let seqTagTotal = 11 + seqDataSize + 4
            if seqTagTotal <= sdBytes.count {
                if !audioSeqSent {
                    let seqTag = sd.getSlice(at: 0, length: seqTagTotal)!
                    tags.append(HuyaFlvTag(type: 8, timestamp: 0, data: seqTag))
                    audioSeqSent = true
                }
                pos = seqTagTotal
            }
        }

        // records: [4B LE total_size][4B LE frameId][FLV audio tag]
        while pos + 8 <= sdBytes.count {
            let totalSize = Int(sd.getInteger(at: pos, endianness: .little, as: UInt32.self) ?? 0)
            let audioFrameId = sd.getInteger(at: pos + 4, endianness: .little, as: UInt32.self) ?? 0
            if totalSize < 8 || pos + totalSize > sdBytes.count { break }
            let flvTagData = sd.getSlice(at: pos + 8, length: totalSize - 8)!
            var flvTs = 0
            if totalSize - 8 >= 8 {
                let tagStart = pos + 8
                let tsLow = (Int(sdBytes[tagStart + 4]) << 16) | (Int(sdBytes[tagStart + 5]) << 8) | Int(sdBytes[tagStart + 6])
                let tsExt = Int(sdBytes[tagStart + 7])
                flvTs = (tsExt << 24) | tsLow
            }
            tags.append(HuyaFlvTag(
                type: 8, timestamp: flvTs, data: flvTagData,
                frameId: Int32(bitPattern: audioFrameId)
            ))
            pos += totalSize
        }
        return tags
    }
}
