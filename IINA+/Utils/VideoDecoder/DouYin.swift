//
//  DouYin.swift
//  IINA+
//
//  Created by xjbeta on 2/19/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa
import WebKit
import PromiseKit
import SwiftSoup
import Alamofire
import Marshal
import PMKAlamofire

class DouYin: NSObject, SupportSiteProtocol {
    
    // MARK: - DY Init
    var webView: WKWebView?
    var webViewLoadingObserver: NSKeyValueObservation?
    
    var prepareTask: Promise<()>?
    var dyFinishNitification: NSObjectProtocol?
    
    var cookies = [String: String]()
    var storageDic = [String: String]()
    
    let douyinEmptyURL = URL(string: "https://live.douyin.com/1")!
    var douyinUA = ""
    
    let privateKeys = [
        "X2J5dGVkX3BhcmFtX3N3",
        "dHRfc2NpZA==",
        "Ynl0ZWRfYWNyYXdsZXI=",
        "WC1Cb2d1cw==",
        "X3NpZ25hdHVyZQ=="
    ]
	
	lazy var webviewConfig: WKWebViewConfiguration = {
		// https://gist.github.com/genecyber/e4a5f7c6f92eaef9ccb5
		let script = """
function addXMLRequestCallback(callback) {
	var oldSend, i;
	if (XMLHttpRequest.callbacks) {
		XMLHttpRequest.callbacks.push(callback);
	} else {
		XMLHttpRequest.callbacks = [callback];
		oldSend = XMLHttpRequest.prototype.send;
		XMLHttpRequest.prototype.send = function () {
			for (i = 0; i < XMLHttpRequest.callbacks.length; i++) {
				XMLHttpRequest.callbacks[i](this);
			}
			oldSend.apply(this, arguments);
		}
	}
}

addXMLRequestCallback(function (xhr) {
	window.webkit.messageHandlers.fetch.postMessage(xhr._url);
});
"""
		
		let scriptInjection = WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
		
		let config = WKWebViewConfiguration()
		let contentController = WKUserContentController()
		contentController.add(self, name: "fetch")
		contentController.addUserScript(scriptInjection)
		config.userContentController = contentController
		
		return config
	}()
	
	
	private var invalidCookiesCount = 0
    
    func liveInfo(_ url: String) -> Promise<LiveInfo> {
        if cookies.count == 0 {
            if prepareTask == nil {
                prepareTask = prepareArgs().ensure {
                    self.prepareTask = nil
                }
            }
            return prepareTask!.then {
                self.getEnterContent(url)
            }
        } else {
            return self.getEnterContent(url)
        }
    }
    
    func decodeUrl(_ url: String) -> Promise<YouGetJSON> {
        liveInfo(url).compactMap {
			var json = YouGetJSON(rawUrl: url)
			
			if let info = $0 as? DouYinEnterData.DouYinLiveInfo {
				json = info.write(to: json)
			} else if let info = $0 as? DouYinInfo {
				json = info.write(to: json)
			} else {
				return nil
			}
			
			return json
        }
    }
    
	
	func getEnterContent(_ url: String) -> Promise<LiveInfo> {
		let cookieString = cookies.map {
			"\($0.key)=\($0.value)"
		}.joined(separator: ";")
		
		let headers = HTTPHeaders([
			"User-Agent": douyinUA,
			"referer": url,
			"Cookie": cookieString
		])
		
		guard let pc = NSURL(string: url)?.pathComponents,
			  pc.count >= 2,
			  pc[0] == "/" else {
			return .init(error: VideoGetError.invalidLink)
		}
		
		let rid = pc[1]
		
		let u = "https://live.douyin.com/webcast/room/web/enter/?aid=6383&app_name=douyin_web&live_id=1&device_platform=web&language=en-US&cookie_enabled=true&browser_language=en-US&browser_platform=Mac&browser_name=Safari&browser_version=16&web_rid=\(rid)&enter_source=&is_need_double_stream=true"
		
		
		return AF.request(u, headers: headers).responseData().map {
			let jsonObj: JSONObject = try JSONParser.JSONObjectWithData($0.data)
			
			let enterData = try DouYinEnterData(object: jsonObj)
			
			if let info = enterData.infos.first {
				return info
			} else if let info = try? DouYinEnterData2(object: jsonObj) {
				return info
			} else {
				throw VideoGetError.notFountData
			}
		}
	}
	
    
    func getContent(_ url: String) -> Promise<LiveInfo> {
        let cookieString = cookies.map {
            "\($0.key)=\($0.value)"
        }.joined(separator: ";")
        
        let headers = HTTPHeaders([
            "User-Agent": douyinUA,
            "referer": url,
            "Cookie": cookieString
        ])
        
		return AF.request(url, headers: headers).responseString().map(on: .global()) {
			self.getJSON($0.string)
		}.map {
			guard let json = $0 else {
				self.invalidCookiesCount += 1
				if self.invalidCookiesCount == 5 {
					self.invalidCookiesCount = 0
					self.cookies.removeAll()
					
					Log("Reload Douyin Cookies")
				}
                throw VideoGetError.notFountData
            }
            
            let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(json)
            
            if let re = try? DouYinInfo(object: jsonObj) {
                return re
            } else {
                let info: DouYinInfo = try jsonObj.value(for: "app")
                return info
            }
        }
    }
    
