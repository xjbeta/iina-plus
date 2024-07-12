//
//  DouYin.swift
//  IINA+
//
//  Created by xjbeta on 2/19/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa
import WebKit
import SwiftSoup
import Alamofire
import Marshal

class DouYin: NSObject, SupportSiteProtocol {
    
    // MARK: - DY Init
    var webView: WKWebView?
	
    var dyFinishNotification: NSObjectProtocol?
    
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
	
	@MainActor
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
	
	enum DYState {
		case none
		case preparing
		case checking
		case finish
	}
	
	@MainActor
	private var cookiesTaskState: DYState = .none
	
	lazy var cookiesManager = DouyinCookiesManager(prepareArgs: prepareArgs)
	
	private var invalidCookiesCount = 0
	
	func liveInfo(_ url: String) async throws -> any LiveInfo {
		let _ = try await cookiesManager.initCookies()
		let info = try await getEnterContent(url)
		return info
	}
	
	func decodeUrl(_ url: String) async throws -> YouGetJSON {
		let info = try await liveInfo(url)
		var json = YouGetJSON(rawUrl: url)
		
		if let info = info as? DouYinEnterData.DouYinLiveInfo {
			json = info.write(to: json)
		} else if let info = info as? DouYinInfo {
			json = info.write(to: json)
		} else {
			throw VideoGetError.notFindUrls
		}
		
		return json
	}
    
	
	func getEnterContent(_ url: String) async throws -> LiveInfo {
		let cookieString = await cookiesManager.cookiesString
		
		let headers = HTTPHeaders([
			"User-Agent": douyinUA,
			"referer": url,
			"Cookie": cookieString
		])
		
		guard let pc = NSURL(string: url)?.pathComponents,
			  pc.count >= 2,
			  pc[0] == "/" else {
			throw VideoGetError.invalidLink
		}
		
		let rid = try {
			if let i = Int(pc[1]) {
				return pc[1]
			} else if pc.count >= 4, pc[2] == "live", let i = Int(pc[3]) {
				return pc[3]
			} else {
				throw VideoGetError.invalidLink
			}
		}()
		
		let u = "https://live.douyin.com/webcast/room/web/enter/?aid=6383&app_name=douyin_web&live_id=1&device_platform=web&language=en-US&cookie_enabled=true&browser_language=en-US&browser_platform=Mac&browser_name=Safari&browser_version=16&web_rid=\(rid)&enter_source=&is_need_double_stream=true"
		
		let data = try await AF.request(u, headers: headers).serializingData().value
		let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(data)
		let enterData = try DouYinEnterData(object: jsonObj)
		
		if let info = enterData.infos.first {
			return info
		} else if let info = try? DouYinEnterData2(object: jsonObj) {
			return info
		} else {
			throw VideoGetError.notFountData
		}
	}
	
    
    func getContent(_ url: String) async throws -> LiveInfo {
		let cookieString = await cookiesManager.cookiesString
        
        let headers = HTTPHeaders([
            "User-Agent": douyinUA,
            "referer": url,
            "Cookie": cookieString
        ])
        
		let text = try await AF.request(url, headers: headers).serializingString().value
		guard let json = getJSON(text) else {
			self.invalidCookiesCount += 1
			if self.invalidCookiesCount == 5 {
				self.invalidCookiesCount = 0
				await cookiesManager.removeAll()
				
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
	
	
	func prepareArgs() async throws -> [String: String] {
        storageDic.removeAll()
        deleteDouYinCookies()
		
		let config = await webviewConfig
		await MainActor.run {
			cookiesTaskState = .preparing
		}
		webView = await WKWebView(frame: .zero, configuration: config)
		guard let webView else { throw VideoGetError.douyuSignError }
		Log("DouYin Cookies start.")
		
#if DEBUG
		await MainActor.run {
			if #available(macOS 13.3, *) {
				webView.isInspectable = true
			}
		}
#endif
		
		async let noti = Task {
			let _ = await webcastUpdatedNotification()
			await MainActor.run {
				cookiesTaskState = .checking
			}
		}
		
		await webView.load(.init(url: douyinEmptyURL))
		
		var loadingCount = 0
		while loadingCount >= 0 {
			loadingCount += 1
			try await Task.sleep(nanoseconds: 330_000_000)
			let isLoading = await webView.isLoading
			guard !isLoading,
				  let title = try await webView.evaluateJavaScriptAsync("document.title") as? String else {
				continue
			}
			
			if loadingCount >= (3 * 120) {
				Log("DouYin Cookies timeout, check cookies.")
				loadingCount = -1
				break
			} else if await cookiesTaskState != .preparing {
				Log("DouYin Cookies webcastUpdated.")
				loadingCount = -2
				break
			} else if title.contains("抖音直播") {
				Log("Douyin cookies web load finish, \(title).")
				loadingCount = -3
				break
			} else if title.contains("验证") {
				Log("Douyin cookies web reload.")
				await self.deleteCookies()
				await webView.load(.init(url: self.douyinEmptyURL))
			}
		}
		
		if loadingCount < -1 {
			let _ = await noti
		}
		
		await MainActor.run {
			cookiesTaskState = .checking
			Log("Douyin cookies checking.")
		}
		
		let cookies = try await loadCookies()
		await MainActor.run {
			cookiesTaskState = .finish
			Log("Douyin cookies finish.")
		}
		await deinitWebView()
		
		return cookies
    }
    

	
	func loadCookies() async throws -> [String: String] {
		guard let webview = webView else {
			throw VideoGetError.douyuSignError
		}
		let cid = "dHRjaWQ=".base64Decode()
		
		let allCookies = await getAllWKCookies()
		
		Log("Douyin getAllWKCookies")
		var cookies = [String: String]()
		
		allCookies.filter {
			$0.domain.contains("douyin")
		}.forEach {
			cookies[$0.name] = $0.value
		}
		
		let re1 = try await webview.evaluateJavaScriptAsync("localStorage.\(cid)")
		let re2 = try await webview.evaluateJavaScriptAsync("window.navigator.userAgent")
		
		
		cookies[cid] = re1 as? String
		guard let ua = re2 as? String else {
			throw CookiesError.invalid
		}
		douyinUA = ua
		
		let re = try await webview.evaluateJavaScriptAsync("localStorage.\(self.privateKeys[0].base64Decode()) + ',' + localStorage.\(self.privateKeys[1].base64Decode())")
		
		Log("Douyin privateKeys")
		
		guard let values = (re as? String)?.split(separator: ",", maxSplits: 1).map(String.init) else {
			throw VideoGetError.douyuSignError
		}
		
		storageDic = [
			self.privateKeys[0].base64Decode(): values[0],
			self.privateKeys[1].base64Decode(): values[1]
		]
		
		await cookiesManager.setCookies(cookies)
		
		let info = try await getEnterContent(douyinEmptyURL.absoluteString)
		
		Log("Douyin test info \(info.title)")
		
		return cookies
	}
	
	@MainActor
	func deinitWebView() async {
		Log("Douyin deinit webview")
		
		webView?.stopLoading()
		webView?.configuration.userContentController.removeScriptMessageHandler(forName: "fetch")
		webView?.removeFromSuperview()
		webView = nil
	}
	
    func deleteCookies() async {
		let cookies = await getAllWKCookies()
		
		await withTaskGroup(of: Int.self) { group in
			cookies.forEach { c in
				group.addTask {
					await self.deleteWKCookie(c)
					return 0
				}
			}
		}
		
		deleteDouYinCookies()
    }
    
    func deleteDouYinCookies() {
        HTTPCookieStorage.shared.cookies?.filter {
            $0.domain.contains("douyin")
        }.forEach(HTTPCookieStorage.shared.deleteCookie)
    }
	
	func webcastUpdatedNotification() async -> Notification {
		await withCheckedContinuation { continuation in
			dyFinishNotification = NotificationCenter.default.addObserver(forName: .douyinWebcastUpdated, object: nil, queue: nil) { n in
				if let n = self.dyFinishNotification {
					NotificationCenter.default.removeObserver(n)
				}
				continuation.resume(returning: n)
			}
		}
	}
    
    
	@MainActor
    func getAllWKCookies() async -> [HTTPCookie] {
		let all = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
		return all.filter({ $0.domain.contains("douyin") })
    }
    
    func deleteWKCookie(_ cookie: HTTPCookie) async {
		await WKWebsiteDataStore.default().httpCookieStore.deleteCookie(cookie)
    }

    deinit {
//        prepareTask = nil
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
            ($0.key, $0.value.https())
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
				($0.key, $0.value.https())
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
