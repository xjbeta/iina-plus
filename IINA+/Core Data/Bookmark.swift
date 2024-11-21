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
    
    @MainActor
    func setInfo(_ info: LiveInfo) async {
        liveTitle = info.title
        liveName = info.name
        
        let isLiveSite = site != .bangumi && site != .bilibili
        
        cover = isLiveSite ? info.avatar : info.cover
        cover?.coverUrlFormatter(site: isLiveSite ? site : .biliLive)

        await updateImage()
        
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
    }
    
    @MainActor
	func setInfoError(_ error: any Error) {
		let s = "Get live status error: \(error) \n - \(url)"
		Log(s)
		liveTitle = url
		state = LiveState.none.raw
	}
    
    @MainActor
    private func updateImage() async {
        image = nil
        guard let c = cover else { return }
        let img = await withCheckedContinuation { continuation in
            SDWebImageManager.shared.loadImage(
                with: .init(string: c),
                progress: nil) { image, _, _, _, _, url in
                    continuation.resume(returning: image?.sd_imageData())
            }
        }
        guard let img else { return }
        image = NSImage(data: img)
    }
    
    func save() {
//        try? (NSApp.delegate as? AppDelegate)?.persistentContainer.viewContext.save()
    }
}
