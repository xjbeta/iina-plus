//
//  SuggestionsWindow.swift
//  iina+
//
//  Created by xjbeta on 2018/7/7.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class SuggestionsWindowController: NSWindowController {
    
    override func windowDidLoad() {
        super.windowDidLoad()
        window?.styleMask = .borderless
        window?.backingType = .buffered
        window?.isOpaque = false
        window?.backgroundColor = .clear
    }
    
    func begin(for searchField: NSSearchField?, with str: String) {
        if let suggesttionsWindow = window,
            let searchField = searchField,
            let parentWindow = searchField.superview?.window,
            let suggestionsVC = suggesttionsWindow.contentViewController as? SuggestionsViewController {
            
            let size = NSSize(width: searchField.frame.size.width, height: 32)
            suggesttionsWindow.setContentSize(size)
            
            
//            let rect = parentWindow.convertToScreen(searchField.frame)
//            var origin = rect.origin
//            origin.y -= 5
//
//            suggesttionsWindow.setFrameTopLeftPoint(origin)
            
            var rect = parentWindow.frame
            rect.origin.y += rect.size.height
            rect.origin.x += 77
            rect.origin.y -= 42
            
            suggesttionsWindow.setFrameTopLeftPoint(rect.origin)
            
            parentWindow.addChildWindow(suggesttionsWindow, ordered: .above)
            
            suggestionsVC.url = str
        }
    }
    
    func cancelSuggestions() {
        if let suggesttionsWindow = window,
            suggesttionsWindow.isVisible {
            suggesttionsWindow.parent?.removeChildWindow(suggesttionsWindow)
            suggesttionsWindow.orderOut(nil)
        }
    }

}

