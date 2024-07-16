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
	
	private var lock = NSLock()
	
	init(prepareArgs: @escaping (() async throws -> [String: String])) {
		self.prepareArgs = prepareArgs
	}
	
	
	func initCookies() async throws -> [String: String] {
		try await withCheckedThrowingContinuation { continuation in
			lock.lock()
			defer { lock.unlock() }
			
			Task {
				do {
					if let handle = refreshCookies {
						let cookies = try await handle.value
						continuation.resume(returning: cookies)
						return
					}
					
					if cookies.count > 0 {
						continuation.resume(returning: cookies)
						return
					}
					
					let task = Task { () throws -> [String: String] in
						defer {
							self.refreshCookies = nil
						}
						return try await prepareArgs()
					}

					self.refreshCookies = task
					cookies = try await task.value
					
					continuation.resume(returning: cookies)
				} catch {
					continuation.resume(throwing: error)
				}
			}
		}
	}
	
	func setCookies(_ cookies: [String: String]) async {
		self.cookies = cookies
	}
	
	func removeAll() async {
		cookies.removeAll()
	}
}
