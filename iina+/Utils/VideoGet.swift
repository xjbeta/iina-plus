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

enum LiveSupportList: String {
    case biliLive = "live.bilibili.com"
    case bilibili = "www.bilibili.com"
    case panda = "www.panda.tv"
    case douyu = "www.douyu.com"
    case huya = "www.huya.com"
    case pandaXingYan = "xingyan.panda.tv"
    case quanmin = "www.quanmin.tv"
    case longzhu = "star.longzhu.com"
    case eGame = "egame.qq.com"
    //    case yizhibo = "www.yizhibo.com"
    case unsupported
    
    init(raw: String?) {
        if let list = LiveSupportList(rawValue: raw ?? "") {
            self = list
        } else {
            self = .unsupported
        }
    }
}


class VideoGet: NSObject {
    
    func decodeUrl(_ url: String) -> Promise<YouGetJSON> {
        return Promise { resolver in
            var yougetJson = YouGetJSON(url:"")
            yougetJson.streams.removeAll()
            guard let url = URL(string: url) else {
                resolver.reject(VideoGetError.notSupported)
                return
            }
            let site = LiveSupportList(raw:url.host)
            
            switch site {
            case .biliLive:
                getBiliLiveRoomId(url).get {
                    yougetJson.title = $0.title
                    }.then {
                        self.getBiliLiveJSON("\($0.roomId)")
                    }.done {
                        $0.2.enumerated().forEach {
                            yougetJson.streams["线路 \($0.offset + 1)"] = Stream(url: $0.element)
                        }
                        resolver.fulfill(yougetJson)
                    }.catch {
                        resolver.reject($0)
                }
            case .douyu:
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
                        resolver.fulfill(yougetJson)
                    }.catch {
                        resolver.reject($0)
                }
            case .panda:
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
                        resolver.fulfill(yougetJson)
                    }.catch {
                        resolver.reject($0)
                }
            case .huya:
                getHuyaInfo(url).done {
                    yougetJson.title = $0.0.title
                    $0.1.enumerated().forEach {
                        yougetJson.streams["线路 \($0.offset + 1)"] = Stream(url: $0.element)
                    }
                    resolver.fulfill(yougetJson)
                    }.catch {
                        resolver.reject($0)
                }
            case .eGame:
                getEgameInfo(url).done {
                    yougetJson.title = $0.0.title
                    $0.1.forEach {
                        var stream = Stream(url: $0.playUrl)
                        stream.videoProfile = $0.desc
                        
                        switch $0.desc {
                        case "蓝光":
                            yougetJson.streams["1"] = stream
                        case "超清":
                            yougetJson.streams["2"] = stream
                        case "高清":
                            yougetJson.streams["3"] = stream
                        case "流畅":
                            yougetJson.streams["4"] = stream
                        default:
                            yougetJson.streams["5"] = stream
                        }
                    }
                    resolver.fulfill(yougetJson)
                    }.catch {
                        resolver.reject($0)
                }
            case .bilibili:
                getBilibili(url).done {
                        yougetJson.title = $0.0
                        yougetJson.streams[$0.1] = Stream(url: $0.2)
                        resolver.fulfill(yougetJson)
                    }.catch {
                        resolver.reject($0)
                }
            default:
                resolver.reject(VideoGetError.notSupported)
            }
        }
    }
    
    func prepareBiliDanmaku(_ url: URL) -> Promise<()> {
        return Promise { resolver in
            guard Preferences.shared.enableDanmaku, url.host == "www.bilibili.com" else {
                resolver.fulfill(())
                return
            }
            guard let aid = Int(url.lastPathComponent.replacingOccurrences(of: "av", with: "")) else {
                resolver.reject(VideoGetError.cantFindIdForDM)
                return
            }
            var cid = 0
            Bilibili().getVideoList(aid).get { vInfo in
                if vInfo.count == 1 {
                    cid = vInfo[0].cid
                } else if let p = url.query?.replacingOccurrences(of: "p=", with: ""),
                    var pInt = Int(p) {
                    pInt -= 1
                    if pInt < vInfo.count,
                        pInt >= 0 {
                        cid = vInfo[pInt].cid
                    }
                }
                }.then { _ in
                    self.downloadDMFile(cid)
                }.done {
                    resolver.fulfill(())
                }.catch {
                    resolver.reject($0)
            }
        }
    }
    
    func liveInfo(_ url: String, _ checkSupport: Bool = true) -> Promise<LiveInfo> {
        return Promise { resolver in
            guard let url = URL(string: url) else {
                resolver.reject(VideoGetError.notSupported)
                return
            }
            let site = LiveSupportList(raw:url.host)
            let roomId = Int(url.lastPathComponent) ?? -1
            switch site {
            case .biliLive:
                var info = BilibiliInfo()
                getBiliLiveRoomId(url).get {
                    info = $0
                    }.then {
                        self.getBiliUserInfo($0.roomId)
                    }.done {
                        info.name = $0.name
                        info.userCover = $0.userCover
                        resolver.fulfill(info)
                    }.catch {
                        resolver.reject($0)
                }
            case .panda:
                getPandaUserInfo(roomId).done {
                    resolver.fulfill($0)
                    }.catch {
                        resolver.reject($0)
                }
            case .douyu:
                getDouyuUserInfo(roomId).done {
                    resolver.fulfill($0)
                    }.catch {
                        resolver.reject($0)
                }
            case .huya:
                getHuyaInfo(url).done {
                    resolver.fulfill($0.0)
                    }.catch {
                        resolver.reject($0)
                }
            case .pandaXingYan:
                getPandaXingYanInfo(roomId).done {
                    resolver.fulfill($0)
                    }.catch {
                        resolver.reject($0)
                }
            case .quanmin:
                getQuanMinInfo(roomId).done {
                    resolver.fulfill($0)
                    }.catch {
                        resolver.reject($0)
                }
            case .longzhu:
                getLongZhuInfo(url).done {
                    resolver.fulfill($0)
                    }.catch {
                        resolver.reject($0)
                }
            case .eGame:
                getEgameInfo(url).done {
                    resolver.fulfill($0.0)
                    }.catch {
                        resolver.reject($0)
                }
            default:
                if checkSupport {
                    resolver.reject(VideoGetError.notSupported)
                } else {
                    var info = BilibiliInfo()
                    info.isLiving = true
                    resolver.fulfill(info)
                }
            }
        }
    }
}



