//
//  BilibiliCardImageBoxView.swift
//  iina+
//
//  Created by xjbeta on 2018/8/15.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import Alamofire

class BilibiliCardImageBoxView: NSView {
    var pic: NSImage? = nil
    var pImages: [NSImage] = []
    var pAid: Int = -1
    var aid: Int = 0 {
        didSet {
            pAid = -1
            pImages = []
        }
    }
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
            if pImages.count == 0 || pAid != aid {
                let id = aid
				Task {
					do {
						let pvideo = try await Processes.shared.videoDecoder.bilibili.getPvideo(id)
                        pImages = await loadPImages(pvideo)
						pAid = id
						updatePreview(.start, per: previewPercent)
					} catch let error {
						Log("Error when get pImages: \(error)")
					}
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
                    index < pImages.count,
                    index >= 0 {
                    imageView?.image = pImages[index]
                    displayedIndex = index
                }
            }
        }
    }
    
    
    
    
    func loadPImages(_ pvideo: BilibiliPvideo) async -> [NSImage] {
        func crop(_ image: NSImage, with rect: NSRect) -> NSImage? {
            guard let croppedImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.cropping(to: rect) else {
                return nil
            }
            let reImage = NSImage(cgImage: croppedImage, size: rect.size)
            return reImage
        }
        
        var pImages: [NSImage] = []
        var limitCount = 0
        let imagesCount = pvideo.imagesCount
        let xLen = pvideo.xLen
        let yLen = pvideo.yLen
        let xSize = pvideo.xSize
        let ySize = pvideo.ySize
        
        let imageDatas = try? await withThrowingTaskGroup(of: Data.self) { group in
            pvideo.images.compactMap { image in
                URL(string: image)
            }.forEach { url in
                group.addTask {
                    try await AF.request(url).serializingData().value
                }
            }
            
            var re = [Data]()
            for try await data in group {
                re.append(data)
            }
            return re
        }
        
        imageDatas?.forEach { data in
            guard let image = NSImage(data: data) else { return }
            
            var xIndex = 0
            var yIndex = 0
            
            while yIndex < yLen {
                while xIndex < xLen {
                    let rect = NSRect(x: xIndex * xSize, y: yIndex * ySize, width: xSize, height: ySize)
                    
                    if let croppedImage = crop(image, with: rect) {
                        pImages.append(croppedImage)
                    }
                    limitCount += 1
                    if limitCount == imagesCount {
                        xIndex = 10
                        yIndex = 10
                    }
                    xIndex += 1
                    if xIndex == xLen {
                        xIndex = 0
                        yIndex += 1
                    }
                }
            }
        }
        return pImages
    }
}
