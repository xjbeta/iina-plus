//
//  HuyaOfficialPort.swift
//  HuyaKit
//
//  ★ 官方源码移植区 —— **上游改版时只需要改本文件** ★
//
//  集中所有「逐字段对齐官方 h5player」的代码（URI 常量 / codecType 翻译 / anticode 签名 /
//  TUP 分片结构 / FLV 重封装）。其余文件的流式部分是我们自己的逻辑，不受上游改版影响。
//
//  上游更新照 MEMORY.md §10；检索入口 §2；核对结果 §9。
//  ⚠️ 检索前先跑解混淆：python3 HuyaKit/doc/official/deobfuscate.py
//

import Foundation
import NIOCore
import CryptoSwift

// MARK: - URI 常量（官方 ProtoUri）

/// TUP 分片 URI（官方 ProtoUri 表；vplayer / mainlib / pcore 都有，直接搜数字）
enum HuyaProtoUri {
    static let video = 512291       // PP2pSliceVideoData（我们用这个）
    static let audio = 512035       // PP2pSliceAudioData V1（我们用这个）
    static let audioV2 = 517411     // PP2pSliceAudioDataV2（官方按协商版本用）
    static let audioV3 = 517667     // PP2pSliceAudioDataV3
    static let data = 511779        // PP2pSliceData（注意 ControlData = 1024547 与它不同）
}

// MARK: - codecType 翻译（官方 _getCodec / getIsH265 / isSupportedH265）

/// 官方 codecType 翻译（vplayer，搜 `_getCodec` / `getIsH265` / `isSupportedH265`）
enum HuyaOfficialCodec {
    /// 族参数：官方 `_getCodec(codecFamily, bitrate)`
    static let familyH264 = 3
    static let familyH265 = 2
    /// `getCodec(H265, 0)` 的结果：0 码率 HEVC 档的私有胶囊，仅官方 wasm265 解码器可解
    static let h265Capsule = 2

    /// 官方 `_getCodec`：iBitRate → URL 里的 codecType
    static func getCodec(codecFamily: Int, bitrate: Int) -> Int {
        var i = bitrate
        if i == 0 {
            switch codecFamily {
            case familyH264: i = 0
            case familyH265: i = 2
            default: i = 4 // AV1
            }
        } else if i % 100 == 0 {
            switch codecFamily {
            case familyH264: i = i > 8000 ? 1000 + (i / 100) : 400 + (i / 100)
            case familyH265: i = i > 8000 ? 4000 + (i / 100) : 500 + (i / 100)
            default: i = 9000 + (i / 100)
            }
        } else if i % 10 == 0 {
            switch codecFamily {
            case familyH264: i = 20000 + (i / 10)
            case familyH265: i = 30000 + (i / 10)
            default: i = 40000 + (i / 10)
            }
        }
        return i
    }

    /// 官方 `getIsH265`：1/4/6/8 为 H.265
    static func isH265CodecType(_ codecType: Int) -> Bool {
        codecType == 1 || codecType == 4 || codecType == 6 || codecType == 8
    }

    /// 官方 `isSupportedH265`（**逐档**判族，与房间顶层 `codecType` 无关；`iIsHEVCSupport` 是线路级）：
    /// `(iIsHEVCSupport > 0 && iHEVCBitRate >= 0) || (isH265(iCodecType) && iBitRate === 0)`
    /// 踩坑见 MEMORY.md §3.3 / §5.1
    static func isH265Gear(
        iBitRate: Int,
        iCodecType: Int,
        iHEVCBitRate: Int,
        isHEVCSupport: Int
    ) -> Bool {
        (isHEVCSupport > 0 && iHEVCBitRate >= 0)
            || (isH265CodecType(iCodecType) && iBitRate == 0)
    }
}

// MARK: - anticode 签名（官方 getAnticode）

/// 官方 `getAnticode` 的签名实现（vplayer，标识符 base64 混淆；解混淆后搜 `getAnticode` / `parseAnticode`）
enum HuyaOfficialSign {
    /// 中间哈希的输入：`md5("{seqid}|{ctype}|{platform}")`
    static let ctype = "huya_webh5"
    static let platform = "web"
    /// 游客 uid。官方取浏览器全局 `D.a.uid`；我们无登录上下文，用 0。
    static let guestUid = 0

    static func md5Hex(_ s: String) -> String {
        Data(s.utf8).md5().map { String(format: "%02x", $0) }.joined()
    }

