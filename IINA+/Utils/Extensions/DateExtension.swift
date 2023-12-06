//
//  DateExtension.swift
//  IINA+
//
//  Created by xjbeta on 2023/12/6.
//  Copyright © 2023 xjbeta. All rights reserved.
//

import Cocoa

extension Date {
	var secondsSinceNow: TimeInterval {
		get {
			abs(timeIntervalSinceNow)
		}
	}
}
