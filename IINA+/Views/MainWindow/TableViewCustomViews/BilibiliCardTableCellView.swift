//
//  BilibiliCardTableCellView.swift
//  iina+
//
//  Created by xjbeta on 2018/8/8.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class BilibiliCardTableCellView: NSTableCellView {

    @IBOutlet weak var imageBoxView: BilibiliCardImageBoxView!
    @IBOutlet var progressView: BilibiliCardProgressView!
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
    }

    
}
