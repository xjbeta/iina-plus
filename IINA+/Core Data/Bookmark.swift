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

//@objc(Bookmark)
public class Bookmark: NSManagedObject {

    lazy var site: SupportSites = {
        SupportSites(url: url)
    }()
    
    func updateState() {
        if site == .unsupported {
            self.state = -1
            self.save()
            return
        }
        
        let limitSec: CGFloat = [.bangumi, .bilibili, .unsupported].contains(site) ? 300 : 20
        
        if let d = updateDate?.timeIntervalSince1970,
           (Date().timeIntervalSince1970 - d) < limitSec {
            return
        }
        
        Processes.shared.videoGet.liveInfo(url).done(on: .main) {
            self.setInfo($0)
            }.catch(on: .main) {
                let s = "Get live status error: \($0) \n - \(self.url)"
                Log(s)
                self.liveTitle = self.url
                self.state = -1
                self.save()
        }
    }
    
    private func setInfo(_ info: LiveInfo) {
        liveTitle = info.title
        liveName = info.name
        
        let isLiveSite = site != .bangumi && site != .bilibili
        
        cover = isLiveSite ? info.avatar : info.cover
        cover?.coverUrlFormatter(site: site)
        
        if info.site == .bangumi {
            liveName = "Bangumi"
        }
        
        if isLiveSite {
            state = info.isLiving ? 1 : 0
        } else if info.site == .bangumi || info.site == .bilibili {
            state = -99
        } else {
            state = -1
        }
        
        updateDate = Date()
        
        save()
    }
    
    func save() {
        try? (NSApp.delegate as? AppDelegate)?.persistentContainer.viewContext.save()
    }
}
