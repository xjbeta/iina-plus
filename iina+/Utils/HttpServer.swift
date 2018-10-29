//
//  HttpServer.swift
//  iina+
//
//  Created by xjbeta on 2018/10/28.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import Swifter

class HttpServer: NSObject {
    private var server: Swifter.HttpServer!
    private var writeText: ((String) -> Void)?
    var connected: (() -> Void)?
    var disConnected: (() -> Void)?
    
    func start() {
        do {
            server = Swifter.HttpServer()
            if let resourcePath = Bundle.main.resourcePath {
                let dir = resourcePath + "/danmaku"
                server["/danmaku/:path"] = directoryBrowser(dir)
            }
            
            server["/danmaku-websocket"] = websocket(connected: { [weak self] session in
                Logger.log("Websocket client connected.")
                self?.writeText = {
                    session.writeText($0)
                }
                self?.connected?()
            }, disconnected: { [weak self] session in
                Logger.log("Websocket client disconnected.")
                self?.writeText = nil
                self?.disConnected?()
            })
            
            server.listenAddressIPv4 = "127.0.0.1"
            try server.start(19080, forceIPv4: true)
            print("Server has started ( port = \(try server.port()) ). Try to connect now...")
        } catch let error {
            print("Server start error: \(error)")
        }
    }

    func stop() {
        server.stop()
    }
    
    enum DanamkuMethod: String {
        case start, stop, initDM, resize, customFont, loadDM, sendDM
    }
    
    struct DanmakuEvent: Encodable {
        var method: String
        var text: String
    }
    
    func send(_ method: DanamkuMethod, text: String = "") {
        do {
            let data = try JSONEncoder().encode(DanmakuEvent(method: method.rawValue, text: text))
            if let str = String(data: data, encoding: .utf8) {
                Logger.log("WriteText to websocket: \(str)")
                writeText?(str)
            }
        } catch let error {
            print(error)
        }
    }
}
