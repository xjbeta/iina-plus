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
    case quanmin = "www.quanmin.tv"
    case longzhu = "star.longzhu.com"
    case eGame = "egame.qq.com"
    //    case yizhibo = "www.yizhibo.com"
    case langPlay = "play.lang.live"
    case cc163 = "cc.163.com"
    case unsupported
    
    var siteName: String {
        switch self {
        case .biliLive:
            return "Bilibili Live"
        case .bilibili:
            return "Bilibili"
        case .bangumi:
            return "Bilibili Bangumi"
        case .douyu:
            return "Douyu"
        case .huya:
            return "Huya"
        case .quanmin:
            return "QuanMin"
        case .longzhu:
            return "LongZhu"
        case .eGame:
            return "eGame"
        case .langPlay:
            return "LangPlay"
        case .cc163:
            return "CC163"
        case .unsupported:
            return "Unsupported"
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
