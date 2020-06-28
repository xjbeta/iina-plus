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
    private var server = Swifter.HttpServer()
    
    struct RegisteredItem {
        enum ContentState: Int {
            case unknown, contented, discontented
        }
        
        
        var id: String
        var site: LiveSupportList
        var url: String
        var session: WebSocketSession? = nil
        var danmaku: Danmaku
        
        var state: ContentState = .unknown
    }
    
    
    private var unknownSessions = [WebSocketSession]()
    private var registeredItems = [RegisteredItem]()
    
    
    func register(_ id: String,
                  site: LiveSupportList,
                  url: String) {
        registeredItems.append(.init(id: id, site: site, url: url, danmaku: .init(site, url: url)))
    }
    
    func start() {
        do {
            if let resourcePath = Bundle.main.resourcePath {
                let dir = resourcePath + "/danmaku"
                server["/danmaku/:path"] = directoryBrowser(dir)
            }
            
            server["/danmaku-websocket"] = websocket(text:{ [weak self] session, text in
                
                guard let sessions = self?.unknownSessions,
                    sessions.contains(session),
                    let i = self?.registeredItems.firstIndex(where: { $0.id == text }) else { return }
                self?.unknownSessions.removeAll {
                    $0 == session
                }
                
                self?.registeredItems[i].state = .contented
                self?.registeredItems[i].session = session
                Log(self?.registeredItems.map({ $0.url }))
                
            }, connected: { [weak self] session in
                Log("Websocket client connected.")
                self?.unknownSessions.append(session)
            }, disconnected: { [weak self] session in
                Log("Websocket client disconnected.")
                self?.registeredItems.removeAll { $0.session == session
                }
                Log(self?.registeredItems.map({ $0.url }))
            })
            
            server.listenAddressIPv4 = "127.0.0.1"
            try server.start(19080, forceIPv4: true)
            Log("Server has started ( port = \(try server.port()) ). Try to connect now...")
        } catch let error {
            Log("Server start error: \(error)")
        }
    }

    func stop() {
        server.stop()
    }
    
    enum DanamkuMethod: String {
        case start,
        stop,
        initDM,
        resize,
        customFont,
        loadDM,
        sendDM,
        liveDMServer,
        dmSpeed,
        dmOpacity,
        dmFontSize,
        dmBlockList
    }
    
    struct DanmakuEvent: Encodable {
        var method: String
        var text: String
    }
    
    func send(_ method: DanamkuMethod, text: String = "") {
        do {
            let data = try JSONEncoder().encode(DanmakuEvent(method: method.rawValue, text: text))
            if let str = String(data: data, encoding: .utf8) {
                writeText?(str)
                if !str.contains("sendDM") {
                    Log("WriteText to websocket: \(str)")
                }
            }
        } catch let error {
            Log(error)
        }
    }
}
