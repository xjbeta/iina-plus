//
//  WKWebViewExtension.swift
//  IINA+
//
//  Created by xjbeta on 2/22/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa
import WebKit

extension WKWebView {
	
	@discardableResult
	func evaluateJavaScriptAsync(_ str: String) async throws -> Any? {
		return try await withCheckedThrowingContinuation { continuation in
			DispatchQueue.main.async {
				self.evaluateJavaScript(str) { data, error in
					if let error = error {
						continuation.resume(throwing: error)
					} else {
						continuation.resume(returning: data)
					}
				}
			}
		}
	}
}
