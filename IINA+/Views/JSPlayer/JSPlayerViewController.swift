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
        startLoading()
        evaluateJavaScript("flv_destroy();")
        danmaku?.stop()
        openLive()
    }
    
    @IBOutlet var volumeBox: NSBox!
    @IBOutlet var volumeButton: NSButton!
    @IBAction func mute(_ sender: NSButton) {
        evaluateJavaScript("flvPlayer.muted = !flvPlayer.muted;")
        playerMuted = !playerMuted
        initVolumeButton()
    }
    
    @IBOutlet var volumeSlider: NSSlider!
    @IBAction func volumeChanged(_ sender: NSSlider) {
        evaluateJavaScript("flvPlayer.volume = \(sender.doubleValue);")
        initVolumeButton()
    }
     
    @IBOutlet var durationButton: NSButton!
    
    @IBOutlet weak var danmakuPrefBox: NSBox!
    @IBOutlet var danmakuPrefButton: NSButton!
    
    @IBOutlet weak var enableDMButton: NSButton!
    @IBAction func enableDanmaku(_ sender: NSButton) {
        let enableDM = sender.state == .on
        send(enableDM ? .start : .stop, text: "", id: "")
        
        startDM()
    }
    
    @IBOutlet weak var speedSlider: NSSlider!
    @IBAction func speedChanged(_ sender: NSSlider) {
        send(.dmSpeed, text: "\(sender.doubleValue)", id: "")
    }
    
    @IBOutlet weak var opacitySlider: NSSlider!
    @IBAction func opacityChanged(_ sender: NSSlider) {
        send(.dmOpacity, text: "\(sender.doubleValue)", id: "")
    }
    
    
    @IBOutlet var qlButton: NSButton!
    @IBOutlet var qlBox: NSBox!
    
    @IBOutlet var linesPopUpButton: NSPopUpButton!
    @IBAction func lineChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title else { return }
        videoLine = sender.indexOfItem(withTitle: title)
        openLive()
    }

    @IBOutlet var quailtyHeightLayoutConstraint: NSLayoutConstraint!
    @IBOutlet var quailtyTableView: NSTableView!
    @IBAction func quailtyChanged(_ sender: NSTableView) {
        let i = quailtyTableView.selectedRow
        guard let re = result, re.videos.count > i else { return }
        videoKey = re.videos[i].key
        openLive()
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
    var mouseInDanmakuBox = false
    
    var hideOSCTimer: WaitTimer?
    
    
// MARK: - Video Values
    var url = ""
    var result: YouGetJSON?
    var videoKey: String? {
        didSet {
            qlButton.title = videoKey ?? ""
        }
    }
    var videoLine = 0
    
// MARK: - Other Value
    
    var webViewFinishLoaded = false
    
    var windowSizeInited = false
    var danmaku: Danmaku?
    let proc = Processes.shared
    
    var playerMuted = false
    
    private var durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()
    
    enum ScriptMessageKeys: String, CaseIterable {
        case print,
             size,
             duration,
             end,
             
             error,
             loadingComplete,
             recoveredEarlyEof
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        qlBox.isHidden = true
        volumeBox.isHidden = true
        danmakuPrefBox.isHidden = true
        
        let pref = Preferences.shared
        speedSlider.doubleValue = pref.dmSpeed
        opacitySlider.doubleValue = pref.dmOpacity
        enableDMButton.state = pref.enableDanmaku ? .on : .off
        
        initVolumeButton()
        initTrackingAreas()
        
        startLoading()
        initWebView()
    }
    
    func initTrackingAreas() {
        startTrackingAreas(view)
        startTrackingAreas(controllersView)
        startTrackingAreas(qlBox)
        startTrackingAreas(volumeBox)
        startTrackingAreas(danmakuPrefBox)
        
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
        case danmakuPrefBox:
            userInfo["id"] = .danmakuPref
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
    
    func openLive() {
        proc.stopDecodeURL()
        proc.videoGet.liveInfo(url, false).get {
            if !$0.isLiving {
                throw VideoGetError.isNotLiving
            }
        }.then { _ in
            self.proc.decodeURL(self.url)
        }.then { re in
            self.proc.videoGet.prepareVideoUrl(re, {
                let videoKeys = re.videos.map {
                    $0.key
                }
                
                if self.videoKey == nil || !videoKeys.contains(self.videoKey!) {
                    self.videoKey = re.videos.first?.key
                }
                
                return videoKeys.firstIndex(of: self.videoKey ?? "😶‍🌫️") ?? 0
            }())
        }.done(on: .main) {
            var re = $0
            re.rawUrl = self.url
            self.result = re
            
            guard let stream = re.videos.first(where: {
                $0.key == self.videoKey
            })?.value else {
                return
            }
            var urls = stream.src
            if let u = stream.url {
                urls.insert(u, at: 0)
            }
            
            guard urls.count > 0 else { return }
            
            if urls.count <= self.videoLine {
                self.videoLine = 0
            }
            
            self.initControllers()
            
            let url = urls[0]
            
            self.evaluateJavaScript("initContent();")
            self.evaluateJavaScript("window.openUrl('\(url)');")
            self.evaluateJavaScript("flvPlayer.muted = \(self.playerMuted);")
            
            switch re.site {
            case .douyu, .eGame, .biliLive, .huya, .douyin:
                self.startDM()
            case .bilibili, .bangumi:
                break
            default:
                break
            }
        }.catch(on: .main, policy: .allErrors) {
            print($0)
        }
    }
    
    
    func initControllers() {
        linesPopUpButton.removeAllItems()
        view.window?.title = result?.title ?? ""
        
        guard let re = result,
              let key = videoKey,
              let s = re.streams[key]
        else { return }
        
        
        let titles = (1..<(s.src.count + 2)).map {
            "Line \($0)"
        }
        
        linesPopUpButton.addItems(withTitles: titles)
        linesPopUpButton.selectItem(at: videoLine)
        
        quailtyTableView.reloadData()
        let index = re.videos.firstIndex {
            $0.key == key
        } ?? 0
        
        
        quailtyTableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        
    }
    
    func initVolumeButton() {
        var name = ""
        if playerMuted {
            name = "NSAudioOutputMuteTemplate"
        } else {
            switch volumeSlider.doubleValue {
            case 0:
                name = "NSAudioOutputVolumeOffTemplate"
            case 0..<0.33:
                name = "NSAudioOutputVolumeLowTemplate"
            case 0.33..<0.66:
                name = "NSAudioOutputVolumeMedTemplate"
            default:
                name = "NSAudioOutputVolumeHighTemplate"
            }
        }
        
        volumeButton.image = .init(named: .init(name))
    }
    
    func initWebView() {
        guard let playerUrl = Bundle.main.url(
            forResource: "flvplayer",
            withExtension: "htm",
            subdirectory: "WebFiles") else { return }
        
        // Background Color
        view.wantsLayer = true
        view.layer?.backgroundColor = .black
        webView.setValue(false, forKey: "drawsBackground")

        webView.navigationDelegate = self
        ScriptMessageKeys.allCases.forEach {
            webView.configuration.userContentController.add(self, name: $0.rawValue)
        }
        
        webView.configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        
        webView.loadFileURL(playerUrl, allowingReadAccessTo: playerUrl.deletingLastPathComponent())
    }
    
    func deinitWebView() {
        webView.stopLoading()
        ScriptMessageKeys.allCases.forEach {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: $0.rawValue)
        }
        
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        webView = nil
    }
    
    func evaluateJavaScript(_ str: String) {
        guard webView != nil else { return }
        webView.evaluateJavaScript(str)
    }
    
    
    func resize() {
        evaluateJavaScript("window.resize();")
    }
    
    func startDM() {
        let pref = Preferences.shared
        if let d = danmaku {
            d.stop()
            danmaku = nil
        }
        guard let url = result?.rawUrl,
              pref.enableDanmaku,
              enableDMButton.state == .on else { return }
        
        danmaku = Danmaku(url)
        danmaku?.loadDM()
        danmaku?.delegate = self
        
        danmaku?.loadCustomFont()
        danmaku?.customDMSpeed()
        danmaku?.customDMOpdacity()
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
            mouseInDanmakuBox = true
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
            mouseInDanmakuBox = false
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
           !mouseInVolumeBox,
           !mouseInDanmakuBox {
            hideOSCTimer?.run()
        } else {
            hideOSCTimer?.stop()
        }
        
        guard mouseInControlls, let v0 = durationButton else {
            if !mouseInQLBox {
                mouseInQL = false
            }
            if !mouseInDanmakuBox {
                mouseInDanmaku = false
            }
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
            danmakuPrefBox.isHidden = !(mouseInDanmaku || mouseInDanmakuBox)
        } else {
            view.window?.hideTitlebar(true)
            controllersView.isHidden = true
            volumeBox.isHidden = true
            qlBox.isHidden = true
            danmakuPrefBox.isHidden = true
        }
    }
    
}

