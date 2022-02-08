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
    
    var contentVC: JSPlayerViewController? {
        window?.contentViewController as? JSPlayerViewController
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
        window?.isMovableByWindowBackground = true
        window?.delegate = contentVC
        
        initTitlebar()
    }
    
    func initTitlebar() {
        guard let titleView = window?.titleView() else { return }

        titleView.wantsLayer = true
        titleView.layer?.backgroundColor = NSColor(red: 0.16, green: 0.16, blue: 0.16, alpha: 1).cgColor
    }
}


extension NSWindow {
    func hideTitlebar(_ hide: Bool) {
        titleView()?.isHidden = styleMask.contains(.fullScreen) ? false : hide
    }
    
    func titleView() -> NSView? {
        return standardWindowButton(.closeButton)?.superview?.superview
    }
}