    /// 官方 fm 模板 `DWq8BcJ3h6DJt6TY_$0_$1_$2_$3` 的填法：
    /// `$0`=uid、`$1`=streamName、`$2`=md5(seqid|ctype|platform)、`$3`=wsTime，再 md5；
    /// `seqid = Number(uid) + Date.now()`（数值相加）。
    /// 与官方的差异及实测见 MEMORY.md §9.2
    static func calcWsSecret(
        fmTemplate: String,
        streamName: String,
        wsTime: String,
        uid: Int = guestUid,
        ctype: String = ctype,
        platform: String = platform,
        nowMs: Int
    ) -> String {
        let seqid = uid + nowMs
        let mid = md5Hex("\(seqid)|\(ctype)|\(platform)")
        var filled = fmTemplate.replacingOccurrences(of: "$0", with: "\(uid)")
        filled = filled.replacingOccurrences(of: "$1", with: streamName)
        filled = filled.replacingOccurrences(of: "$2", with: mid)
        filled = filled.replacingOccurrences(of: "$3", with: wsTime)
        return md5Hex(filled)
    }
}

// MARK: - TUP 分片结构（官方 PP2pSliceVideoData / PP2pSliceAudioData）

/// 官方 `PP2pSliceVideoData` 的 unmarshall（旧结构，与 `dMod=mseh-25` 配套）
/// 字段顺序：`checkSum(1) / seqNum(2) / frameNum(2) / frameId(4) / configCount(4) + {key(1),val(4)}×n / streamData(16位长度)`
struct HuyaVideoSlice: Sendable {
    let checkSum: UInt8
    let seqNum: UInt16
    let frameNum: UInt16
    let frameId: UInt32
    let config: [UInt8: UInt32]
    let streamData: ByteBuffer

    /// 帧类型：0=I, 1=P, 2=B
    var frameType: Int { Int(seqNum) & 3 }
    var isKeyframe: Bool { frameType == 0 }
}

/// 官方 `PP2pSliceAudioData` V1 的 unmarshall：`checkSum(1) / codecType(2) / streamData(16位长度)`
struct HuyaAudioSlice: Sendable {
    let checkSum: UInt8
    let codecType: UInt16
    let streamData: ByteBuffer
}

/// TUP/JCE 小端读取器；init 时读掉 10 字节头 `length(4) + uri(4) + resCode(2)`
struct HuyaJceReader {
    private var buffer: ByteBuffer
    let length: UInt32
    let uri: UInt32
    let resCode: UInt16

    var pos: Int { buffer.readerIndex }

    init(buffer: ByteBuffer) {
        self.buffer = buffer
        self.length = self.buffer.readInteger(endianness: .little, as: UInt32.self) ?? 0
        self.uri = self.buffer.readInteger(endianness: .little, as: UInt32.self) ?? 0
        self.resCode = self.buffer.readInteger(endianness: .little, as: UInt16.self) ?? 0
    }

    mutating func readUInt8() -> UInt8 { buffer.readInteger(as: UInt8.self) ?? 0 }
    mutating func readUInt16() -> UInt16 { buffer.readInteger(endianness: .little, as: UInt16.self) ?? 0 }
    mutating func readUInt32() -> UInt32 { buffer.readInteger(endianness: .little, as: UInt32.self) ?? 0 }
    mutating func readUInt64() -> UInt64 { buffer.readInteger(endianness: .little, as: UInt64.self) ?? 0 }

    /// uint16 长度前缀的字节数组
    mutating func readUInt8Array() -> ByteBuffer {
        let length = Int(readUInt16())
        return buffer.readSlice(length: length) ?? ByteBuffer()
    }
}

/// 分片解析（字段顺序对齐官方 marshall/unmarshall）
enum HuyaSliceParser {
    /// 官方 `PP2pSliceVideoData`（URI 512291）
    static func parseVideo(payload: ByteBuffer) -> HuyaVideoSlice? {
        var reader = HuyaJceReader(buffer: payload)
        let checkSum = reader.readUInt8()
        let seqNum = reader.readUInt16()
        let frameNum = reader.readUInt16()
        let frameId = reader.readUInt32()

        let configCount = Int(reader.readUInt32())
        var config: [UInt8: UInt32] = [:]
        for _ in 0..<configCount {
            let key = reader.readUInt8()
            let val = reader.readUInt32()
            config[key] = val
        }

        let streamData = reader.readUInt8Array()
        return HuyaVideoSlice(
            checkSum: checkSum,
            seqNum: seqNum,
            frameNum: frameNum,
            frameId: frameId,
            config: config,
            streamData: streamData
        )
    }

    /// 官方 `PP2pSliceAudioData` V1（URI 512035）
    static func parseAudio(payload: ByteBuffer) -> HuyaAudioSlice? {
        var reader = HuyaJceReader(buffer: payload)
        let checkSum = reader.readUInt8()
        let codecType = reader.readUInt16()
        let streamData = reader.readUInt8Array()
        return HuyaAudioSlice(checkSum: checkSum, codecType: codecType, streamData: streamData)
    }
}

