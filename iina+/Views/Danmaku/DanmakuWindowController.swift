//
//  DanmakuWindowController.swift
//  iina+
//
//  Created by xjbeta on 2018/8/31.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import SwiftHTTP
import Marshal

class DanmakuWindowController: NSWindowController, NSWindowDelegate {

    var targeTitle = ""
    var videoUrl = ""
    var waittingSocket = false
    
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
        waittingSocket = true
        if let url = URL(string: url),
            let aid = Int(url.lastPathComponent.replacingOccurrences(of: "av", with: "")) {
            var cid = 0
            
            let group = DispatchGroup()
            group.enter()
            Bilibili().getVideoList(aid, { vInfo in
                if vInfo.count == 1 {
                    cid = vInfo[0].cid
                } else if let p = url.query?.replacingOccurrences(of: "p=", with: ""),
                    let pInt = Int(p),
                    pInt < vInfo.count,
                    pInt > 0 {
                    cid = vInfo[pInt].cid
                }
                group.leave()
            }) { re in
                do {
                    let _ = try re()
                } catch let error {
                    Logger.log("Get cid for danmamu error: \(error)")
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                guard cid != 0 else { return }
                HTTP.GET("https://api.bilibili.com/x/v1/dm/list.so?oid=\(cid)") {
                    FileManager.default.createFile(atPath: "/Users/xjbeta/Developer/CommentCoreLibrary/download/1.xml", contents: $0.data, attributes: nil)
                    
                    if let danmakuViewController = self.contentViewController as? DanmakuViewController {
                        DispatchQueue.main.async {
                            danmakuViewController.webView.evaluateJavaScript("loadDM(\"../download/1.xml\");") { (_, _) in
                            }
                        }
                    }
                }
            }
        }
    }
    
    func initMpvSocket() {
        Processes.shared.mpvSocket { socketStr in
            do {
                let data = socketStr.data(using: .utf8) ?? Data()
                let json = try JSONParser.JSONObjectWithData(data)
                let socketEvent = try MpvSocketEvent(object: json)
                if let event = socketEvent.event {
                    switch event {
                    case .pause:
                        print("pause")
                    case .unpause:
                        print("unpause")
                    case .propertyChange:
                        if socketEvent.name == "time-pos" {
                            
                            
                        } else if socketEvent.name == "window-scale" {
                            print("window-scale")
                        }
                    case .idle:
                        print("idle")
                    }
                } else if let re = socketEvent.success {
                    print(re)
                } else {
                    print(socketStr)
                }
            } catch let error {
                print(error)
            }
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
                    let w = WindowData(d)
                    var re = w.frame
                    re.origin.y = (NSScreen.main?.frame.size.height)! - re.size.height - re.origin.y
                    window?.setFrame(re, display: true)
                    window?.orderFront(self)
                    if waittingSocket {
                        initMpvSocket()
                        waittingSocket = false
                    }
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
    
    init(_ d: [String: AnyObject]) {
        let _r = d[kCGWindowBounds as String] as? [String: Int]
        frame = NSRect(x: _r?["X"] ?? 0, y: _r?["Y"] ?? 0,
                          width: _r?["Width"] ?? 0, height: _r?["Height"] ?? 0)
        name = d[kCGWindowName as String] as? String ?? ""
        pid = d[kCGWindowOwnerPID as String] as? Int ?? -1
        wid = d[kCGWindowNumber as String] as? Int ?? -1
        layer = d[kCGWindowLayer as String] as? Int ?? 0
        opacity = d[kCGWindowAlpha as String] as? CGFloat ?? 0.0
    }
}




struct MpvSocketEvent: Unmarshaling {
    var event: MpvEvent?
    var id: Int?
    var name: String?
    var data: String?
    var success: Bool?
    
    
    init(object: MarshaledObject) throws {
        let eventStr: String? = try object.value(for: "event")
        event = MpvEvent(rawValue: eventStr ?? "")
        id = try object.value(for: "id")
        name = try object.value(for: "name")
        data = try object.value(for: "data")
        let errorStr: String? = try object.value(for: "error")
        if errorStr != nil {
            success = errorStr == "success"
        }
    }
}


enum MpvEvent: String {
    case propertyChange = "property-change"
    case pause
    case idle
    case unpause
}
