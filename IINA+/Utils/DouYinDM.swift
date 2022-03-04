//
//  DouYinDM.swift
//  IINA+
//
//  Created by xjbeta on 2/21/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa
import WebKit
import Alamofire
import PromiseKit

class DouYinDM: NSObject {
    var url = ""
    var delegate: DanmakuDelegate?
    
    let proc = Processes.shared
    var ua: String {
        proc.videoGet.douyin.douyinUA
    }
    
    var storageDic: [String: String] {
        proc.videoGet.douyin.storageDic
    }
    
    var cookies = [String: String]()
    
    var roomId = ""
    
    private let tokenString = "bXNUb2tlbg==".base64Decode()
    private var webview: WKWebView? = WKWebView()
    private var requestTimer: Timer?
    
    var privateKeys: [String] {
        proc.videoGet.douyin.privateKeys
    }
    
    func start(_ url: String) {
        self.url = url
        
        let path = Bundle.main.url(forResource: "douyin", withExtension: "html")!
        
        DispatchQueue.main.async {
            self.webview?.navigationDelegate = self
            self.webview?.loadFileURL(path, allowingReadAccessTo: path.deletingLastPathComponent())
        }
    }
    
    
    func getRoomId() -> Promise<()> {
        if roomId != "" {
            return .init()
        } else {
            let dy = proc.videoGet.douyin
            return dy.getInfo(.init(string: url)!).done {
                self.cookies = dy.cookies
                self.roomId = ($0 as! DouYinInfo).roomId
            }
        }
    }
    
    func prepareCookies() -> Promise<()> {
        
        let kvs = [
            privateKeys[0].base64Decode(),
            privateKeys[1].base64Decode()
        ].compactMap {
            storageDic[$0] == nil ? nil : ($0, storageDic[$0]!)
        }
        
        guard kvs.count == 2, let webview = self.webview else {
            return .init(error: DouYinDMError.deinited)
        }
        
        let acts = kvs.map {
            webview.evaluateJavaScript("window.sessionStorage.setItem('\($0.0)', '\($0.1)')").asVoid()
        }

        return when(fulfilled: acts)
    }
    
    func prepareURL(internalExt: String = "",
                   cursor: String = "0",
                   lastRtt: String = "-1") -> Promise<String> {
        guard let webview = webview else {
            return .init(error: DouYinDMError.deinited)
        }
        
        let u0 = "https:"
        let u1 = "Ly9saXZlLmRvdXlpbi5jb20vd2ViY2FzdC9pbS9mZXRjaC8/".base64Decode()
        
        let u = u0 + u1
        
        var pars = "aid=6383&live_id=1&device_platform=web&language=en-US&room_id=\(roomId)&resp_content_type=protobuf&version_code=9999&identity=audience&internal_ext=\(internalExt)&cursor=\(cursor)&last_rtt=\(lastRtt)&did_rule=3"

        pars += "&\(tokenString)=\(self.cookies[tokenString] ?? "")"
        
        let key = privateKeys[2].base64Decode()
        
        let pkey1 = privateKeys[3].base64Decode()
        let pkey2 = privateKeys[4].base64Decode()
        
        return when(fulfilled: [
            webview.evaluateJavaScript("this['\(key)'].test1('\(pars)', null)"),
            webview.evaluateJavaScript("this['\(key)'].test2({url: '\(u1 + pars)'}, undefined, 'forreal')")
        ]).compactMap {
            $0 as? [String]
        }.map {
            u + pars + "&\(pkey1)=\($0[0])" + "&\(pkey2)=\($0[1])"
        }
    }
    
    func requestDM(_ url: String) -> Promise<(Response, Int)> {
        Promise { resolver in
            let date = Date()
            let cookieString = cookies.map {
                "\($0.key)=\($0.value)"
            }.joined(separator: ";")
            
            let headers = HTTPHeaders([
                "User-Agent": ua,
                "referer": "https://live.douyin.com",
                "Cookie": cookieString
            ])
            
            AF.request(url, headers: headers).response {
                if let newToken = $0.response?.headers.filter ({
                    $0.name == "eC1tcy10b2tlbg==".base64Decode()
                }).first?.value {
                    self.cookies[self.tokenString] = newToken
                }
                
                guard let data = $0.data else {
                    resolver.reject(VideoGetError.notFountData)
                    return
                }
                
                let rtt = Int(abs(date.timeIntervalSinceNow * 1000))
                do {
                    let re = try Response(serializedData: data)
                    resolver.resolve((re, rtt), $0.error)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    func decodeDM(_ result: (Response, Int)) {
        let re = result.0
        let lastRtt = "\(result.1)"
        let internalExt = re.internalExt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let cursor = re.cursor
        
        let msgs = re.messages.filter {
            $0.method == "WebcastChatMessage"
        }.compactMap {
            try? ChatMessage(serializedData: $0.payload)
        }
        
//        Log(msgs.map({ $0.content }))
        
        msgs.forEach {
            delegate?.send(.sendDM, text: $0.content, id: "")
        }
        
        requestTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] timer in
            guard let self = self else { return }
            self.prepareURL(internalExt: internalExt, cursor: cursor, lastRtt: lastRtt).then {
                self.requestDM($0)
            }.done {
                self.decodeDM($0)
            }.catch {
                Log($0)
            }
        }
    }
    
    func stop() {
        requestTimer?.invalidate()
        requestTimer = nil
        DispatchQueue.main.async {
            self.webview?.stopLoading()
            self.webview = nil
        }
    }
    
    enum DouYinDMError: Error {
        case deinited
    }
    
    func startRequests() {
        getRoomId().then {
            self.prepareCookies()
        }.then {
            self.prepareURL()
        }.then {
            self.requestDM($0)
        }.done {
            self.decodeDM($0)
        }.catch {
            Log($0)
        }
    }
}

extension DouYinDM: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        startRequests()
    }
}
