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
    
    var isSelected: Bool = false {
        didSet {
            needsDisplay = true
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let selectionRect = NSInsetRect(bounds, 0, 0)
        let selectionPath = NSBezierPath(roundedRect: selectionRect, xRadius: 6, yRadius: 6)
        if isSelected {
            NSColor.selectedControlColor.setFill()
        } else {
            NSColor.white.setFill()
        }
        selectionPath.fill()
    }
    
    func resetInfo() {
        titleTextField.stringValue = ""
        nameTextField.stringValue = ""
        userCoverImageView.image = nil
        liveStatusImageView.image = nil
    }
    
    func setInfo(_ info: LiveInfo) {
        DispatchQueue.main.async {
            self.titleTextField.stringValue = info.title
            self.nameTextField.stringValue = info.name
            self.userCoverImageView.image = info.userCover
            self.liveStatusImageView.image = info.isLiving ? NSImage(named: "NSStatusAvailable") : NSImage(named: "NSStatusUnavailable")
        }
    }
    
    
    func screenshot(_ rect: CGRect? = nil) -> NSImage {
        let image = NSImage()
        let rect = rect ?? self.bounds
        
        if let bitmap = self.bitmapImageRepForCachingDisplay( in: rect ) {
            self.cacheDisplay( in: rect, to: bitmap )
            image.addRepresentation( bitmap )
        }
        
        return image
    }
    
}

extension NSColor {
    public class var customBackgroundColor: NSColor {
        return NSColor(calibratedRed: 0.97, green: 0.95, blue: 0.94, alpha: 1)
    }
}
