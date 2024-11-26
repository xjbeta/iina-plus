//
//  HttpServer.swift
//  iina+
//
//  Created by xjbeta on 2018/10/28.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import WebKit
import NIO
import NIOHTTP1



@MainActor
class HttpServer: NSObject {
    
	private var dash = [String: String]()
	
	
    private var danmukuObservers: [NSObjectProtocol] = []
    
    private var httpFilesURL: URL?
    
    let videoDecoder = VideoDecoder()
    
    let nioServer = NIOHTTPServer()

    
    func start() {
        
        
        prepareWebSiteFiles()
        guard let dir = httpFilesURL?.path else { return }
        
        
        Task {
            await nioServer.start()
        }
        
        
//        // Video API
//        server.POST["/video/danmakuurl"] = { request -> HttpResponse in
//            guard let url = request.parameters["url"],
//				  let json = try? await self.decode(url),
//                  let key = json.videos.first?.key,
//                  let data = json.danmakuUrl(key)?.data(using: .utf8) else {
//                return .badRequest(nil)
//            }
//            return HttpResponse.ok(.data(data))
//        }
//        
//        server.POST["/video/iinaurl"] = { request -> HttpResponse in
//            
//            var type = IINAUrlType.normal
//            if let tStr = request.parameters["type"],
//               let t = IINAUrlType(rawValue: tStr) {
//                type = t
//            }
//            
//            guard let url = request.parameters["url"],
//                  let json = try? await self.decode(url),
//                  let key = json.videos.first?.key,
//                  let data = json.iinaURLScheme(key, type: type)?.data(using: .utf8) else {
//                return .badRequest(nil)
//            }
//            return HttpResponse.ok(.data(data))
//        }
//		
//		server.get["/dash/**"] = { request -> HttpResponse in
//			let id = request.path.subString(from: "/dash/", to: ".mpd")
//			guard let content = self.dash[id]?.data(using: .utf8) else { return .badRequest(.none) }
//			
//			return .ok(.data(content))
//		}
//        
//        server.get["/video"] = { request -> HttpResponse in
//            let encoder = JSONEncoder()
//            encoder.outputFormatting = .prettyPrinted
//            var pars = [String: String]()
//            request.queryParams.forEach {
//                pars[$0.0] = $0.1.removingPercentEncoding
//            }
//            let key = pars["key"] ?? ""
//            
//            guard let url = pars["url"],
//                  let json = try? await self.decode(url, key: key),
//                  let data = pars["pluginAPI"] == nil ? try? encoder.encode(json) : json.iinaPlusArgsString(key)?.data(using: .utf8)
//            else {
//                return .badRequest(nil)
//            }
//            
//            return HttpResponse.ok(.data(data))
//        }
//        
//        // Danmaku API
//        server["/danmaku/:path"] = directoryBrowser(dir)
//        
//        server["/danmaku-websocket"] = websocket(text:{ [weak self] session, text in
//			self?.websocketReceived(session, text: text)
//        }, connected: { [weak self] session in
//			self?.websocketConnected(session)
//        }, disconnected: { [weak self] session in
//			self?.websocketDisconnected(session)
//        })
                          

        
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
        

        
        
//        danmukuObservers.append(Preferences.shared.observe(\.danmukuFontFamilyName, options: .new, changeHandler: { _, _ in
//			Task { @MainActor in
//				self.connectedItems.forEach {
//					$0.loadCustomFont()
//				}
//			}
//        }))
//        danmukuObservers.append(Preferences.shared.observe(\.dmSpeed, options: .new, changeHandler: { _, _ in
//			Task { @MainActor in
//				self.connectedItems.forEach {
//					$0.customDMSpeed()
//				}
//			}
//        }))
//        danmukuObservers.append(Preferences.shared.observe(\.dmOpacity, options: .new, changeHandler: { _, _ in
//			Task { @MainActor in
//				self.connectedItems.forEach {
//					$0.customDMOpdacity()
//				}
//			}
//        }))
    }
    
    
    

    func stop() {
//        server.stop()
//        danmukuObservers.forEach {
//            NotificationCenter.default.removeObserver($0)
//        }
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
    
    
    
    private func decode(_ url: String, key: String = "") async throws -> YouGetJSON? {
		var json = try await self.videoDecoder.decodeUrl(url)
		json = try await videoDecoder.prepareVideoUrl(json, key)
		
        return json
    }
	
	@MainActor
	func registerDash(_ bvid: String, content: String) -> String {
//		guard let address = server.listenAddressIPv4,
//				let port = try? server.port() else {
//			assert(false, "HttpServer can't register dash.")
//			return ""
//		}
//		
//		self.dash[bvid] = content
//		return "http://\(address):\(port)/dash/\(bvid).mpd"
        
        return ""
	}
}



//extension HttpRequest {
//    var parameters: [String: String] {
//        get {
//            let requestBodys = String(bytes: body, encoding: .utf8)?.split(separator: "&") ?? []
//            
//            var parameters = [String: String]()
//            requestBodys.forEach {
//                let kv = $0.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
//                guard kv.count == 2 else { return }
//                parameters[kv[0]] = kv[1]
//            }
//            return parameters
//        }
//    }
//}

