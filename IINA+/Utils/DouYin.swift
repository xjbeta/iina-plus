//
//  DouYin.swift
//  IINA+
//
//  Created by xjbeta on 2/19/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa
import WebKit
import PromiseKit
import SwiftSoup
import Alamofire
import Marshal

class DouYin: NSObject {
    
    var prepareTask: Promise<()>?
    var dyFinishNitification: NSObjectProtocol?
    
    var cookies = [String: String]()
    var storageDic = [String: String]()
    
    let douyinEmptyURL = URL(string: "https://live.douyin.com/1")!
    var douyinUA = ""
    
    let privateKeys = [
        "X2J5dGVkX3BhcmFtX3N3",
        "dHRfc2NpZA==",
        "Ynl0ZWRfYWNyYXdsZXI=",
        "WC1Cb2d1cw==",
        "X3NpZ25hdHVyZQ=="
    ]
    
    func getInfo(_ url: URL) -> Promise<LiveInfo> {
        if cookies.count == 0 {
            if prepareTask == nil {
                prepareTask = prepareArgs()
            }
            return prepareTask!.then {
                self.getContent(url)
            }
        } else {
            return self.getContent(url)
        }
    }
    
    func getContent(_ url: URL) -> Promise<LiveInfo> {
        Promise { resolver in
            let cookieString = cookies.map {
                "\($0.key)=\($0.value)"
            }.joined(separator: ";")
            
            let headers = HTTPHeaders([
                "User-Agent": douyinUA,
                "referer": "https://live.douyin.com",
                "Cookie": cookieString
            ])
            
            AF.request(url, headers: headers).response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                guard let text = response.text,
                      let json = self.getJSON(text) else {
                    resolver.reject(VideoGetError.notFountData)
                    return
                }
                
                do {
                    let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(json)
                    let info = try DouYinInfo(object: jsonObj)
                    resolver.fulfill(info)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    func getJSON(_ text: String) -> Data? {
        try? SwiftSoup
            .parse(text)
            .getElementById("RENDER_DATA")?
            .data()
            .removingPercentEncoding?
            .data(using: .utf8)
    }
    
    func prepareArgs() -> Promise<()> {
        cookies.removeAll()
        storageDic.removeAll()
        deleteDouYinCookies()
        
        return Promise { resolver in
            dyFinishNitification = NotificationCenter.default.addObserver(forName: .finishLoadDY, object: nil, queue: .main) { _ in
                if let n = self.dyFinishNitification {
                    NotificationCenter.default.removeObserver(n)
                }
                resolver.fulfill(())
            }
            NotificationCenter.default.post(name: .startLoadDY, object: nil)
        }
    }
    
    func deleteCookies() -> Promise<()> {
        getAllWKCookies().then {
            when(fulfilled: $0.map(self.deleteWKCookie))
        }.get {
            self.deleteDouYinCookies()
        }
    }
    
    func deleteDouYinCookies() {
        HTTPCookieStorage.shared.cookies?.filter {
            $0.domain.contains("douyin")
        }.forEach(HTTPCookieStorage.shared.deleteCookie)
    }
    
    
    func getAllWKCookies() -> Promise<[HTTPCookie]> {
        return Promise { resolver in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies {
                let cookies = $0.filter({ $0.domain.contains("douyin") })
                resolver.fulfill(cookies)
            }
        }
    }
    
    func deleteWKCookie(_ cookie: HTTPCookie) -> Promise<()> {
        return Promise { resolver in
            WKWebsiteDataStore.default().httpCookieStore.delete(cookie) {
                resolver.fulfill_()
            }
        }
    }

    deinit {
        prepareTask = nil
    }
    
    func checkDouYinCookies(_ webview: WKWebView, _ cookies: [HTTPCookie]) -> Promise<()> {
        let cookieKeys = [
            "bGl2ZV9jYW5fYWRkX2R5XzJfZGVza3RvcA==",
            "eGdwbGF5ZXJfdXNlcl9pZA==",
            "dHR3aWQ=",
            "X19hY19ub25jZQ==",
            "X19hY19zaWduYXR1cmU=",
            "TU9OSVRPUl9XRUJfSUQ=",
        ].map {
            $0.base64Decode()
        }
        
        let cid = "dHRjaWQ=".base64Decode()
        
        return Promise { resolver in
            guard self.cookies.count == 0 else {
                resolver.reject(CookiesError.invalid)
                return
            }
            
            let dyCookies = cookies.filter {
                $0.domain.contains("douyin")
            }
            
            let names = dyCookies.map({ $0.name }).sorted()
            
            if cookieKeys.allSatisfy(names.contains) {
                Log("DouYin Cookies prepared.")
                
                dyCookies.filter {
                    cookieKeys.contains($0.name)
                }.forEach {
                    self.cookies[$0.name] = $0.value
                }
                
                resolver.fulfill_()
            } else {
                resolver.reject(CookiesError.waintingForCookies)
            }
        }.then {
            when(fulfilled: [
                webview.evaluateJavaScript("localStorage.\(cid)"),
                webview.evaluateJavaScript("window.navigator.userAgent")
            ])
        }.done {
            guard let id = $0[0] as? String, let ua = $0[1] as? String else {
                throw CookiesError.invalid
            }
            self.cookies[cid] = id
            self.douyinUA = ua
        }
    }
    
    enum CookiesError: Error {
        case invalid, waintingForCookies
    }
}
