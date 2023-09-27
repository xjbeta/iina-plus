//
//  HackURLProtocol.swift
//  IINA+
//
//  Created by xjbeta on 2023/9/27.
//  Copyright © 2023 xjbeta. All rights reserved.
//

import Cocoa

private let WebViewPlayerProtocolHandledKey = "WebViewPlayerProtocolHandledKey"

class HackURLProtocol: URLProtocol {
	
	var session: URLSession?
	var dataTask: URLSessionDataTask?
	var stopNotification: NSObjectProtocol?
	
	
	override class func canInit(with request: URLRequest) -> Bool {
		guard let str = request.url?.absoluteString,
			  let origin = request.urlRequest?.allHTTPHeaderFields?["Origin"] else { return false }
		
		if let _ = self.property(forKey: WebViewPlayerProtocolHandledKey, in: request) {
			return false
		}
		
		// webPlayer
		if str.contains(HackUrl.key) {
			return true
		}
		
		// douyin init
		if origin.contains("douyin.com") {
			if str.contains("webcast/im/push/v2") {
				NotificationCenter.default.post(name: .douyinWebcastUpdated, object: nil)
			} else if str.contains("live.douyin.com/webcast/im/fetch"),
					  str.contains("last_rtt=-1") {
				NotificationCenter.default.post(name: .douyinWebcastUpdated, object: nil)
			}
			
			return false
		}
		
		// block kuaishou flv
		if origin.contains("live.kuaishou.com"),
		   str.contains(".flv?") {
			return true
		}
		
		return false
	}
	
	
	override class func canonicalRequest(for request: URLRequest) -> URLRequest {
		request
	}
	
	override class func requestIsCacheEquivalent(_ a: URLRequest, to b: URLRequest) -> Bool {
		super.requestIsCacheEquivalent(a, to: b)
	}
	
	override func startLoading() {
		guard let url = request.url?.absoluteString,
			  url.contains(HackUrl.key),
			  let newRequest = ((request as NSURLRequest).mutableCopy() as? NSMutableURLRequest)
		else { return }
		
		print("URLProtocol", "startLoading")
		
		let hackUrl = HackUrl.decode(url)
		newRequest.url = .init(string: hackUrl.url)
		
		
		switch hackUrl.site {
		case .biliLive:
			newRequest.setValue("https://live.bilibili.com", forHTTPHeaderField: "Referer")
			newRequest.setValue("https://live.bilibili.com", forHTTPHeaderField: "Origin")
		case .qqLive:
			newRequest.setValue("https://live.qq.com", forHTTPHeaderField: "Referer")
			newRequest.setValue("https://live.qq.com", forHTTPHeaderField: "Origin")
			newRequest.setValue("bytes=0-", forHTTPHeaderField: "Range")
			newRequest.setValue("1", forHTTPHeaderField: "Icy-MetaData")
			newRequest.setValue("libmpv", forHTTPHeaderField: "User-Agent")
		default:
			break
		}
		
		HackURLProtocol.setProperty(true, forKey: WebViewPlayerProtocolHandledKey, in: newRequest)
		
		session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
		
		dataTask = session?.dataTask(with: newRequest as URLRequest)
		
		// stopLoading doesn't work for wkwebview
		stopNotification = NotificationCenter.default.addObserver(forName: .webPlayerWindowClosed, object: nil, queue: .main) { [weak self] in
			guard let info = $0.userInfo as? [String: String],
				  let url = info["url"],
				  let self = self else { return }
			
			
			if self.dataTask != nil {
				self.dataTask?.cancel()
				self.dataTask = nil
			}
		}
		
		dataTask?.resume()
	}
	
	override func stopLoading() {
		print("URLProtocol", "stopLoading")
		
		if let n = stopNotification {
			NotificationCenter.default.removeObserver(n)
		}
		
		if dataTask != nil {
			dataTask?.cancel()
			dataTask = nil
		}
	}
}

extension HackURLProtocol: URLSessionDelegate, URLSessionDataDelegate {
	
	func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
		completionHandler(.allow)
	}

	func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		client?.urlProtocol(self, didLoad: data)
	}
	
	
	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		if let error = error {
			client?.urlProtocol(self, didFailWithError: error)
		} else {
			client?.urlProtocolDidFinishLoading(self)
		}
	}
}


class HackUrl: NSObject {
	static let key = "https://hack.iina-plus.key/webplayer/live.flv"
	
	static func encode(_ url: String, site: SupportSites) -> String {
		guard var uc = URLComponents(string: key),
			  let site = site.rawValue.base64Encode().addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
			  let url = url.base64Encode().addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
		else {
			fatalError("HackUrl encode \(url) \(site.rawValue)")
		}
				
		uc.queryItems = [
			.init(name: "site", value: site),
			.init(name: "url", value: url)
		]
		
		return uc.url?.absoluteString ?? key
	}
	
	static func decode(_ url: String) -> (url: String, site: SupportSites) {
		let uc = URLComponents(string: url)

		var url = ""
		var site = ""
		
		uc?.queryItems?.forEach {
			switch $0.name {
			case "site":
				site = $0.value?.removingPercentEncoding?.base64Decode() ?? ""
			case "url":
				url = $0.value?.removingPercentEncoding?.base64Decode() ?? ""
			default:
				break
			}
		}
		
		guard !url.isEmpty, let site = SupportSites(rawValue: site) else {
			fatalError("HackUrl decode \(url)")
		}
		
		return (url, site)
	}
}
