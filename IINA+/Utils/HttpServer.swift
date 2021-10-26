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
    
    private var httpFilesURL: URL?
    
    let videoGet = VideoGet()
    
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
        prepareWebSiteFiles()
        
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
            guard let dir = httpFilesURL?.path else { return }
            
            server.POST["/video"] = { request -> HttpResponse in
                let requestBodys = String(bytes: request.body, encoding: .utf8)?.split(separator: "&") ?? []
                
                var parameters = [String: String]()
                requestBodys.forEach {
                    let kv = $0.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
                    guard kv.count == 2 else { return }
                    parameters[kv[0]] = kv[1]
                }
                
                guard let url = parameters["url"]?.removingPercentEncoding else {
                    return HttpResponse.badRequest(nil)
                }
                
                var re = Data()
                let queue = DispatchGroup()
                queue.enter()
                    
                self.videoGet.decodeUrl(url).done {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    re = try encoder.encode($0)
                }.ensure {
                    queue.leave()
                }.catch {
                    print($0)
                }
                queue.wait()
                return HttpResponse.ok(.data(re))
            }
            
            server["/danmaku/:path"] = directoryBrowser(dir)
            
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
            
            let port = Preferences.shared.dmPort
            
            try server.start(.init(port), forceIPv4: true)
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
    
    private func prepareWebSiteFiles() {
        do {
            guard var resourceURL = Bundle.main.resourceURL,
                let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
            let folderName = "danmaku"
            resourceURL.appendPathComponent(folderName)
            
            var filesURL = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            filesURL.appendPathComponent(bundleIdentifier)
            filesURL.appendPathComponent(folderName)
            
            httpFilesURL = filesURL
            
            if FileManager.default.fileExists(atPath: filesURL.path) {
                try FileManager.default.removeItem(at: filesURL)
            }
            
            try FileManager.default.copyItem(at: resourceURL, to: filesURL)
        } catch let error {
            Log(error)
        }
    }
    
    struct DanmakuEvent: Encodable {
        var method: String
        var text: String
    }
    
    private func loadCustomFont(_ id: String = "rua-uuid~~~") {
        let pref = Preferences.shared
        let font = pref.danmukuFontFamilyName
        let size = pref.danmukuFontSize
        let weight = pref.danmukuFontWeight
        
        var text = ".customFont {"
        text += "color: #fff;"
        text += "font-family: '\(font) \(weight)', SimHei, SimSun, Heiti, 'MS Mincho', 'Meiryo', 'Microsoft YaHei', monospace;"
        text += "font-size: \(size)px;"
        
        
        text += "letter-spacing: 0;line-height: 100%;margin: 0;padding: 3px 0 0 0;position: absolute;text-decoration: none;text-shadow: -1px 0 black, 0 1px black, 1px 0 black, 0 -1px black;-webkit-text-size-adjust: none;-ms-text-size-adjust: none;text-size-adjust: none;-webkit-transform: matrix3d(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);transform: matrix3d(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);-webkit-transform-origin: 0% 0%;-ms-transform-origin: 0% 0%;transform-origin: 0% 0%;white-space: pre;word-break: keep-all;}"
        
        Log("Danmaku font \(font) \(weight), \(size)px.")
        
        send(.customFont, text: text, id: id)
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
