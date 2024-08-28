//
//  TaskExtension.swift
//  IINA+
//
//  Created by xjbeta on 2024/8/19.
//  Copyright © 2024 xjbeta. All rights reserved.
//

import Cocoa

extension Task where Success == Never, Failure == Never {
	public static func sleep(seconds duration: UInt64) async throws {
		try await sleep(nanoseconds: duration * 1_000_000_000)
	}
	
	public static func sleep(milliseconds duration: UInt64) async throws {
		try await sleep(nanoseconds: duration * 1_000_000)
	}
}
