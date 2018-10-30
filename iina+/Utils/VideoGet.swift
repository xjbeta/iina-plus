//
//  VideoGet.swift
//  iina+
//
//  Created by xjbeta on 2018/10/28.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import SwiftHTTP
import PromiseKit
import Marshal
import CommonCrypto

class VideoGet: NSObject {
    let supportList = ["live.bilibili.com",
                       "www.douyu.com",
                       "www.panda.tv",
                       "www.huya.com",
                       "egame.qq.com",
                       "www.bilibili.com"]
    
    
    func decodeUrl(_ url: String,
                   _ block: @escaping (_ youget: YouGetJSON) -> Void,
                   _ error: @escaping (_ error: Error) -> Void) {
        
        var yougetJson = YouGetJSON(url:"")
        guard let url = URL(string: url) else { return }
        yougetJson.streams.removeAll()
        switch url.host {
        case "live.bilibili.com":
            getBiliLiveRoomId(url).get {
                yougetJson.title = $0.1
                }.then {
                    self.getBiliLiveJSON("\($0.0)")
                }.done {
                    $0.2.enumerated().forEach {
                        yougetJson.streams["线路 \($0.offset + 1)"] = Stream(url: $0.element)
                    }
                    block(yougetJson)
                }.catch {
                    error($0)
            }
        case "www.douyu.com":
            getDouyuRoomIds(url).then {
                when(resolved: $0.map { self.getDouyuUrl($0) })
                }.done {
                    try $0.forEach {
                        switch $0 {
                        case .fulfilled(let strings):
                            yougetJson.streams[strings.0] = Stream(url: strings.1)
                        case .rejected(let error):
                            throw error
                        }
                    }
                    block(yougetJson)
                }.catch {
                    error($0)
            }
        case "www.panda.tv":
            getPandaRoomID(url).then {
                when(resolved: $0.map { self.getPandaInfo($0) })
                }.done {
                    try $0.forEach {
                        switch $0 {
                        case .fulfilled(let strings):
                            yougetJson.streams[strings.0] = Stream(url: strings.1)
                        case .rejected(let error):
                            throw error
                        }
                    }
                    block(yougetJson)
                }.catch {
                    error($0)
            }
        case "www.huya.com":
            getHuyaInfo(url).done {
                yougetJson.title = $0.0
                $0.1.enumerated().forEach {
                    yougetJson.streams["线路 \($0.offset + 1)"] = Stream(url: $0.element)
                }
                block(yougetJson)
                }.catch {
                    error($0)
            }
            
        case "egame.qq.com":
            getEgameInfo(url).done {
                yougetJson.title = $0.0
                $0.1.forEach {
                    yougetJson.streams[$0.desc] = Stream(url: $0.playUrl)
                }
                block(yougetJson)
                }.catch {
                    error($0)
            }
        case "www.bilibili.com":
            getBilibili(url).done {
                yougetJson.title = $0.0
                yougetJson.streams[$0.1] = Stream(url: $0.2)
                block(yougetJson)
                }.catch {
                    error($0)
            }
        default:
            error(VideoGetError.notSupported)
        }
    }
    
    
    
}

// MARK: - Bilibili

struct BilibiliVideo: Unmarshaling {
    var videos: [String: String]
    var audios: [String]
    
    
    struct DashObject: Unmarshaling {
        var id: Int
        var url: String
        var backupUrl: [String]
        init(object: MarshaledObject) throws {
            id = try object.value(for: "id")
            url = try object.value(for: "baseUrl")
            backupUrl = try object.value(for: "backupUrl")
        }
    }
    
    init(object: MarshaledObject) throws {
        
        let acceptDescription: [String] = try object.value(for: "accept_description")
        let acceptQuality: [Int] = try object.value(for: "accept_quality")
        
        let video: [DashObject] = try object.value(for: "dash.video")
        let audio: [DashObject] = try object.value(for: "dash.audio")
        
        var videos: [String: String] = [:]
        
        video.forEach {
            guard let index = acceptQuality.firstIndex(of: $0.id),
                index > 0,
                index < acceptDescription.count else {
                    return
            }
            let des = acceptDescription[index]
            videos[des] = $0.url
        }
        self.videos = videos
        audios = audio.map {
            $0.url
        }
    }
}


