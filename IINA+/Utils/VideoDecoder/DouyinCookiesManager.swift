//
//  DouyinCookiesManager.swift
//  IINA+
//
//  Created by xjbeta on 2024/8/19.
//  Copyright © 2024 xjbeta. All rights reserved.
//

import Cocoa
import WebKit
import Alamofire

@MainActor
class DouyinCookiesManager: NSObject {
    let douyinUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15"
    
	private var webView: WKWebView?
	
	private let douyinEmptyURL = URL(string: "https://live.douyin.com/1")!
	
	private lazy var webviewConfig: WKWebViewConfiguration = {
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
	
	private var douyinWebcastUpdated: (() -> Void)?
	
    private let tokenBucket = TokenBucket(tokens: 1)
	private var _cookies = [String: String]()
	
	private var shouldRetry = false
	
	enum DYState {
		case none
		case preparing
		case checking
		case finish
	}
	
	enum CookiesError: Error {
		case signature, invalid, waintingForCookies, timeout, unknown
	}
	
    private var douyuJSContext: JSContext = {
        let context = JSContext()!
        if #available(macOS 13.3, *) {
            context.isInspectable = true
        }
        
        if let path = Bundle.main.path(forResource: "douyin", ofType: "js") {
            context.evaluateScript(try? String(contentsOfFile: path))
        } else {
            Log("Not found douyin.js.")
        }
        return context
    }()
    
    func request(_ url: String, headers: HTTPHeaders = .init(), cookies: [String: String]? = nil) async throws -> DataRequest {
        var cookies = cookies ?? [:]
        if cookies["ttwid"] == nil {
            cookies = try await self.cookies()
        }
        
        let msToken = generateRandomString(length: 180)
        let msTokenString = "&msToken=\(msToken)"
        
        let up = url.split(separator: "?", maxSplits: 1).map(String.init)
        
        guard let ttwid = cookies["ttwid"],
              up.count == 2,
              let abogus = douyuJSContext.evaluateScript("generate_a_bogus('\(up[1] + msTokenString)', '\(douyinUA)')").toString().addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) else {
            Log("Not found ttwid or abogus.")
            throw CookiesError.signature
        }
        
        let u = url + msTokenString + "&a_bogus=\(abogus)"
        
        
        var headers = headers
        headers.add(name: "User-Agent", value: douyinUA)
        headers.add(name: "Cookie", value: "ttwid=\(ttwid)")
        
        return AF.request(u, headers: headers)
    }
    
    func cookies() async throws -> [String: String] {
        try await tokenBucket.withToken {
            try await internelCookies()
        }
    }
    
	private func internelCookies() async throws -> [String: String] {
		if shouldRetry {
			Log("retry 60s")
			updateInternalCookies([:])
			try await Task.sleep(seconds: 60)
			updateRetry(false)
		}
		
		if _cookies.count > 0 {
//			Log("cached cookies")
			return _cookies
		}
		
		do {
			let cookies = try await withThrowingTaskGroup(of: [String: String].self) { group in
				group.addTask {
					try await self.prepareCookies()
				}
				
				group.addTask {
					try await Task.sleep(seconds: 120)
					Log("timeout")
					throw CookiesError.timeout
				}
				let result = try await group.next()!
				group.cancelAll()
				return result
			}
			return cookies
		} catch {
			Log("should retry, catch \(error)")
			updateRetry(true)
			deinitWebViewAsync()
			throw error
		}
	}
	
	
	private func updateInternalCookies(_ cookies: [String: String]) {
		_cookies = cookies
	}
	
    private func updateRetry(_ retry: Bool) {
		self.shouldRetry = retry
	}
	
    private func prepareCookies() async throws -> [String: String] {
		Log("start")
        await deleteDouYinCookies()
		
		let config = webviewConfig
		webView = WKWebView(frame: .zero, configuration: config)
        webView?.customUserAgent = douyinUA
		guard let webView else { throw CookiesError.unknown }
		
#if DEBUG
		if #available(macOS 13.3, *) {
			webView.isInspectable = true
		}
