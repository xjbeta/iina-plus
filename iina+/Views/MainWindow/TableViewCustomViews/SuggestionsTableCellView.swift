//
//  SuggestionsTableCellView.swift
//  iina+
//
//  Created by xjbeta on 2018/7/8.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class SuggestionsTableCellView: NSTableCellView {

    var isSelected: Bool = false {
        didSet {
            needsDisplay = true
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let selectionRect = NSInsetRect(bounds, 0, 0)
        let selectionPath = NSBezierPath(roundedRect: selectionRect, xRadius: 3, yRadius: 3)
        if isSelected {
            NSColor.customHighlightColor.setFill()
        } else {
            NSColor.white.setFill()
        }
        selectionPath.fill()
    }
    
    func setStream(_ stream: (key: String, value: Stream)) {
        var strArray = [stream.key]
        if let videoProfile = stream.value.videoProfile {
            strArray.append(videoProfile)
        }
        
        if let size = stream.value.size, size != 0 {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            strArray.append(formatter.string(fromByteCount: size))
        }
        
        strArray = strArray.reduce([String]()) { result, str in
            var re = result
            if !re.contains(str), str != "" {
                re.append(str)
            }
            return re
        }
        
        textField?.stringValue = strArray.joined(separator: " - ")
    }
    
}