// MARK: - FLV 重封装（官方 hevcFindNextStartCode / getExtradata265 / hvc1）

/// 官方 FLV/HEVC 侧移植（vplayer，搜 `hevcFindNextStartCode` / `getExtradata265` / `hvc1` / `NAL_VPS`）
enum HuyaOfficialFlv {
    /// HEVC NAL 类型（官方 `NAL_VPS` / `NAL_SPS` / `NAL_PPS`）
    static let nalVPS = 32
    static let nalSPS = 33
    static let nalPPS = 34

    /// 官方 `hevcFindNextStartCode`：按 start code 切 NALU，类型取 `(126 & b) >> 1`
    static func parseHevcAnnexB(_ data: ByteBuffer) -> [(naluType: Int, naluData: ByteBuffer)] {
        let bytes = data.readableBytesView
        var nalus: [ByteBuffer] = []
        var naluStart: Int? = nil
        var i = 0

        while i < bytes.count {
            if i + 3 <= bytes.count && bytes[i] == 0 && bytes[i+1] == 0 && bytes[i+2] == 1 {
                if let start = naluStart {
                    nalus.append(data.getSlice(at: start, length: i - start)!)
                }
                naluStart = i + 3
                i += 3
                continue
            }
            if i + 4 <= bytes.count && bytes[i] == 0 && bytes[i+1] == 0 && bytes[i+2] == 0 && bytes[i+3] == 1 {
                if let start = naluStart {
                    nalus.append(data.getSlice(at: start, length: i - start)!)
                }
                naluStart = i + 4
                i += 4
                continue
            }
            i += 1
        }

        if let start = naluStart, start < bytes.count {
            nalus.append(data.getSlice(at: start, length: bytes.count - start)!)
        }

        return nalus.compactMap { nalu -> (naluType: Int, naluData: ByteBuffer)? in
            let naluBytes = nalu.readableBytesView
            guard naluBytes.count >= 2 else { return nil }
            let naluType = Int((naluBytes[0] >> 1) & 0x3F)
            return (naluType: naluType, naluData: nalu)
        }
    }

    /// 官方 `getExtradata265`：构造 hvcC（22 字节头 + VPS/SPS/PPS 三数组，每 NALU 前 2 字节 BE 长度）
    static func buildHvcc(vps: [ByteBuffer], sps: [ByteBuffer], pps: [ByteBuffer]) -> ByteBuffer? {
        guard let firstSps = sps.first else { return nil }
        let spsBytes = firstSps.readableBytesView
        guard spsBytes.count >= 15 else { return nil }

        var hvcc = ByteBufferAllocator().buffer(capacity: 1024)
        hvcc.writeInteger(UInt8(1))                    // [0] configurationVersion = 1
        hvcc.writeBytes(spsBytes[3..<4])               // [1] profile_space + tier + profile_idc
        hvcc.writeBytes(spsBytes[4..<8])               // [2:6] profile_compatibility_flags
        hvcc.writeBytes(spsBytes[8..<14])              // [6:12] constraint_indicator_flags
        hvcc.writeBytes(spsBytes[14..<15])             // [12] general_level_idc
        hvcc.writeBytes([0xf0, 0x00])                  // [13:15] min_spatial_segmentation_idc
        hvcc.writeInteger(UInt8(0xfc))                 // [15] parallelismType
        hvcc.writeInteger(UInt8(0xfd))                 // [16] chroma_format_idc
        hvcc.writeInteger(UInt8(0xf8))                 // [17] bit_depth_luma_minus8
        hvcc.writeInteger(UInt8(0xf8))                 // [18] bit_depth_chroma_minus8
        hvcc.writeBytes([0x00, 0x00])                  // [19:21] avg_frame_rate = 0
        hvcc.writeInteger(UInt8(0x0f))                 // [21] length_size_minus_one(3)

        hvcc.writeInteger(UInt8(3))                    // numOfArrays = 3
        for (type, list) in [(nalVPS, vps), (nalSPS, sps), (nalPPS, pps)] {
            hvcc.writeInteger(UInt8(0xa0 | UInt8(type)))
            hvcc.writeInteger(UInt16(list.count), endianness: .big)
            for nalu in list {
                hvcc.writeInteger(UInt16(nalu.readableBytes), endianness: .big)
                hvcc.writeImmutableBuffer(nalu)
            }
        }
        return hvcc
    }

