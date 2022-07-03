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
import PMKAlamofire

class DouYin: NSObject, SupportSiteProtocol {
    
    // MARK: - DY Init
    var webView: WKWebView?
    var webViewLoadingObserver: NSKeyValueObservation?
    
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
    
    func liveInfo(_ url: String) -> Promise<LiveInfo> {
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
    
    func decodeUrl(_ url: String) -> Promise<YouGetJSON> {
        liveInfo(url).compactMap {
            ($0 as? DouYinInfo)?.write(to: YouGetJSON(rawUrl: url))
        }
    }
    
    
    func getContent(_ url: String) -> Promise<LiveInfo> {
        let cookieString = cookies.map {
            "\($0.key)=\($0.value)"
        }.joined(separator: ";")
        
        let headers = HTTPHeaders([
            "User-Agent": douyinUA,
            "referer": "https://live.douyin.com",
            "Cookie": cookieString
        ])
        
        return AF.request(url, headers: headers).responseString().map {
            guard let json = self.getJSON($0.string) else {
                throw VideoGetError.notFountData
            }
            
            let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(json)
            return try DouYinInfo(object: jsonObj)
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
            webView = WKWebView()
            
            webViewLoadingObserver?.invalidate()
            webViewLoadingObserver = webView?.observe(\.isLoading) { webView, _ in
                guard !webView.isLoading else { return }
                Log("Load Douyin webview finished.")
                
                webView.evaluateJavaScript("document.title") { str, error in
                    guard let s = str as? String else { return }
                    Log("Douyin webview title \(s).")
                    if s.contains("抖音直播") {
                        self.webViewLoadingObserver?.invalidate()
                        self.webViewLoadingObserver = nil
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                            guard self?.cookies.count == 0,
                                  let webview = self?.webView else {
                                return
                            }
                            
                            Log("DouYin Cookies timeout, Reload.")
                            webview.load(.init(url: self!.douyinEmptyURL))
                        }
                    } else if s.contains("验证") {
                        self.deleteCookies().done {
                            self.webView?.load(.init(url: self.douyinEmptyURL))
                        }.catch({ _ in })
                    }
                }
            }
            
            WKWebsiteDataStore.default().httpCookieStore.remove(self)
            WKWebsiteDataStore.default().httpCookieStore.add(self)
            
            webView?.load(.init(url: douyinEmptyURL))
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
        Promise { resolver in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies {
                let cookies = $0.filter({ $0.domain.contains("douyin") })
                resolver.fulfill(cookies)
            }
        }
    }
    
    func deleteWKCookie(_ cookie: HTTPCookie) -> Promise<()> {
        Promise { resolver in
            WKWebsiteDataStore.default().httpCookieStore.delete(cookie) {
                resolver.fulfill_()
            }
        }
    }

    deinit {
        prepareTask = nil
    }
    
    func checkDouYinCookies(_ webview: WKWebView, _ cookies: [HTTPCookie]) -> Promise<()> {
        
        let cid = "dHRjaWQ=".base64Decode()
        
        let dyCookies = cookies.filter {
            $0.domain.contains("douyin")
        }
        
        return webview.evaluateJavaScript("self.__LOADABLE_LOADED_CHUNKS__.map(x => x[0][0]).length").then { length -> Promise<()> in
            if let l = length as? Int, l > 10 {
                dyCookies.forEach {
                    self.cookies[$0.name] = $0.value
                }
                
                Log("Douyin webview chatroom___item inited.")
                return .value(())
            } else {
                throw CookiesError.waintingForCookies
            }
        }.then {
            when(fulfilled: [
                webview.evaluateJavaScript("localStorage.\(cid)"),
                webview.evaluateJavaScript("window.navigator.userAgent")
            ])
        }.done {
            guard let id = $0[0] as? String,
                  let ua = $0[1] as? String else {
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

extension DouYin: WKHTTPCookieStoreObserver {
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        guard webViewLoadingObserver == nil,
              let webView = webView,
              cookies.count == 0 else {
            return
        }
        
        cookieStore.getAllCookies().then {
            self.checkDouYinCookies(webView, $0)
        }.then {
            webView.evaluateJavaScript(
                "localStorage.\(self.privateKeys[0].base64Decode()) + ',' + localStorage.\(self.privateKeys[1].base64Decode())")
        }.compactMap { re -> [String: String]? in
            guard let values = (re as? String)?.split(separator: ",", maxSplits: 1).map(String.init) else { return nil }
            return [
                self.privateKeys[0].base64Decode(): values[0],
                self.privateKeys[1].base64Decode(): values[1]
            ]
        }.done {
            self.webView?.stopLoading()
            self.webView?.removeFromSuperview()
            self.webView = nil
            WKWebsiteDataStore.default().httpCookieStore.remove(self)
            self.storageDic = $0
            NotificationCenter.default.post(name: .finishLoadDY, object: nil)
        }.catch {
            switch $0 {
            case DouYin.CookiesError.invalid:
                break
            case DouYin.CookiesError.waintingForCookies:
                break
            default:
                Log($0)
            }
        }
    }
}

struct DouYinInfo: Unmarshaling, LiveInfo {
    var title: String
    var name: String
    var avatar: String
    var cover: String
    var isLiving: Bool
    var site = SupportSites.douyin
    
    var roomId: String
    var webRid: String
    var urls = [String: String]()
    
    
    init(object: MarshaledObject) throws {
        roomId = try object.value(for: "initialState.roomStore.roomInfo.roomId")
        webRid = try object.value(for: "initialState.roomStore.roomInfo.web_rid")
        
        title = try object.value(for: "initialState.roomStore.roomInfo.room.title")
        let status: Int = try object.value(for: "initialState.roomStore.roomInfo.room.status")
        isLiving = status == 2
        
        let flvUrls: [String: String]? = try? object.value(for: "initialState.roomStore.roomInfo.room.stream_url.flv_pull_url")
        urls = flvUrls ?? [:]
        
        /*
        let hlsUrls: [String: String] = try object.value(for: "initialState.roomStore.roomInfo.room.stream_url.hls_pull_url_map")
         */
        //        name = try object.value(for: "initialState.roomStore.roomInfo.room.stream_url.live_core_sdk_data.anchor.nickname")
        
        name = try object.value(for: "initialState.roomStore.roomInfo.anchor.nickname")
        
        let covers: [String]? = try object.value(for: "initialState.roomStore.roomInfo.room.cover.url_list")
        cover = covers?.first ?? ""
        
        let avatars: [String] = try object.value(for: "initialState.roomStore.roomInfo.anchor.avatar_thumb.url_list")
        avatar = avatars.first ?? ""
    }
    
    func write(to yougetJson: YouGetJSON) -> YouGetJSON {
        var json = yougetJson
        json.title = title
        
        
        urls.map {
            ($0.key, $0.value.replacingOccurrences(of: "http://", with: "https://"))
        }.sorted { v0, v1 in
            v0.0 < v1.0
        }.enumerated().forEach {
            var stream = Stream(url: $0.element.1)
            stream.quality = 999 - $0.offset
            json.streams[$0.element.0] = stream
        }
        
        return json
    }
}
