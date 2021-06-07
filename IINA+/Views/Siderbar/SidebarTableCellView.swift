//
//  SidebarTableCellView.swift
//  iina+
//
//  Created by xjbeta on 2018/8/10.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class SidebarTableCellView: NSTableCellView {

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    var isSelected = false {
        didSet {
            setImage(item)
        }
    }
    
    var isMouseInside = false {
        didSet {
            setImage(item)
        }
    }
    
    var item: SidebarItem = .none {
        didSet {
            setImage(item)
        }
    }
    
    func setImage(_ item: SidebarItem) {
        var imageName = ""
        switch item {
        case .bilibili:
            imageName = "bilibiliItem"
        case .bookmarks:
            imageName = "bookmarkItem"
        case .search:
            imageName = "searchItem"
        default:
            return
        }
        if isSelected || isMouseInside {
            imageName += "Selected"
        }
        
        imageView?.image = NSImage(named: imageName)
    }
    
    
    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
    }
    
    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
    }
    
    override func updateTrackingAreas() {
        trackingAreas.forEach {
            removeTrackingArea($0)
        }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeInActiveApp, .mouseMoved],
                                       owner: self,
                                       userInfo: nil))
    }
    
}
