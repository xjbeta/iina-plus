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
	private var updating = false
    
    func updateState(_ force: Bool = false) {
        if site == .unsupported {
            self.state = LiveState.none.raw
            self.save()
            return
        }
        
        let limitSec: CGFloat = [.bangumi, .bilibili, .unsupported].contains(site) ? 300 : 20
        
		if inited {
			if updating {
				return
			}
			
			if let s = updateDate?.secondsSinceNow,
			   s < limitSec {
				return
			}
		}
		
        inited = true
        
        /*
        if let d = updateDate?.timeIntervalSince1970,
           (Date().timeIntervalSince1970 - d) > 1800 {
            state = LiveState.none.raw
        }
         */
		updating = true
		
		Task {
			do {
				let info = try await Processes.shared.videoDecoder.liveInfo(url)
				await setInfo(info)
			} catch let error {
				await setInfoError(error)
			}
			
			await MainActor.run {
				updateDate = Date()
				updating = false
				save()
			}
		}
    }
    
	@MainActor
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
    }
	
	@MainActor
	private func setInfoError(_ error: any Error) {
		let s = "Get live status error: \(error) \n - \(url)"
		Log(s)
		self.liveTitle = url
		self.state = LiveState.none.raw
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
