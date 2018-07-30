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
        
    }
    
    func windowDidBecomeMain(_ notification: Notification) {
        NotificationCenter.default.post(name: .reloadLiveStatus, object: nil)
    }
    
    func windowDidResignMain(_ notification: Notification) {
        if let view = window?.contentViewController as? MainViewController {
            view.suggestionsWindowController.cancelSuggestions()
        }
    }
    
    func windowWillStartLiveResize(_ notification: Notification) {
        if let view = window?.contentViewController as? MainViewController {
            view.suggestionsWindowController.cancelSuggestions()
        }
    }
}
