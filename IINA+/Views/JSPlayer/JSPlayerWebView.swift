//
//  JSPlayerWebView.swift
//  IINA+
//
//  Created by xjbeta on 1/29/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa
import WebKit

class JSPlayerWebView: WKWebView {

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Drawing code here.
    }
    
    override var acceptsFirstResponder: Bool {
        false
    }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
    
    override var mouseDownCanMoveWindow: Bool {
        true
    }
    
}
