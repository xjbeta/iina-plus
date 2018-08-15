//
//  BilibiliCardImageBoxView.swift
//  iina+
//
//  Created by xjbeta on 2018/8/15.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class BilibiliCardImageBoxView: NSView {
    var pic: NSImage? = nil
    var pImages: [NSImage] = []
    var aid: Int = 0
    var displayedIndex = -1
    
    var imageView: NSImageView? {
        return self.subviews.compactMap { $0 as? NSImageView }.first
    }
    
    var progressView: BilibiliCardProgressView? {
        return self.subviews.compactMap { $0 as? BilibiliCardProgressView }.first
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Drawing code here.
    }
    
    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let per = Float(location.x) / Float(frame.width)
        progressView?.doubleValue = Double(per)
        if pImages.count > 0 {
            let index = lroundf(Float(pImages.count - 1) * per)
            if index != displayedIndex,
                index <= pImages.count,
                index >= 0 {
                imageView?.image = pImages[index]
                displayedIndex = index
            }
        }
    }
    
    
    override func mouseEntered(with event: NSEvent) {
        if pImages.count == 0 {
            Bilibili().getPvideo(aid, {
                self.pImages = $0.pImages
            }) { re in
                do {
                    let _ = try re()
                } catch let error {
                    Logger.log("Error when get pImages: \(error)")
                }
            }
        }
        
        progressView?.isHidden = false
    }
    
    override func mouseExited(with event: NSEvent) {
        progressView?.isHidden = true
        imageView?.image = pic
        displayedIndex = -1
    }
    
    override func updateTrackingAreas() {
        trackingAreas.forEach {
            removeTrackingArea($0)
        }
        
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .mouseMoved],
                                       owner: self,
                                       userInfo: nil))
        if let mouseLocation = window?.mouseLocationOutsideOfEventStream {
            if isMousePoint(mouseLocation, in: bounds) {
                mouseEntered(with: NSEvent())
            } else {
                mouseExited(with: NSEvent())
            }
            
        }
        super.updateTrackingAreas()
    }
}
