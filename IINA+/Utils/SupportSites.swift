//
//  SupportSites.swift
//  IINA+
//
//  Created by xjbeta on 11/15/21.
//  Copyright © 2021 xjbeta. All rights reserved.
//

import Cocoa

enum SupportSites: String {
    case biliLive = "live.bilibili.com"
    case bilibili = "www.bilibili.com/video"
    case bangumi = "www.bilibili.com/bangumi"
    case douyu = "www.douyu.com"
    case huya = "www.huya.com"
    case eGame = "egame.qq.com"
    case cc163 = "cc.163.com"
    case unsupported
    
    var siteName: String {
        switch self {
        case .biliLive:
            return NSLocalizedString("SupportSites.Bilibili Live", comment: "Bilibili Live")
        case .bilibili:
            return NSLocalizedString("SupportSites.Bilibili", comment: "Bilibili")
        case .bangumi:
            return NSLocalizedString("SupportSites.Bilibili Bangumi", comment: "Bilibili Bangumi")
        case .douyu:
            return NSLocalizedString("SupportSites.Douyu", comment: "Douyu")
        case .huya:
            return NSLocalizedString("SupportSites.Huya", comment: "Huya")
        case .eGame:
            return NSLocalizedString("SupportSites.eGame", comment: "eGame")
        case .cc163:
            return NSLocalizedString("SupportSites.CC163", comment: "CC163")
        case .unsupported:
            return NSLocalizedString("SupportSites.Unsupported", comment: "Unsupported")
        }
    }
    
    init(url: String) {
        guard let u = URL(string: url) else {
            self = .unsupported
            return
        }
        
        let host = u.host ?? ""
        if host == "www.bilibili.com", u.pathComponents.count >= 2 {
            switch u.pathComponents[1] {
            case "video":
                self = .bilibili
            case "bangumi":
                self = .bangumi
            default:
                self = .unsupported
            }
        } else if let list = SupportSites(rawValue: host) {
            self = list
        } else {
            self = .unsupported
        }
    }
}
