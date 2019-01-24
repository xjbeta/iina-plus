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
    
    var url: URL? {
        didSet {
            getInfo()
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
    }
    
    func getInfo() {
        guard let url = url else { return }
        Processes.shared.videoGet.liveInfo(url.absoluteString).done(on: .main) {
            self.setInfo($0)
            }.catch(on: .main) {
                Log("Get live status error: \($0)")
                self.setErrorInfo(url.absoluteString)
        }
    }
    
    func resetInfo() {
        titleTextField.stringValue = ""
        nameTextField.stringValue = ""
        userCoverImageView.image = nil
        liveStatusImageView.image = nil
    }
    
    func setInfo(_ info: LiveInfo) {
        self.titleTextField.stringValue = info.title
        self.nameTextField.stringValue = info.name
        self.userCoverImageView.image = info.userCover
        self.liveStatusImageView.image = info.isLiving ? NSImage(named: "NSStatusAvailable") : NSImage(named: "NSStatusUnavailable")
    }
    
    func setErrorInfo(_ str: String) {
        if self.userCoverImageView.image == nil {
            self.titleTextField.stringValue = str
            self.userCoverImageView.image = nil
            self.nameTextField.stringValue = ""
        }
        self.liveStatusImageView.image = NSImage(named: "NSStatusNone")
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
