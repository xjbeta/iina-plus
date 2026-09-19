//
//  SupportSites.swift
//  IINA+
//
//  Created by xjbeta on 11/15/21.
//  Copyright © 2021 xjbeta. All rights reserved.
//

import Cocoa

enum SupportSites {
    case b23
    case biliLive
    case bilibili
    case bangumi
    case douyu
    case huya
    case cc163
    case douyin
    case qieTV
    case local
    case unsupported

    private static let siteHosts: [SupportSites: [String]] = [
        .b23: [
            "b23.tv"
        ],
        .biliLive: [
            "live.bilibili.com"
        ],
        .bangumi: [
            "www.bilibili.com",
            "bilibili.com"
        ],
        .bilibili: [
            "www.bilibili.com",
            "bilibili.com"
        ],
        .douyu: [
            "www.douyu.com",
            "douyu.com"
        ],
        .huya: [
            "www.huya.com",
            "huya.com"
        ],
        .cc163: [
            "cc.163.com",
            "ds.163.com"
        ],
        .douyin: [
            "live.douyin.com",
            "www.douyin.com",
            "douyin.com"
        ],
        .qieTV: [
            "www.qie.tv",
            "qie.tv",
            "live.qq.com"
        ]
    ]

    var hosts: [String] {
        SupportSites.siteHosts[self] ?? []
    }

    init(url: String) {
        guard url != "",
              var comps = URLComponents(string: url),
              let host = comps.host else {
            self = .unsupported
            return
        }

        comps.host = SupportSites.canonicalHost(host)

        let normalizedURL = comps.url?.absoluteString ?? url
        let normalizedHost = comps.host ?? host

        if normalizedHost == "www.douyin.com" {
            let pathParts = comps.path.split(separator: "/").map(String.init)
            guard pathParts.count >= 2,
                  pathParts[0] == "live",
                  let rid = Int(pathParts[1]) else {
                self = .unsupported
                return
            }
            self = .init(url: "https://live.douyin.com/\(rid)")
            return
        }

        if let bUrl = BilibiliUrl(url: normalizedURL) {
            switch bUrl.urlType {
            case .video:
                self = .bilibili
            case .bangumi:
                self = .bangumi
            default:
                self = .unsupported
            }
        } else {
            self = SupportSites(host: normalizedHost) ?? .unsupported
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
		case .qieTV:
			return NSLocalizedString("SupportSites.QieTV", comment: "QieTV")
		case .unsupported:
			return NSLocalizedString("SupportSites.Unsupported", comment: "Unsupported")
		case .b23, .local:
			return ""
		}
	}

    func supportWebPlayer() -> Bool {
		![.bilibili, .bangumi, .b23, .local].contains(self)
    }

	var urlFilterPredicate: String {
		switch self {
		case .bilibili:
			return "url CONTAINS 'bilibili.com/video/'"
		case .bangumi:
			return "url CONTAINS 'bilibili.com/bangumi/'"
		default:
			let tokens = hosts
			if tokens.isEmpty {
				return ""
			} else if tokens.count == 1 {
				return "url CONTAINS '\(tokens[0])'"
			} else {
				return tokens.map { "url CONTAINS '\($0)'" }.joined(separator: " || ")
			}
		}
	}

	static func canonicalHost(_ host: String) -> String {
		SupportSites.siteHosts.first(where: { $0.value.contains(host) })?.value.first ?? host
	}

    init?(host: String) {
        let normalizedHost = SupportSites.canonicalHost(host)
        guard let site = SupportSites.siteHosts.first(where: { $0.value.contains(normalizedHost) })?.key else {
            return nil
        }
        self = site
    }

    static func isBilibiliHost(_ host: String?) -> Bool {
		guard let host else { return false }
		return SupportSites.siteHosts[.bilibili]?.contains(host) == true || SupportSites.siteHosts[.bangumi]?.contains(host) == true
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
