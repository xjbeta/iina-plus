//
//  JSPlayerViewController.swift
//  IINA+
//
//  Created by xjbeta on 1/26/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa
import PromiseKit
import WebKit

class JSPlayerViewController: NSViewController {
    
// MARK: - WebView
    @IBOutlet var ratioConstraint: NSLayoutConstraint!
    @IBOutlet var webView: WKWebView!

// MARK: - Player Controllers
    
    @IBOutlet var loadingProgressIndicator: NSProgressIndicator!
    
    
    @IBOutlet var reloadButton: NSButton!
    @IBAction func reloadVideo(_ sender: NSButton) {
        
    }
    
    @IBOutlet var volumeButton: NSButton!
    @IBAction func mute(_ sender: NSButton) {
        
    }
    
    @IBOutlet var volumeSlider: NSSlider!
    @IBAction func volumeChanged(_ sender: NSSlider) {
        
    }
    
    
    @IBOutlet var linesPopUpButton: NSPopUpButton!
    @IBAction func lineChanged(_ sender: NSPopUpButton) {
        
    }
    
    @IBOutlet var quailtyButton: NSButton!
    @IBOutlet var quailtyHeightLayoutConstraint: NSLayoutConstraint!
    @IBOutlet var quailtyTableView: NSTableView!
    @IBAction func quailtyChanged(_ sender: NSTableView) {
        
        let i = quailtyTableView.selectedRow
        guard let re = result,
              re.videos.count > i else { return }

        let kv = re.videos[i]
        key = kv.key
        
        openResult()
    }
    
    
    var url = ""
    
    var webViewFinishLoaded = false
    
    var windowWillClose = false
    var key: String?
    var result: YouGetJSON?
    
    var danmaku: Danmaku?
    
    enum ScriptMessageKeys: String, CaseIterable {
        case print,
             size,
             
             error,
             loadingComplete,
             recoveredEarlyEof
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        startLoading()
        initWebView()
        loadWebView()
    }
    
    func startLoading(stop: Bool = false) {
        reloadButton.isHidden = !stop
        loadingProgressIndicator.isHidden = stop
        
        if stop {
            loadingProgressIndicator.stopAnimation(nil)
        } else {
            loadingProgressIndicator.startAnimation(nil)
        }
    }
    
    func decodeUrl() {
        let proc = Processes.shared
        proc.stopDecodeURL()
        proc.videoGet.liveInfo(url, false).get {
            if !$0.isLiving {
                throw VideoGetError.isNotLiving
            }
        }.then { _ in
            proc.decodeURL(self.url)
        }.done(on: .main) {
            var re = $0
            re.rawUrl = self.url
            self.result = re
            if self.key == nil {
                self.key = re.videos.first?.key
            }
            
            self.initControllers()
            self.openResult()
        }.catch(on: .main, policy: .allErrors) {
            print($0)
        }
    }
    
    
    func initControllers() {
        linesPopUpButton.removeAllItems()
        view.window?.title = result?.title ?? ""
        
        guard let re = result,
              let key = key,
              let s = re.streams[key]
        else { return }
        
        
        let titles = (1..<(s.src.count + 2)).map {
            "Line \($0)"
        }
        
        linesPopUpButton.addItems(withTitles: titles)
        
        quailtyButton.title = key
        quailtyTableView.reloadData()
        let index = re.videos.firstIndex {
            $0.key == key
        } ?? 0
        
        quailtyTableView.selectRowIndexes(IndexSet.init(integer: index), byExtendingSelection: true)
        
    }
    
    func openResult() {
        guard !windowWillClose,
              let re = result,
              let key = key,
              let url = re.streams[key]?.url
        else {
            return
        }
        
        webView.evaluateJavaScript("window.openUrl('\(url)');")
        webView.evaluateJavaScript("initContent('\(UUID().uuidString)', \(Preferences.shared.dmPort));")
        
        switch re.site {
        case .douyu, .eGame, .biliLive, .huya:
            startDM(re.rawUrl)
        case .bilibili, .bangumi:
            break
        default:
            break
        }
    }
    
    func initWebView() {
        // Background Color
//        view.wantsLayer = true
//        view.layer?.backgroundColor = .white
//        webView.setValue(false, forKey: "drawsBackground")
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
    
    func resize() {
        webView.evaluateJavaScript("window.resize();")
    }
    
    func startDM(_ url: String) {
        if let d = danmaku {
            d.stop()
            danmaku = nil
        }
        
        danmaku = Danmaku(url)
        danmaku?.loadDM()
        danmaku?.delegate = self
    }
    
    
    
}

extension JSPlayerViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Log("Finish")
        webViewFinishLoaded = true
        guard url != "", result == nil else { return }
        
        decodeUrl()
    }
}

extension JSPlayerViewController: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        resize()
    }
    
    func windowWillClose(_ notification: Notification) {
        Log("windowWillClose")
        windowWillClose = true
        danmaku?.stop()
        danmaku = nil
        webView.load(URLRequest(url: URL(string:"about:blank")!))
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
            view.window?.aspectRatio = size
            resize()
//            view.window?.setFrame(<#T##frameRect: NSRect##NSRect#>, display: <#T##Bool#>, animate: <#T##Bool#>)
            
            self.startLoading(stop: true)
            
        case .loadingComplete:
            break
        case .recoveredEarlyEof:
            break
        case .error:
            break
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


extension JSPlayerViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        result?.videos.count ?? 0
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        result?.videos[row].key
    }
}
