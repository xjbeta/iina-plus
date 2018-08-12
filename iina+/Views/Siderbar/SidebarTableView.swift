//
//  SidebarTableView.swift
//  iina+
//
//  Created by xjbeta on 2018/8/10.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class SidebarTableView: NSTableView {

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Drawing code here.
    }
    
    override var mouseDownCanMoveWindow: Bool {
        return true
    }
    
}
