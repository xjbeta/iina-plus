//
//  CharacterSetExtension.swift
//  IINA+
//
//  Created by xjbeta on 2024/10/4.
//  Copyright © 2024 xjbeta. All rights reserved.
//

import Cocoa

extension CharacterSet {
	static let urlQueryValueAllowed: CharacterSet = {
		let generalDelimitersToEncode = ":#[]@?/" // does not include "?" or "/" due to RFC 3986 - Section 3.4
		let subDelimitersToEncode = "!$&'()*+,;="
		
		var allowed = CharacterSet.urlQueryAllowed
		allowed.remove(charactersIn: generalDelimitersToEncode + subDelimitersToEncode)
		
		return allowed
	}()
}
