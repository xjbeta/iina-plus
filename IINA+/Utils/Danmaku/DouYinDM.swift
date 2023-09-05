//
//  DouYinDM.swift
//  IINA+
//
//  Created by xjbeta on 2/21/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa
import WebKit
import PromiseKit

class DouYinDM: NSObject {
	var url = ""
	
	let proc = Processes.shared
	var ua: String {
		proc.videoDecoder.douyin.douyinUA
	}
	
	var privateKeys: [String] {
		proc.videoDecoder.douyin.privateKeys
	}
	
	var storageDic: [String: String] {
		proc.videoDecoder.douyin.storageDic
	}
	
	
	var cookies = [String: String]()
	
	var roomId = ""
	
	
	private var webView = WKWebView()
	var requestPrepared: ((URLRequest) -> Void)?
	
	func initWS() -> Promise<URLRequest> {
		let s = "bGl2ZV9pZD0xLGFpZD02MzgzLHZlcnNpb25fY29kZT0xODA4MDAsd2ViY2FzdF9zZGtfdmVyc2lvbj0xLjMuMCxyb29tX2lkPQ==".base64Decode()
		+ roomId
		+ "LHN1Yl9yb29tX2lkPSxzdWJfY2hhbm5lbF9pZD0sZGlkX3J1bGU9Myx1c2VyX3VuaXF1ZV9pZD0sZGV2aWNlX3BsYXRmb3JtPXdlYixkZXZpY2VfdHlwZT0sYWM9LGlkZW50aXR5PWF1ZGllbmNl".base64Decode()
		
		let code = "\("d2luZG93LmJ5dGVkX2FjcmF3bGVyLmZyb250aWVyU2lnbg==".base64Decode())({'\("WC1NUy1TVFVC".base64Decode())':'\(s.md5())'})"
		
		return webView.evaluateJavaScript(code).map { re -> URLRequest in
			guard let value = (re as? [String: String])?.first?.value else {
				throw DouYinDMError.signFailed
			}
			
			var ws = "d3NzOi8vd2ViY2FzdDMtd3Mtd2ViLWhsLmRvdXlpbi5jb20vd2ViY2FzdC9pbS9wdXNoL3YyLz9hcHBfbmFtZT1kb3V5aW5fd2ViJnZlcnNpb25fY29kZT0xODA4MDAmd2ViY2FzdF9zZGtfdmVyc2lvbj0xLjMuMCZ1cGRhdGVfdmVyc2lvbl9jb2RlPTEuMy4wJmNvbXByZXNzPWd6aXAmaG9zdD1odHRwczovL2xpdmUuZG91eWluLmNvbSZhaWQ9NjM4MyZsaXZlX2lkPTEmZGlkX3J1bGU9MyZkZWJ1Zz10cnVlJmVuZHBvaW50PWxpdmVfcGMmc3VwcG9ydF93cmRzPTEmaW1fcGF0aD0vd2ViY2FzdC9pbS9mZXRjaC8mZGV2aWNlX3BsYXRmb3JtPXdlYiZjb29raWVfZW5hYmxlZD10cnVlJmJyb3dzZXJfbGFuZ3VhZ2U9ZW4tVVMmYnJvd3Nlcl9wbGF0Zm9ybT1NYWNJbnRlbCZicm93c2VyX29ubGluZT10cnVlJnR6X25hbWU9QXNpYS9TaGFuZ2hhaSZpZGVudGl0eT1hdWRpZW5jZSZoZWFydGJlYXREdXJhdGlvbj0xMDAwMCZyb29tX2lkPQ==".base64Decode()
			
			ws += self.roomId
			ws += "JnNpZ25hdHVyZT0=".base64Decode()
			ws += value
			
			print("dy ws, \(ws)")
			
			
			guard let u = URL(string: ws) else {
				throw DouYinDMError.signFailed
			}
			var req = URLRequest(url: u)
			let cookieString = self.cookies.map {
				"\($0.key)=\($0.value)"
			}.joined(separator: ";")
			
			req.setValue(cookieString, forHTTPHeaderField: "Cookie")
			req.setValue("https://live.douyin.com", forHTTPHeaderField: "referer")
			req.setValue(self.ua, forHTTPHeaderField: "User-Agent")
			
			return req
		}
	}
	
	func start(_ url: String) {
		self.url = url
		let path = Bundle.main.url(forResource: "douyin", withExtension: "html", subdirectory: "DouYin")!
		DispatchQueue.main.async {
			self.webView.navigationDelegate = self
			self.webView.loadFileURL(path, allowingReadAccessTo: path.deletingLastPathComponent())
		}
	}
	
	func getRoomId() -> Promise<()> {
		if roomId != "" {
			return .init()
		} else {
			let dy = proc.videoDecoder.douyin
			return dy.liveInfo(url).done {
				self.cookies = dy.cookies
				if let rid = ($0 as? DouYinEnterData.DouYinLiveInfo)?.roomId {
					self.roomId = rid
				} else {
					self.roomId = ($0 as! DouYinInfo).roomId
				}
			}
		}
	}
	
	enum DouYinDMError: Error {
		case signFailed
		case cookiesCount
	}
	
	func prepareCookies() -> Promise<()> {
		
		let kvs = [
			privateKeys[0].base64Decode(),
			privateKeys[1].base64Decode()
		].compactMap {
			storageDic[$0] == nil ? nil : ($0, storageDic[$0]!)
		}
		
		if kvs.count != 2 {
			Log("DouYinDMError.cookiesCount")
		}
		
		let acts = kvs.map {
			webView.evaluateJavaScript("window.sessionStorage.setItem('\($0.0)', '\($0.1)')").asVoid()
		}
		
		return when(fulfilled: acts)
	}
	
	func startRequests() {
		getRoomId().then {
			self.prepareCookies()
		}.then {
			self.initWS()
		}.done {
			self.requestPrepared?($0)
		}.ensure(on: .main) {
			self.stop()
		}.catch {
			Log($0)
		}
	}
	
	func stop() {
		DispatchQueue.main.async { [weak self] in
			guard let self = self else { return }
			self.webView.navigationDelegate = nil
			self.webView.stopLoading()
			self.webView = .init()
		}
	}
}


extension DouYinDM: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        startRequests()
    }
}