extension JSPlayerViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Log("Finish")
        webViewFinishLoaded = true
        guard url != "", result == nil else { return }
        
        openLive()
    }
}

extension JSPlayerViewController: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        resize()
    }
    
    func windowWillClose(_ notification: Notification) {
        Log("windowWillClose")
        result = nil
        videoKey = nil
        videoLine = 0
        
        danmaku?.stop()
        danmaku = nil
        deinitWebView()
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
            if let msg = message.body as? String,
               msg.contains("Playback seems stuck") {
                
                print("==========================================")
                print("==========================================")
                print("===========Playback seems stuck===========")
                print("==========================================")
                print("==========================================")
            }
        case .duration:
            let d = message.body as? Int ?? 0
            durationButton.title = durationFormatter.string(from: .init(d)) ?? "00:00"
        case .size:
            guard let wh = message.body as? [CGFloat],
                  wh.count == 2,
                  let window = view.window else {
                return
            }
            let w = wh[0]
            let h = wh[1]
            let size = CGSize(width: w, height: h)
            
            guard size != .zero else { return }
            
            window.aspectRatio = size
            
            var newFrame = NSRect(origin: .zero, size: size)
            
            if !windowSizeInited,
                var frame = NSScreen.main?.frame {
                let newH = frame.width / size.width * size.height
                frame.origin.y = frame.height - newH
                frame.size.height = newH
                
                newFrame = frame
            } else {
                var f = window.frame
                f.size.height = f.width / size.width * size.height
                newFrame = f
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                window.animator().setFrame(newFrame, display: true)
            } completionHandler: {
                self.resize()
                self.windowSizeInited = true
            }
            self.startLoading(stop: true)
            
        case .end:
            print("==========================================")
            print("==================Ended===================")
            print("==========================================")
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
//        print(method, str)
        evaluateJavaScript("window.dmMessage(\(str));")
    }
}


extension JSPlayerViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        result?.videos.count ?? 0
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        result?.videos[row].key
    }
    
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("MainWindowTableRowView"), owner: self) as? MainWindowTableRowView
    }
}
