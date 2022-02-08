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
    @IBOutlet var webView: WKWebView!

// MARK: - Player Controllers
    enum PlayerController: Int {
        case titlebar, mainControllers, volume, qlSelector, danmakuPref
    }
    
    
    @IBOutlet var controllersView: ControllersVisualEffectView!
    @IBOutlet var loadingProgressIndicator: NSProgressIndicator!
    
    
    @IBOutlet var reloadButton: NSButton!
    @IBAction func reloadVideo(_ sender: NSButton) {
        
    }
    
    @IBOutlet var volumeBox: NSBox!
    @IBOutlet var volumeButton: NSButton!
    @IBAction func mute(_ sender: NSButton) {
        
    }
    
    @IBOutlet var volumeSlider: NSSlider!
    @IBAction func volumeChanged(_ sender: NSSlider) {
        
    }
    
    
    @IBOutlet var danmakuPrefButton: NSButton!
    
    
    
    @IBOutlet var qlButton: NSButton!
    @IBOutlet var qlBox: NSBox!
    
    @IBOutlet var linesPopUpButton: NSPopUpButton!
    @IBAction func lineChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title else { return }
        line = sender.indexOfItem(withTitle: title)
        openResult()
    }

    @IBOutlet var quailtyHeightLayoutConstraint: NSLayoutConstraint!
    @IBOutlet var quailtyTableView: NSTableView!
    @IBAction func quailtyChanged(_ sender: NSTableView) {
        
        let i = quailtyTableView.selectedRow
        guard let re = result,
              re.videos.count > i else { return }

        let kv = re.videos[i]
        
        if key != kv.key {
            key = kv.key
            openResult()
        }
    }
    

// MARK: - Mouse State
    var mouseInWindow = false
    var mouseInControlls = false
    var mouseInWindowTimeOut = false
    
    var mouseInQL = false
    var mouseInQLBox = false
    
    var mouseInVolume = false
    var mouseInVolumeBox = false
    
    var mouseInDanmaku = false
    
    var hideOSCTimer: WaitTimer?
    
    
