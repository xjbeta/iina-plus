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
    
    private var isLiveSite = false
    
    var url: URL? {
        didSet {
            if oldValue == url {
                getInfo()
            } else {
                resetInfo()
                getInfo()
            }
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
    }
    
    func getInfo() {
        guard let url = url else { return }
        let str = url.absoluteString
        let site = LiveSupportList(url: str)
        
        isLiveSite = site != .bangumi && site != .bilibili
        
        let vg = Processes.shared.videoGet
        vg.liveInfo(str).done(on: .main) {
            guard url == self.url else { return }
            self.setInfo($0)
            }.catch(on: .main) {
                Log("Get live status error: \($0) \n - \(str)")
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
        titleTextField.stringValue = info.title
        nameTextField.stringValue = info.name
        
        if isLiveSite {
            userCoverImageView.setImage(info.avatar)
            liveStatusImageView.isHidden = false
            liveStatusImageView.image = info.isLiving ? NSImage(named: "NSStatusAvailable") : NSImage(named: "NSStatusUnavailable")
        } else {
            userCoverImageView.setImage(info.cover)
            liveStatusImageView.isHidden = true
        }
        
        if info.site == .bangumi {
            nameTextField.stringValue = "Bangumi"
            
            nameTextField.textColor = NSColor(red:0.94, green:0.58, blue:0.70, alpha:1.00)
        } else {
            nameTextField.textColor = .labelColor
        }
        
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
