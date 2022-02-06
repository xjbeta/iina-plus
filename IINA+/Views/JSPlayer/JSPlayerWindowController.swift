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
    }
}
