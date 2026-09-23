//
//  HTTPHandler.swift
//  IINA+
//
//  Created by xjbeta on 2024/11/25.
//  Copyright © 2024 xjbeta. All rights reserved.
//



import Foundation
import Alamofire
import NIO
import NIOHTTP1
import HuyaKit

enum HTTPHandler {
    private final class DouyuClientState: @unchecked Sendable {
        private let lock = NSLock()
        private var closed = false

        var isClosed: Bool { lock.withLock { closed } }
        func markClosed() { lock.withLock { closed = true } }
    }

    static func handleChannel(
        _ channel: NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>
    ) async throws {
        try await channel.executeThenClose { inbound, outbound in
            var currentURL = ""
            var parameters = [String: String]()
            var currentMethod: NIOHTTP1.HTTPMethod = .UNBIND

            for try await part in inbound {
                switch part {
                case .head(let head):
                    let u = head.uri
                    let up = u.split(separator: "?", maxSplits: 1).map(String.init)

                    if up.count == 2 {
                        currentURL = up[0]
                        currentMethod = head.method
                        parameters = parseParameters(up[1])
                    } else if up.count == 1, head.method == .GET {
                        currentURL = up[0]
                        currentMethod = head.method
                    } else {
                        currentURL = ""
                        currentMethod = .UNBIND
                        parameters = [:]
                    }

                    Log("HTTP \(head.method) \(currentURL)")

                case .body:
                    break

                case .end:
                    if currentURL.hasPrefix("/huya/") {
                        // Long-lived stream; end when client disconnects (Connection: close)
                        try await handleStreamRequest(
                            url: currentURL,
                            method: currentMethod,
                            parameters: parameters,
                            outbound: outbound,
                            closeFuture: channel.channel.closeFuture
                        )
                        return
                    }
                    if currentURL.hasPrefix("/douyu/") {
                        try await handleRequest(
                            url: currentURL,
                            method: currentMethod,
                            parameters: parameters,
                            outbound: outbound,
                            closeFuture: channel.channel.closeFuture
                        )
                        return
                    }
                    try await handleRequest(
                        url: currentURL,
                        method: currentMethod,
                        parameters: parameters,
                        outbound: outbound
                    )
                }
            }
        }
    }

