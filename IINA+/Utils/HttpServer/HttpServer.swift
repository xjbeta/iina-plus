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
    
    
    let nioServer = NIOHTTPServer()

    
    func start() {
        
        
        prepareWebSiteFiles()
        guard let dir = httpFilesURL?.path else { return }
        
        
        Task {
            await nioServer.start()
        }
        
        
		
//		server.get["/dash/**"] = { request -> HttpResponse in
//			let id = request.path.subString(from: "/dash/", to: ".mpd")
//			guard let content = self.dash[id]?.data(using: .utf8) else { return .badRequest(.none) }
//			
//			return .ok(.data(content))
//		}
        
        
//
//        
//        // Danmaku API
//        server["/danmaku/:path"] = directoryBrowser(dir)
//
        
        

        
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