extension VideoGet {
    
    // MARK: - BiliLive
    func getBiliLiveRoomId(_ url: URL) -> Promise<(BilibiliInfo)> {
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
                    let status: Int = try json.value(for: "data.live_status")
                    
                    var info = BilibiliInfo()
                    info.title = title
                    info.isLiving = status == 1
                    info.roomId = longID
                    resolver.fulfill(info)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    func getBiliUserInfo(_ roomId: Int) -> Promise<(BilibiliInfo)> {
        return Promise { resolver in
            HTTP.GET("https://api.live.bilibili.com/live_user/v1/UserInfo/get_anchor_in_room?roomid=\(roomId)") { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data)
                    var info = BilibiliInfo()
                    info.name = try json.value(for: "data.info.uname")
                    let userCoverURL: String = try json.value(for: "data.info.face")
                    if let url = URL(string: userCoverURL) {
                        info.userCover = NSImage(contentsOf: url)
                    }
                    resolver.fulfill(info)
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
    func getDouyuUserInfo(_ roomID: Int) -> Promise<DouyuInfo> {
        return Promise { resolver in
            HTTP.GET("http://open.douyucdn.cn/api/RoomApi/room/\(roomID)") { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data)
                    let info: DouyuInfo = try json.value(for: "data")
                    resolver.fulfill(info)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    
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
    func getPandaUserInfo(_ roomId: Int) -> Promise<PandaInfo> {
        return Promise { resolver in
            HTTP.GET("https://room.api.m.panda.tv/index.php?method=room.shareapi&roomid=\(roomId)") { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data)
                    let info: PandaInfo = try json.value(for: "data")
                    resolver.fulfill(info)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
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
    
    func getHuyaInfo(_ url: URL) -> Promise<(HuyaInfo, [String])> {
//        https://github.com/zhangn1985/ykdl/blob/master/ykdl/extractors/huya/live.py
        return Promise { resolver in
            HTTP.GET(url.absoluteString) { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                let roomInfoData = response.text?.subString(from: "var TT_ROOM_DATA = ", to: ";var").data(using: .utf8) ?? Data()
                let profileInfoData = response.text?.subString(from: "var TT_PROFILE_INFO = ", to: ";var").data(using: .utf8) ?? Data()
                let playerInfoData = response.text?.subString(from: "var hyPlayerConfig = ", to: ";\r\n").data(using: .utf8) ?? Data()
                
                do {
                    var roomInfoJson: JSONObject = try JSONParser.JSONObjectWithData(roomInfoData)
                    let profileInfoData: JSONObject = try JSONParser.JSONObjectWithData(profileInfoData)
                    let playerInfoJson: JSONObject = try JSONParser.JSONObjectWithData(playerInfoData)
                    
                    roomInfoJson.merge(profileInfoData) { (current, _) in current }
                    let info: HuyaInfo = try HuyaInfo(object: roomInfoJson)
                    
                    if !info.isLiving {
                        resolver.fulfill((info, []))
                        return
                    }
                    
                    let huyaUrl: [HuyaUrl] = try playerInfoJson.value(for: "stream.data")
                    guard let urls = huyaUrl.first?.urls else {
                        resolver.reject(VideoGetError.notFindUrls)
                        return
                    }
                    resolver.fulfill((info, urls))
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    // MARK: - Panda XingYan
    func getPandaXingYanInfo(_ roomId: Int) -> Promise<PandaXingYanInfo> {
        return Promise { resolver in
            HTTP.GET("https://m.api.xingyan.panda.tv/room/baseinfo?xid=\(roomId)") { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data)
                    let info: PandaXingYanInfo = try json.value(for: "data")
                    resolver.fulfill(info)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    
    // MARK: - eGame
    
    struct EgameUrl: Unmarshaling {
        var playUrl: String
        var desc: String
        
        init(object: MarshaledObject) throws {
            playUrl = try object.value(for: "playUrl")
            desc = try object.value(for: "desc")
        }
    }
    
    func getEgameInfo(_ url: URL) -> Promise<(EgameInfo, [EgameUrl])> {
        return Promise { resolver in
            HTTP.GET(url.absoluteString) { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                
                let jsonData = response.text?.subString(from: "window.__NUXT__=", to: ";</script>").data(using: .utf8) ?? Data()
                
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(jsonData)
                    let info: EgameInfo = try EgameInfo(object: json)
                    let urls: [EgameUrl] = try json.value(for: "state.live-info.liveInfo.videoInfo.streamInfos")
                    
                    resolver.fulfill((info, urls))
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
    
    func downloadDMFile(_ cid: Int) -> Promise<()> {
        return Promise { resolver in
            HTTP.GET("https://comment.bilibili.com/\(cid).xml") { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                if let resourcePath = Bundle.main.resourcePath {
                    let danmakuFilePath = resourcePath + "/danmaku/iina-plus-danmaku.xml"
                    FileManager.default.createFile(atPath: danmakuFilePath, contents: response.data, attributes: nil)
                    Logger.log("Saved DM in \(danmakuFilePath)")
                }
                resolver.fulfill(())
            }
        }
    }
    
    
    // MARK: - QuanMin
    func getQuanMinInfo(_ roomID: Int) -> Promise<QuanMinInfo> {
        return Promise { resolver in
            HTTP.GET("https://www.quanmin.tv/json/rooms/\(roomID)/noinfo6.json") { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data)
                    let info = try QuanMinInfo(object: json)
                    resolver.fulfill(info)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    
    //MARK: - LongZhu
    
    func getLongZhuInfo(_ url: URL) -> Promise<LongZhuInfo> {
        return Promise { resolver in
            HTTP.GET(url.absoluteString) { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let pageData = response.text?.subString(from: "var pageData = ", to: ";\n").data(using: .utf8) ?? Data()
                    let profileData = response.text?.subString(from: "var roomHost = ", to: ";\n").data(using: .utf8) ?? Data()
                    var pageInfo: JSONObject = try JSONParser.JSONObjectWithData(pageData)
                    let profileInfo: JSONObject = try JSONParser.JSONObjectWithData(profileData)
                    pageInfo.merge(profileInfo) { (current, _) in current }
                    let info = try LongZhuInfo(object: pageInfo)
                    resolver.fulfill(info)
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
    
    case cantFindIdForDM
}
