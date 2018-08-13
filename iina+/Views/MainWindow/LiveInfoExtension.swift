//
//  LiveInfoExtension.swift
//  iina+
//
//  Created by xjbeta on 2018/7/26.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import SwiftHTTP
import Marshal
//import JavaScriptCore

enum LiveSupportList: String {
    case bilibili = "live.bilibili.com"
    case panda = "www.panda.tv"
    case douyu = "www.douyu.com"
    case huya = "www.huya.com"
    case pandaXingYan = "xingyan.panda.tv"
    case quanmin = "www.quanmin.tv"
    case longzhu = "star.longzhu.com"
//    case yizhibo = "www.yizhibo.com"
    case unsupported
    
    init(raw: String?) {
        if let list = LiveSupportList.init(rawValue: raw ?? "") {
            self = list
        } else {
            self = .unsupported
        }
    }
}

protocol LiveInfo {
    var title: String { get }
    var name: String { get }
    var userCover: NSImage? { get }
    var isLiving: Bool { get }
}

struct BilibiliInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var userCover: NSImage?
    var isLiving = false
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "title")
        name = try object.value(for: "info.uname")
        
        let userCoverURL: String = try object.value(for: "info.face")
        if let url = URL(string: userCoverURL) {
            userCover = NSImage(contentsOf: url)
        }
        isLiving = "\(try object.any(for: "live_status"))" == "1"
    }
}

struct PandaInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var userCover: NSImage?
    var isLiving = false
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "roominfo.name")
        name = try object.value(for: "hostinfo.name")
        let userCoverURL: String = try object.value(for: "hostinfo.avatar")
        if let str = URL(string: userCoverURL)?.lastPathComponent,
            let url = URL(string: "https://i.h2.pdim.gs/" + str) {
            userCover = NSImage(contentsOf: url)
        }
        isLiving = "\(try object.any(for: "roominfo.status"))" == "2"
    }
}

struct DouyuInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var userCover: NSImage?
    var isLiving = false
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "room_name")
        name = try object.value(for: "owner_name")
        let userCoverURL: String = try object.value(for: "avatar")
        if let url = URL(string: userCoverURL) {
            userCover = NSImage(contentsOf: url)
        }
        isLiving = "\(try object.any(for: "room_status"))" == "1"
    }
}

struct HuyaInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var userCover: NSImage?
    var isLiving = false
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "introduction")
        name = try object.value(for: "nick")
        var userCoverURL: String = try object.value(for: "avatar")
        userCoverURL = userCoverURL.replacingOccurrences(of: "http://", with: "https://")
        if let url = URL(string: userCoverURL) {
            userCover = NSImage(contentsOf: url)
        }
        isLiving = "\(try object.any(for: "isOn"))" == "1"
    }
}

struct PandaXingYanInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var userCover: NSImage?
    var isLiving = false
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "roominfo.name")
        name = try object.value(for: "hostinfo.nickName")
        let userCoverURL: String = try object.value(for: "hostinfo.avatar")
        if let str = URL(string: userCoverURL)?.lastPathComponent,
            let url = URL(string: "https://i.h2.pdim.gs/" + str) {
            userCover = NSImage(contentsOf: url)
        }
        isLiving = "\(try object.any(for: "roominfo.playstatus"))" == "1"
    }
}

struct QuanMinInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var userCover: NSImage?
    var isLiving = false
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "title")
        name = try object.value(for: "nick")
        let userCoverURL: String = try object.value(for: "avatar")
        if let url = URL(string: userCoverURL) {
            userCover = NSImage(contentsOf: url)
        }
        isLiving = "\(try object.any(for: "status"))" == "2"
    }
}

struct LongZhuInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var userCover: NSImage?
    var isLiving = false
    
    init(object: MarshaledObject) throws {
        if let title: String = try object.value(for: "live.title") {
            self.title = title
            isLiving = true
        } else {
            self.title = try object.value(for: "defaultTitle")
            isLiving = false
        }
        name = try object.value(for: "username")
        var userCoverURL: String = try object.value(for: "avatar")
        userCoverURL = userCoverURL.replacingOccurrences(of: "http://", with: "https://")
        if let url = URL(string: userCoverURL) {
            userCover = NSImage(contentsOf: url)
        }
    }
}

struct YiZhiBo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var userCover: NSImage?
    var isLiving = false
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "nickname")
        name = try object.value(for: "nickname")
        let userCoverURL: String = try object.value(for: "avatar")
        if let url = URL(string: userCoverURL) {
            userCover = NSImage(contentsOf: url)
        }
        isLiving = "\(try object.any(for: "status"))" == "10"
    }
}

typealias HTTPErrorCallback = () throws -> Bool

