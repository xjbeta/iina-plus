//
//  JSPlayerWindowController.swift
//  IINA+
//
//  Created by xjbeta on 1/28/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa

class JSPlayerWindowController: NSWindowController {
    
    override func windowDidLoad() {
        super.windowDidLoad()
    
        window?.delegate = self
    }
    
}

extension JSPlayerWindowController: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
    }
}
