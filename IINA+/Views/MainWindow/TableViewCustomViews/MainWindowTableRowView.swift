//
//  LiveStatusTableRowView.swift
//  iina+
//
//  Created by xjbeta on 2018/7/30.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class MainWindowTableRowView: NSTableRowView {
    
	var isContextualMenuTarget: Bool = false {
		didSet {
			needsDisplay = true
		}
	}
	
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
		
		if isContextualMenuTarget {
			
			let i: CGFloat = 2
			
			let rect = NSMakeRect(dirtyRect.origin.x + i,
								  dirtyRect.origin.y + i,
								  dirtyRect.width - i*2,
								  dirtyRect.height - i*2)
			
			let border = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
			border.lineWidth = 2
			
			if isSelected, isEmphasized {
				NSColor.white.setStroke()
			} else {
				NSColor.controlAccentColor.setStroke()
			}
			
			border.stroke()
		}
    }
    
	override func drawSelection(in dirtyRect: NSRect) {
		let color = isEmphasized ? NSColor.controlAccentColor : NSColor.unemphasizedSelectedContentBackgroundColor
		
		color.setFill()
		NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
	}
}
