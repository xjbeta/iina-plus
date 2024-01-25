//
//  JSPlayerURLSchemeHandler.swift
//  IINA+
//
//  Created by xjbeta on 2023/10/31.
//  Copyright © 2023 xjbeta. All rights reserved.
//

import Cocoa
import WebKit

// https://github.com/snowhaze/SnowHaze-iOS/blob/master/SnowHaze/TorSchemeHandler.swift

class JSPlayerURLSchemeHandler: NSObject, WKURLSchemeHandler {
	
	static let schemeName = "plusplayer"
	
	var map = [URLSessionDataTask: WKURLSchemeTask]()
	var session: URLSession?
	
	func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
		let schemeName = JSPlayerURLSchemeHandler.schemeName
		
		guard let url = urlSchemeTask.request.url?.absoluteString,
			  url.hasPrefix(schemeName)
		else { return }
		
		let hackUrl = JSPlayerURL.decode(url)
		
		var request = urlSchemeTask.request
		request.url = .init(string: hackUrl.url)
		request.timeoutInterval = 180
		
		request.setValue("bytes=0-", forHTTPHeaderField: "Range")
		request.setValue("keep-alive", forHTTPHeaderField: "Connection")
		
		switch hackUrl.site {
		case .biliLive:
			request.setValue("https://live.bilibili.com", forHTTPHeaderField: "Referer")
			request.setValue("https://live.bilibili.com", forHTTPHeaderField: "Origin")
		case .qqLive:
			request.setValue("libmpv", forHTTPHeaderField: "User-Agent")
		default:
			break
		}
		
		session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
		
		if let dataTask = session?.dataTask(with: request) {
			dataTask.resume()
			map[dataTask] = urlSchemeTask
		}
	}
	
	func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
		guard let task = map.first(where: { $0.value === urlSchemeTask })?.key else {
			return
		}
		map[task] = nil
		task.cancel()
	}
	
	func stop() {
		session?.invalidateAndCancel()
		map.forEach {
			$0.key.cancel()
		}
		map = [:]
	}
}

extension JSPlayerURLSchemeHandler: URLSessionDelegate, URLSessionDataDelegate {
	
	func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
		DispatchQueue.main.async { [weak self] in
			guard let self = self else {
				return
			}
			guard let schemeTask = self.map[dataTask] else {
				dataTask.cancel()
				return completionHandler(.cancel)
			}
			schemeTask.didReceive(response)
			completionHandler(.allow)
		}
	}

	func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		DispatchQueue.main.async { [weak self] in
			guard let self = self else {
				return
			}
			guard let schemeTask = self.map[dataTask] else {
				dataTask.cancel()
				return
			}
			schemeTask.didReceive(data)
		}
	}
	
	
	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		DispatchQueue.main.async { [weak self] in
			guard let self = self else {
				return
			}
			guard let dataTask = task as? URLSessionDataTask, let schemeTask = self.map[dataTask] else {
				task.cancel()
				return
			}
			self.map[dataTask] = nil
			if let error = error {
				schemeTask.didFailWithError(error)
			} else {
				schemeTask.didFinish()
			}
		}
	}
	
}

