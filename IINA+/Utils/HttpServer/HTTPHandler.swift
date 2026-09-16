//
//  HTTPHandler.swift
//  IINA+
//
//  Created by xjbeta on 2024/11/25.
//  Copyright © 2024 xjbeta. All rights reserved.
//



import Foundation
import NIO
import NIOHTTP1
import HuyaKit

enum HTTPHandler {

    static func handleChannel(
        _ channel: NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>
    ) async throws {
        try await channel.executeThenClose { inbound, outbound in
            var currentURL = ""
            var parameters = [String: String]()
            var currentMethod: HTTPMethod = .UNBIND

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
                        try await handleHuyaStreamRequest(
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
    private static func handleHuyaStreamRequest(
        url: String,
        method: HTTPMethod,
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
        method: HTTPMethod,
        parameters: [String: String],
        outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>
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

        case (_, .GET) where url.starts(with: "/video.mp4"):
            guard let path = Bundle.main.path(forResource: "empty", ofType: "m4a"),
                  let data = FileManager.default.contents(atPath: path) else { return }
            try await sendResponse(outbound: outbound, bodyData: data)

        default:
            try await sendBadRequest(outbound: outbound)
        }
    }

    // MARK: - Helpers

    private static func decode(_ url: String, key: String = "") async throws -> YouGetJSON? {
        var json = try await Processes.shared.videoDecoder.decodeUrl(url)
        json = try await Processes.shared.videoDecoder.prepareVideoUrl(json, key)
        return json
    }

    private static func sendResponse(
        outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>,
        bodyData: Data
    ) async throws {
        var newHeaders = HTTPHeaders()
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
        let headers = HTTPHeaders([("Connection", "close"), ("Content-Length", "0")])
        let head = HTTPResponseHead(version: .http1_1, status: .badRequest, headers: headers)
        try await outbound.write(contentsOf: [
            .head(head),
            .end(nil),
        ])
    }
}