extension VideoGet {
    
    // MARK: - Bilibili
    func getBiliLiveRoomId(_ url: URL) -> Promise<(Int, String)> {
        let roomID = url.lastPathComponent
        return Promise { resolver in
            HTTP.GET("https://api.live.bilibili.com/room/v1/Room/get_info?room_id=\(roomID)") { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data)
                    let longID: Int = try json.value(for: "data.room_id")
                    let title: String = try json.value(for: "data.title")
                    resolver.fulfill((longID, title))
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    
    func getBiliLiveJSON(_ roomID: String, _ quality: Int = 4) -> Promise<(Int, [String], [String])> {
//        4 原画
//        3 高清
        return Promise { resolver in
            HTTP.GET("https://api.live.bilibili.com/room/v1/Room/playUrl?cid=\(roomID)&quality=\(quality)") { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                struct Durl: Unmarshaling {
                    var url: String
                    init(object: MarshaledObject) throws {
                        url = try object.value(for: "url")
                    }
                }
                
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data)
                    let currentQuality: Int = try json.value(for: "data.current_quality")
                    let acceptQuality: [String] = try json.value(for: "data.accept_quality")
                    let dUrls: [Durl] = try json.value(for: "data.durl")
                    let urls = dUrls.map({ $0.url })
                    resolver.fulfill((currentQuality, acceptQuality, urls))
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    // MARK: - Douyu
    func getDouyuRoomIds(_ url: URL) -> Promise<([Int])> {
        return Promise { resolver in
            let paths = url.pathComponents
            if paths.count > 2, paths[1] == "t" {
                HTTP.GET(url.absoluteString) { response in
                    if let error = response.error {
                        resolver.reject(error)
                    }

                    var onlineIdStr = response.text?.subString(from: "\"online_id\":[", to: "],") ?? ""
                    onlineIdStr = onlineIdStr.replacingOccurrences(of: "\"", with: "")
                    let roomIds = onlineIdStr.components(separatedBy: ",").compactMap {
                        Int($0)
                    }
                    resolver.fulfill(roomIds)
                }
            } else if let id = Int(url.lastPathComponent) {
                resolver.fulfill([id])
            } else {
                resolver.reject(VideoGetError.douyuUrlError)
            }
        }
    }
    
    func getDouyuUrl(_ roomID: Int) -> Promise<(String, String)> {
        
        return Promise { resolver in
            // https://github.com/soimort/you-get/blob/master/src/you_get/extractors/douyutv.py
            let args = "room/\(roomID)?aid=wp&client_sys=wp&time=\(Int(Date().timeIntervalSince1970))"
            let auth_md5 = args + "zNzMV1y4EMxOHS6I5WKm"
            let auth_str = MD5(auth_md5) ?? ""
            
            HTTP.GET("http://www.douyutv.com/api/v1/" + args + "&auth=" + auth_str) { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data)
                    let title: String = try json.value(for: "data.room_name")
                    let rtmpUrl: String = try json.value(for: "data.rtmp_url")
                    let rtmpLive: String = try json.value(for: "data.rtmp_live")
                    
                    resolver.fulfill((title, rtmpUrl + "/" + rtmpLive))
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    // MARK: - Panda
    func getPandaRoomID(_ url: URL) -> Promise<([Int])>  {
//        https://www.panda.tv/s8
        return Promise { resolver in
            if let id = Int(url.lastPathComponent) {
                resolver.fulfill([id])
            } else {
                HTTP.GET(url.absoluteString) { response in
                    if let error = response.error {
                        resolver.reject(error)
                    }
                    var text = response.text ?? ""
                    var ids: [Int] = []
                    
                    let startStr = "data-room-id=\""
                    while Int(text.subString(from: startStr, to: "\">")) != nil {
                        ids.append(Int(text.subString(from: "data-room-id=\"", to: "\">"))!)
                        if let endIndex = text.range(of: startStr)?.upperBound {
                            text.removeSubrange(text.startIndex ..< endIndex)
                        } else {
                            text = ""
                        }
                    }
                    resolver.fulfill(ids)
                }
            }
        }
    }
    
    
    
    
    func getPandaInfo(_ roomID: Int) -> Promise<(String, String)>  {
        return Promise { resolver in
            HTTP.GET("https://www.panda.tv/api_room_v2?roomid=\(roomID)") { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data)
                    
                    let status: String = try json.value(for: "data.videoinfo.status")
                    guard status == "2" else {
                        resolver.reject(VideoGetError.isNotLiving)
                        return
                    }
                    
                    
                    let plflagStr: String = try json.value(for: "data.videoinfo.plflag")
                    let plflag = plflagStr.components(separatedBy: "_").last ?? ""
                    let roomKey: String = try json.value(for: "data.videoinfo.room_key")
                    let plflagList: String = try json.value(for: "data.videoinfo.plflag_list")
                    
                    let plflagListJson: JSONObject = try JSONParser.JSONObjectWithData(plflagList.data(using: .utf8) ?? Data())
                    let sign: String = try plflagListJson.value(for: "auth.sign")
                    let ts: String = try plflagListJson.value(for: "auth.time")
                    let rid: String = try plflagListJson.value(for: "auth.rid")
                    
                    let title: String = try json.value(for: "data.roominfo.name")

                    let url = "https://pl\(plflag).live.panda.tv/live_panda/\(roomKey).flv?sign=\(sign)&ts=\(ts)&rid=\(rid)"
                    resolver.fulfill((title, url))
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    // MARK: - Huya
    
    struct HuyaUrl: Unmarshaling {
        var urls: [String]
        struct StreamInfo: Unmarshaling {
            var sFlvUrl: String
            var sStreamName: String
            var sFlvUrlSuffix: String
            var sFlvAntiCode: String
            
            init(object: MarshaledObject) throws {
                sFlvUrl = try object.value(for: "sFlvUrl")
                sStreamName = try object.value(for: "sStreamName")
                sFlvUrlSuffix = try object.value(for: "sFlvUrlSuffix")
                sFlvAntiCode = try object.value(for: "sFlvAntiCode")
            }
        }
        init(object: MarshaledObject) throws {
            let streamInfos: [StreamInfo] = try object.value(for: "gameStreamInfoList")
            urls = streamInfos.map {
                $0.sFlvUrl + "/" + $0.sStreamName + "." + $0.sFlvUrlSuffix + "?" + $0.sFlvAntiCode
            }
        }
    }
    
    func getHuyaInfo(_ url: URL) -> Promise<(String, [String])> {
//        https://github.com/zhangn1985/ykdl/blob/master/ykdl/extractors/huya/live.py
        return Promise { resolver in
            HTTP.GET(url.absoluteString) { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                let roomInfoData = response.text?.subString(from: "var TT_ROOM_DATA = ", to: ";var").data(using: .utf8) ?? Data()
                let playerInfoData = response.text?.subString(from: "var hyPlayerConfig = ", to: ";\n").data(using: .utf8) ?? Data()
                
                do {
                    let roomInfoJson: JSONObject = try JSONParser.JSONObjectWithData(roomInfoData)
                    let playerInfoJson: JSONObject = try JSONParser.JSONObjectWithData(playerInfoData)
                    let status: String = try roomInfoJson.value(for: "state")
                        
                    if status != "ON" {
                        resolver.reject(VideoGetError.isNotLiving)
                    }
                    let title: String = try roomInfoJson.value(for: "introduction")
                    let huyaUrl: [HuyaUrl] = try playerInfoJson.value(for: "stream.data")
                    guard let urls = huyaUrl.first?.urls else {
                        resolver.reject(VideoGetError.notFindUrls)
                        return
                    }
                    resolver.fulfill((title, urls))
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    // MARK: - egame.qq
    
    struct EgameUrl: Unmarshaling {
        var playUrl: String
        var desc: String
        
        init(object: MarshaledObject) throws {
            playUrl = try object.value(for: "playUrl")
            desc = try object.value(for: "desc")
        }
    }
    
    func getEgameInfo(_ url: URL) -> Promise<(String, [EgameUrl])> {
        return Promise { resolver in
            HTTP.GET(url.absoluteString) { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                
                let jsonData = response.text?.subString(from: "window.__NUXT__=", to: ";</script>").data(using: .utf8) ?? Data()
                
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(jsonData)
                    
                    let isLive: Int = try json.value(for: "state.live-info.liveInfo.profileInfo.isLive")
                    guard isLive == 1 else {
                        resolver.reject(VideoGetError.isNotLiving)
                        return
                    }
                    let title: String = try json.value(for: "state.live-info.liveInfo.videoInfo.title")
                    let urls: [EgameUrl] = try json.value(for: "state.live-info.liveInfo.videoInfo.streamInfos")
                    
                    resolver.fulfill((title, urls))
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    // MARK: - Bilibili
    func getBilibili(_ url: URL) -> Promise<((String, String, String))> {
        
        
        let headers = ["Referer": "https://www.bilibili.com/",
                       "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:38.0) Gecko/20100101 Firefox/38.0 Iceweasel/38.2.1"]
        
        
        // https://github.com/xioxin/biliATV/issues/24
        var cookieProperties = [HTTPCookiePropertyKey: String]()
        cookieProperties[HTTPCookiePropertyKey.name] = "CURRENT_QUALITY" as String
        cookieProperties[HTTPCookiePropertyKey.value] = "112" as String
        cookieProperties[HTTPCookiePropertyKey.domain] = ".bilibili.com" as String
        cookieProperties[HTTPCookiePropertyKey.path] = "/" as String
        let cookie = HTTPCookie(properties: cookieProperties)
        HTTPCookieStorage.shared.setCookie(cookie!)
        
        
        return Promise { resolver in
            HTTP.GET(url.absoluteString, headers: headers) { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                let playInfoData = response.text?.subString(from: "window.__playinfo__=", to: "</script>").data(using: .utf8) ?? Data()
                let initialStateData = response.text?.subString(from: "window.__INITIAL_STATE__=", to: ";(function()").data(using: .utf8) ?? Data()
                    
                do {
                    let playInfoJson: JSONObject = try JSONParser.JSONObjectWithData(playInfoData)
                    let initialStateJson: JSONObject = try JSONParser.JSONObjectWithData(initialStateData)
                    
                    var title: String = try initialStateJson.value(for: "videoData.title")
                    struct Page: Unmarshaling {
                        var page: Int
                        var part: String
                        init(object: MarshaledObject) throws {
                            page = try object.value(for: "page")
                            part = try object.value(for: "part")
                        }
                    }
                    let pages: [Page] = try initialStateJson.value(for: "videoData.pages")
                    
                    let quality: Int = try playInfoJson.value(for: "data.quality")
                    
                    let acceptQuality: [Int] = try playInfoJson.value(for: "data.accept_quality")
                    let acceptDescription: [String] = try playInfoJson.value(for: "data.accept_description")
                    var qualityDescription = "url"
                    if acceptQuality.count == acceptDescription.count,
                        let index = acceptQuality.firstIndex(of: quality),
                        index >= 0,
                        index < acceptDescription.count {
                        qualityDescription = acceptDescription[index]
                    }
                    
                    if let p = url.query?.replacingOccurrences(of: "p=", with: ""),
                        let pInt = Int(p),
                        pInt - 1 > 0, pInt - 1 < pages.count {
                        title += " - P\(pInt) - \(pages[pInt - 1].part)"
                    }
                    
                    struct Durl: Unmarshaling {
                        var url: String
                        init(object: MarshaledObject) throws {
                            url = try object.value(for: "url")
                        }
                    }
                    
                    let durls: [Durl] = try playInfoJson.value(for: "data.durl")
                    
                    guard let url = durls.first?.url else {
                        resolver.reject(VideoGetError.notFindUrls)
                        return
                    }
                    
                    resolver.fulfill(((title, qualityDescription, url)))
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    
    

    
    
    // https://stackoverflow.com/a/53044349
    func MD5(_ string: String) -> String? {
        let length = Int(CC_MD5_DIGEST_LENGTH)
        var digest = [UInt8](repeating: 0, count: length)
        
        if let d = string.data(using: String.Encoding.utf8) {
            _ = d.withUnsafeBytes { (body: UnsafePointer<UInt8>) in
                CC_MD5(body, CC_LONG(d.count), &digest)
            }
        }
        
        return (0..<length).reduce("") {
            $0 + String(format: "%02x", digest[$1])
        }
    }
}

enum VideoGetError: Error {
    case douyuUrlError
    
    case isNotLiving
    case notFindUrls
    case notSupported
}
