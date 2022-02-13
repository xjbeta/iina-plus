//
//  ColorPickButton.swift
//  IINA+
//
//  Created by xjbeta on 1/25/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa

class ColorPickButton: NSButton {

    var color: NSColor = .white {
        didSet {
            updateColor()
        }
    }
    
    private var isMD = false
    private var mdColor: NSColor = .selectedControlColor
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        title = ""
        bezelStyle = .texturedSquare
        isBordered = false
        wantsLayer = true
        
        layer?.cornerRadius = 3
        layer?.borderWidth = 0.6
        layer?.borderColor = NSColor.gray.cgColor
        
        updateColor()
    }
    
    override func mouseDown(with event: NSEvent) {
        isMD = true
        updateColor()
    }
    
    override func mouseUp(with event: NSEvent) {
        isMD = false
        updateColor()
        performClick(self)
    }
    
    func updateColor() {
        layer?.backgroundColor = (isMD ? mdColor : color).cgColor
    }
    
}
