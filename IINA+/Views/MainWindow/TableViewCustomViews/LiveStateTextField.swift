//
//  LiveStateTextField.swift
//  IINA+
//
//  Created by xjbeta on 1/26/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa

class LiveStateTextField: NSTextField {
    var colorObserver: NSKeyValueObservation?
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.quaternaryLabelColor.cgColor
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        guard colorObserver == nil else { return }
        colorObserver = observe(\.textColor, options: [.initial, .new]) { textField, _ in
			Task { @MainActor in
				textField.backgroundColor = textField.textColor
			}
        }
    }
    
    deinit {
        colorObserver?.invalidate()
        colorObserver = nil
    }
}
