//
//  Bilibili.swift
//  iina+
//
//  Created by xjbeta on 2018/8/6.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import SwiftHTTP
import Marshal
import PromiseKit

@objc(BilibiliCard)
class BilibiliCard: NSObject, Unmarshaling {
    var aid: Int = 0
    var dynamicId: Int = 0
    @objc var title: String = ""
    @objc var pic: NSImage?
    @objc var name: String = ""
    @objc var duration: TimeInterval = 0
    @objc var views: Int = 0
//    var pubdate = 1533581945
    
    
    override init() {
        super.init()
    }
    
    required init(object: MarshaledObject) throws {
        dynamicId = try object.value(for: "desc.dynamic_id")
        let jsonStr: String = try object.value(for: "card")
        if let data = jsonStr.data(using: .utf8) {
            let json: JSONObject = try JSONParser.JSONObjectWithData(data)
            aid = try json.value(for: "aid")
    
            title = try json.value(for: "title")
            let picUrl: String = try json.value(for: "pic")
            if let url = URL(string: picUrl) {
                pic = NSImage(contentsOf: url)
            }
    
            duration = try json.value(for: "duration")
            name = try json.value(for: "owner.name")
            views = try json.value(for: "stat.view")
        }
    }
}

enum BilibiliDynamicAction {
    case `init`, new, history
}

class Bilibili: NSObject {

    func isLogin(_ isLoginBlock: ((Bool) -> Void)?,
                 _ nameBlock: ((String) -> Void)?,
                 _ error: @escaping ((HTTPErrorCallback) -> Void)) {
        HTTP.GET("https://api.bilibili.com/x/web-interface/nav") { response in
            error {
                if let error = response.error { throw error }
                let json: JSONObject = try JSONParser.JSONObjectWithData(response.data)
                let isLogin: Bool = try json.value(for: "data.isLogin")
                isLoginBlock?(isLogin)
                if isLogin {
                    let name: String = try json.value(for: "data.uname")
                    nameBlock?(name)
                }
                return false
            }
        }
    }
    
    func logout(_ block: (() -> Void)?,
                _ error: @escaping ((HTTPErrorCallback) -> Void)) {
        HTTP.GET("https://account.bilibili.com/login?act=exit") { response in
            error {
                if let error = response.error { throw error }
                block?()
                return false
            }
        }
    }
    
    func getUid(_ block: ((Int) -> Void)?,
                _ error: @escaping ((HTTPErrorCallback) -> Void)) {
        HTTP.GET("https://api.bilibili.com/x/web-interface/nav") { response in
            error {
                if let error = response.error { throw error }
                let json: JSONObject = try JSONParser.JSONObjectWithData(response.data)
                let uid: Int = try json.value(for: "data.mid")
                block?(uid)
                return false
            }
        }
    }
    
    func dynamicList(_ action: BilibiliDynamicAction = .init,
                     _ dynamicID: Int = -1,
                     _ block: (([BilibiliCard]) -> Void)?,
                     _ error: @escaping ((HTTPErrorCallback) -> Void)) {
        getUid({ uid in
            var http: HTTP? = nil
            let headers = ["referer": "https://www.bilibili.com"]
            
            switch action {
            case .init:
                http = HTTP.GET("https://api.vc.bilibili.com/dynamic_svr/v1/dynamic_svr/dynamic_new?uid=\(uid)&type=8", headers: headers)
            case .history:
                http = HTTP.GET("https://api.vc.bilibili.com/dynamic_svr/v1/dynamic_svr/dynamic_history?uid=\(uid)&offset_dynamic_id=\(dynamicID)&type=8", headers: headers)
            case .new:
                http = HTTP.GET("https://api.vc.bilibili.com/dynamic_svr/v1/dynamic_svr/dynamic_new?uid=\(uid)&current_dynamic_id=\(dynamicID)&type=8", headers: headers)
            default: break
            }
            
            http?.onFinish = { response in
                error {
                    if let error = response.error { throw error }
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data)
                    let cards: [BilibiliCard] = try json.value(for: "data.cards")
                    block?(cards)
                    return false
                }
            }
            http?.run()
        }) { re in
            error {
                let _ = try re()
                return false
            }
        }
    }
    
}



