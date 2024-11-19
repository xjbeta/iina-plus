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

enum DanamkuMethod: String, Encodable {
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


@MainActor
class HttpServer: NSObject, DanmakuDelegate {
    
    private var server = Swifter.HttpServer()
    
	private var dash = [String: String]()
	
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
				  let json = try? await self.decode(url),
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
                  let json = try? await self.decode(url),
                  let key = json.videos.first?.key,
                  let data = json.iinaURLScheme(key, type: type)?.data(using: .utf8) else {
                return .badRequest(nil)
            }
            return HttpResponse.ok(.data(data))
        }
		
		server.get["/dash/**"] = { request -> HttpResponse in
			let id = request.path.subString(from: "/dash/", to: ".mpd")
			guard let content = await self.dash[id]?.data(using: .utf8) else { return .badRequest(.none) }
			
			return .ok(.data(content))
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
                  let json = try? await self.decode(url, key: key),
                  let data = pars["pluginAPI"] == nil ? try? encoder.encode(json) : json.iinaPlusArgsString(key)?.data(using: .utf8)
            else {
                return .badRequest(nil)
            }
            
            return HttpResponse.ok(.data(data))
        }
        
        // Danmaku API
        server["/danmaku/:path"] = directoryBrowser(dir)
        
        server["/danmaku-websocket"] = websocket(text:{ [weak self] session, text in
			self?.websocketReceived(session, text: text)
        }, connected: { [weak self] session in
			self?.websocketConnected(session)
        }, disconnected: { [weak self] session in
			self?.websocketDisconnected(session)
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
         case .douyu, .huya, .biliLive:
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
			Task { @MainActor in
				self.connectedItems.forEach {
					$0.loadCustomFont()
				}
			}
        }))
        danmukuObservers.append(Preferences.shared.observe(\.dmSpeed, options: .new, changeHandler: { _, _ in
			Task { @MainActor in
				self.connectedItems.forEach {
					$0.customDMSpeed()
				}
			}
        }))
        danmukuObservers.append(Preferences.shared.observe(\.dmOpacity, options: .new, changeHandler: { _, _ in
			Task { @MainActor in
				self.connectedItems.forEach {
					$0.customDMOpdacity()
				}
			}
        }))
    }

    func stop() {
        server.stop()
        danmukuObservers.forEach {
            NotificationCenter.default.removeObserver($0)
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
    
	@MainActor
    func send(_ event: DanmakuEvent, sender: Danmaku) {
        connectedItems.filter {
            $0.url == sender.url
        }.forEach {
            $0.send(event)
        }
    }
    
    
    private func decode(_ url: String, key: String = "") async throws -> YouGetJSON? {
		var json = try await self.videoDecoder.decodeUrl(url)
		json = try await videoDecoder.prepareVideoUrl(json, key)
		
        return json
    }
	
	@MainActor
	func registerDash(_ bvid: String, content: String) -> String {
		guard let address = server.listenAddressIPv4,
				let port = try? server.port() else {
			assert(false, "HttpServer can't register dash.")
			return ""
		}
		
		self.dash[bvid] = content
		return "http://\(address):\(port)/dash/\(bvid).mpd"
	}
}

extension HttpServer {
	func websocketConnected(_ session: WebSocketSession) {
		Log("Websocket client connected.")
		Task { @MainActor in
			unknownSessions.append(session)
		}
	}
	
	func websocketDisconnected(_ session: WebSocketSession) {
		Log("Websocket client disconnected.")
		
		Task { @MainActor in
			connectedItems.removeAll { $0.session == session}
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
	
	func websocketReceived(_ session: WebSocketSession, text: String) {
		Task { @MainActor in
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
									   session: session)
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
									   session: session)
					re.version = 1
					return re
				} else {
					return nil
				}
			}()
			
			guard unknownSessions.contains(session),
				  let ws = ws else {
				return
			}
			
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

struct DanmakuComment: Encodable {
    var text: String
    var imageSrc: String?
    var imageWidth: Int?
}

struct DanmakuEvent: Encodable {
    var method: DanamkuMethod
    var text: String
    
    var dms: [DanmakuComment]?
    
    func string() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct DanmakuWS {
    var id: String
    var site: SupportSites
    var url: String
    var session: WebSocketSession? = nil
    
    var webview: WKWebView? = nil
    
    var version = 0
    
    @MainActor
    func send(_ event: DanmakuEvent) {
        switch version {
        case 0 where event.method == .sendDM:
            event.dms?.forEach {
                let de = DanmakuEvent(method: .sendDM, text: $0.text)
                guard let str = de.string(), let s = session else { return }
                s.writeText(str)
            }
        default:
            guard let str = event.string() else { return }

            if let s = session {
                s.writeText(str)
            } else if let wv = webview {
				wv.evaluateJavaScript("window.dmMessage(\(str));") { _,_ in }
            }
            
            if !str.contains("sendDM") {
                Log("WriteText to \(id): \(str)")
            }
        }
    }
    
    @MainActor
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
        
        send(.init(method: .customFont, text: text))
    }

    @MainActor
    func customDMSpeed() {
        send(.init(method: .dmSpeed, text: "\(Int(Preferences.shared.dmSpeed))"))
    }

    @MainActor
    func customDMOpdacity() {
        send(.init(method: .dmOpacity, text: "\(Preferences.shared.dmOpacity)"))
    }
    
    func loadFilters() {
//        var types = Preferences.shared.dmBlockType
//        if Preferences.shared.dmBlockList.type != .none {
//            types.append("List")
//        }
//        send(.init(method: .dmBlockList, text: types.joined(separator: ", ")))
    }
    
    @MainActor
    func loadXMLDM() {
        send(.init(method: .loadDM, text: id))
    }
}
