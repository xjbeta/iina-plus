//
//  SelectVideoCollectionViewItemButton.swift
//  iina+
//
//  Created by xjbeta on 2018/8/21.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class SelectVideoCollectionViewItemButton: NSButton {

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let selectionRect = NSInsetRect(bounds, 0, 0)
        let selectionPath = NSBezierPath(roundedRect: selectionRect, xRadius: 3, yRadius: 3)
        if isHighlighted {
            NSColor.customHighlightColor.setFill()
        } else {
            NSColor.white.setFill()
        }
        selectionPath.fill()

        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 1
        style.alignment = .left
//        style.lineHeightMultiple
    
        let str = NSMutableAttributedString(string: title, attributes: [.paragraphStyle: style])
        

        if let cell = cell as? NSButtonCell {
            var rect = bounds
            let padding: CGFloat = 8
            rect.origin.x += padding
            rect.origin.y += padding
            rect.size.width -= padding * 2
            rect.size.height -= padding * 2
            
//            cell.lineBreakMode = .byTruncatingMiddle
            cell.drawTitle(str, withFrame: rect, in: self)
        }
    }
    
}

