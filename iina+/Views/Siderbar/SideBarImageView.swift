//
//  SideBarImageView.swift
//  Art Book
//
//  Created by xjbeta on 2018/12/23.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class SideBarImageView: NSImageView {
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .medium
        super.draw(dirtyRect)
    }
}
