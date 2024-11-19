//
//  BilibiliCardTableCellView.swift
//  iina+
//
//  Created by xjbeta on 2018/8/8.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import SDWebImage

class BilibiliCardTableCellView: NSTableCellView {

    @IBOutlet weak var imageBoxView: BilibiliCardImageBoxView!
    @IBOutlet var progressView: BilibiliCardProgressView!
    
    @IBOutlet weak var titleTextField: NSTextField!
    @IBOutlet weak var upTextField: NSTextField!
    @IBOutlet weak var viewsTextField: NSTextField!
    
    @IBOutlet weak var durationTextField: NSTextField!
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
    }

    func update(_ card: BilibiliCard) {
        imageView?.image = nil
        
        titleTextField.stringValue = card.title
        upTextField.stringValue = card.name
        viewsTextField.integerValue = card.views
        durationTextField.doubleValue = card.duration
        
        let aid = card.aid
        
        imageBoxView.aid = aid
        imageBoxView.imageView?.image = nil
        imageBoxView.pic = nil
        imageBoxView.updatePreview(.stop)
        
        var url = card.picUrl
        url.coverUrlFormatter(site: .bilibili)
        
        if let imageView = imageView {
            SDWebImageManager.shared.loadImage(with: .init(string: url), progress: nil) { img,_,_,_,_,_ in
                guard self.imageBoxView.aid == aid else { return }
                self.imageBoxView.pic = img
                imageView.image = img
            }
        }
    }
}
