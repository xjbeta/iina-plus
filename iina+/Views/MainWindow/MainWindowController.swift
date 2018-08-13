//
//  MainWindowController.swift
//  iina+
//
//  Created by xjbeta on 2018/7/13.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class MainWindowController: NSWindowController, NSWindowDelegate {
    
    override func windowDidLoad() {
        super.windowDidLoad()
        window?.isMovableByWindowBackground = true
        window?.backgroundColor = NSColor(red:0.86, green:0.89, blue:0.94, alpha:1.00)
        
    }
    
    func windowDidBecomeMain(_ notification: Notification) {
        NotificationCenter.default.post(name: .reloadMainWindowTableView, object: nil)
    }
    
}


