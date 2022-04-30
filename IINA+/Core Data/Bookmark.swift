//
//  Bookmark+CoreDataClass.swift
//  iina+
//
//  Created by xjbeta on 2018/7/19.
//  Copyright © 2018 xjbeta. All rights reserved.
//
//

import Cocoa
import Foundation
import CoreData
import SDWebImage

//@objc(Bookmark)
public class Bookmark: NSManagedObject {

    lazy var site: SupportSites = {
        SupportSites(url: url)
    }()
    
    @objc dynamic var image: NSImage?
    
    private var inited = false
    
    func updateState(_ force: Bool = false) {
        if site == .unsupported {
            self.state = LiveState.none.raw
            self.save()
            return
        }
        
        let limitSec: CGFloat = [.bangumi, .bilibili, .unsupported].contains(site) ? 300 : 20
        
        if let d = updateDate?.timeIntervalSince1970,
           (Date().timeIntervalSince1970 - d) < limitSec, inited {
            return
        }
        
        inited = true
        
        if let d = updateDate?.timeIntervalSince1970,
           (Date().timeIntervalSince1970 - d) > 1800 {
            state = LiveState.none.raw
        }
        
        Processes.shared.videoDecoder.liveInfo(url).done(on: .main) {
            self.setInfo($0)
            }.catch(on: .main) {
                let s = "Get live status error: \($0) \n - \(self.url)"
                Log(s)
                self.liveTitle = self.url
                self.state = LiveState.none.raw
                self.save()
        }
    }
    
    private func setInfo(_ info: LiveInfo) {
        liveTitle = info.title
        liveName = info.name
        
        let isLiveSite = site != .bangumi && site != .bilibili
        
        cover = isLiveSite ? info.avatar : info.cover
        cover?.coverUrlFormatter(site: isLiveSite ? site : .biliLive)

        updateImage()
        
        if info.site == .bangumi {
            liveName = "Bangumi"
        }
        
        if isLiveSite {
            state = (info.isLiving ? LiveState.living : LiveState.offline).raw
        } else if info.site == .bangumi || info.site == .bilibili {
            state = LiveState.offline.raw
        } else {
            state = LiveState.none.raw
        }
        
        updateDate = Date()
        
        save()
    }
    
    private func updateImage() {
        image = nil
        if let c = cover {
            SDWebImageManager.shared.loadImage(
                with: .init(string: c),
                progress: nil) { image, _, _, _, _, url in
                    self.image = image
            }
        }
    }
    
    func save() {
        try? (NSApp.delegate as? AppDelegate)?.persistentContainer.viewContext.save()
    }
}
