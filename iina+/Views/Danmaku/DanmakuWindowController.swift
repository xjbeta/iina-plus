//
//  DanmakuWindowController.swift
//  iina+
//
//  Created by xjbeta on 2018/8/31.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import AppKit

class DanmakuWindowController: NSWindowController, NSWindowDelegate {
    var targeTitle = ""
    var waittingSocket = false
    
    override func windowDidLoad() {
        super.windowDidLoad()
        
        window?.level = .floating
        window?.backgroundColor = NSColor.clear
        window?.isOpaque = false
        window?.ignoresMouseEvents = true
        window?.orderOut(self)
        
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(foremostAppActivated), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        
        NotificationCenter.default.addObserver(forName: .updateDanmakuWindow, object: nil, queue: .main) { _ in
            self.resizeWindow()
        }
    }
    
    func setObserver(_ pid: pid_t) {
        
        let observerCallback: AXObserverCallback = { _,_,_,_  in
            NotificationCenter.default.post(name: .updateDanmakuWindow, object: nil)
        }
        var window: CFTypeRef?
        
        let app = AXUIElementCreateApplication(pid)
        AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window)
        
        let observer: UnsafeMutablePointer<AXObserver?> = UnsafeMutablePointer<AXObserver?>.allocate(capacity: 1)
        AXObserverCreate(pid, observerCallback as AXObserverCallback, observer)
        
        if let observer = observer.pointee {
            guard let windowRef = window else { return }
            AXObserverAddNotification(observer, windowRef as! AXUIElement, kAXMovedNotification as CFString, nil)
            AXObserverAddNotification(observer, windowRef as! AXUIElement, kAXResizedNotification as CFString, nil)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), CFRunLoopMode.defaultMode)
        }
    }

    
    func initDanmaku(_ site: LiveSupportList, _ title: String, _ url: String) {
        waittingSocket = true
        targeTitle = site == .huya ? "yes" : title
        if let danmakuViewController = self.contentViewController as? DanmakuViewController {
            danmakuViewController.initDanmaku(site, url)
        }
    }
    
    func initMpvSocket() {
        if let danmakuViewController = self.contentViewController as? DanmakuViewController {
            danmakuViewController.initMpvSocket()
        }
    }
    
    @objc func foremostAppActivated(_ notification: NSNotification) {
        guard Preferences.shared.enableDanmaku else { return }
        guard let app = NSWorkspace.shared.frontmostApplication,
            app.bundleIdentifier == "com.colliderli.iina" else {
                if let window = window, window.isVisible {
                    window.orderOut(self)
                    Logger.log("hide danmaku window")
                }
                return
        }
        
        Logger.log("AXIsProcessTrusted  \(AXIsProcessTrusted())")
        guard AXIsProcessTrusted() else {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "No accessibility API permission."
            alert.informativeText = "Check enableDanmaku check in preferences."
            alert.addButton(withTitle: "OK")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                Preferences.shared.enableDanmaku = false
            }
            return
        }
        
        resizeWindow()
        
        if waittingSocket {
            initMpvSocket()
            waittingSocket = false
            setObserver(app.processIdentifier)
        }
    }
    
    func resizeWindow() {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        
        let app = AXUIElementCreateApplication(pid)
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &children)
        
        guard let windows = children as? [AXUIElement] else { return }
        
        let targeWindows = windows.filter { element in
            var title: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
            if let t = title as? String, t == targeTitle {
                return true
            }
            return false
        }
        
        guard let targeWindow = targeWindows.first else { return }
        
        var position: CFTypeRef?
        var size: CFTypeRef?
        var p = CGPoint()
        var s = CGSize()
        AXUIElementCopyAttributeValue(targeWindow, kAXPositionAttribute as CFString, &position)
        AXUIElementCopyAttributeValue(targeWindow, kAXSizeAttribute as CFString, &size)

        guard position != nil, size != nil else { return }
        AXValueGetValue(position as! AXValue, AXValueType.cgPoint, &p)
        AXValueGetValue(size as! AXValue, AXValueType.cgSize, &s)
        
        var rect = NSRect(origin: p, size: s)
        
        rect.origin.y = (NSScreen.main?.frame.size.height)! - rect.size.height - rect.origin.y
        guard let window = window else { return }
        window.setFrame(rect, display: true)
        if !window.isVisible {
            window.orderFront(self)
            Logger.log("show danmaku window")
        }
    }
}
