//
//  LiveStatusTableCellView.swift
//  iina+
//
//  Created by xjbeta on 2018/7/26.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class LiveStatusTableCellView: NSTableCellView {

    @IBOutlet weak var userCoverImageView: NSImageView!
    @IBOutlet weak var liveStatusImageView: NSImageView!
    @IBOutlet weak var titleTextField: NSTextField!
    @IBOutlet weak var nameTextField: NSTextField!
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Drawing code here.
    }
    
}
