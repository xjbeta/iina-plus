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


extension MainViewController {
    func getInfo(_ str: String, _ block: @escaping (_ liveInfo: LiveInfo) -> Void) {
        if let url = URL.init(string: str) {
            let roomID = url.lastPathComponent
            switch url.host {
            case "live.bilibili.com":
                let header = [
                    "User-Agent": "花Q pilipili"
                ]
                
                HTTP.GET("https://api.live.bilibili.com/room/v1/Room/get_info?room_id=\(roomID)", headers: header) {
                    let json: JSONObject = try! JSONParser.JSONObjectWithData($0.data)
                    var roomInfo: JSONObject = try! json.value(for: "data")
                    let roomIDLong: Int = try! roomInfo.value(for: "room_id")
                    HTTP.GET("https://api.live.bilibili.com/live_user/v1/UserInfo/get_anchor_in_room?roomid=\(roomIDLong)", headers: header) {
                        let json: JSONObject = try! JSONParser.JSONObjectWithData($0.data)
                        let userInfo: JSONObject = try! json.value(for: "data")
                        
                        roomInfo.merge(userInfo, uniquingKeysWith: { _,_ in
                            return ""
                        })
                        do {
                            let info: BilibiliInfo = try BilibiliInfo(object: roomInfo)
                            block(info)
                        } catch let er {
                            
                        }
                    }
                }
            case "panda.tv", "www.panda.tv":
                HTTP.GET("https://room.api.m.panda.tv/index.php?method=room.shareapi&roomid=\(roomID)") {
                    do {
                        let json: JSONObject = try JSONParser.JSONObjectWithData($0.data)
                        let info: PandaInfo = try json.value(for: "data")
                        block(info)
                    } catch let er {
                        print(er)
                    }
                }
            case "www.douyu.com":
                HTTP.GET("http://open.douyucdn.cn/api/RoomApi/room/\(roomID)") {
                    do {
                        let json: JSONObject = try JSONParser.JSONObjectWithData($0.data)
                        let info: DouyuInfo = try json.value(for: "data")
                        block(info)
                    } catch let er {
                        print(er)
                    }
                }
            default:
                break
            }
        }
    }
}
