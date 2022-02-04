//
//  JSPlayerViewController.swift
//  IINA+
//
//  Created by xjbeta on 1/26/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa
import WebKit

protocol JSPlayerDelegate {
    func jsPlayer(_ viewController: JSPlayerViewController, didFinish webview: WKWebView)
    
    
}


class JSPlayerViewController: NSViewController {
    @IBOutlet var ratioConstraint: NSLayoutConstraint!
    @IBOutlet var webView: WKWebView!
    

    
    var delegate: JSPlayerDelegate?
    var danmaku: Danmaku?
    
    enum ScriptMessageKeys: String, CaseIterable {
        case print, size
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        initWebView()
        loadWebView()
    }
    
    func initWebView() {
        // Background Color
        view.wantsLayer = true
        view.layer?.backgroundColor = .black
        webView.setValue(false, forKey: "drawsBackground")
        

        
    }
    
    func loadWebView() {
        let port = Preferences.shared.dmPort
        webView.navigationDelegate = self
        ScriptMessageKeys.allCases.forEach {
            webView.configuration.userContentController.add(self, name: $0.rawValue)
        }
        
        
        let u = "http://127.0.0.1:\(port)/danmaku/index.htm"
        guard let url = URL(string: u) else {
            return
        }
        let request = URLRequest(url: url)
        webView.load(request)
    }
    
    func open(_ url: String) {
        webView.evaluateJavaScript("window.openUrl('\(url)');")
        webView.evaluateJavaScript("initContent('\(UUID().uuidString)', \(Preferences.shared.dmPort));")
    }
    
    func resize() {
        webView.evaluateJavaScript("window.resize();")
    }
    
    func startDM(_ url: String) {
        self.danmaku = Danmaku(url)
        self.danmaku?.loadDM()
        self.danmaku?.delegate = self
    }
    
}

extension JSPlayerViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Log("Finish")
        
        delegate?.jsPlayer(self, didFinish: webView)
        
    }
}

extension JSPlayerViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        
        guard let key = ScriptMessageKeys(rawValue: message.name) else {
            return
        }
        
        switch key {
        case .print:
            print("Player, ", message.body)
        case .size:
            guard let wh = message.body as? [CGFloat],
                    wh.count == 2 else {
                return
            }
            let w = wh[0]
            let h = wh[1]
            let size = CGSize(width: w, height: h)
            print(size)
            ratioConstraint.animator().constant = w / h
            resize()
        }
    }
}

extension JSPlayerViewController: DanmakuDelegate {
    struct DanmakuEvent: Encodable {
        var method: String
        var text: String
    }
    
    func send(_ method: DanamkuMethod, text: String, id: String) {
        guard let data = try? JSONEncoder().encode(DanmakuEvent(method: method.rawValue, text: text)),
            let str = String(data: data, encoding: .utf8) else { return }
        if method != .sendDM {
            print(str)
        }
        webView.evaluateJavaScript("window.dmMessage(\(str));")
    }
}
