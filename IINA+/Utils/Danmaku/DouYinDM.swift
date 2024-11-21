//
//  DouYinDM.swift
//  IINA+
//
//  Created by xjbeta on 2/21/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa
import WebKit

@MainActor
class DouYinDM: NSObject {
	var url = ""
	
	
	private var webView = WKWebView()
	var requestPrepared: ((URLRequest) -> Void)?
	
	func initWS(_ roomId: String, cookies: [String: String], ua: String) async throws -> URLRequest {
		let s = "bGl2ZV9pZD0xLGFpZD02MzgzLHZlcnNpb25fY29kZT0xODA4MDAsd2ViY2FzdF9zZGtfdmVyc2lvbj0xLjMuMCxyb29tX2lkPQ==".base64Decode()
		+ roomId
		+ "LHN1Yl9yb29tX2lkPSxzdWJfY2hhbm5lbF9pZD0sZGlkX3J1bGU9Myx1c2VyX3VuaXF1ZV9pZD0sZGV2aWNlX3BsYXRmb3JtPXdlYixkZXZpY2VfdHlwZT0sYWM9LGlkZW50aXR5PWF1ZGllbmNl".base64Decode()
		
		let code = "\("d2luZG93LmJ5dGVkX2FjcmF3bGVyLmZyb250aWVyU2lnbg==".base64Decode())({'\("WC1NUy1TVFVC".base64Decode())':'\(s.md5())'})"
		
		
		let re = try await webView.evaluateJavaScriptAsync(code, type: [String: String].self)
		
		guard let value = re?.first?.value else {
			throw DouYinDMError.signFailed
		}
		
		var ws = "d3NzOi8vd2ViY2FzdDMtd3Mtd2ViLWhsLmRvdXlpbi5jb20vd2ViY2FzdC9pbS9wdXNoL3YyLz9hcHBfbmFtZT1kb3V5aW5fd2ViJnZlcnNpb25fY29kZT0xODA4MDAmd2ViY2FzdF9zZGtfdmVyc2lvbj0xLjMuMCZ1cGRhdGVfdmVyc2lvbl9jb2RlPTEuMy4wJmNvbXByZXNzPWd6aXAmaG9zdD1odHRwczovL2xpdmUuZG91eWluLmNvbSZhaWQ9NjM4MyZsaXZlX2lkPTEmZGlkX3J1bGU9MyZkZWJ1Zz10cnVlJmVuZHBvaW50PWxpdmVfcGMmc3VwcG9ydF93cmRzPTEmaW1fcGF0aD0vd2ViY2FzdC9pbS9mZXRjaC8mZGV2aWNlX3BsYXRmb3JtPXdlYiZjb29raWVfZW5hYmxlZD10cnVlJmJyb3dzZXJfbGFuZ3VhZ2U9ZW4tVVMmYnJvd3Nlcl9wbGF0Zm9ybT1NYWNJbnRlbCZicm93c2VyX29ubGluZT10cnVlJnR6X25hbWU9QXNpYS9TaGFuZ2hhaSZpZGVudGl0eT1hdWRpZW5jZSZoZWFydGJlYXREdXJhdGlvbj0xMDAwMCZyb29tX2lkPQ==".base64Decode()
		
		ws += roomId
		ws += "JnNpZ25hdHVyZT0=".base64Decode()
		ws += value
		
		print("dy ws, \(ws)")
		
		guard let u = URL(string: ws) else {
			throw DouYinDMError.signFailed
		}
		var req = URLRequest(url: u)
		let cookieString = cookies.map {
			"\($0.key)=\($0.value)"
		}.joined(separator: ";")
		
		req.setValue(cookieString, forHTTPHeaderField: "Cookie")
		req.setValue("https://live.douyin.com", forHTTPHeaderField: "referer")
		req.setValue(ua, forHTTPHeaderField: "User-Agent")
		
		return req
	}
	
	func start(_ url: String) {
		self.url = url
		let path = Bundle.main.url(forResource: "douyin", withExtension: "html", subdirectory: "DouYin")!
		DispatchQueue.main.async {
			self.webView.navigationDelegate = self
			self.webView.loadFileURL(path, allowingReadAccessTo: path.deletingLastPathComponent())
		}
	}
	
	func getRoomId() async throws -> String {
		let douyin = await Processes.shared.videoDecoder.douyin
		let info = try await douyin.liveInfo(self.url)
		
		if let rid = (info as? DouYinEnterData.DouYinLiveInfo)?.roomId {
			return rid
		} else {
			return (info as! DouYinInfo).roomId
		}
	}
	
	enum DouYinDMError: Error {
		case signFailed
		case cookiesCount
	}
	
	func prepareCookies() async {
		let douyin = await Processes.shared.videoDecoder.douyin
		
		let storageDic = douyin.cookiesManager.storageDic
		let privateKeys = douyin.cookiesManager.privateKeys
		
		let kvs = [
			privateKeys[0].base64Decode(),
			privateKeys[1].base64Decode()
		].compactMap {
			storageDic[$0] == nil ? nil : ($0, storageDic[$0]!)
		}
		
		if kvs.count != 2 {
			Log("DouYinDMError.cookiesCount")
		}
		
		for kv in kvs {
			let _ = try? await webView.evaluateJavaScriptAsync("window.sessionStorage.setItem('\(kv.0)', '\(kv.1)')", type: String.self)
		}
	}
	
	func startRequests() {
		Task {
            do {
				let rid = try await getRoomId()
				let douyin = await Processes.shared.videoDecoder.douyin
				
				let cookies = try await douyin.cookiesManager.cookies()
				let ua = await douyin.cookiesManager.douyinUA()
				
				await prepareCookies()
				let req = try await initWS(rid, cookies: cookies, ua: ua)
				
				requestPrepared?(req)
            } catch {
                Log("DouYinDM request error \(error)")
            }
			
			stop()
        }
	}
	
	func stop() {
		webView.navigationDelegate = nil
		webView.stopLoading()
		webView = .init()
	}
}


extension DouYinDM: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        startRequests()
    }
}
