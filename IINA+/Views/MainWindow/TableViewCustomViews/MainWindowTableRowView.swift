//
//  LiveStatusTableRowView.swift
//  iina+
//
//  Created by xjbeta on 2018/7/30.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class MainWindowTableRowView: NSTableRowView {
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    
    override func drawFocusRingMask() {
        let selectionRect = NSInsetRect(bounds, 0, 0)
        NSBezierPath(roundedRect: selectionRect, xRadius: 6, yRadius: 6).fill()
    }
    
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle == .regular else {
            super.drawSelection(in: dirtyRect)
            return
        }
        
        isEmphasized ? NSColor.systemBlue.setFill() : NSColor.secondarySelectedControlColor.setFill()
        NSBezierPath(roundedRect: dirtyRect, xRadius: 5, yRadius: 5).fill()
        
    }
}
