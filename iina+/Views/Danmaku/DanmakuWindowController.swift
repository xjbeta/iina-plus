//
//  DanmakuWindowController.swift
//  iina+
//
//  Created by xjbeta on 2018/8/31.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class DanmakuWindowController: NSWindowController, NSWindowDelegate {

    var targeTitle = ""
    var videoUrl = ""
    
    override func windowDidLoad() {
        super.windowDidLoad()
        window?.setFrame((NSScreen.main?.frame)!, display: false)
        
        window?.level = NSWindow.Level(rawValue: Int(kCGStatusWindowLevel))
        window?.backgroundColor = NSColor.clear
        window?.isOpaque = false
        window?.ignoresMouseEvents = true
        window?.orderOut(self)
        
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(foremostAppActivated), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        
        
    }
    
    func initDanmaku(_ title: String, url: String) {
        targeTitle = title
        videoUrl = url
        
        
        Processes.shared.mpvSocket {
            
            
            
            
            
        }
    }
    
    
    
    @objc func foremostAppActivated(_ notification: NSNotification) {
        if let app = notification.userInfo?["NSWorkspaceApplicationKey"] as? NSRunningApplication {
            if app.bundleIdentifier == "com.colliderli.iina" || app.bundleIdentifier == "com.xjbeta.iina-plus" {
                let tt = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .optionOnScreenAboveWindow], kCGNullWindowID) as? [[String: AnyObject]]
                if let d = tt?.filter ({
                    if let owner = $0["kCGWindowOwnerName"] as? String,
                        owner == "IINA",
                        let title = $0["kCGWindowName"] as? String,
                        title == targeTitle {
                        return true
                    } else {
                        return false
                    }
                }).first {
                    let _r = d[kCGWindowBounds as String] as? [String: Int]
                    let rect = NSRect(x: _r?["X"] ?? 0, y: _r?["Y"] ?? 0,
                                      width: _r?["Width"] ?? 0, height: _r?["Height"] ?? 0)
                    let w = WindowData(
                        name: d[kCGWindowName as String] as? String ?? "",
                        pid: d[kCGWindowOwnerPID as String] as? Int ?? -1,
                        wid: d[kCGWindowNumber as String] as? Int ?? -1,
                        layer: d[kCGWindowLayer as String] as? Int ?? 0,
                        opacity: d[kCGWindowAlpha as String] as? CGFloat ?? 0.0,
                        frame: rect
                    )
                    
                    var re = w.frame
                    re.origin.y = (NSScreen.main?.frame.size.height)! - re.size.height - re.origin.y
                    window?.setFrame(re, display: true)

                    window?.orderFront(self)
                }
            } else {
                window?.orderOut(self)
            }
        }
    }
    
    
}

struct WindowData {
    public let name: String
    public let pid: Int
    public let wid: Int
    public let layer: Int
    public let opacity: CGFloat
    public let frame: CGRect
}