	func getJSON(_ text: String) -> Data? {
		if text.contains("RENDER_DATA") {
//			return try? SwiftSoup
//				.parse(text)
//				.getElementById("RENDER_DATA")?
//				.data()
//				.removingPercentEncoding?
//				.data(using: .utf8)

			return text.subString(
				from: "<script id=\"RENDER_DATA\" type=\"application/json\">",
				to: "</script>")
			.removingPercentEncoding?
			.data(using: .utf8)
		} else {
			guard let s = text.split(separator: "\n").map(String.init).last else {
				return nil
			}
			
			var re = s.components(separatedBy: "self.__pace_f.push")
				.map {
					$0.subString(to: "</script>")
				}
				.compactMap { str -> String? in
					var s = str
					guard let f = s.firstIndex(of: "{"),
						  let e = s.lastIndex(of: "}")
					else { return nil }
					
					s.removeSubrange(e..<s.endIndex)
					s.removeSubrange(s.startIndex..<f)
					s += "}"
					
					s = s.replacingOccurrences(of: "\\\"", with: "\"")
					s = s.replacingOccurrences(of: "\\\"", with: "\"")
					if let sRange = s.range(of: "\"state\"") {
						s.replaceSubrange(sRange, with: "\"initialState\"")
					}
					return s
				}
			
			guard re.count > 0 else { return nil }
			
			re = re.filter {
				$0.contains("web_rid")
			}

			return re.first?.data(using: .utf8)
		}
	}
    
    func prepareArgs() -> Promise<()> {
        cookies.removeAll()
        storageDic.removeAll()
        deleteDouYinCookies()
		
		enum DYState {
			case none
			case checking
			case finish
		}
		
		var state = DYState.none
		var timerStarted = false
		
        return Promise { resolver in
            dyFinishNitification = NotificationCenter.default.addObserver(forName: .douyinWebcastUpdated, object: nil, queue: .main) { _ in
				guard state == .none else { return }
				state = .checking
				
				Log("Douyin WebcastUpdated")
				
                if let n = self.dyFinishNitification {
                    NotificationCenter.default.removeObserver(n)
                }
				
				self.loadCookies().done {
					resolver.fulfill_()
				}.ensure {
					self.deinitWebView()
					state = .finish
				}.catch {
					resolver.reject($0)
				}
            }
			
			webView = WKWebView(frame: .zero, configuration: webviewConfig)
			
#if DEBUG
			if #available(macOS 13.3, *) {
				webView?.isInspectable = true
			}
#endif
	       
            webViewLoadingObserver?.invalidate()
            webViewLoadingObserver = webView?.observe(\.isLoading) { webView, _ in
                guard !webView.isLoading else { return }
                Log("Load Douyin webview finished.")
                
                webView.evaluateJavaScript("document.title") { str, error in
                    guard let s = str as? String else { return }
                    Log("Douyin webview title \(s).")
                    if s.contains("抖音直播") {
                        self.webViewLoadingObserver?.invalidate()
                        self.webViewLoadingObserver = nil
                    } else if s.contains("验证") {
						Log("Douyin reload init url")
                        self.deleteCookies().done {
                            self.webView?.load(.init(url: self.douyinEmptyURL))
                        }.catch({ _ in })
                    }
                }
				
				guard !timerStarted else { return }
				timerStarted = true
				DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
					guard state == .none else { return }
					Log("DouYin Cookies timeout, check cookies.")
					NotificationCenter.default.post(name: .douyinWebcastUpdated, object: nil)
				}
            }
			
