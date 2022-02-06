//
//  JSPlayerWindowController.swift
//  IINA+
//
//  Created by xjbeta on 1/28/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa
import WebKit

class JSPlayerWindowController: NSWindowController {
    
    var playerVC: JSPlayerViewController? {
        window?.contentViewController as? JSPlayerViewController
    }
    
    var result: YouGetJSON? {
        didSet {
            window?.title = result?.title ?? ""
        }
    }
    var key: String?
    
    var willClose = false
    
    override func windowDidLoad() {
        super.windowDidLoad()
        window?.delegate = self
        playerVC?.delegate = self
    }
    
}

extension JSPlayerWindowController: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        playerVC?.resize()
        window?.isMovableByWindowBackground = true
    }
    
    func windowWillClose(_ notification: Notification) {
        willClose = true
        playerVC?.webView.load(URLRequest(url: URL(string:"about:blank")!))
    }
}

extension JSPlayerWindowController: JSPlayerDelegate {
    func jsPlayer(_ viewController: JSPlayerViewController, didFinish webview: WKWebView) {
        guard !willClose,
              let re = result,
              let key = key,
              let url = re.streams[key]?.url
        else {
            return
        }
        
        viewController.open(url)
        switch re.site {
        case .douyu, .eGame, .biliLive, .huya:
            viewController.startDM(re.rawUrl)
        case .bilibili, .bangumi:
            break
        default:
            break
        }
    }
    
}
