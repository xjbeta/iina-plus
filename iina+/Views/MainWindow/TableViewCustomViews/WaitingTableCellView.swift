//
//  WaitingTableCellView.swift
//  iina+
//
//  Created by xjbeta on 2018/7/13.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class WaitingTableCellView: NSTableCellView {

    @IBOutlet weak var waitProgressIndicator: NSProgressIndicator!
    @IBOutlet weak var errorInfoTextField: NSTextField!
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
    }
}
