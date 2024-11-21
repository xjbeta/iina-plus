//
//  MBGA.swift
//  IINA+
//
//  Created by xjbeta on 2022/9/28.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Foundation

// Make Bilibili Great Again!
// https://greasyfork.org/zh-CN/scripts/415714-make-bilibili-grate-again

class MBGA: NSObject {
    enum BilibiliCDN: Int {
        case mirror, cache, mcdn, pcdn
        func name() -> String {
            switch self {
            case .mirror: return "Mirror"
            case .cache: return "Cache"
            case .mcdn: return "MCDN"
            case .pcdn: return "PCDN"
            }
        }
    }
    
    static func update(_ urls: [String]) -> [String] {
		let urls: [String] = Array(Set(urls))
		
		return urls.sorted { u1, u2 in
			cdnLevel(for: u1).rawValue < cdnLevel(for: u2).rawValue
		}
		
		/*
        urls.compactMap { u -> String? in
            guard var uc = URLComponents(string: u),
                  let host = uc.host else { return u }
            
            if host.hasSuffix(".mcdn.bilivideo.cn") {
//                document.head.innerHTML.match(/up[\w-]+\.bilivideo\.com/)
//                uc.host = "upos-sz-mirrorcoso1.bilivideo.com"
//                uc.port = 443
            } else if host.hasSuffix(".szbdyd.com"),
                      let host = uc.queryItems?.first(where: { $0.name == "xy_usource" })?.value {
                uc.host = host
                uc.port = 443
            }
            return uc.string
        }.sorted { u1, u2 in
            cdnLevel(for: u1).rawValue < cdnLevel(for: u2).rawValue
        }
		*/
    }
    
    static func cdnLevel(for url: String) -> BilibiliCDN {
		guard let uc = URLComponents(string: url),
              let host = uc.host else { return .mcdn }
        
        if host.contains(".mcdn.bilivideo.cn") {
            return .mcdn
        } else if host.contains(".szbdyd.com") {
            return .pcdn
        } else if host.contains("bilivideo.com") && host.hasPrefix("up") {
            return .mirror
        } else {
            return .cache
        }
    }
}
