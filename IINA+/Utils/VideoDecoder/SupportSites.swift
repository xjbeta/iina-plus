//
//  SupportSites.swift
//  IINA+
//
//  Created by xjbeta on 11/15/21.
//  Copyright © 2021 xjbeta. All rights reserved.
//

import Cocoa

enum SupportSites: String {
    case b23 = "b23.tv"
    case biliLive = "live.bilibili.com"
    case bilibili = "www.bilibili.com/video"
    case bangumi = "www.bilibili.com/bangumi"
    case douyu = "www.douyu.com"
    case huya = "www.huya.com"
    case cc163 = "cc.163.com"
    case douyin = "live.douyin.com"
    case qqLive = "live.qq.com"
    case local
    case unsupported
    
    init(url: String) {
        guard url != "",
              let u = URL(string: url) else {
            self = .unsupported
            return
        }
        
        let host = u.host ?? ""
        if let bUrl = BilibiliUrl(url: url) {
            switch bUrl.urlType {
            case .video:
                self = .bilibili
            case .bangumi:
                self = .bangumi
            default:
                self = .unsupported
            }
		} else if host == "www.douyin.com",
				  let pc = NSURL(string: url)?.pathComponents,
				  pc.count >= 4,
				  pc[2] == "live",
					let rid = Int(pc[3]) {
			
			self = .init(url: "https://live.douyin.com/\(rid)")
		} else if let list = SupportSites(rawValue: host) {
            self = list
        } else {
            self = .unsupported
        }
    }
    
    var siteName: String {
        // Auto-generate with `bartycrouch update`
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
        case .cc163:
            return NSLocalizedString("SupportSites.CC163", comment: "CC163")
        case .douyin:
            return NSLocalizedString("SupportSites.DouYin", comment: "DouYin")
        case .qqLive:
            return NSLocalizedString("SupportSites.QQLive", comment: "QQ Live")
        case .unsupported:
            return NSLocalizedString("SupportSites.Unsupported", comment: "Unsupported")
        case .b23, .local:
            return ""
        }
    }
	
	func supportWebPlayer() -> Bool {
		![.bilibili, .bangumi, .b23, .local].contains(self)
	}
}


enum LiveState: Int {
    case living = 1
    case offline = 0
    case video = -99
    case replay = 2
    case `none` = -1
    
    var raw: Int16 {
        get {
            return Int16(rawValue)
        }
    }
    
    var color: NSColor {
        get {
            let pref = Preferences.shared
            switch self {
            case .living:
                return pref.stateLiving
            case .offline:
                return pref.stateOffline
            case .video:
                return .clear
            case .replay:
                return pref.stateReplay
            case .none:
                return pref.stateUnknown
            }
        }
    }
}

protocol SupportSiteProtocol {
    func liveInfo(_ url: String) async throws -> LiveInfo
    func decodeUrl(_ url: String) async throws -> YouGetJSON
}
