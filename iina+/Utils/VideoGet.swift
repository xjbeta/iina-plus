//
//  VideoGet.swift
//  iina+
//
//  Created by xjbeta on 2018/10/28.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import Alamofire
import PromiseKit
import Marshal
import CommonCrypto
import JavaScriptCore
import WebKit

enum LiveSupportList: String {
    case biliLive = "live.bilibili.com"
    case bilibili = "www.bilibili.com/video"
    case bangumi = "www.bilibili.com/bangumi"
    case douyu = "www.douyu.com"
    case huya = "www.huya.com"
    case quanmin = "www.quanmin.tv"
    case longzhu = "star.longzhu.com"
    case eGame = "egame.qq.com"
    //    case yizhibo = "www.yizhibo.com"
    case langPlay = "play.lang.live"
    case unsupported
    
    init(url: String) {
        guard let u = URL(string: url) else {
            self = .unsupported
            return
        }
        
        let host = u.host ?? ""
        if host == "www.bilibili.com", u.pathComponents.count >= 2 {
            switch u.pathComponents[1] {
            case "video":
                self = .bilibili
            case "bangumi":
                self = .bangumi
            default:
                self = .unsupported
            }
        } else if let list = LiveSupportList(rawValue: host) {
            self = list
        } else {
            self = .unsupported
        }
    }
}


class VideoGet: NSObject {
    
    let douyuWebview = WKWebView()
    var douyuWebviewObserver: NSKeyValueObservation?
    
    func decodeUrl(_ url: String) -> Promise<YouGetJSON> {
        
        var yougetJson = YouGetJSON(url:"")
        yougetJson.streams.removeAll()
        guard let url = URL(string: url) else {
            return .init(error: VideoGetError.notSupported)
        }
        let site = LiveSupportList(url: url.absoluteString)
        
        switch site {
        case .biliLive:
            return getBiliLiveRoomId(url).get {
                yougetJson.title = $0.title
            }.then {
                self.getBiliLiveJSON("\($0.roomId)")
            }.map {
                $0.2.enumerated().forEach {
                    yougetJson.streams["线路 \($0.offset + 1)"] = Stream(url: $0.element)
                }
                return yougetJson
            }
        case .douyu:
            var roomId = 0
            var roomTitle = ""
            return getDouyuHtml(url.absoluteString).get {
                guard let rid = Int($0.roomId) else {
                    throw VideoGetError.douyuNotFoundRoomId
                }
                roomId = rid
            }.then { _ in
                self.douyuBetard(roomId)
            }.get {
                roomTitle = $0.title
            }.then { _ in
                self.getDouyuUrl(roomId)
            }.map {
                yougetJson.streams[roomTitle] = Stream(url: $0)
                return yougetJson
            }
        case .huya:
            return getHuyaInfo(url).map {
                yougetJson.title = $0.0.title
                $0.1.enumerated().forEach {
                    yougetJson.streams["线路 \($0.offset + 1)"] = Stream(url: $0.element)
                }
                return yougetJson
            }
        case .eGame:
            return getEgameInfo(url).map {
                yougetJson.title = $0.0.title
                $0.1.sorted {
                    $0.levelType > $1.levelType
                }.enumerated().forEach {
                    var stream = Stream(url: $0.element.playUrl)
                    stream.videoProfile = $0.element.desc
                    yougetJson.streams["\($0.offset + 1)"] = stream
                }
                return yougetJson
            }
        case .bilibili:
            return getBilibili(url)
            
        case .bangumi:
            return getBangumi(url)
        case .langPlay:
            let roomId = Int(url.lastPathComponent) ?? -1
            return getLangPlayInfo(roomId).map {
                yougetJson.title = $0.title
                $0.streamItems.forEach {
                    yougetJson.streams[$0.title] = Stream(url: $0.url)
                }
                return yougetJson
            }
        default:
            return .init(error: VideoGetError.notSupported)
        }
    }
    