#endif
		var loadingCount = 0
		
		douyinWebcastUpdated = {
			Log("douyinWebcastUpdated")
			loadingCount = -99
			self.douyinWebcastUpdated = nil
		}
		
		webView.load(.init(url: douyinEmptyURL))
		Log("load")
		
		while loadingCount >= 0 {
			loadingCount += 1
			try await Task.sleep(milliseconds: 500)
//			Log("time")
			let isLoading = webView.isLoading
			guard !isLoading,
				  let title = try await webView.evaluateJavaScriptAsync("document.title", type: String.self) else {
				continue
			}
			
			if loadingCount >= (2 * 125) {
				Log("timeout, check cookies.")
				deinitWebViewAsync()
				throw CookiesError.timeout
			} else if title.contains("抖音直播") {
				Log("web load finish, \(title).")
				loadingCount = -98
				break
			} else if title.contains("验证") {
				Log("web reload.")
				await self.deleteCookies()
				webView.load(.init(url: self.douyinEmptyURL))
			}
		}
		
		Log("loadCookies")
		let cookies = try await loadCookies()
		
		Log("finish.")
		deinitWebViewAsync()
		
		return cookies
	}
	
	
	private func loadCookies() async throws -> [String: String] {
		let allCookies = await getAllWKCookies()
		
		Log("getAllWKCookies")
		var cookies = [String: String]()
		
		allCookies.filter {
			$0.domain.contains("douyin")
		}.forEach {
			cookies[$0.name] = $0.value
		}
        
        try await verifyCookies(cookies)
		updateInternalCookies(cookies)
		
		return cookies
	}
	
    private func verifyCookies(_ cookies: [String: String]) async throws {
		Log("verifyCookies")
				
		let u = "https://live.douyin.com/webcast/room/web/enter/?aid=6383&app_name=douyin_web&live_id=1&device_platform=web&language=zh-CN&enter_from=page_refresh&cookie_enabled=true&screen_width=1920&screen_height=1080&browser_language=zh-CN&browser_platform=MacIntel&browser_name=Safari&browser_version=18.6&web_rid=1&room_id_str=6760514382213548814&enter_source=&is_need_double_stream=false&insert_task_id=&live_reason="
        
        
        
		do {
            let _ = try await self.request(u, cookies: cookies).serializingString().value
		} catch {
			switch error {
			case AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength):
                Log("Empty verifyCookies response")
			default:
				Log(error)
			}
            updateRetry(true)
            throw CookiesError.invalid
		}
	}
	
	
	func deleteCookies() async {
		let cookies = await getAllWKCookies()
		
		await withTaskGroup(of: Void.self) { group in
			cookies.forEach { c in
				group.addTask {
					await self.deleteWKCookie(c)
				}
			}
		}
		
        await deleteDouYinCookies()
	}
	
    func deleteDouYinCookies() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                HTTPCookieStorage.shared.cookies?.filter {
                    $0.domain.contains("douyin")
                }.forEach(HTTPCookieStorage.shared.deleteCookie)
                continuation.resume()
            }
        }
	}
	
	func getAllWKCookies() async -> [HTTPCookie] {
		let all = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
		return all.filter({ $0.domain.contains("douyin") })
	}
	
	
	func deleteWKCookie(_ cookie: HTTPCookie) async {
		await WKWebsiteDataStore.default().httpCookieStore.deleteCookie(cookie)
	}
	
	
	func deinitWebViewAsync() {
//		deinitWebView()
	}
    
    private func generateRandomString(length: Int) -> String {
        let characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"
        return (0..<length).map { _ in
            String(characters.randomElement() ?? "G")
        }.joined()
    }
	
	func deinitWebView() {
		Log("Douyin deinit webview")
		douyinWebcastUpdated = nil
		webView?.stopLoading()
		webView?.removeFromSuperview()
		webView = nil
	}
}

extension DouyinCookiesManager: WKScriptMessageHandler {
	func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
		guard let msg = message.body as? String else { return }
		
		func post() {
			douyinWebcastUpdated?()
		}
		
//        let endpoints = [
//            "webcast/im/push/v2",
//            "aweme/v1/web/get/user/settings",
//            "aweme/v1/web/emoji/list"
//        ]
//
//        if endpoints.contains(where: { msg.contains($0) }) {
//            post()
//        }
        
        if msg.contains("webcast/room/web/enter") {
            post()
        }
	}
}
