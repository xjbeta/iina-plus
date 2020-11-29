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
    
    var state: PreviewStatus = .init🐴
    
    var imageView: NSImageView? {
        return (self.superview as? BilibiliCardTableCellView)?.imageView
    }
    
    var progressView: BilibiliCardProgressView? {
        return (self.superview as? BilibiliCardTableCellView)?.progressView
    }
    
    var timer: DispatchSourceTimer?
    let timeOut: DispatchTimeInterval = .seconds(1)
    
    var previewPercent: Float = 0
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Drawing code here.
    }
    
    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let per = Float(location.x) / Float(frame.width)
        previewPercent = per
        
        if let view = progressView {
            if view.isHidden {
                timer?.schedule(deadline: .now() + timeOut, repeating: 0)
            } else {
                updatePreview(.start, per: per)
            }
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        timer = DispatchSource.makeTimerSource(flags: [], queue: .main)
        timer?.schedule(deadline: .now() + timeOut, repeating: 0)
        timer?.setEventHandler {
            self.updatePreview(.init🐴)
            self.stopTimer()
        }
        timer?.resume()
    }
    
    override func mouseExited(with event: NSEvent) {
        updatePreview(.stop)
        stopTimer()
    }
    
    func stopTimer() {
        if timer != nil {
            timer?.cancel()
            timer = nil
        }
    }
    
    enum PreviewStatus {
        case stop, start, init🐴
    }
    
    func updatePreview(_ status: PreviewStatus, per: Float = 0) {
        switch status {
        case .init🐴:
            state = .init🐴
            if pImages.count == 0 {
                Bilibili().getPvideo(aid).done(on: .main) { pvideo in
                    self.pImages = pvideo.pImages
                    self.updatePreview(.start, per: self.previewPercent)
                    }.catch { error in
                        Log("Error when get pImages: \(error)")
                }
            } else {
                self.updatePreview(.start, per: self.previewPercent)
            }
        case .stop:
            state = .stop
            progressView?.isHidden = true
            imageView?.image = pic
            displayedIndex = -1
        case .start:
            state = .start
            progressView?.isHidden = false
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