    /// 官方 `hvc1()`：hvcC → Enhanced FLV video tag（4CC `hvc1`）
    ///
    /// FFmpeg 6.1+ 的 flvdec 只认 4CC `hvc1`，标准 codecId=12 需要 FFmpeg 8.1+。
    /// byte0 = 0x90 = IsEx(bit7) | FrameType(key) | PacketType(0=seq)，bytes1-4 = `hvc1`
    static func buildHevcSeqTag(hvccData: ByteBuffer) -> ByteBuffer {
        var tagData = ByteBufferAllocator().buffer(capacity: 6 + hvccData.readableBytes)
        tagData.writeBytes([0x90, 0x68, 0x76, 0x63, 0x31])
        tagData.writeImmutableBuffer(hvccData)
        return wrapFlvVideoTag(tagData: tagData, timestamp: 0)
    }

    /// AVCDecoderConfigurationRecord → FLV video tag（H.264 seq header）
    static func buildAvcSeqTag(seqHeaderData: ByteBuffer) -> ByteBuffer {
        var tagData = ByteBufferAllocator().buffer(capacity: 5 + seqHeaderData.readableBytes)
        tagData.writeBytes([0x17, 0x00, 0x00, 0x00, 0x00]) // keyframe|AVC + seq header
        tagData.writeImmutableBuffer(seqHeaderData)
        return wrapFlvVideoTag(tagData: tagData, timestamp: 0)
    }

    /// AnnexB → 4 字节 BE 长度前缀
    ///
    /// ⚠️ **不能删**：虎牙 payload 是 AnnexB，而我们的 FLV 打成 `hvc1`（规范要求 length-prefixed）。
    /// 实测去掉它 ffmpeg 立刻报 `Invalid NAL unit size`，流完全不可解（见 MEMORY.md §4.3）。
    static func annexBToLengthPrefixed(_ data: ByteBuffer) -> ByteBuffer {
        let nalus = parseHevcAnnexB(data)
        var out = ByteBufferAllocator().buffer(capacity: data.readableBytes)
        for (_, nalu) in nalus {
            out.writeInteger(UInt32(nalu.readableBytes), endianness: .big)
            out.writeImmutableBuffer(nalu)
        }
        return out
    }

    /// FLV video tag 外壳（tagType/dataSize/timestamp/streamId/prevTagSize）
    private static func wrapFlvVideoTag(tagData: ByteBuffer, timestamp: Int) -> ByteBuffer {
        let dataSize = tagData.readableBytes
        var tag = ByteBufferAllocator().buffer(capacity: 11 + dataSize + 4)
        tag.writeInteger(UInt8(0x09)) // tagType = 9 (video)
        tag.writeInteger(UInt8((dataSize >> 16) & 0xFF))
        tag.writeInteger(UInt8((dataSize >> 8) & 0xFF))
        tag.writeInteger(UInt8(dataSize & 0xFF))
        let ts = UInt32(timestamp & 0xFFFFFFFF)
        tag.writeInteger(UInt8((ts >> 16) & 0xFF))
        tag.writeInteger(UInt8((ts >> 8) & 0xFF))
        tag.writeInteger(UInt8(ts & 0xFF))
        tag.writeInteger(UInt8((ts >> 24) & 0xFF))
        tag.writeBytes([0x00, 0x00, 0x00]) // streamId
        tag.writeImmutableBuffer(tagData)
        tag.writeInteger(UInt32(11 + dataSize), endianness: .big) // prevTagSize
        return tag
    }
}

// MARK: - 非官方移植（我们自己的 FLV 时间戳改写）

/// FLV tag 时间戳改写（bytes 4-7 大端）。**这段是我们自己的逻辑**，不是官方移植。
///
/// H.264（codecId=7）清 cts（data[13:16]）让 mpv 的 PTS = DTS 保持单调；
/// H.265 保留原 cts（与官方一致，MSE 下 B 帧重排需要）。
enum HuyaFlvTimestamp {
    static func rewrite(_ tagData: ByteBuffer, newTs: Int) -> ByteBuffer {
        var out = tagData
        let ts = UInt32(newTs & 0xFFFFFFFF)
        out.setInteger(UInt8((ts >> 16) & 0xFF), at: 4)
        out.setInteger(UInt8((ts >> 8) & 0xFF), at: 5)
        out.setInteger(UInt8(ts & 0xFF), at: 6)
        out.setInteger(UInt8((ts >> 24) & 0xFF), at: 7)

        let tagType = out.getInteger(at: 0, as: UInt8.self) ?? 0
        let frameCodec = out.getInteger(at: 11, as: UInt8.self) ?? 0
        let packetType = out.getInteger(at: 12, as: UInt8.self) ?? 0
        if out.readableBytes >= 16 && tagType == 9 && packetType == 1 && (frameCodec & 0x0F) == 7 {
            out.setInteger(UInt8(0), at: 13)
            out.setInteger(UInt8(0), at: 14)
            out.setInteger(UInt8(0), at: 15)
        }
        return out
    }
}