            webView?.load(.init(url: douyinEmptyURL))
        }
    }
    

	
	func loadCookies() -> Promise<()> {
		guard let webview = webView else {
			return .init(error: VideoGetError.douyuSignError)
		}
		let cid = "dHRjaWQ=".base64Decode()
		
		return getAllWKCookies().get {
			Log("Douyin getAllWKCookies")
			$0.filter {
				$0.domain.contains("douyin")
			}.forEach {
				self.cookies[$0.name] = $0.value
			}
		}.then { _ in
			when(fulfilled: [
				webview.evaluateJavaScript("localStorage.\(cid)"),
				webview.evaluateJavaScript("window.navigator.userAgent")
			])
		}.get {
			Log("Douyin cid UA")
			let id = $0[0] as? String
			guard let ua = $0[1] as? String else {
				throw CookiesError.invalid
			}
			self.cookies[cid] = id
			self.douyinUA = ua
		}.then { _ in
			webview.evaluateJavaScript(
				"localStorage.\(self.privateKeys[0].base64Decode()) + ',' + localStorage.\(self.privateKeys[1].base64Decode())")
		}.compactMap { re -> [String: String]? in
			
			Log("Douyin privateKeys")
			guard let values = (re as? String)?.split(separator: ",", maxSplits: 1).map(String.init) else { return nil }
			return [
				self.privateKeys[0].base64Decode(): values[0],
				self.privateKeys[1].base64Decode(): values[1]
			]
		}.get {
			self.storageDic = $0
		}.then { _ in
			self.getEnterContent(self.douyinEmptyURL.absoluteString)
		}.done { info in
			Log("Douyin test info \(info.title)")
		}
	}
	
	func deinitWebView() {
		Log("Douyin deinit webview")
		
		self.webView?.stopLoading()
		self.webView?.configuration.userContentController.removeScriptMessageHandler(forName: "fetch")
		self.webView?.removeFromSuperview()
		self.webView = nil
	}
	
    func deleteCookies() -> Promise<()> {
        getAllWKCookies().then {
            when(fulfilled: $0.map(self.deleteWKCookie))
        }.get {
            self.deleteDouYinCookies()
        }
    }
    
    func deleteDouYinCookies() {
        HTTPCookieStorage.shared.cookies?.filter {
            $0.domain.contains("douyin")
        }.forEach(HTTPCookieStorage.shared.deleteCookie)
    }
    
    
    func getAllWKCookies() -> Promise<[HTTPCookie]> {
        Promise { resolver in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies {
                let cookies = $0.filter({ $0.domain.contains("douyin") })
                resolver.fulfill(cookies)
            }
        }
    }
    
    func deleteWKCookie(_ cookie: HTTPCookie) -> Promise<()> {
        Promise { resolver in
            WKWebsiteDataStore.default().httpCookieStore.delete(cookie) {
                resolver.fulfill_()
            }
        }
    }

    deinit {
        prepareTask = nil
    }
    
    enum CookiesError: Error {
        case invalid, waintingForCookies
    }
}

extension DouYin: WKScriptMessageHandler {
	func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
		guard let msg = message.body as? String else { return }
		
		func post() {
			NotificationCenter.default.post(name: .douyinWebcastUpdated, object: nil)
		}
		
		if msg.contains("webcast/im/push/v2") {
			post()
		} else if msg.contains("live.douyin.com/webcast/im/fetch"),
				  msg.contains("last_rtt=-1") {
			post()
		} else if msg.contains("live.douyin.com/aweme/v1/web/emoji/list") {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
				post()
			}
		}
	}
}

struct DouYinInfo: Unmarshaling, LiveInfo {
    var title: String
    var name: String
    var avatar: String
    var cover: String
    var isLiving: Bool
    var site = SupportSites.douyin
    
