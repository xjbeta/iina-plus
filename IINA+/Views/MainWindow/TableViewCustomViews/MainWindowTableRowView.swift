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
    
    override func drawSelection(in dirtyRect: NSRect) {
        isEmphasized ? NSColor.systemBlue.setFill() : NSColor.secondarySelectedControlColor.setFill()
        NSBezierPath(roundedRect: dirtyRect, xRadius: 5, yRadius: 5).fill()
    }
}
