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
    
    var storageDic: [String: String] {
        proc.videoDecoder.douyin.storageDic
    }
    
    var cookies = [String: String]()
    
    var roomId = ""
    
    
    private var webview: WKWebView? = WKWebView()
    private var requestTimer: Timer?
    
    var privateKeys: [String] {
        proc.videoDecoder.douyin.privateKeys
    }
    
    var requestPrepared: ((URLRequest) -> Void)?
    
    func initWS() {
        let ws = "d3NzOi8vd2ViY2FzdDMtd3Mtd2ViLWhsLmRvdXlpbi5jb20vd2ViY2FzdC9pbS9wdXNoL3YyLz9hcHBfbmFtZT1kb3V5aW5fd2ViJnZlcnNpb25fY29kZT0xODA4MDAmd2ViY2FzdF9zZGtfdmVyc2lvbj0xLjMuMCZ1cGRhdGVfdmVyc2lvbl9jb2RlPTEuMy4wJmNvbXByZXNzPWd6aXAmaG9zdD1odHRwczovL2xpdmUuZG91eWluLmNvbSZhaWQ9NjM4MyZsaXZlX2lkPTEmZGlkX3J1bGU9MyZkZWJ1Zz10cnVlJmVuZHBvaW50PWxpdmVfcGMmc3VwcG9ydF93cmRzPTEmaW1fcGF0aD0vd2ViY2FzdC9pbS9mZXRjaC8mZGV2aWNlX3BsYXRmb3JtPXdlYiZjb29raWVfZW5hYmxlZD10cnVlJmJyb3dzZXJfbGFuZ3VhZ2U9ZW4tVVMmYnJvd3Nlcl9wbGF0Zm9ybT1NYWNJbnRlbCZicm93c2VyX29ubGluZT10cnVlJnR6X25hbWU9QXNpYS9TaGFuZ2hhaSZpZGVudGl0eT1hdWRpZW5jZSZoZWFydGJlYXREdXJhdGlvbj0xMDAwMCZyb29tX2lkPQ==".base64Decode() + "\(roomId)"
        
        guard let u = URL(string: ws) else { return }
        var req = URLRequest(url: u)
        let cookieString = cookies.map {
            "\($0.key)=\($0.value)"
        }.joined(separator: ";")
        
        req.setValue(cookieString, forHTTPHeaderField: "Cookie")
        req.setValue("https://live.douyin.com", forHTTPHeaderField: "referer")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        
        requestPrepared?(req)
    }
    
    
    func start(_ url: String) {
        self.url = url
        let path = Bundle.main.url(forResource: "douyin", withExtension: "html")!
        DispatchQueue.main.async {
            self.webview?.navigationDelegate = self
            self.webview?.loadFileURL(path, allowingReadAccessTo: path.deletingLastPathComponent())
        }
    }
    
    
    func getRoomId() -> Promise<()> {
        if roomId != "" {
            return .init()
        } else {
            let dy = proc.videoDecoder.douyin
            return dy.liveInfo(url).done {
                self.cookies = dy.cookies
                self.roomId = ($0 as! DouYinInfo).roomId
            }
        }
    }
    
    func prepareCookies() -> Promise<()> {
        
        let kvs = [
            privateKeys[0].base64Decode(),
            privateKeys[1].base64Decode()
        ].compactMap {
            storageDic[$0] == nil ? nil : ($0, storageDic[$0]!)
        }
        
        guard kvs.count == 2, let webview = self.webview else {
            return .init(error: DouYinDMError.deinited)
        }
        
        let acts = kvs.map {
            webview.evaluateJavaScript("window.sessionStorage.setItem('\($0.0)', '\($0.1)')").asVoid()
        }

        return when(fulfilled: acts)
    }
    
    enum DouYinDMError: Error {
        case deinited
    }
    
    func startRequests() {
        getRoomId().then {
            self.prepareCookies()
        }.done {
            self.initWS()
        }.ensure(on: .main) {
            self.stop()
        }.catch {
            Log($0)
        }
    }
    
    func stop() {
        webview?.navigationDelegate = nil
        webview?.stopLoading()
        webview = nil
    }
}

extension DouYinDM: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        startRequests()
    }
}