    func prepareDanmakuFile(_ url: URL, yougetJSON: YouGetJSON, id: String) -> Promise<()> {
        return Promise { resolver in
            guard Preferences.shared.enableDanmaku else {
                resolver.fulfill(())
                return
            }
            
            if url.host == "www.bilibili.com" {
                self.downloadDMFileV2(
                    cid: yougetJSON.bilibiliCid,
                    length: yougetJSON.duration,
                    id: id).done {
                    resolver.fulfill(())
                }.catch {
                    resolver.reject($0)
                }
            } else {
                resolver.fulfill(())
            }
        }
    }
    
    func liveInfo(_ url: String, _ checkSupport: Bool = true) -> Promise<LiveInfo> {
        
        guard let url = URL(string: url) else {
            return .init(error: VideoGetError.notSupported)
        }
        let site = LiveSupportList(url: url.absoluteString)
        let roomId = Int(url.lastPathComponent) ?? -1
        switch site {
        case .biliLive:
            var info = BiliLiveInfo()
            return getBiliLiveRoomId(url).get {
                info = $0
            }.then {
                self.getBiliUserInfo($0.roomId)
            }.map {
                info.name = $0.name
                info.avatar = $0.avatar
                return info
            }
        case .douyu:
            return getDouyuHtml(url.absoluteString).map {
                Int($0.roomId) ?? -1
            }.then {
                self.douyuBetard($0)
            }.map {
                $0 as LiveInfo
            }
        case .huya:
            return getHuyaInfo(url).map {
                $0.0
            }
        case .quanmin:
            return getQuanMinInfo(roomId).map {
                $0 as LiveInfo
            }
        case .longzhu:
            return getLongZhuInfo(url).map {
                $0 as LiveInfo
            }
        case .eGame:
            return getEgameInfo(url).map {
                $0.0
            }
        case .langPlay:
            return getLangPlayInfo(roomId).map {
                $0 as LiveInfo
            }
        case .bilibili:
            return getBilibiliHTMLDatas(url).map {
                let initialStateJson: JSONObject = try JSONParser.JSONObjectWithData($0.initialStateData)
                
                var info = BilibiliInfo()
                info.title = try initialStateJson.value(for: "videoData.title")
                info.cover = try initialStateJson.value(for: "videoData.pic")
                info.cover = info.cover.replacingOccurrences(of: "http://", with: "https://")
                info.name = try initialStateJson.value(for: "videoData.owner.name")
                info.isLiving = true
                return info
            }
            
        case .bangumi:
            return getBilibiliHTMLDatas(url).map {
                try BangumiInfo(object: try JSONParser.JSONObjectWithData($0.initialStateData))
            }.map {
                var info = BilibiliInfo()
                
                info.title = $0.mediaInfo.title
                info.cover = $0.mediaInfo.squareCover
                info.isLiving = true
                return info
            }
        default:
            if checkSupport {
                return .init(error: VideoGetError.notSupported)
            } else {
                var info = BiliLiveInfo()
                info.isLiving = true
                
                return .value(info)
            }
        }
    }
    
    deinit {
        douyuWebview.stopLoading()
        douyuWebviewObserver?.invalidate()
    }
}



extension VideoGet {
    
