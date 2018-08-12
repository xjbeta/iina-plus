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

    override var isSelected: Bool {
        didSet {
            if let cell = subviews.first as? LiveStatusTableCellView {
                cell.isSelected = isSelected
            } else if let cell = subviews.first as? BilibiliCardTableCellView {
                cell.isSelected = isSelected
            } else if let cell = subviews.first as? SuggestionsTableCellView {
                cell.isSelected = isSelected
            }
        }
    }
    
    
    override func drawFocusRingMask() {
        let selectionRect = NSInsetRect(bounds, 0, 0)
        NSBezierPath(roundedRect: selectionRect, xRadius: 6, yRadius: 6).fill()
    }
}
