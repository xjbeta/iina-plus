//
//  HuyaTupParser.swift
//  HuyaProxy
//
//  TUP 包的**流式**解析 —— 我们自己的逻辑（增量缓冲、跨 HTTP chunk）。
//  URI 常量与分片结构（官方移植部分）在 HuyaOfficialPort.swift。
//
//  SwiftNIO ByteBuffer based, avoids Data._Representation COW concurrency crash
//

import Foundation
import NIOCore

// MARK: - HuyaTupPacket

struct HuyaTupPacket: Sendable {
    let seq: UInt64
    let uri: UInt32
    let payload: ByteBuffer
}

// MARK: - HuyaTupParser (one shot parse)

enum HuyaTupParser {
    /// Parse TUP packets from a full .slice buffer
    static func parse(data: ByteBuffer) -> [HuyaTupPacket] {
        var buffer = data
        var packets: [HuyaTupPacket] = []

        while buffer.readableBytes >= 10 {
            let readerIndex = buffer.readerIndex
            let h = Int(buffer.getInteger(at: readerIndex + 8, endianness: .little, as: UInt16.self) ?? 0)
            if h < 10 {
                buffer.moveReaderIndex(forwardBy: 1)
                continue
            }
            if buffer.readableBytes < h {
                break
            }
            let seq = buffer.getInteger(at: readerIndex, endianness: .little, as: UInt64.self) ?? 0
            let uri = buffer.getInteger(at: readerIndex + 14, endianness: .little, as: UInt32.self) ?? 0
            let payload = buffer.getSlice(at: readerIndex + 10, length: h - 10) ?? ByteBuffer()
            packets.append(HuyaTupPacket(seq: seq, uri: uri, payload: payload))
            buffer.moveReaderIndex(forwardBy: h)
        }
        return packets
    }
}

// MARK: - HuyaTupStreamParser (streaming parse)

/// 增量 TUP 包解析（官方 `ProtoLinkFetch.pump`，vplayer 搜 `ProtoLinkFetch`）
///
/// `feed(data:)` parses complete packets; partial ones are buffered
/// across chunks (HTTP chunked transfer)
struct HuyaTupStreamParser: Sendable {
    private var buffer = ByteBuffer()
    private(set) var totalFed = 0
    private(set) var totalPackets = 0

    mutating func feed(_ data: ByteBuffer) -> [HuyaTupPacket] {
        buffer.writeBytes(data.readableBytesView)
        totalFed += data.readableBytes

        var packets: [HuyaTupPacket] = []

        while buffer.readableBytes >= 10 {
            let readerIndex = buffer.readerIndex

            // packet length at offset 8-10, LE
            let h = Int(buffer.getInteger(at: readerIndex + 8, endianness: .little, as: UInt16.self) ?? 0)
            if h < 10 {
                buffer.moveReaderIndex(forwardBy: 1)
                continue
            }
            // incomplete packet, wait for more data
            if buffer.readableBytes < h {
                break
            }

            let seq = buffer.getInteger(at: readerIndex, endianness: .little, as: UInt64.self) ?? 0
            let uri = buffer.getInteger(at: readerIndex + 14, endianness: .little, as: UInt32.self) ?? 0
            let payload = buffer.getSlice(at: readerIndex + 10, length: h - 10) ?? ByteBuffer()
            packets.append(HuyaTupPacket(seq: seq, uri: uri, payload: payload))

            buffer.moveReaderIndex(forwardBy: h)
        }

        if buffer.readerIndex > 0 {
            buffer.discardReadBytes()
        }

        totalPackets += packets.count
        return packets
    }

    mutating func reset() {
        buffer.clear()
        totalFed = 0
        totalPackets = 0
    }
}

// MARK: - First keyframe tracker (packet-header only)

    /// 只查头部的「首个完整视频关键帧」增量检测：关键帧标志在 slice 头里
    /// （frameType = seqNum&3，0 = 关键帧），无需解码 streamData；
    /// 帧完整 = 收到数 == pktNum(frameNum)。用于首片下载的自适应提前停止。
struct HuyaFirstKeyframeTracker: Sendable {
    private var parser = HuyaTupStreamParser()
    // frameId → (received count, expected pktNum, is keyframe)
    private var frames: [UInt32: (count: Int, pktNum: Int, isKey: Bool)] = [:]

    mutating func feed(_ data: ByteBuffer) -> Bool {
        for pkt in parser.feed(data) where pkt.uri == UInt32(HuyaProtoUri.video) {
            guard let v = HuyaSliceParser.parseVideo(payload: pkt.payload) else { continue }
            var entry = frames[v.frameId] ?? (count: 0, pktNum: Int(v.frameNum), isKey: v.isKeyframe)
            entry.count += 1
            entry.isKey = entry.isKey || v.isKeyframe
            frames[v.frameId] = entry
            if entry.isKey && entry.count >= entry.pktNum {
                return true
            }
        }
        return false
    }
}
