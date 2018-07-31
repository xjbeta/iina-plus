//
//  LiveStatusTableRowView.swift
//  iina+
//
//  Created by xjbeta on 2018/7/30.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class LiveStatusTableRowView: NSTableRowView {
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawSelection(in: bounds)
    }

    override var isSelected: Bool {
        didSet {
            drawSelection(in: bounds)
            needsDisplay = true
        }
    }
    
    override func drawSelection(in dirtyRect: NSRect) {
        let selectionRect = NSInsetRect(bounds, 4, 4)
        let selectionPath = NSBezierPath(roundedRect: selectionRect, xRadius: 6, yRadius: 6)
        if isSelected {
            NSColor.selectedControlColor.setFill()
        } else {
            NSColor.white.setFill()
        }
        selectionPath.fill()
    }

    let defaultRowColor = NSColor(catalogName: "System", colorName: "controlAlternatingRowColor")
    
}

extension NSColor {
    public class var customBackgroundColor: NSColor {
        return NSColor(calibratedRed: 0.97, green: 0.95, blue: 0.94, alpha: 1)
    }
}
