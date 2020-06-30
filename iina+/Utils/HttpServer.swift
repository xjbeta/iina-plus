//
//  HttpServer.swift
//  iina+
//
//  Created by xjbeta on 2018/10/28.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import Swifter

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

class HttpServer: NSObject, DanmakuDelegate {
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
    private var danmukuObservers: [NSObjectProtocol] = []
    private let sid = "rua-uuid~~~"
    
    
    func register(_ id: String,
                  site: LiveSupportList,
                  url: String) {
        let d = Danmaku(site, url: url)
        d.id = id
        d.delegate = self
        if site == .bilibili {
            do {
                try d.prepareBlockList()
            } catch let error {
                Log("Prepare DM block list error: \(error)")
            }
        }
        registeredItems.append(.init(id: id, site: site, url: url, danmaku: d))
    }
    
    func start() {
        danmukuObservers.append(Preferences.shared.observe(\.danmukuFontFamilyName, options: .new, changeHandler: { _, _ in
            self.loadCustomFont()
        }))
        danmukuObservers.append(Preferences.shared.observe(\.dmSpeed, options: .new, changeHandler: { _, _ in
            self.customDMSpeed()
        }))
        danmukuObservers.append(Preferences.shared.observe(\.dmOpacity, options: .new, changeHandler: { _, _ in
            self.customDMOpdacity()
        }))
        
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
                
                self?.loadCustomFont(text)
                self?.customDMSpeed(text)
                self?.customDMOpdacity(text)
                if let site = self?.registeredItems[i].site,
                    site == .bilibili {
                    self?.loadFilters(text)
                }
                
                self?.registeredItems[i].danmaku.loadDM()
            }, connected: { [weak self] session in
                Log("Websocket client connected.")
                self?.unknownSessions.append(session)
            }, disconnected: { [weak self] session in
                Log("Websocket client disconnected.")
                self?.registeredItems.first {
                    $0.session == session
                    }?.danmaku.stop()
                
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
        danmukuObservers.forEach {
            NotificationCenter.default.removeObserver($0)
        }
    }
    
    struct DanmakuEvent: Encodable {
        var method: String
        var text: String
    }
    
    private func loadCustomFont(_ id: String = "rua-uuid~~~") {
        guard let font = Preferences.shared.danmukuFontFamilyName else { return }
        send(.customFont, text: font, id: id)
    }

    private func customDMSpeed(_ id: String = "rua-uuid~~~") {
        let dmSpeed = Int(Preferences.shared.dmSpeed)
        send(.dmSpeed, text: "\(dmSpeed)", id: id)
    }

    private func customDMOpdacity(_ id: String = "rua-uuid~~~") {
        send(.dmOpacity, text: "\(Preferences.shared.dmOpacity)", id: id)
    }
    
    private func loadFilters(_ id: String = "rua-uuid~~~") {
        var types = Preferences.shared.dmBlockType
        if Preferences.shared.dmBlockList.type != .none {
            types.append("List")
        }
        send(.dmBlockList, text: types.joined(separator: ", "), id: id)
    }

    
    func send(_ method: DanamkuMethod, text: String = "", id: String) {
        guard let data = try? JSONEncoder().encode(DanmakuEvent(method: method.rawValue, text: text)),
            let str = String(data: data, encoding: .utf8) else { return }
        
        if id == sid {
            self.registeredItems.forEach {
                $0.session?.writeText(str)
            }
        } else {
            self.registeredItems.first {
                $0.id == id
                }?.session?.writeText(str)
        }
        
        if !str.contains("sendDM") {
            Log("WriteText to websocket: \(str)")
        }
    }
}