extension MainViewController {
    func getInfo(_ url: URL,
                 _ completion: @escaping ((LiveInfo) -> Void),
                 _ error: @escaping ((HTTPErrorCallback) -> Void)) {
        
        let site = LiveSupportList(raw:url.host)
        let roomID = url.lastPathComponent
        switch site {
        case .bilibili:
            let header = [
                "User-Agent": "Hua Q pilipili"
            ]
            
            HTTP.GET("https://api.live.bilibili.com/room/v1/Room/get_info?room_id=\(roomID)", headers: header) { response in
                var roomInfo = JSONObject()
                var roomIDLong: Int = 0
                error {
                    if let error = response.error { throw error }
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data)
                    roomInfo = try json.value(for: "data")
                    roomIDLong = try roomInfo.value(for: "room_id")
                    HTTP.GET("https://api.live.bilibili.com/live_user/v1/UserInfo/get_anchor_in_room?roomid=\(roomIDLong)", headers: header) { response in
                        error {
                            if let error = response.error { throw error }
                            let json: JSONObject = try JSONParser.JSONObjectWithData(response.data)
                            let userInfo: JSONObject = try json.value(for: "data")
                            
                            roomInfo.merge(userInfo) { (current, _) in current }
                            let info: BilibiliInfo = try BilibiliInfo(object: roomInfo)
                            completion(info)
                            return false
                        }
                    }
                    return false
                }
            }
        case .panda:
            HTTP.GET("https://room.api.m.panda.tv/index.php?method=room.shareapi&roomid=\(roomID)") { response in
                error {
                    if let error = response.error { throw error }
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data)
                    let info: PandaInfo = try json.value(for: "data")
                    completion(info)
                    return false
                }
            }
        case .douyu:
            HTTP.GET("http://open.douyucdn.cn/api/RoomApi/room/\(roomID)") { response in
                error {
                    if let error = response.error { throw error }
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data)
                    let info: DouyuInfo = try json.value(for: "data")
                    completion(info)
                    return false
                }
            }
        case .huya:
            HTTP.GET(url.absoluteString) { response in
                error {
                    let roomData = response.text?.subString(from: "var TT_ROOM_DATA = ", to: ";var").data(using: .utf8) ?? Data()
                    let profileData = response.text?.subString(from: "var TT_PROFILE_INFO = ", to: ";var").data(using: .utf8) ?? Data()
                    var roomInfo: JSONObject = try JSONParser.JSONObjectWithData(roomData)
                    let profileInfo: JSONObject = try JSONParser.JSONObjectWithData(profileData)
                    
                    roomInfo.merge(profileInfo) { (current, _) in current }
                    
                    let info: HuyaInfo = try HuyaInfo(object: roomInfo)
                    completion(info)
                    return false
                }
            }
        case .pandaXingYan:
            HTTP.GET("https://m.api.xingyan.panda.tv/room/baseinfo?xid=\(roomID)") { response in
                error {
                    if let error = response.error { throw error }
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data)
                    let info: PandaXingYanInfo = try json.value(for: "data")
                    completion(info)
                    return false
                }
            }
        case .quanmin:
            HTTP.GET("https://www.quanmin.tv/json/rooms/\(roomID)/noinfo6.json") { response in
                error {
                    if let error = response.error { throw error }
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data)
                    let info = try QuanMinInfo(object: json)
                    completion(info)
                    return false
                }
            }
        case .longzhu:
            HTTP.GET(url.absoluteString) { response in
                error {
                    let pageData = response.text?.subString(from: "var pageData = ", to: ";\n").data(using: .utf8) ?? Data()
                    let profileData = response.text?.subString(from: "var roomHost = ", to: ";\n").data(using: .utf8) ?? Data()
                    var pageInfo: JSONObject = try JSONParser.JSONObjectWithData(pageData)
                    let profileInfo: JSONObject = try JSONParser.JSONObjectWithData(profileData)
                    pageInfo.merge(profileInfo) { (current, _) in current }
                    let info = try LongZhuInfo(object: pageInfo)
                    completion(info)
                    return false
                }
            }
//        case .yizhibo:
//            HTTP.GET(url.absoluteString) { response in
//                error {
//                    var anchorStr = response.text?.subString(from: "window.anchor = ", to: ";") ?? ""
//                    anchorStr = "var json = " + anchorStr + "; JSON.stringify(json);"
//                    let jsContext = JSContext()
//                    let anchorJSON = jsContext?.evaluateScript(anchorStr)?.toString() ?? ""
//                    let anchorData = anchorJSON.data(using: .utf8) ?? Data()
//                    let anchorInfo: JSONObject = try JSONParser.JSONObjectWithData(anchorData)
//                    let info = try YiZhiBo(object: anchorInfo)
//                    completion(info)
//                    return false
//                }
//            }
        case .unsupported:
            break
        }
    }
}

