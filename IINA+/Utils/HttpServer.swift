//
//  HttpServer.swift
//  iina+
//
//  Created by xjbeta on 2018/10/28.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import Swifter
import WebKit

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
    
    private var unknownSessions = [WebSocketSession]()
    var connectedItems = [DanmakuWS]()
    
    private var danmakus = [Danmaku]()
    private var danmukuObservers: [NSObjectProtocol] = []
    
    private var httpFilesURL: URL?
    
    let videoDecoder = VideoDecoder()
    
    func start() {
        prepareWebSiteFiles()
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
            
            var clickType: IINAUrlType = .none
            
            let ws: DanmakuWS? = {
                if text.starts(with: "iinaDM://") {
                    clickType = .plugin
                    let u = String(text.dropFirst("iinaDM://".count))
                    
                    return .init(id: u,
                                 site: .init(url: u),
                                 url: u,
                                 session: session)
                } else if text.starts(with: "iinaWebDM://") {
                    let hex = String(text.dropFirst("iinaWebDM://".count))
                    clickType = .danmaku
                    guard let ids = String(data: Data(hex: hex), encoding: .utf8)?.split(separator: "👻").map(String.init),
                            ids.count == 2 else { return nil }
                    let u = ids[1]
                    
                    return .init(id: ids[0],
                                 site: .init(url: u),
                                 url: u,
                                 session: session)
                } else {
                    return nil
                }
            }()
            
            
            guard let sessions = self?.unknownSessions,
                  sessions.contains(session),
                  let ws = ws else {
                return
            }
            
            DispatchQueue.main.async {
                switch clickType {
                case .danmaku:
                    ws.loadCustomFont()
                    ws.customDMSpeed()
                    ws.customDMOpdacity()
                    
                    if [.bilibili, .bangumi, .b23].contains(ws.site) {
                        ws.loadFilters()
                        ws.loadXMLDM()
                        session.socket.close()
                    } else if ws.site != .unsupported {
                        self?.loadNewDanmaku(ws)
                        self?.connectedItems.append(ws)
                    }
                case .plugin:
                    guard ![.unsupported, .bangumi, .bilibili, .b23].contains(
                        ws.site) else { return }
                    self?.loadNewDanmaku(ws)
                    self?.connectedItems.append(ws)
                default:
                    break
                }
            }
        }, connected: { [weak self] session in
            Log("Websocket client connected.")
            self?.unknownSessions.append(session)
        }, disconnected: { [weak self] session in
            Log("Websocket client disconnected.")
            self?.connectedItems.removeAll { $0.session == session
            }
            guard let items = self?.connectedItems else { return }
            self?.danmakus.removeAll { dm in
                let remove = !items.contains(where: { $0.url == dm.url })
                if remove {
                    dm.stop()
                }
                return remove
            }
            
            Log("Danmaku list: \(self?.danmakus.map({ $0.url }) ?? [])")
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
        
        
        do {
            try server.start(.init(port), forceIPv4: true)
            Log("Server has started ( port = \(try server.port()) ). Try to connect now...")
        } catch let error {
            Log("Server start error: \(error)")
        }
        
        danmukuObservers.append(Preferences.shared.observe(\.danmukuFontFamilyName, options: .new, changeHandler: { _, _ in
            self.connectedItems.forEach {
                $0.loadCustomFont()
            }
        }))
        danmukuObservers.append(Preferences.shared.observe(\.dmSpeed, options: .new, changeHandler: { _, _ in
            self.connectedItems.forEach {
                $0.customDMSpeed()
            }
        }))
        danmukuObservers.append(Preferences.shared.observe(\.dmOpacity, options: .new, changeHandler: { _, _ in
            self.connectedItems.forEach {
                $0.customDMOpdacity()
            }
        }))
    }

    func stop() {
        server.stop()
        danmukuObservers.forEach {
            NotificationCenter.default.removeObserver($0)
        }
    }
    
    func loadNewDanmaku(_ ws: DanmakuWS) {
        guard !danmakus.contains(where: { $0.url == ws.url }) else { return }
        let d = Danmaku(ws.url)
        d.id = ws.url
        d.delegate = self
        danmakus.append(d)
        d.loadDM()
        
        Log(danmakus.map({ $0.url }))
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
    
    func send(_ method: DanamkuMethod, text: String = "", sender: Danmaku) {
        self.connectedItems.filter {
            $0.url == sender.url
        }.forEach {
            $0.send(method, text: text)
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

struct DanmakuEvent: Encodable {
    var method: String
    var text: String
}

struct DanmakuWS {
    var id: String
    var site: SupportSites
    var url: String
    var session: WebSocketSession? = nil
    
    var webview: WKWebView? = nil
    
    func send(_ method: DanamkuMethod, text: String = "") {
        guard let data = try? JSONEncoder().encode(DanmakuEvent(method: method.rawValue, text: text)),
            let str = String(data: data, encoding: .utf8) else { return }
        
        if let s = session {
            s.writeText(str)
        } else if let wv = webview {
            wv.evaluateJavaScript("window.dmMessage(\(str));").catch { _ in }
        }
        
        if !str.contains("sendDM") {
            Log("WriteText to \(id): \(str)")
        }
    }
    
    func loadCustomFont() {
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
        
        send(.customFont, text: text)
    }

    func customDMSpeed() {
        let dmSpeed = Int(Preferences.shared.dmSpeed)
        send(.dmSpeed, text: "\(dmSpeed)")
    }

    func customDMOpdacity() {
        send(.dmOpacity, text: "\(Preferences.shared.dmOpacity)")
    }
    
    func loadFilters() {
        var types = Preferences.shared.dmBlockType
        if Preferences.shared.dmBlockList.type != .none {
            types.append("List")
        }
        send(.dmBlockList, text: types.joined(separator: ", "))
    }
    
    func loadXMLDM() {
        send(.loadDM, text: id)
    }
}
