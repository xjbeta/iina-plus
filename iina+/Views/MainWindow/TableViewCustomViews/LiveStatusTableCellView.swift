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
    
    var url: URL? {
        didSet {
            getInfo()
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let selectionRect = NSInsetRect(bounds, 0, 0)
        let selectionPath = NSBezierPath(roundedRect: selectionRect, xRadius: 3, yRadius: 3)
        if isSelected {
            if #available(OSX 10.14, *) {
                NSColor.selectedContentBackgroundColor.setFill()
            } else {
                NSColor.customHighlightColor.setFill()
            }
        } else {
            if #available(OSX 10.14, *) {
                NSColor.unemphasizedSelectedTextBackgroundColor.setFill()
            } else {
                NSColor.white.setFill()
            }
        }
        selectionPath.fill()
        
    }
    
    func getInfo() {
        guard let url = url else { return }
        getInfo(url, { liveInfo in
            self.setInfo(liveInfo)
        }) { re in
            do {
                let _ = try re()
            } catch let error {
                Logger.log("Get live status error: \(error)")
                self.setErrorInfo(url.absoluteString)
            }
        }
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
    
    func setErrorInfo(_ str: String) {
        DispatchQueue.main.async {
            if self.userCoverImageView.image == nil {
                self.titleTextField.stringValue = str
                self.userCoverImageView.image = nil
                self.nameTextField.stringValue = ""
            }
            self.liveStatusImageView.image = NSImage(named: "NSStatusNone")
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
    public class var customHighlightColor: NSColor {
        return NSColor(red:0.75, green:0.89, blue:0.99, alpha:1.00)
    }
}