    /// Race the stream loop against the client disconnect (channel.closeFuture,
    /// event-driven, no polling): mpv close -> TCP EOF -> channel close
    private static func handleStreamRequest(
        url: String,
        method: NIOHTTP1.HTTPMethod,
        parameters: [String: String],
        outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>,
        closeFuture: EventLoopFuture<Void>
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await handleRequest(url: url, method: method, parameters: parameters, outbound: outbound)
            }
            group.addTask {
                // client disconnect -> channel close -> closeFuture completes
                try await closeFuture.get()
                throw ClientDisconnectedError()
            }
            do {
                try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    // MARK: - Request Handling

    private static func handleRequest(
        url: String,
        method: NIOHTTP1.HTTPMethod,
        parameters: [String: String],
        outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>,
        closeFuture: EventLoopFuture<Void>? = nil
    ) async throws {
        switch (url, method) {
        case ("/video/danmakuurl", .POST):
            guard let url = parameters["url"],
                  let json = try? await decode(url),
                  let key = json.videos.first?.key,
                  let data = json.danmakuUrl(key)?.data(using: .utf8) else {
                try await sendBadRequest(outbound: outbound)
                return
            }
            try await sendResponse(outbound: outbound, bodyData: data)

        case ("/video/iinaurl", .POST):
            var type = IINAUrlType.normal
            if let tStr = parameters["type"],
               let t = IINAUrlType(rawValue: tStr) {
                type = t
            }

            guard let url = parameters["url"],
                  let json = try? await decode(url),
                  let key = json.videos.first?.key,
                  let data = json.iinaURLScheme(key, type: type)?.data(using: .utf8) else {
                try await sendBadRequest(outbound: outbound)
                return
            }
            try await sendResponse(outbound: outbound, bodyData: data)

        case ("/video", .GET):
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let key = parameters["key"] ?? ""

            guard let url = parameters["url"],
                  let json = try? await decode(url, key: key),
                  let data = parameters["pluginAPI"] == nil ? try? encoder.encode(json) : json.iinaPlusArgsString(key)?.data(using: .utf8) else {
                try await sendBadRequest(outbound: outbound)
                return
            }
            try await sendResponse(outbound: outbound, bodyData: data)

        case ("/danmaku/test.htm", .GET):
            guard let path = Bundle.main.path(forResource: "test", ofType: "htm"),
                  let data = FileManager.default.contents(atPath: path) else { return }
            try await sendResponse(outbound: outbound, bodyData: data)

        case (_, .GET) where url.hasPrefix("/huya/"):
            // Huya .slice proxy (HuyaKit): FLV relay。
            // `.ts` 路线已于 2026-09-15 废弃 —— 实测 FLV 容器在 mpv/ffmpeg 下 0 错误解码，
            // 原始阻塞点是超分档(codecType=2)的私有 slice NAL，与容器无关，且已被
            // 「胶囊档回退同名 H.264/H.265 变体」绕过，故不需要 TS 复用。
            guard let roomId = URL(string: url)?.deletingPathExtension().lastPathComponent,
                  !roomId.isEmpty else {
                try await sendBadRequest(outbound: outbound)
                return
            }
            try await HuyaProxyServer.shared.handleHuyaRequest(
                roomId: roomId,
                outbound: outbound
            )

        case (_, .GET) where url.hasPrefix("/douyu/"):
            guard let roomIdString = URL(string: url)?.deletingPathExtension().lastPathComponent,
                  let roomId = Int(roomIdString),
                  let rate = Int(parameters["rate"] ?? "0"), rate >= 0,
                  let line = Int(parameters["line"] ?? "0"), line >= 0 else {
                try await sendBadRequest(outbound: outbound)
                return
            }
            try await handleDouyuStreamRequest(
                roomId: roomId,
                rate: rate,
                line: line,
                outbound: outbound,
                closeFuture: closeFuture
            )

        case (_, .GET) where url.starts(with: "/video.mp4"):
            guard let path = Bundle.main.path(forResource: "empty", ofType: "m4a"),
                  let data = FileManager.default.contents(atPath: path) else { return }
            try await sendResponse(outbound: outbound, bodyData: data)

        default:
            try await sendBadRequest(outbound: outbound)
        }
    }

    // MARK: - Helpers

    private static func handleDouyuStreamRequest(
        roomId: Int,
        rate: Int,
        line: Int,
        outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>,
        closeFuture: EventLoopFuture<Void>?
    ) async throws {
        let clientState = DouyuClientState()
        closeFuture?.whenComplete { _ in clientState.markClosed() }
        let playback: (streams: [(String, Stream)], cdns: [String], selectedCDN: String)
        do {
            playback = try await Processes.shared.videoDecoder.douyu.getDouyuPlayback(roomId, rate: rate)
        } catch {
            Log("Douyu stream URL refresh failed for room \(roomId)")
            try await sendBadGateway(outbound: outbound)
            return
        }

        let alternatives = playback.cdns.filter { $0 != playback.selectedCDN }
        for cdn in [""] + alternatives {
            if Task.isCancelled || clientState.isClosed { return }
            let streams: [(String, Stream)]
            if cdn.isEmpty {
                streams = playback.streams
            } else {
                guard let refreshed = try? await Processes.shared.videoDecoder.douyu.getDouyuUrl(roomId, rate: rate, cdn: cdn) else { continue }
                streams = refreshed
            }
            guard let stream = streams.first(where: { $0.1.rate == rate })?.1 else { continue }
            let urls = ([stream.url].compactMap { $0 } + stream.src).filter { !$0.isEmpty }
            guard let selectedURL = urls.first else { continue }
            let preferredURL = urls.indices.contains(line) ? urls[line] : selectedURL
            for url in [preferredURL] + urls.filter({ $0 != preferredURL }) {
                if Task.isCancelled || clientState.isClosed { return }
                guard let upstreamURL = URL(string: url) else { continue }
                if await relayDouyuStream(
                    upstreamURL: upstreamURL,
                    roomId: roomId,
                    outbound: outbound,
                    closeFuture: closeFuture
                ) { return }
            }
        }
        if !Task.isCancelled && !clientState.isClosed {
            try await sendBadGateway(outbound: outbound)
        }
    }

    private static func relayDouyuStream(
        upstreamURL: URL,
        roomId: Int,
        outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>,
        closeFuture: EventLoopFuture<Void>?
    ) async -> Bool {
        var request = URLRequest(url: upstreamURL)
        request.timeoutInterval = 20
        request.setValue("bytes=0-", forHTTPHeaderField: "Range")
        request.setValue("https://www.douyu.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let streamRequest = AF.streamRequest(request).validate(statusCode: 200..<300)
        closeFuture?.whenComplete { _ in streamRequest.cancel() }
        let streamTask = streamRequest.streamTask()
        var sentHead = false
        var firstData = Data()

        do {
            try await withTaskCancellationHandler {
                streamLoop: for try await streamEvent in streamTask.streamingData() {
                    try Task.checkCancellation()
                    switch streamEvent.event {
                    case .stream(.success(let data)):
                        var chunk = data
                        if !sentHead {
                            firstData.append(data)
                            guard firstData.count >= 3 else { continue }
                            guard firstData.starts(with: [0x46, 0x4c, 0x56]) else {
                                Log("Douyu relay received non-FLV data from \(upstreamURL.host ?? "unknown") (HTTP \(streamRequest.response?.statusCode ?? 0), prefix \(firstData.prefix(8).map { String(format: "%02x", $0) }.joined()))")
                                streamRequest.cancel()
                                break streamLoop
                            }
                            let headers = NIOHTTP1.HTTPHeaders([
                                ("Content-Type", "video/x-flv"),
                                ("Cache-Control", "no-cache"),
                                ("Connection", "close")
                            ])
                            let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
                            try await outbound.write(.head(head))
                            sentHead = true
                            chunk = firstData
                            firstData = Data()
                        }
                        var buffer = ByteBufferAllocator().buffer(capacity: chunk.count)
                        buffer.writeBytes(chunk)
                        try await outbound.write(.body(buffer))

                    case .stream(.failure(let error)):
                        throw error

                    case .complete(let completion):
                        if let error = completion.error { throw error }
                    }
                }
            } onCancel: {
                streamRequest.cancel()
            }
        } catch {
            if !Task.isCancelled, (error as? AFError)?.isExplicitlyCancelledError != true {
                Log("Douyu stream relay ended for room \(roomId) from \(upstreamURL.host ?? "unknown") (HTTP \(streamRequest.response?.statusCode ?? 0)): \(type(of: error))")
            }
        }
        streamRequest.cancel()

        if sentHead {
            try? await outbound.write(.end(nil))
        }
        return sentHead
    }

    private static func decode(_ url: String, key: String = "") async throws -> YouGetJSON? {
        var json = try await Processes.shared.videoDecoder.decodeUrl(url)
        json = try await Processes.shared.videoDecoder.prepareVideoUrl(json, key)
        return json
    }

    private static func sendResponse(
        outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>,
        bodyData: Data
    ) async throws {
        var newHeaders = NIOHTTP1.HTTPHeaders()
        newHeaders.add(name: "Content-Length", value: "\(bodyData.count)")
        newHeaders.add(name: "Connection", value: "close")

        let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: newHeaders)
        var buffer = ByteBufferAllocator().buffer(capacity: bodyData.count)
        buffer.writeBytes(bodyData)

        try await outbound.write(contentsOf: [
            .head(head),
            .body(buffer),
            .end(nil),
        ])
    }

    private static func parseParameters(_ string: String) -> [String: String] {
        let requestBodys = string.split(separator: "&")
        var parameters = [String: String]()
        requestBodys.forEach {
            let kv = $0.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            guard kv.count == 2 else { return }
            parameters[kv[0]] = kv[1].removingPercentEncoding
        }
        return parameters
    }

    private static func sendBadRequest(
        outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>
    ) async throws {
        let headers = NIOHTTP1.HTTPHeaders([("Connection", "close"), ("Content-Length", "0")])
        let head = HTTPResponseHead(version: .http1_1, status: .badRequest, headers: headers)
        try await outbound.write(contentsOf: [
            .head(head),
            .end(nil),
        ])
    }

    private static func sendBadGateway(
        outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>
    ) async throws {
        let headers = NIOHTTP1.HTTPHeaders([("Connection", "close"), ("Content-Length", "0")])
        let head = HTTPResponseHead(version: .http1_1, status: .badGateway, headers: headers)
        try await outbound.write(contentsOf: [
            .head(head),
            .end(nil),
        ])
    }
}
