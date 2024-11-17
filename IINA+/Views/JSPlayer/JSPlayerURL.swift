//
//  JSPlayerURL.swift
//  IINA+
//
//  Created by xjbeta on 2023/11/2.
//  Copyright © 2023 xjbeta. All rights reserved.
//

import Cocoa

class JSPlayerURL: NSObject {
	
	static func encode(_ url: String, site: SupportSites) -> String {
        let key = JSPlayerSchemeName + "://hack.iina-plus.key/webplayer/live.flv"
        
		guard var uc = URLComponents(string: key),
			  let site = site.rawValue.base64Encode().addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
			  let url = url.base64Encode().addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
		else {
			fatalError("JSPlayerURL encode \(url) \(site.rawValue)")
		}
				
		uc.queryItems = [
			.init(name: "site", value: site),
			.init(name: "url", value: url)
		]
		
		return uc.url?.absoluteString ?? key
	}
	
	static func decode(_ url: String) -> (url: String, site: SupportSites) {
		let uc = URLComponents(string: url)

		var url = ""
		var site = ""
		
		uc?.queryItems?.forEach {
			switch $0.name {
			case "site":
				site = $0.value?.removingPercentEncoding?.base64Decode() ?? ""
			case "url":
				url = $0.value?.removingPercentEncoding?.base64Decode() ?? ""
			default:
				break
			}
		}
		
		guard !url.isEmpty, let site = SupportSites(rawValue: site) else {
			fatalError("JSPlayerURL decode \(url)")
		}
		
		return (url, site)
	}
}
