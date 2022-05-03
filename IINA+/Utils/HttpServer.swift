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
        var site: SupportSites
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
    
    let videoDecoder = VideoDecoder()
    
    func register(_ id: String,
                  site: SupportSites,
                  url: String) {
        let d = Danmaku(url)
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
            self.registeredItems.forEach {
                $0.danmaku.loadCustomFont()
            }
        }))
        danmukuObservers.append(Preferences.shared.observe(\.dmSpeed, options: .new, changeHandler: { _, _ in
            self.registeredItems.forEach {
                $0.danmaku.customDMSpeed()
            }
        }))
        danmukuObservers.append(Preferences.shared.observe(\.dmOpacity, options: .new, changeHandler: { _, _ in
            self.registeredItems.forEach {
                $0.danmaku.customDMOpdacity()
            }
        }))
        
        do {
            guard let dir = httpFilesURL?.path else { return }
            
            // Video API
            server.POST["/video/danmakuurl"] = { request -> HttpResponse in
                
                
                
                guard let url = request.parameters["url"],
                      let json = self.decode(url),
                      let key = json.videos.first?.key,
                      let data = json.danmakuUrl(key)?.data(using: .utf8) else {
                    return .badRequest(nil)
                }
                return HttpResponse.ok(.data(data))
            }
            
            server.POST["/video/iinaurl"] = { request -> HttpResponse in
                
                var type = IINAUrlType.normal
                if let tStr = request.parameters["type"],
                   let t = IINAUrlType(rawValue: tStr) {
                    type = t
                }
                
                guard let url = request.parameters["url"],
                      let json = self.decode(url),
                      let key = json.videos.first?.key,
                      let data = json.iinaUrl(key, type: type)?.data(using: .utf8) else {
                    return .badRequest(nil)
                }
                return HttpResponse.ok(.data(data))
            }
            
            server.get["/video"] = { request -> HttpResponse in
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                var pars = [String: String]()
                request.queryParams.forEach {
                    pars[$0.0] = $0.1.removingPercentEncoding
                }
                let key = pars["key"] ?? ""
                
                guard let url = pars["url"],
                      let json = self.decode(url, key: key),
                      let data = pars["pluginAPI"] == nil ? try? encoder.encode(json) : json.iinaPlusArgsString(key)?.data(using: .utf8)
                else {
                    return .badRequest(nil)
                }
                
                return HttpResponse.ok(.data(data))
            }
            
            // Danmaku API
            server["/danmaku/:path"] = directoryBrowser(dir)
            
            server["/danmaku-websocket"] = websocket(text:{ [weak self] session, text in
                guard let sessions = self?.unknownSessions,
                      sessions.contains(session) else {
                    return
                }
                
                if let i = self?.registeredItems.firstIndex(where: { $0.id == text }) {
                    self?.unknownSessions.removeAll {
                        $0 == session
                    }
                    
                    self?.registeredItems[i].state = .contented
                    self?.registeredItems[i].session = session
                    Log(self?.registeredItems.map({ $0.url }))
                    
                    if Processes.shared.iinaArchiveType() == .danmaku {
                        if let site = self?.registeredItems[i].site,
                           site == .bilibili {
                            self?.registeredItems[i].danmaku.loadFilters(text)
                        }
                        
                        self?.registeredItems[i].danmaku.loadCustomFont(text)
                        self?.registeredItems[i].danmaku.customDMSpeed(text)
                        self?.registeredItems[i].danmaku.customDMOpdacity(text)
                    }
                    self?.registeredItems[i].danmaku.loadDM()
                } else if text.starts(with: "iinaDM://") {
                    let u = String(text.dropFirst("iinaDM://".count))
                    
                    let site = SupportSites(url: u)
                    
                    
                    guard ![.unsupported, .bangumi, .bilibili, .b23].contains(site) else { return }
                    
                    DispatchQueue.main.async {
                        let d = Danmaku(u)
                        d.id = u
                        d.delegate = self
                        
                        self?.registeredItems.append(.init(
                            id: u,
                            site: site,
                            url: u,
                            session: session,
                            danmaku: d,
                            state: .contented))
                        d.loadDM()
                    }
                }

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
            
            /*
            server.POST["/danmaku/open"] = { request -> HttpResponse in
                
                guard let url = request.parameters["url"],
                      let uuid = request.parameters["id"] else {
                    return .badRequest(nil)
                }
                
                let site = SupportSites(url: url)
                
                switch site {
                case .bilibili, .bangumi:
                    // Return DM File
                    return .badRequest(nil)
                case .eGame, .douyu, .huya, .biliLive:
                    self.register(uuid, site: site, url: url)
                default:
                    return .badRequest(nil)
                }
                
                return HttpResponse.ok(.data(data))
            }
            
            server.POST["/danmaku/close"] = { request -> HttpResponse in
                guard let uuid = request.parameters["uuid"] else {
                    return .badRequest(nil)
                }
                
                resign
                
                
                return HttpResponse.ok(.data(data))
            }
            */
             
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
            let folderName = "WebFiles"
            resourceURL.appendPathComponent(folderName)
            
            var filesURL = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            filesURL.appendPathComponent(bundleIdentifier)
            filesURL.appendPathComponent(folderName)
            
            httpFilesURL = filesURL
            
            if FileManager.default.fileExists(atPath: filesURL.path) {
                try FileManager.default.removeItem(at: filesURL)
            }
            
            try FileManager.default.copyItem(at: resourceURL, to: filesURL)
            Log(resourceURL.path)
            Log(filesURL.path)
            
        } catch let error {
            Log(error)
        }
    }
    
    struct DanmakuEvent: Encodable {
        var method: String
        var text: String
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
    
    
    private func decode(_ url: String, key: String = "") -> YouGetJSON? {
        var re: YouGetJSON?
        let queue = DispatchGroup()
        queue.enter()
        videoDecoder.decodeUrl(url).then{
            self.videoDecoder.prepareVideoUrl($0, key)
        }.done {
            re = $0
        }.ensure {
            queue.leave()
        }.catch {
            Log($0)
        }
        queue.wait()
        return re
    }
}

extension HttpRequest {
    var parameters: [String: String] {
        get {
            let requestBodys = String(bytes: body, encoding: .utf8)?.split(separator: "&") ?? []
            
            var parameters = [String: String]()
            requestBodys.forEach {
                let kv = $0.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
                guard kv.count == 2 else { return }
                parameters[kv[0]] = kv[1]
            }
            return parameters
        }
    }
}
