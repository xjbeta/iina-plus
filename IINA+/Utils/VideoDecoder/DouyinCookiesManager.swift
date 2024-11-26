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
		case invalid, waintingForCookies, timeout, unknown
	}
	
	let privateKeys = [
		"X2J5dGVkX3BhcmFtX3N3",
		"dHRfc2NpZA==",
		"Ynl0ZWRfYWNyYXdsZXI=",
		"WC1Cb2d1cw==",
		"X3NpZ25hdHVyZQ=="
	]
	
	private var douyinUA = ""
	var storageDic = [String: String]()
	
	func headers() async throws -> HTTPHeaders {
		let cookie = try await cookiesString()
		return await HTTPHeaders([
			"User-Agent": douyinUA(),
			"Cookie": cookie
		])
	}
	
	func cookiesString() async throws -> String {
		try await cookies().map {
			"\($0.key)=\($0.value)"
		}.joined(separator: ";")
	}
	
	
	func douyinUA() async -> String {
		douyinUA
	}
    
    func cookies() async throws -> [String: String] {
        try await tokenBucket.withToken {
            try await internelCookies()
        }
    }
    
	func internelCookies() async throws -> [String: String] {
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
	
	
	func updateInternalCookies(_ cookies: [String: String]) {
		_cookies = cookies
	}
	
	
	func updateRetry(_ retry: Bool) {
		self.shouldRetry = retry
	}
	
	
	func prepareCookies() async throws -> [String: String] {
		Log("start")
        await deleteDouYinCookies()
		storageDic.removeAll()
		
		let config = webviewConfig
		webView = WKWebView(frame: .zero, configuration: config)
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
	
	
	func loadCookies() async throws -> [String: String] {
		guard let webview = webView else {
			throw VideoGetError.douyuSignError
		}
		let cid = "dHRjaWQ=".base64Decode()
		
		let allCookies = await getAllWKCookies()
		
		Log("getAllWKCookies")
		var cookies = [String: String]()
		
		allCookies.filter {
			$0.domain.contains("douyin")
		}.forEach {
			cookies[$0.name] = $0.value
		}
		
		let re1 = try await webview.evaluateJavaScriptAsync("localStorage.\(cid)", type: String.self)
		let re2 = try await webview.evaluateJavaScriptAsync("window.navigator.userAgent", type: String.self)
		
		cookies[cid] = re1
		Log("cid \(re1 ?? ""), ua \(re2 ?? "")")
		
		guard let ua = re2 else {
			Log("nil userAgent")
			throw CookiesError.invalid
		}
		
		let re = try await webview.evaluateJavaScriptAsync("localStorage.\(self.privateKeys[0].base64Decode()) + ',' + localStorage.\(self.privateKeys[1].base64Decode())", type: String.self)
		
		Log("privateKeys")
		
		guard let values = re?.split(separator: ",", maxSplits: 1).map(String.init) else {
			throw VideoGetError.douyuSignError
		}
		
		storageDic = [
			self.privateKeys[0].base64Decode(): values[0],
			self.privateKeys[1].base64Decode(): values[1]
		]
		
		try await verifyCookies(cookies, ua: ua)
		
		douyinUA = ua
		updateInternalCookies(cookies)
		
		return cookies
	}
	
	func verifyCookies(_ cookies: [String: String], ua: String) async throws {
		Log("verifyCookies")
		
		let cookie = cookies.map {
			"\($0.key)=\($0.value)"
		}.joined(separator: ";")
		
		let headers = HTTPHeaders([
			"User-Agent": ua,
			"Cookie": cookie
		])
		
		let u = "https://live.douyin.com/webcast/room/web/enter/?aid=6383&app_name=douyin_web&live_id=1&device_platform=web&language=en-US&cookie_enabled=true&browser_language=en-US&browser_platform=Mac&browser_name=Safari&browser_version=16&web_rid=1&enter_source=&is_need_double_stream=true"
		
		do {
			let _ = try await AF.request(u, headers: headers).serializingData().value
		} catch {
			switch error {
			case AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength):
				updateRetry(true)
				throw CookiesError.invalid
			default:
				Log(error)
			}
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
		deinitWebView()
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
