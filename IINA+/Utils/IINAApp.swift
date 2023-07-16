//
//  IINAApp.swift
//  IINA+
//
//  Created by xjbeta on 2023/7/15.
//  Copyright © 2023 xjbeta. All rights reserved.
//

import Cocoa

class IINAApp: NSObject {
	
	func buildVersion() -> Int {
		let b = Bundle(path: "/Applications/IINA.app")
		let build = b?.infoDictionary?["CFBundleVersion"] as? String ?? ""
		return Int(build) ?? 0
	}
	
	func archiveType() -> IINAUrlType {
		let build = buildVersion()
		
		let b = Bundle(path: "/Applications/IINA.app")
		guard let version = b?.infoDictionary?["CFBundleShortVersionString"] as? String else {
			return .none
		}
		if version.contains("Danmaku") {
			return .danmaku
		} else if version.contains("plugin") {
			return .plugin
		} else if build >= 135 {
			return .plugin
		}
		return .normal
	}
	

}
