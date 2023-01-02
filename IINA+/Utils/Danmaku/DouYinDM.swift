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
import SocketRocket
import Gzip

class DouYinDM: NSObject {
    var url = ""
    var delegate: DanmakuSubDelegate?
    
    let proc = Processes.shared
    var ua: String {
        proc.videoDecoder.douyin.douyinUA
    }
    
    var storageDic: [String: String] {
        proc.videoDecoder.douyin.storageDic
    }
    
    var cookies = [String: String]()
    
    var roomId = ""
    
    var socket: SRWebSocket?
    
    private let tokenString = "bXNUb2tlbg==".base64Decode()
    private var webview: WKWebView? = WKWebView()
    private var requestTimer: Timer?
    
    var privateKeys: [String] {
        proc.videoDecoder.douyin.privateKeys
    }
    
    func initWS() {
        
        let ws = "d3NzOi8vd2ViY2FzdDMtd3Mtd2ViLWhsLmRvdXlpbi5jb20vd2ViY2FzdC9pbS9wdXNoL3YyLz9hcHBfbmFtZT1kb3V5aW5fd2ViJnZlcnNpb25fY29kZT0xODA4MDAmd2ViY2FzdF9zZGtfdmVyc2lvbj0xLjMuMCZ1cGRhdGVfdmVyc2lvbl9jb2RlPTEuMy4wJmNvbXByZXNzPWd6aXAmaG9zdD1odHRwczovL2xpdmUuZG91eWluLmNvbSZhaWQ9NjM4MyZsaXZlX2lkPTEmZGlkX3J1bGU9MyZkZWJ1Zz10cnVlJmVuZHBvaW50PWxpdmVfcGMmc3VwcG9ydF93cmRzPTEmaW1fcGF0aD0vd2ViY2FzdC9pbS9mZXRjaC8mZGV2aWNlX3BsYXRmb3JtPXdlYiZjb29raWVfZW5hYmxlZD10cnVlJmJyb3dzZXJfbGFuZ3VhZ2U9ZW4tVVMmYnJvd3Nlcl9wbGF0Zm9ybT1NYWNJbnRlbCZicm93c2VyX29ubGluZT10cnVlJnR6X25hbWU9QXNpYS9TaGFuZ2hhaSZpZGVudGl0eT1hdWRpZW5jZSZoZWFydGJlYXREdXJhdGlvbj0xMDAwMCZyb29tX2lkPQ==".base64Decode() + "\(roomId)"
        
        guard let u = URL(string: ws) else { return }
        var req = URLRequest(url: u)
        let cookieString = cookies.map {
            "\($0.key)=\($0.value)"
        }.joined(separator: ";")
        
        req.setValue(cookieString, forHTTPHeaderField: "Cookie")
        req.setValue("https://live.douyin.com", forHTTPHeaderField: "referer")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        
        socket?.delegate = nil
        socket?.close()
        socket = nil
        
        socket = SRWebSocket(urlRequest: req)
        socket?.delegate = self
        socket?.open()
        
        requestTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) {_ in
            
            var pf = DouYinPushFrame()
            pf.payloadType = "hb"
            
            try? self.socket?.sendPing(pf.serializedData())
        }
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
            let dy = proc.videoDecoder.douyin
            return dy.liveInfo(url).done {
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
    
    
    func stop() {
        requestTimer?.invalidate()
        requestTimer = nil
        socket?.close()
        socket = nil
        
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
        }.done {
            self.initWS()
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

extension DouYinDM: SRWebSocketDelegate {
    func webSocketDidOpen(_ webSocket: SRWebSocket) {
        Log("webSocketDidOpen")
        
    }
    
    func webSocket(_ webSocket: SRWebSocket, didCloseWithCode code: Int, reason: String?, wasClean: Bool) {
        Log("webSocketdidClose \(reason ?? "")")
    }
    
    func webSocket(_ webSocket: SRWebSocket, didReceiveMessageWith data: Data) {
        do {
            let re = try DouYinResponse(serializedData: data)
            let ree = try DouYinDMResponse(serializedData: re.data.gunzipped())
            
            ree.messages.filter {
                $0.method == "WebcastChatMessage"
            }.compactMap {
                try? ChatMessage(serializedData: $0.payload)
            }.forEach {
                delegate?.send(.init(method: .sendDM, text: $0.content))
            }
            
            guard ree.needAck else { return }
            
            var pf = DouYinPushFrame()
            pf.payloadType = "ack"
            pf.logid = re.wssPushLogID
            
            let payload: [UInt8] = {
                var t = [UInt8]()
                func push(_ e: UInt32) {
                    t.append(UInt8(e))
                }
                
                ree.internalExt.unicodeScalars.forEach {
                    let e = $0.value
                    switch e {
                    case _ where e < 128:
                        push(e)
                    case _ where e < 2048:
                        push(192 + (e >> 6))
                        push(128 + (63 & e))
                    case _ where e < 65536:
                        push(224 + (e >> 12))
                        push(128 + (e >> 6 & 63))
                        push(128 + (63 & e))
                    default:
                        break
                    }
                }
                
                return t
            }()
            
            pf.data = Data(payload)
            
            try? webSocket.send(data: pf.serializedData())
            
        } catch let error {
            Log("\(error)")
        }
    }
    
    func webSocket(_ webSocket: SRWebSocket, didFailWithError error: Error) {
        Log(error)
    }
}
