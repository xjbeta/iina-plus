//
//  WKWebViewExtension.swift
//  IINA+
//
//  Created by xjbeta on 2/22/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa
import WebKit
import PromiseKit

extension WKWebView {
    func evaluateJavaScript(_ jsString: String) -> Promise<(Any?)> {
        Promise { r in
            evaluateJavaScript(jsString) { re, error in
                if let e = error {
                    r.reject(e)
                } else  {
                    r.fulfill(re)
                }
            }
        }
    }
}

extension WKHTTPCookieStore {
    func getAllCookies() -> Promise<[HTTPCookie]> {
        Promise { r in
            self.getAllCookies {
                r.fulfill($0)
            }
        }
    }
}