// MARK: - Other Value
    var url = ""
    var result: YouGetJSON?
    var key: String?
    var line = 0
    
    var webViewFinishLoaded = false
    
    var windowWillClose = false
    
    
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
        qlBox.isHidden = true
        volumeBox.isHidden = true
        
        initTrackingAreas()
        
        startLoading()
        initWebView()
        loadWebView()
    }
    
    func initTrackingAreas() {
        startTrackingAreas(view)
        startTrackingAreas(controllersView)
        startTrackingAreas(qlBox)
        startTrackingAreas(volumeBox)
        
        hideOSCTimer?.stop()
        hideOSCTimer = nil
        hideOSCTimer = WaitTimer(timeOut: .seconds(3), queue: .main) {
            self.mouseInWindowTimeOut = true
            self.updateControllersState()
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }
    
    func startTrackingAreas(_ view: NSView) {
        var userInfo = [AnyHashable: PlayerController]()
        
        switch view {
        case self.view:
            userInfo["id"] = .titlebar
        case controllersView:
            userInfo["id"] = .mainControllers
        case qlBox:
            userInfo["id"] = .qlSelector
        case volumeBox:
            userInfo["id"] = .volume
        default:
            break
        }
        
        view.trackingAreas.forEach {
            view.removeTrackingArea($0)
        }
        view.addTrackingArea(
            NSTrackingArea(rect: view.frame,
                           options: [
                            .activeAlways,
                            .mouseMoved,
                            .mouseEnteredAndExited,
                            .assumeInside,
                            .inVisibleRect
                           ],
                           owner: view,
                           userInfo: userInfo))
    }
    
    
    func startLoading(stop: Bool = false) {
        reloadButton.isHidden = !stop
        loadingProgressIndicator.isHidden = stop
        
        if stop {
            loadingProgressIndicator.stopAnimation(nil)
        } else {
            loadingProgressIndicator.startAnimation(nil)
        }
        
        updateControllersState()
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
        
        qlButton.title = key
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
              let s = re.streams[key],
              (line - 1) < s.src.count,
              let vUrl = line == 0 ? s.url : s.src[line - 1]
        else {
            return
        }
        
        
        
        webView.evaluateJavaScript("window.openUrl('\(vUrl)');")
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
    
    
    
    override func mouseEntered(with event: NSEvent) {
        switch getEventId(event) {
        case .titlebar:
            mouseInWindow = true
        case .mainControllers:
            mouseInControlls = true
        case .qlSelector:
            mouseInQLBox = true
        case .volume:
            mouseInVolumeBox = true
        case .danmakuPref:
            break
        case .none:
            break
        }
        
        updateControllersState()
    }
    
    override func mouseExited(with event: NSEvent) {
        switch getEventId(event) {
        case .titlebar:
            mouseInWindow = false
        case .mainControllers:
            mouseInControlls = false
        case .qlSelector:
            mouseInQLBox = false
        case .volume:
            mouseInVolumeBox = false
        case .danmakuPref:
            break
        case .none:
            break
        }
        updateControllersState()
    }
    
    override func mouseMoved(with event: NSEvent) {
        mouseInWindowTimeOut = false
        if mouseInWindow,
            !mouseInControlls,
            !mouseInQLBox,
            !mouseInVolumeBox {
            hideOSCTimer?.run()
        } else {
            hideOSCTimer?.stop()
        }
        
        guard mouseInControlls,
              let v0 = reloadButton.isHidden ? loadingProgressIndicator : reloadButton
        else {
            if !mouseInQLBox {
                mouseInQL = false
            }
            mouseInDanmaku = false
            if !mouseInVolumeBox {
                mouseInVolume = false
            }
            updateControllersState()
            return
        }
        
        let x = controllersView.convert(event.locationInWindow, from: nil).x
        
        let f0 = controllersView.convert(v0.frame, to: nil)
        let f1 = controllersView.convert(volumeButton.frame, to: nil)
        let f2 = controllersView.convert(danmakuPrefButton.frame, to: nil)
        let f3 = controllersView.convert(qlButton.frame, to: nil)

        func centerX(_ frame1: NSRect, _ frame2: NSRect) -> CGFloat {
            var e = frame1.origin.x + frame1.width
            e += (frame2.origin.x - e) / 2
            return e
        }
        
        let x05 = centerX(f0, f1)
        let x15 = centerX(f1, f2)
        let x25 = centerX(f2, f3)
        
        switch x {
//        case 0..<x05:
//            print("reload")
        case x05..<x15:
            mouseInVolume = true
            mouseInDanmaku = false
            mouseInQL = false
        case x15..<x25:
            mouseInDanmaku = true
            mouseInVolume = false
            mouseInQL = false
        case x25...controllersView.frame.width:
            mouseInQL = true
            mouseInDanmaku = false
            mouseInVolume = false
        default:
            mouseInQL = false
            mouseInDanmaku = false
            mouseInVolume = false
        }
        
        updateControllersState()
    }

    func getEventId(_ event: NSEvent) -> PlayerController? {
        event.trackingArea?.userInfo?["id"] as? PlayerController
    }
    
    
    func updateControllersState() {
        let isLoading = !loadingProgressIndicator.isHidden
        if isLoading,
           !mouseInWindow {
            view.window?.hideTitlebar(false)
            controllersView.isHidden = false
        } else if mouseInWindow {
            view.window?.hideTitlebar(mouseInWindowTimeOut)
            controllersView.isHidden = mouseInWindowTimeOut
            
            volumeBox.isHidden = !(mouseInVolume || mouseInVolumeBox)
            qlBox.isHidden = !(mouseInQL || mouseInQLBox)
        } else {
            view.window?.hideTitlebar(true)
            controllersView.isHidden = true
            volumeBox.isHidden = true
            qlBox.isHidden = true
//            danmakuBox.isHidden = true
        }
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
    
    func windowWillEnterFullScreen(_ notification: Notification) {
        view.window?.hideTitlebar(false)
    }
    
    func windowWillExitFullScreen(_ notification: Notification) {
        updateControllersState()
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
