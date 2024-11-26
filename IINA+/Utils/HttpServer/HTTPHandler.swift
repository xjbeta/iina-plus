//
//  HTTPHandler.swift
//  IINA+
//
//  Created by xjbeta on 2024/11/25.
//  Copyright © 2024 xjbeta. All rights reserved.
//



import Foundation
@preconcurrency import NIO
@preconcurrency import NIOHTTP1
@preconcurrency import NIOWebSocket


@preconcurrency
final class HTTPHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    
    private var currentURL = ""
    private var parameters = [String: String]()
    private var currentMethod: HTTPMethod = .UNBIND
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let reqPart = self.unwrapInboundIn(data)
        switch reqPart {
        case .head(let head):
            let u = head.uri
            let up = u.split(separator: "?", maxSplits: 1).map(String.init)
            guard up.count == 2 else {
                currentURL = ""
                currentMethod = .UNBIND
                parameters = [:]
                return
            }
            currentURL = up[0]
            currentMethod = head.method
            parameters = parameters(up[1])
        case .body:
            break
        case .end:
            Task {
                await handleRequest(context: context)
            }
        }
    }
    
    
    private func handleRequest(context: ChannelHandlerContext) async {
        switch (currentURL, currentMethod) {
        case ("/video/danmakuurl", .POST):
            guard let url = parameters["url"],
                  let json = try? await self.decode(url),
                  let key = json.videos.first?.key,
                  let data = json.danmakuUrl(key)?.data(using: .utf8) else {
                sendBadRequest(context: context)
                return
            }
            sendResponse(context: context, bodyData: data)
        case ("/video/iinaurl", .POST):
            var type = IINAUrlType.normal
            if let tStr = parameters["type"],
               let t = IINAUrlType(rawValue: tStr) {
                type = t
            }
            
            guard let url = parameters["url"],
                  let json = try? await self.decode(url),
                  let key = json.videos.first?.key,
                  let data = json.iinaURLScheme(key, type: type)?.data(using: .utf8) else {
                sendBadRequest(context: context)
                return
            }
            sendResponse(context: context, bodyData: data)
        case ("/video", .GET):
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let key = parameters["key"] ?? ""
            
            guard let url = parameters["url"],
                  let json = try? await self.decode(url, key: key),
                  let data = parameters["pluginAPI"] == nil ? try? encoder.encode(json) : json.iinaPlusArgsString(key)?.data(using: .utf8) else {
                sendBadRequest(context: context)
                return
            }
            sendResponse(context: context, bodyData: data)
        case (let url, .GET) where url.starts(with: "/dash/"):
            break
        default:
            sendBadRequest(context: context)
        }
    }
    
    private func parameters(_ string: String) -> [String: String] {
        let requestBodys = string.split(separator: "&")
        var parameters = [String: String]()
        requestBodys.forEach {
            let kv = $0.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            guard kv.count == 2 else { return }
            parameters[kv[0]] = kv[1].removingPercentEncoding
        }
        return parameters
    }
    
    private func decode(_ url: String, key: String = "") async throws -> YouGetJSON? {
        let videoDecoder = VideoDecoder()
        var json = try await videoDecoder.decodeUrl(url)
        json = try await videoDecoder.prepareVideoUrl(json, key)
        return json
    }
    

    private func sendResponse(context: ChannelHandlerContext, bodyData: Data) {
        context.eventLoop.execute {
            let responseHeaders: HTTPHeaders
            
            var newHeaders = HTTPHeaders()
            newHeaders.add(name: "Content-Length", value: "\(bodyData.count)")
            newHeaders.add(name: "Connection", value: "close")
            responseHeaders = newHeaders
            
            let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: responseHeaders)
            var buffer = context.channel.allocator.buffer(capacity: bodyData.count)
            buffer.writeBytes(bodyData)
            
            context.write(self.wrapOutboundOut(.head(head)), promise: nil)
            context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        }
    }
    
    private func sendBadRequest(context: ChannelHandlerContext) {
        context.eventLoop.execute {
            let headers = HTTPHeaders([("Connection", "close"), ("Content-Length", "0")])
            let head = HTTPResponseHead(version: .http1_1, status: .badRequest, headers: headers)
            context.write(self.wrapOutboundOut(.head(head)), promise: nil)
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        }
    }
}
