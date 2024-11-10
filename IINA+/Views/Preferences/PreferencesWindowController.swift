//
//  PreferencesWindowController.swift
//  iina+
//
//  Created by xjbeta on 2018/7/30.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class PreferencesWindowController: NSWindowController {

    override func windowDidLoad() {
        super.windowDidLoad()
        window?.isMovableByWindowBackground = true
        window?.titlebarAppearsTransparent = true
        window?.titleVisibility = .hidden
        window?.delegate = self
        
		reloadIINAState()
        
        if let preferencesTabViewController = contentViewController as? PreferencesTabViewController {
            preferencesTabViewController.autoResizeWindow(preferencesTabViewController.tabView.selectedTabViewItem, animate: false)
        }
    }

	func reloadIINAState() {
		Task {
			await Processes.shared.iina.updateIINAState()
		}
	}
	
}

extension PreferencesWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
		reloadIINAState()
        NSColorPanel.shared.close()
    }
}
