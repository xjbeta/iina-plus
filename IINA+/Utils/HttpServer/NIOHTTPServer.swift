//
//  NIOHTTPServer.swift
//  IINA+
//
//  Created by xjbeta on 2024/11/25.
//  Copyright © 2024 xjbeta. All rights reserved.
//


import Foundation
@preconcurrency import NIO
@preconcurrency import NIOHTTP1
@preconcurrency import NIOWebSocket


actor NIOHTTPServer {
    func start() {
        Task(priority: .background) {
            do {
                try setupServer()
            } catch {
                Log("Start NIOHTTPServer failed: \(error)")
            }
        }
    }

    func setupServer() throws {
        let upgrader = NIOWebSocketServerUpgrader(
            shouldUpgrade: { channel, head in
                channel.eventLoop.makeSucceededFuture(HTTPHeaders())
            },
            upgradePipelineHandler: { channel, _ in
                channel.pipeline.addHandler(DanmakuWebSocketHandler())
            })
        
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        
        let bootstrap = ServerBootstrap(group: group)
        // Specify backlog and enable SO_REUSEADDR for the server itself
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        
        // Set the handlers that are applied to the accepted Channels
            .childChannelInitializer { channel in
                let httpHandler = HTTPHandler()
                let config: NIOHTTPServerUpgradeConfiguration = (
                    upgraders: [ upgrader ],
                    completionHandler: { _ in
                        channel.pipeline.removeHandler(httpHandler, promise: nil)
                    }
                )
                return channel.pipeline.configureHTTPServerPipeline(withServerUpgrade: config).flatMap {
                    channel.pipeline.addHandler(httpHandler)
                }
            }
        
        // Enable SO_REUSEADDR for the accepted Channels
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        
        defer {
            try? group.syncShutdownGracefully()
        }
        
        let port = Preferences.shared.dmPort
        
        let channel = try bootstrap.bind(host: "127.0.0.1", port: port).wait()
        
        guard let localAddress = channel.localAddress else {
#warning("post notification")
            Log("Address was unable to bind. Please check that the socket was not closed or that the address family was understood.")
            return
        }
        Log("Server started and listening on \(localAddress)")
        
        // This will never unblock as we don't close the ServerChannel
        try channel.closeFuture.wait()
        
        Log("Server closed")
    }
    
}