    // MARK: - BiliLive
    func getBiliLiveRoomId(_ url: URL) -> Promise<(BiliLiveInfo)> {
        let roomID = url.lastPathComponent
        return Promise { resolver in
            AF.request("https://api.live.bilibili.com/room/v1/Room/get_info?room_id=\(roomID)").response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data ?? Data())
                    let longID: Int = try json.value(for: "data.room_id")

                    var info = BiliLiveInfo()
                    info.title = try json.value(for: "data.title")
                    info.isLiving = try json.value(for: "data.live_status") == 1
                    info.roomId = longID
                    info.cover = try json.value(for: "data.user_cover")
                    resolver.fulfill(info)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    func getBiliUserInfo(_ roomId: Int) -> Promise<(BiliLiveInfo)> {
        return Promise { resolver in
            AF.request("https://api.live.bilibili.com/live_user/v1/UserInfo/get_anchor_in_room?roomid=\(roomId)").response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data ?? Data())
                    var info = BiliLiveInfo()
                    info.name = try json.value(for: "data.info.uname")
                    info.avatar = try json.value(for: "data.info.face")
                    resolver.fulfill(info)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    func getBiliLiveRoomInfo(_ mid: Int) -> Promise<(BiliLiveInfo)> {
        return Promise { resolver in
            AF.request("http://api.live.bilibili.com/room/v1/Room/getRoomInfoOld?mid=\(mid)").response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data ?? Data())
//                    var info = BilibiliInfo()
//                    info.name = try json.value(for: "data.info.uname")
//                    info.userCover = try json.value(for: "data.info.face")
//                    resolver.fulfill(info)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    func getBiliLiveJSON(_ roomID: String, _ quality: Int = 10000) -> Promise<(Int, [String], [String])> {
//        4 原画
//        3 高清
        return Promise { resolver in
//           https://api.live.bilibili.com/room/v1/Room/playUrl?cid=7734200&qn=10000&platform=web
            AF.request("https://api.live.bilibili.com/room/v1/Room/playUrl?cid=\(roomID)&qn=\(quality)&platform=web").response { response in
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
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data ?? Data())
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
    func getDouyuHtml(_ url: String) -> Promise<(roomId: String, roomIds: [String], isLiving: Bool, pageId: String)> {
        return Promise { resolver in
            AF.request(url).response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                
                let showStatus = response.text?.subString(from: "$ROOM.show_status =", to: ";") == "1"

                if var roomId = response.text?.subString(from: "$ROOM.room_id =", to: ";"), roomId != "" {
                    roomId = roomId.replacingOccurrences(of: " ", with: "")
                    
                    var roomIds = [String]()
                    var pageId = ""
                    
                    if let roomIdsStr = response.text?.subString(from: "window.room_ids=[", to: "],"), roomIdsStr != "" {
                        
                        roomIds = roomIdsStr.replacingOccurrences(of: "\"", with: "").split(separator: ",").map(String.init)
                        
                        pageId = response.text?.subString(from: "\"pageId\":", to: ",") ?? ""
                    }

                    resolver.fulfill((roomId, roomIds, showStatus, pageId))
                } else {
                    resolver.reject(VideoGetError.douyuNotFoundRoomId)
                }
            }
        }
    }
    
    func douyuBetard(_ rid: Int) -> Promise<DouyuInfo> {
        return Promise { resolver in
            AF.request("https://www.douyu.com/betard/\(rid)").response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data ?? Data())
                    
                    let info: DouyuInfo = try DouyuInfo(object: json)
                    resolver.fulfill(info)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    
//    https://butterfly.douyucdn.cn/api/page/loadPage?name=pageData2&pageId=1149&view=0
    func getDouyuEventRoomNames(_ pageId: String) -> Promise<()> {
        return Promise { resolver in
            AF.request("https://butterfly.douyucdn.cn/api/page/loadPage?name=pageData2&pageId=\(pageId)&view=0").response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                resolver.fulfill(())
            }
        }
    }
    
    private func getDouyuDid() -> Promise<(String)> {
//        10000000000000000000000000001501
        
        
        let douyuCookie = "https://passport.douyu.com/lapi/did/api/get"
        let time = UInt32(NSDate().timeIntervalSinceReferenceDate)
        srand48(Int(time))
        let random = "\(drand48())"
        let parameters = ["client_id": "1",
                          "callback": ("jsonp_" + random).replacingOccurrences(of: ".", with: "")]
        let headers = HTTPHeaders(["Referer": "http://www.douyu.com"])
        
        return Promise { resolver in
            AF.request(douyuCookie, parameters: parameters, headers: headers).response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    var str = response.text
                    str = str?.subString(from: "(", to: ")")
                    let json = try JSONParser.JSONObjectWithData(str?.data(using: .utf8) ?? Data())
                    let didStr: String = try json.value(for: "data.did")
                    resolver.fulfill(didStr)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }

    
    private func getDouyuSign(_ roomID: Int, didStr: String, time: String) -> Promise<(sign: String, v: String)> {
        return Promise { resolver in
            douyuWebview.stopLoading()
            douyuWebviewObserver?.invalidate()
            douyuWebviewObserver = nil
            douyuWebviewObserver = douyuWebview.observe(\.isLoading) { (webView, _) in
                if !webView.isLoading {
                    when(fulfilled: [self.douyuEvaluateJavaScript("window.ub98484234(\(roomID), '\(didStr)', \(time));"), self.douyuEvaluateJavaScript("window.vdwdae325w_64we;")]).done {
                        self.douyuWebviewObserver?.invalidate()
                        self.douyuWebview.load(.init(url: URL(string: "about:blank")!))
                        resolver.fulfill((sign: $0[0], v: $0[1]))
                        }.catch {
                           resolver.reject($0)
                    }
                }
            }
            
            douyuWebview.load(.init(url: URL(string: "https://www.douyu.com/\(roomID)")!))
        }
    }
    
    private func douyuEvaluateJavaScript(_ javaScriptString: String) -> Promise<(String)> {
        return Promise { resolver in
            douyuWebview.evaluateJavaScript(javaScriptString) { (re, error) in
                guard let str = re as? String, error == nil else {
                    resolver.reject(error!)
                    return
                }
                resolver.fulfill(str)
            }
        }
    }
    
    private func getDouyuRtmpUrl(_ roomID: Int, didStr: String) -> Promise<(String)> {
//        window[Object(ae.a)(256042, "9f4f419501570ad13334")]
        return Promise { resolver in
            let time = "\(Int(Date().timeIntervalSince1970))"
            getDouyuSign(roomID, didStr: didStr, time: time).done {
                let signStr = $0.sign.subString(from: "sign=")
                guard signStr.count > 0 else {
                    resolver.reject(VideoGetError.douyuSignError)
                    return
                }
                let pars = ["v": $0.v,
                            "did": didStr,
                            "tt": time,
                            "sign": signStr,
                            "cdn": "ali-h5",
                            "rate": "0",
                            "ver": "Douyu_219111405",
                            "iar": "0",
                            "ive": "0"]
                AF.request("https://www.douyu.com/lapi/live/getH5Play/\(roomID)", method: .post, parameters: pars).response { response in
                    if let error = response.error {
                        resolver.reject(error)
                    }
                    do {
                        let json: JSONObject = try JSONParser.JSONObjectWithData(response.data ?? Data())
                        let rtmpUrl: String = try json.value(for: "data.rtmp_url")
                        let rtmpLive: String = try json.value(for: "data.rtmp_live")
                        resolver.fulfill(rtmpUrl + "/" + rtmpLive)
                    } catch let error {
                        resolver.reject(error)
                    }
                }
                }.catch {
                    resolver.reject($0)
            }
        }
    }
    
    
    func getDouyuUrl(_ roomID: Int) -> Promise<(String)> {
        return getDouyuDid().then { res -> Promise<(String)> in
                return self.getDouyuRtmpUrl(roomID, didStr: res)
        }
    }
    
    // MARK: - Huya
    
    func getHuyaInfo(_ url: URL) -> Promise<(HuyaInfo, [String])> {
//        https://github.com/zhangn1985/ykdl/blob/master/ykdl/extractors/huya/live.py
        return Promise { resolver in
            AF.request(url.absoluteString).response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                 
                let hyPlayerConfigStr: String? = {
                    guard let text = response.text else { return nil }
                    var str = text.subString(from: "var hyPlayerConfig = ", to: "window.TT_LIVE_TIMING")
                    guard let index = str.lastIndex(of: ";") else { return nil }
                    str.removeSubrange(index ..< str.endIndex)
                    return str
                }()
                
                guard let roomInfoData = response.text?.subString(from: "var TT_ROOM_DATA = ", to: ";var").data(using: .utf8),
                      let profileInfoData = response.text?.subString(from: "var TT_PROFILE_INFO = ", to: ";var").data(using: .utf8),
                      let playerInfoData = hyPlayerConfigStr?.data(using: .utf8) else {
                    resolver.reject(VideoGetError.notFindUrls)
                    return
                }
                
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
                    

                    
                    let streamStr: String = try playerInfoJson.value(for: "stream")
                    
                    guard let streamData = Data(base64Encoded: streamStr) else {
                        resolver.reject(VideoGetError.notFindUrls)
                        return
                    }
                    
                    let streamJSON: JSONObject = try JSONParser.JSONObjectWithData(streamData)
                    
                    let huyaStream: HuyaStream = try HuyaStream(object: streamJSON)
                
                    var urls = [String]()
                    
                    if info.isSeeTogetherRoom {
                        urls = huyaStream.data.first?.urlsBak ?? []
                    } else {
                        urls = huyaStream.data.first?.urls ?? []
                    }
                    
                    if urls.count > 0 {
                        resolver.fulfill((info, urls))
                    } else {
                        resolver.reject(VideoGetError.notFindUrls)
                    }
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    // MARK: - eGame
    
    func getEgameInfo(_ url: URL) -> Promise<(EgameInfo, [EgameUrl])> {
        return Promise { resolver in
            AF.request(url.absoluteString).response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                
                guard var jsString = response.text?.subString(from: "window.__NUXT__=", to: "</script>") else {
                    resolver.reject(VideoGetError.egameFunctionNotFound)
                    return
                }
                jsString = "jsonObj=" + jsString
                
                let jsContext = JSContext()
                jsContext?.evaluateScript(jsString)
                let result = jsContext?.evaluateScript("JSON.stringify(jsonObj)")
                
                let jsonData = result?.toString()?.data(using: .utf8) ?? Data()
                
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
    func getBilibili(_ url: URL) -> Promise<(YouGetJSON)> {
        setBilibiliQuality()
        return getBilibiliHTMLDatas(url).then {
            self.decodeBilibiliDatas(
                url,
                playInfoData: $0.playInfoData,
                initialStateData: $0.initialStateData)
        }
    }
    
    func getBilibiliHTMLDatas(_ url: URL) -> Promise<((playInfoData: Data, initialStateData: Data))> {
        let headers = HTTPHeaders(
            ["Referer": "https://www.bilibili.com/",
             "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:38.0) Gecko/20100101 Firefox/38.0 Iceweasel/38.2.1"])
        return Promise { resolver in
            AF.request(url.absoluteString, headers: headers).response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                let playInfoData = response.text?.subString(from: "window.__playinfo__=", to: "</script>").data(using: .utf8) ?? Data()
                let initialStateData = response.text?.subString(from: "window.__INITIAL_STATE__=", to: ";(function()").data(using: .utf8) ?? Data()
                resolver.fulfill((playInfoData: playInfoData,
                                  initialStateData: initialStateData))
            }
        }
    }
    
    func decodeBilibiliDatas(_ url: URL,
                             playInfoData: Data,
                             initialStateData: Data) -> Promise<(YouGetJSON)> {
        var yougetJson = YouGetJSON(url:"")
        yougetJson.streams.removeAll()
        
        return Promise { resolver in
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
                
                
                
                if let p = url.query?.replacingOccurrences(of: "p=", with: ""),
                     let pInt = Int(p),
                     pInt - 1 > 0, pInt - 1 < pages.count {
                     title += " - P\(pInt) - \(pages[pInt - 1].part)"
                 }
                yougetJson.title = title
                yougetJson.bilibiliCid = try initialStateJson.value(for: "videoData.cid")
                yougetJson.duration = try initialStateJson.value(for: "videoData.duration")

                if let playInfo: BilibiliPlayInfo = try? playInfoJson.value(for: "data") {
                    playInfo.videos.sorted(by: { $0.id > $1.id }).enumerated().forEach {
                        var stream = Stream(url: $0.element.url)
                        stream.videoProfile = $0.element.description
                        yougetJson.streams["\($0.offset + 1)"] = stream
                    }
                    
                    guard let audios = playInfo.audios else {
                        resolver.fulfill(yougetJson)
                        return
                    }
                    
                    guard let audio = audios.max(by: { $0.bandwidth > $1.bandwidth }),
                          playInfo.videos.count > 0 else {
                            resolver.reject(VideoGetError.notFindUrls)
                            return
                    }
                    
                    yougetJson.audio = audio.url
                    resolver.fulfill(yougetJson)
                } else if let info: BilibiliSimplePlayInfo = try? playInfoJson.value(for: "data"), let url = info.url {
                    
                    var stream = Stream(url: url)
                    stream.videoProfile = info.description
                    yougetJson.streams[info.description] = stream
                    resolver.fulfill(yougetJson)
                } else {
                    resolver.reject(VideoGetError.notFindUrls)
                }
            } catch let error {
                resolver.reject(error)
            }
        }
    }
    
    func setBilibiliQuality() {
        // https://github.com/xioxin/biliATV/issues/24
        var cookieProperties = [HTTPCookiePropertyKey: String]()
        cookieProperties[HTTPCookiePropertyKey.name] = "CURRENT_QUALITY" as String
        cookieProperties[HTTPCookiePropertyKey.value] = "112" as String
        cookieProperties[HTTPCookiePropertyKey.domain] = ".bilibili.com" as String
        cookieProperties[HTTPCookiePropertyKey.path] = "/" as String
        let cookie = HTTPCookie(properties: cookieProperties)
        HTTPCookieStorage.shared.setCookie(cookie!)
        
    }

    // MARK: - Bangumi
    
    func getBangumi(_ url: URL) -> Promise<(YouGetJSON)> {
        setBilibiliQuality()

        return getBilibiliHTMLDatas(url).then {
            self.getBangumiVipData(
                url,
                bangumiInfo: try BangumiInfo(object: try JSONParser.JSONObjectWithData($0.initialStateData)),
                playInfoData: $0.playInfoData)
        }.then {
            self.decodeBangumiDatas(
                url,
                bangumiInfo: $0.bangumiInfo,
                playInfoData: $0.playInfoData)
        }
    }
    
    
    func getBangumiVipData(_ url: URL,
                           bangumiInfo: BangumiInfo,
                           playInfoData: Data) -> Promise<((bangumiInfo: BangumiInfo, playInfoData: Data))> {
        return Promise { resolver in
            guard url.absoluteString.contains("bangumi") else {
                resolver.fulfill((bangumiInfo, playInfoData))
                return
            }
            
            getBangumiVideoData(info: bangumiInfo).done {
                guard let data = $0 else {
                    resolver.reject(VideoGetError.notFountData)
                    return
                }
                
                
                struct Message: Decodable {
                    let code: Int
                    let message: String
                }
                
                let message = try JSONDecoder().decode(Message.self, from: data)
                
                guard message.code == 0,
                      message.message == "success" else {
                    Log((message.code, message.message))
                    resolver.reject(VideoGetError.needVip)
                    return
                }
                
                resolver.fulfill((bangumiInfo, data))
            }.catch {
                resolver.reject($0)
            }
        }
    }
    
    func decodeBangumiDatas(_ url: URL,
                            bangumiInfo: BangumiInfo,
                            playInfoData: Data) -> Promise<(YouGetJSON)> {
        
        
        var yougetJson = YouGetJSON(url:"")
        yougetJson.streams.removeAll()
        
        yougetJson.bilibiliCid = bangumiInfo.epInfo.cid
        
        return Promise { resolver in
            do {
                yougetJson.title = bangumiInfo.title
                
                let playInfoJson: JSONObject = try JSONParser.JSONObjectWithData(playInfoData)
                
                if let playInfo: BilibiliPlayInfo = (try? playInfoJson.value(for: "result")) ?? (try? playInfoJson.value(for: "data")) {
                    
                    yougetJson.duration = playInfo.duration
                    
                    playInfo.videos.sorted(by: { $0.id > $1.id }).enumerated().forEach {
                        var stream = Stream(url: $0.element.url)
                        stream.videoProfile = $0.element.description
                        yougetJson.streams["\($0.offset + 1)"] = stream
                    }
                    
                    guard let audios = playInfo.audios else {
                        resolver.fulfill(yougetJson)
                        return
                    }
                    
                    guard let audio = audios.max(by: { $0.bandwidth > $1.bandwidth }),
                          playInfo.videos.count > 0 else {
                            resolver.reject(VideoGetError.notFindUrls)
                            return
                    }
                    
                    yougetJson.audio = audio.url
                    resolver.fulfill(yougetJson)
                } else if let info: BilibiliSimplePlayInfo = try? playInfoJson.value(for: "result"),
                          let url = info.url,
                          let duration = info.duration {
                    yougetJson.duration = duration
                    
                    var stream = Stream(url: url)
                    stream.videoProfile = info.description
                    yougetJson.streams[info.description] = stream
                    resolver.fulfill(yougetJson)
                } else {
                    resolver.reject(VideoGetError.notFindUrls)
                }
            } catch let error {
                resolver.reject(error)
            }
        }
    }
    
    
    
    func getBangumiVideoData(info: BangumiInfo) -> Promise<(Data?)> {
        return Promise { resolver in
            
            let header = HTTPHeaders(
                ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0.2 Safari/605.1.15",
                 "origin": "https://www.bilibili.com",
                 "referer": "https://www.bilibili.com/bangumi/play/ep\(info.epInfo.id)"])
            
            let pars: [String: Any] = [
                "bvid": info.epInfo.bvid,
                "cid": info.epInfo.cid,
                "ep_id": info.epInfo.id,
                "fnval": 80,
                "fnver": 0,
                "fourk": 1,
                "otype": "json",
                "qn": 80,
                //                "session": info.epInfo,
                "type": ""]
            
            AF.request("https://api.bilibili.com/pgc/player/web/playurl",
                       method: .get,
                       parameters: pars,
                       headers: header).response { response in
                        
                        if let error = response.error {
                            resolver.reject(error)
                        }
                        resolver.fulfill(response.data)
                       }
//            https://api.bilibili.com/pgc/player/web/playurl?cid=237945449&qn=80&type=&otype=json&fourk=1&bvid=BV1GA411J7Zh&ep_id=339061&fnver=0&fnval=80&session=e7b6ccb354f010af13a689cb0f057a72
            

        }
    }
    
    // MARK: - Bilibili Danmaku
    func downloadDMFile(_ cid: Int, id: String) -> Promise<()> {
        return Promise { resolver in
            AF.request("https://comment.bilibili.com/\(cid).xml").response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                self.saveDMFile(response.data, with: id)
                resolver.fulfill(())
            }
        }
    }
    
    
    func downloadDMFileV2(cid: Int, length: Int, id: String) -> Promise<()> {
        
//        segment_index  6min
        
        let c = Int(ceil(Double(length) / 360))
        let s = c > 1 ? Array(1...c) : [1]
        
        return when(fulfilled: s.map {
            getDanmakuContent(cid: cid, index: $0)
        }).done {
            let dms = Array($0.joined()).map { dm -> String in
                let s1 = ["\(Double(dm.progress) / 1000)",
                          "\(dm.mode)",
                          "\(dm.fontsize)",
                          "\(dm.color)",
                          "\(dm.ctime)",
                          "\(dm.pool)",
                          "\(dm.midHash)",
                          "\(dm.id)"].joined(separator: ",")
                var s2 = dm.content
                        
                s2 = s2.replacingOccurrences(of: "<", with: "&lt;")
                s2 = s2.replacingOccurrences(of: ">", with: "&gt;")
                s2 = s2.replacingOccurrences(of: "&", with: "&amp;")
                s2 = s2.replacingOccurrences(of: "'", with: "&apos;")
                s2 = s2.replacingOccurrences(of: "\"", with: "&quot;")
                
                return "<d p=\"\(s1)\">\(s2)</d>"
            }

            var dmContent = #"<?xml version="1.0" encoding="UTF-8"?><i><chatserver>chat.bilibili.tv</chatserver><chatid>170102</chatid>"#
            
            dmContent += dms.joined(separator: "\\n")
            dmContent += "\\n</i>"
            
            self.saveDMFile(dmContent.data(using: .utf8), with: id)
        }
    }
    
    func saveDMFile(_ data: Data?, with id: String) {
        
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
            var filesURL = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return
        }
        let folderName = "danmaku"
        
        filesURL.appendPathComponent(bundleIdentifier)
        filesURL.appendPathComponent(folderName)
        let fileName = "danmaku" + "-" + id + ".xml"
        
        filesURL.appendPathComponent(fileName)
        let path = filesURL.path
        
        FileManager.default.createFile(atPath: path, contents: data, attributes: nil)
        Log("Saved DM in \(path)")
    }
    
    func getDanmakuContent(cid: Int, index: Int) -> Promise<([DanmakuElem])> {
        return Promise { resolver in
            let u = "https://api.bilibili.com/x/v2/dm/web/seg.so?type=1&oid=\(cid)&segment_index=\(index)"
            
            AF.request(u).response { response in
                if let error = response.error {
                    resolver.reject(error)
                    return
                }

                guard let d = response.data else {
                    resolver.fulfill([])
                    return
                }
                
                do {
                    let re = try DmSegMobileReply(serializedData: d)
                    resolver.fulfill(re.elems)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    // MARK: - QuanMin
    func getQuanMinInfo(_ roomID: Int) -> Promise<QuanMinInfo> {
        return Promise { resolver in
            AF.request("https://www.quanmin.tv/json/rooms/\(roomID)/noinfo6.json").response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data ?? Data())
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
            AF.request(url.absoluteString).response { response in
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
    
// MARK: - LangPlay
    func getLangPlayInfo(_ roomID: Int) -> Promise<(LangPlayInfo)> {
        let url = "https://game-api.lang.live/webapi/v1/room/info?room_id=\(roomID)"
        return Promise { resolver in
            AF.request(url).response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data ?? Data())
                    let info = try LangPlayInfo(object: json)
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
        
        if let d = string.data(using: .utf8) {
            _ = d.withUnsafeBytes { body -> String in
                CC_MD5(body.baseAddress, CC_LONG(d.count), &digest)
                return ""
            }
        }
        
        return (0 ..< length).reduce("") {
            $0 + String(format: "%02x", digest[$1])
        }
    }
}

enum VideoGetError: Error {
    case invalidLink
    
    case douyuUrlError
    case douyuSignError
    case douyuNotFoundRoomId
    case douyuRoomIdsCountError
    
    case isNotLiving
    case notFindUrls
    case notSupported
    case egameFunctionNotFound
    
    case cantFindIdForDM
    
    case prepareDMFailed
    
    case cantWatch
    case notFountData
    case needVip
}
