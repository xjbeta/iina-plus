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

let JSPlayerSchemeName = "plusplayer"

class JSPlayerURLSchemeHandler: NSObject, WKURLSchemeHandler {
	
	
	var map = [URLSessionDataTask: WKURLSchemeTask]()
	var session: URLSession?
	
	func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
		let schemeName = JSPlayerSchemeName
		
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
		case .huya:
			request.setValue("https://www.huya.com/", forHTTPHeaderField: "Referer")
			request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3.1 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
		default:
			break
		}
		
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
		
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

extension JSPlayerURLSchemeHandler: URLSessionDelegate, @preconcurrency URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        
        guard let schemeTask = map[dataTask] else {
            dataTask.cancel()
            return .cancel
        }
        schemeTask.didReceive(response)
        return .allow
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task { @MainActor in
            guard let schemeTask = self.map[dataTask] else {
                dataTask.cancel()
                return
            }
            schemeTask.didReceive(data)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in
            guard let dataTask = task as? URLSessionDataTask,
                  let schemeTask = self.map[dataTask] else {
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

