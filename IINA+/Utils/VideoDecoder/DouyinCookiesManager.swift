//
//  DouyinCookiesManager.swift
//  IINA+
//
//  Created by xjbeta on 2024/6/29.
//  Copyright © 2024 xjbeta. All rights reserved.
//

import Cocoa

actor DouyinCookiesManager {

	var cookies = [String: String]()
	
	var cookiesString: String {
		get {
			cookies.map {
				"\($0.key)=\($0.value)"
			}.joined(separator: ";")
		}
	}
	
	private var refreshCookies: Task<[String: String], Error>?
	
	private let prepareArgs: (() async throws -> [String: String])
	
	init(prepareArgs: @escaping (() async throws -> [String: String])) {
		self.prepareArgs = prepareArgs
	}
	
	
	func initCookies() async throws -> [String: String] {
		if let handle = refreshCookies {
			return try await handle.value
		}
		
		if cookies.count > 0 {
			return cookies
		}
		cookies = try await refreshCookies()
		return cookies
	}
	
	private func refreshCookies() async throws -> [String: String] {
		if let refreshTask = refreshCookies {
			return try await refreshTask.value
		}

		let task = Task { () throws -> [String: String] in
			return try await prepareArgs()
		}

		self.refreshCookies = task
		return try await task.value
	}
	
	func setCookies(_ cookies: [String: String]) async {
		self.cookies = cookies
	}
	
	func removeAll() async {
		cookies.removeAll()
	}
}
