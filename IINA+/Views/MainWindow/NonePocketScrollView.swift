//
//  NonePocketScrollView.swift
//  IINA+
//
//  Created by xjbeta on 2025/9/16.
//  Copyright © 2025 xjbeta. All rights reserved.
//

import Cocoa

class NonePocketScrollView: NSScrollView {

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Drawing code here.
    }
    
    override var automaticallyAdjustsContentInsets: Bool {
        get {
            false
        }
        set { }
    }
    
    override func addSubview(_ view: NSView) {
        let name = String(describing: type(of: view))
        if name == "NSScrollPocket" {
            return
        }
        super.addSubview(view)
    }
    
}
