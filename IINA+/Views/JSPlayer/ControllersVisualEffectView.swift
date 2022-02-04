//
//  ControllersVisualEffectView.swift
//  IINA+
//
//  Created by xjbeta on 2/4/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa

class ControllersVisualEffectView: NSVisualEffectView {

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)


    }
    
    override func viewDidMoveToWindow() {
        blendingMode = .withinWindow
        if #available(macOS 10.14, *) {
            material = .fullScreenUI
        } else {
            material = .popover
        }
        appearance = .init(named: .vibrantDark)
        wantsLayer = true
        layer?.cornerRadius = 8   
    }
}