    var roomId: String
    var webRid: String
    var urls = [String: String]()
    
    
    init(object: MarshaledObject) throws {
        if let rid: String = try? object.value(for: "initialState.roomStore.roomInfo.roomId") {
            roomId = rid
        } else {
            roomId = try object.value(for: "initialState.roomStore.roomInfo.room.id_str")
        }
        webRid = try object.value(for: "initialState.roomStore.roomInfo.web_rid")
        
        title = try object.value(for: "initialState.roomStore.roomInfo.room.title")
        let status: Int = try object.value(for: "initialState.roomStore.roomInfo.room.status")
        isLiving = status == 2
        
        let flvUrls: [String: String]? = try? object.value(for: "initialState.roomStore.roomInfo.room.stream_url.flv_pull_url")
        urls = flvUrls ?? [:]
        
        /*
        let hlsUrls: [String: String] = try object.value(for: "initialState.roomStore.roomInfo.room.stream_url.hls_pull_url_map")
         */
        //        name = try object.value(for: "initialState.roomStore.roomInfo.room.stream_url.live_core_sdk_data.anchor.nickname")
        
        name = try object.value(for: "initialState.roomStore.roomInfo.anchor.nickname")
        
        let covers: [String]? = try object.value(for: "initialState.roomStore.roomInfo.room.cover.url_list")
        cover = covers?.first ?? ""
        
        let avatars: [String] = try object.value(for: "initialState.roomStore.roomInfo.anchor.avatar_thumb.url_list")
        avatar = avatars.first ?? ""
    }
    
    func write(to yougetJson: YouGetJSON) -> YouGetJSON {
        var json = yougetJson
        json.title = title
        
        
        urls.map {
            ($0.key, $0.value.replacingOccurrences(of: "http://", with: "https://"))
        }.sorted { v0, v1 in
            v0.0 < v1.0
        }.enumerated().forEach {
            var stream = Stream(url: $0.element.1)
            stream.quality = 999 - $0.offset
            json.streams[$0.element.0] = stream
        }
        
        return json
    }
}

struct DouYinEnterData: Unmarshaling {
	var infos: [DouYinLiveInfo]
	
	struct DouYinLiveInfo: Unmarshaling, LiveInfo {
		var title: String
		var name: String
		var avatar: String
		var cover: String
		var isLiving: Bool
		var site = SupportSites.douyin
		
		var urls: [String: String]
		var roomId: String
		
		init(object: MarshaledObject) throws {
			title = try object.value(for: "title")
			
			name = (try? object.value(for: "owner.nickname")) ?? ""
			let avatars: [String] = (try? object.value(for: "owner.avatar_thumb.url_list")) ?? []
			avatar = avatars.first ?? ""
			let covers: [String] = (try? object.value(for: "cover.url_list")) ?? []
			cover = covers.first ?? ""
			
			
			let status: Int = try object.value(for: "status")
			isLiving = status == 2
						
			roomId = try object.value(for: "id_str")

			urls = (try? object.value(for: "stream_url.flv_pull_url")) ?? [:]
//			let hlsUrls: [String: String] = try object.value(for: "stream_url.hls_pull_url_map")
		}
		
		func write(to yougetJson: YouGetJSON) -> YouGetJSON {
			var json = yougetJson
			json.title = title


			urls.map {
				($0.key, $0.value.replacingOccurrences(of: "http://", with: "https://"))
			}.sorted { v0, v1 in
				v0.0 < v1.0
			}.enumerated().forEach {
				var stream = Stream(url: $0.element.1)
				stream.quality = 999 - $0.offset
				json.streams[$0.element.0] = stream
			}

			return json
		}
	}
	
	
	init(object: MarshaledObject) throws {
		infos = try object.value(for: "data.data")
		
		let name: String = try object.value(for: "data.user.nickname")
		let avatars: [String] = try object.value(for: "data.user.avatar_thumb.url_list")
		let avatar = avatars.first ?? ""
		
		self.infos = infos.map {
			var info = $0
			if !info.isLiving {
				info.name = name
				info.avatar = avatar
			}
			return info
		}
		
	}
}


struct DouYinEnterData2: Unmarshaling, LiveInfo {
	var title: String
	var name: String
	var avatar: String
	var cover: String
	var isLiving: Bool
	var site = SupportSites.douyin
	
	init(object: MarshaledObject) throws {
		title = "直播已结束"
		name = try object.value(for: "data.user.nickname")
		
		let avatars: [String] = (try? object.value(for: "data.user.avatar_thumb.url_list")) ?? []
		
		avatar = avatars.first ?? ""
		cover = ""
		isLiving = false
	}
}
