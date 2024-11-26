//
//  BilibiliCardProgressView.swift
//  iina+
//
//  Created by xjbeta on 2018/8/15.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class BilibiliCardProgressView: NSView {

    var doubleValue: Double = 0 {
        didSet {
            needsDisplay = true
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let fullPath = NSBezierPath(roundedRect: bounds, xRadius: 0, yRadius: 0)
        NSColor.windowBackgroundColor.setFill()
        fullPath.fill()
        
        let size = NSSize(width: bounds.width * CGFloat(doubleValue), height: bounds.height)
        let rect = NSRect(origin: bounds.origin, size: size)
        let path = NSBezierPath(roundedRect: rect, xRadius: 0, yRadius: 0)
        NSColor.red.setFill()
        path.fill()
    }
}
