//
//  WebSocketDanmakuHandler.swift
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
final class DanmakuWebSocketHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame
    
    private var awaitingClose: Bool = false
    
    
    private var contextList = [ChannelHandlerContext]()
    private var connectedItems = [DanmakuWS]()
    private var danmakus = [Danmaku]()
    
    
    public func handlerAdded(context: ChannelHandlerContext) {
        websocketConnected(context)
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = self.unwrapInboundIn(data)
        
        switch frame.opcode {
        case .connectionClose:
            self.receivedClose(context: context, frame: frame)
        case .ping:
            self.pong(context: context, frame: frame)
        case .text:
            var data = frame.unmaskedData
            let text = data.readString(length: data.readableBytes) ?? ""
            Task {
                await websocketReceived(context, text: text)
            }
        case .binary, .continuation, .pong:
            // We ignore these frames.
            break
        default:
            // Unknown frames are errors.
            self.closeOnError(context: context)
        }
    }
    
    public func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }
    
    private func receivedClose(context: ChannelHandlerContext, frame: WebSocketFrame) {
        // Handle a received close frame. In websockets, we're just going to send the close
        // frame and then close, unless we already sent our own close frame.
        if awaitingClose {
            // Cool, we started the close and were waiting for the user. We're done.
            context.close(promise: nil)
        } else {
            // This is an unsolicited close. We're going to send a response frame and
            // then, when we've sent it, close up shop. We should send back the close code the remote
            // peer sent us, unless they didn't send one at all.
            var data = frame.unmaskedData
            let closeDataCode = data.readSlice(length: 2) ?? ByteBuffer()
            let closeFrame = WebSocketFrame(fin: true, opcode: .connectionClose, data: closeDataCode)
            _ = context.write(self.wrapOutboundOut(closeFrame)).map { () in
                context.close(promise: nil)
            }
        }
        
        
//        private var contextList = [ChannelHandlerContext]()
//        private var connectedItems = [DanmakuWS]()
//        private var danmakus = [Danmaku]()
        
    }
    
    private func pong(context: ChannelHandlerContext, frame: WebSocketFrame) {
        var frameData = frame.data
        let maskingKey = frame.maskKey
        
        if let maskingKey = maskingKey {
            frameData.webSocketUnmask(maskingKey)
        }
        
        let responseFrame = WebSocketFrame(fin: true, opcode: .pong, data: frameData)
        context.write(self.wrapOutboundOut(responseFrame), promise: nil)
    }
    
    private func closeOnError(context: ChannelHandlerContext) {
        // We have hit an error, we want to close. We do that by sending a close frame and then
        // shutting down the write side of the connection.
        var data = context.channel.allocator.buffer(capacity: 2)
        data.write(webSocketErrorCode: .protocolError)
        let frame = WebSocketFrame(fin: true, opcode: .connectionClose, data: data)
        context.write(self.wrapOutboundOut(frame)).whenComplete { (_: Result<Void, Error>) in
            context.close(mode: .output, promise: nil)
        }
        awaitingClose = true
    }
    
    
    private func sendText(context: ChannelHandlerContext, _ string: String) {
        guard context.channel.isActive else { return }

        // We can't send if we sent a close message.
        guard !self.awaitingClose else { return }

        // We can't really check for error here, but it's also not the purpose of the
        // example so let's not worry about it.
        
        var buffer = context.channel.allocator.buffer(capacity: string.bytes.count)
        buffer.writeString(string)

        let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
        let _ = context.writeAndFlush(self.wrapOutboundOut(frame))
    }
}

extension DanmakuWebSocketHandler {
    func websocketConnected(_ context: ChannelHandlerContext) {
        Log("Websocket client connected. \(context.name)")
        Task { @MainActor in
            contextList.append(context)
        }
    }
    
    func websocketDisconnected(_ context: ChannelHandlerContext) {
        Log("Websocket client disconnected.")
        
        Task { @MainActor in
            connectedItems.removeAll { $0.contextName == context.name}
            let items = self.connectedItems
            danmakus.removeAll { dm in
                let remove = !items.contains(where: { $0.url == dm.url })
                if remove {
                    dm.stop()
                }
                return remove
            }
            
            Log("Danmaku list: \(danmakus.map({ $0.url }))")
        }
    }
    
    @MainActor
    func websocketReceived(_ context: ChannelHandlerContext, text: String) {
        var clickType: IINAUrlType = .none
        
        let ws: DanmakuWS? = {
            if text.starts(with: "iinaDM://") {
                clickType = .plugin
                var v = 0
                var u = String(text.dropFirst("iinaDM://".count))
                
                if u.starts(with: "v=") {
                    let vu = u.split(separator: "&", maxSplits: 1)
                    guard vu.count == 2 else { return nil }
                    v = Int(vu[0].dropFirst(2)) ?? 0
                    u = String(vu[1])
                }
                
                var re = DanmakuWS(id: u,
                                   site: .init(url: u),
                                   url: u,
                                   contextName: context.name)
                re.delegate = self
                re.version = v
                return re
            } else if text.starts(with: "iinaWebDM://") {
                let hex = String(text.dropFirst("iinaWebDM://".count))
                clickType = .danmaku
                guard let ids = String(data: Data(hex: hex), encoding: .utf8)?.split(separator: "👻").map(String.init),
                      ids.count == 2 else { return nil }
                let u = ids[1]
                
                var re = DanmakuWS(id: ids[0],
                                   site: .init(url: u),
                                   url: u,
                                   contextName: context.name)
                re.version = 1
                re.delegate = self
                return re
            } else {
                return nil
            }
        }()
        
        guard contextList.contains(where: { $0.name == context.name }),
              let ws = ws else {
            return
        }
        
        Task { @MainActor in
            switch clickType {
            case .danmaku:
                ws.loadCustomFont()
                ws.customDMSpeed()
                ws.customDMOpdacity()
                
                if [.bilibili, .bangumi, .b23].contains(ws.site) {
                    ws.loadFilters()
                    ws.loadXMLDM()
                    context.close()
                } else if ws.site != .unsupported {
                    loadNewDanmaku(ws)
                    connectedItems.append(ws)
                }
            case .plugin where ![.unsupported, .bangumi, .bilibili, .b23].contains(ws.site):
                loadNewDanmaku(ws)
                connectedItems.append(ws)
            default:
                break
            }
        }
    }
}

extension DanmakuWebSocketHandler: DanmakuDelegate {
    func send(_ event: DanmakuEvent, sender: Danmaku) {
        connectedItems.filter {
            $0.url == sender.url
        }.forEach {
            $0.send(event)
        }
    }
    
    @MainActor
    func loadNewDanmaku(_ ws: DanmakuWS) {
        guard !danmakus.contains(where: { $0.url == ws.url }) else { return }
        let d = Danmaku(ws.url)
        d.id = ws.url
        d.delegate = self
        danmakus.append(d)
        d.loadDM()
        
        Log(danmakus.map({ $0.url }))
    }
}


extension DanmakuWebSocketHandler: DanmakuWSDelegate {
    func writeDanmakuEventText(contextName: String, _ string: String) {
        guard let context = contextList.first(where: { $0.name == contextName }) else { return }
        context.eventLoop.execute {
            self.sendText(context: context, string)
        }
    }
}
