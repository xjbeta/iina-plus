//
//  SuggestionsView.swift
//  iina+
//
//  Created by xjbeta on 2018/7/7.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class SuggestionsView: NSView {

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.cornerRadius = 5
    }
    
}
