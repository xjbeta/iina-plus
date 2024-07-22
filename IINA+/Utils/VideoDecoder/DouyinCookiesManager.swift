//
//  DouyinCookiesManager.swift
//  IINA+
//
//  Created by xjbeta on 2024/6/29.
//  Copyright © 2024 xjbeta. All rights reserved.
//

import Cocoa

actor DouyinCookiesManager {

	private var _cookies = [String: String]()
	var cookies: [String: String] {
		_cookies
	}
	
	var cookiesString: String {
		cookies.map {
			"\($0.key)=\($0.value)"
		}.joined(separator: ";")
	}
	
	private var refreshCookies: Task<[String: String], Error>
	
	private let prepareArgs: (() async throws -> [String: String])
	
	init(prepareArgs: @escaping (() async throws -> [String: String])) {
		self.prepareArgs = prepareArgs
		
		refreshCookies = Task { () throws -> [String: String] in
			try await prepareArgs()
		}
	}
	
	func initCookies() async throws -> [String: String] {
		if cookies.count > 0 {
			return cookies
		}
		return try await refreshCookies.value
	}
	
	func setCookies(_ cookies: [String: String]) async {
		_cookies = cookies
	}
	
	func removeAll() async {
		_cookies.removeAll()
	}
}
