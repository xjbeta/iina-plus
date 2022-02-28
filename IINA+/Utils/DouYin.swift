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
    var webview: WKWebView?
    var prepareTask: Promise<()>?
    var douyinCNObserver: NSObjectProtocol?
    let douyinCookiesNotification = NSNotification.Name("DouyinCookiesNotification")
    var loadingObserver: NSKeyValueObservation?
    
    var cookies = [String: String]()
    
    var storageDic = [String: String]()
    
    
    let douyinEmptyURL = URL(string: "https://live.douyin.com/1145141919810")!
    
    var session: Session?
    
    let douyinUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)"
    
    let privateKeys = [
        "X2J5dGVkX3BhcmFtX3N3",
        "dHRfc2NpZA==",
        "Ynl0ZWRfYWNyYXdsZXI=",
        "WC1Cb2d1cw==",
        "X3NpZ25hdHVyZQ=="
    ]
    
    func getInfo(_ url: URL) -> Promise<LiveInfo> {
        if session == nil {
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
        return Promise { resolver in
            session?.request(url).response { response in
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
        guard session == nil else {
            return .value(())
        }
        deleteDouYinCookies()

        return Promise { resolver in
            webview?.stopLoading()
            webview = WKWebView()
            startDouYinCookieStoreObserver()
            
            loadingObserver = webview?.observe(\.isLoading) { webView, _ in
                guard !webView.isLoading else { return }
                Log("Load Douyin webview finished.")
                
                webView.evaluateJavaScript("document.title") { str, error in
                    guard let s = str as? String else { return }
                    Log("Douyin webview title \(s).")
                    if s.contains("抖音直播") {
                        self.loadingObserver?.invalidate()
                        self.loadingObserver = nil
                    } else if s.contains("验证") {
                        self.deleteCookies().done {
                            self.webview?.load(.init(url: self.douyinEmptyURL))
                        }.catch({ _ in })
                    }
                }
            }
            
            douyinCNObserver = NotificationCenter.default.addObserver(forName: douyinCookiesNotification, object: nil, queue: .main) { _ in
                if let n = self.douyinCNObserver {
                    NotificationCenter.default.removeObserver(n)
                }
                resolver.fulfill(())
            }
            
            webview?.load(.init(url: douyinEmptyURL))
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
    
    func startDouYinCookieStoreObserver(_ start: Bool = true) {
        let httpCookieStore = WKWebsiteDataStore.default().httpCookieStore
        if start {
            httpCookieStore.add(self)
        } else {
            httpCookieStore.remove(self)
        }
    }

    deinit {
        webview?.stopLoading()
        webview = nil
        prepareTask = nil
        session = nil
        startDouYinCookieStoreObserver(false)
    }
    
    func checkDouYinCookies(_ cookies: [HTTPCookie]) -> Promise<()> {
        guard let webview = webview else {
            return  .init(error: CookiesError.invalid)
        }
        
        let cookieKeys = [
            "X19hY19ub25jZQ==",
            "X19hY19zaWduYXR1cmU=",
            "bXNUb2tlbg==",
            "dHRfc2NpZA=="
        ].map {
            $0.base64Decode()
        }
        
        let cid = "dHRjaWQ=".base64Decode()
        
        return Promise { resolver in
            guard self.loadingObserver == nil,
                  self.session == nil,
                  self.cookies.count == 0 else {
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
                
                self.startDouYinCookieStoreObserver(false)
                resolver.fulfill_()
            } else {
                resolver.reject(CookiesError.waintingForCookies)
            }
        }.then {
            webview.evaluateJavaScript("localStorage.\(cid)")
        }.compactMap {
            $0 as? String
        }.done {
            self.cookies[cid] = $0
            
            let cValue = self.cookies.map ({
                "\($0.key)=\($0.value)"
            }).joined(separator: ";")
            
            let configuration = URLSessionConfiguration.af.default
            
            configuration.headers.add(.userAgent(self.douyinUA))
            configuration.headers.add(name: "referer", value: "https://live.douyin.com")
            configuration.headers.add(name: "Cookie", value: cValue)
            
            self.session = Session(configuration: configuration)
            self.webview?.stopLoading()
        }
    }
    
    enum CookiesError: Error {
        case invalid, waintingForCookies
    }
}

extension DouYin: WKHTTPCookieStoreObserver {
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        guard let webview = self.webview else { return }
        
        cookieStore.getAllCookies().then {
            self.checkDouYinCookies($0)
        }.then {
            webview.evaluateJavaScript("localStorage.\(self.privateKeys[0].base64Decode()) + ',' + localStorage.\(self.privateKeys[1].base64Decode())")
        }.compactMap { re -> [String: String]? in
            guard let values = (re as? String)?.split(separator: ",", maxSplits: 1).map(String.init) else { return nil }
            return [
                self.privateKeys[0].base64Decode(): values[0],
                self.privateKeys[1].base64Decode(): values[1]
            ]
        }.done {
            self.storageDic = $0
            self.webview = nil
            NotificationCenter.default.post(name: self.douyinCookiesNotification, object: nil)
        }.catch {
            switch $0 {
            case CookiesError.invalid:
                break
            case CookiesError.waintingForCookies:
                break
            default:
                print($0)
            }
        }
    }
}
