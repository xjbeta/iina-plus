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
    case bilibili = "www.bilibili.com"
    case douyu = "www.douyu.com"
    case huya = "www.huya.com"
    case quanmin = "www.quanmin.tv"
    case longzhu = "star.longzhu.com"
    case eGame = "egame.qq.com"
    //    case yizhibo = "www.yizhibo.com"
    case kingkong = "www.kingkong.com.tw"
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
    
    let douyuWebview = WKWebView()
    var douyuWebviewObserver: NSKeyValueObservation?
    
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
                var roomId = 0
                var roomTitle = ""
                getDouyuHtml(url.absoluteString).get {
                    guard let rid = Int($0.roomId) else {
                        resolver.reject(VideoGetError.douyuNotFoundRoomId)
                        return
                    }
                    roomId = rid
                    }.then { _ in
                        self.douyuBetard(roomId)
                    }.get {
                        roomTitle = $0.title
                    }.then { _ in
                        self.getDouyuUrl(roomId)
                    }.done {
                        yougetJson.streams[roomTitle] = Stream(url: $0)
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
                    $0.1.sorted {
                        $0.levelType > $1.levelType
                        }.enumerated().forEach {
                            var stream = Stream(url: $0.element.playUrl)
                            stream.videoProfile = $0.element.desc
                            yougetJson.streams["\($0.offset + 1)"] = stream
                    }
                    resolver.fulfill(yougetJson)
                    }.catch {
                        resolver.reject($0)
                }
            case .bilibili:
                getBilibili(url).done {
                    yougetJson.title = $0.0
                    yougetJson.audio = $0.2
                    $0.1.sorted(by: { $0.0 > $1.0 }).enumerated().forEach {
                        var stream = Stream(url: $0.element.2)
                        stream.videoProfile = $0.element.1
                        yougetJson.streams["\($0.offset + 1)"] = stream
                    }
                    resolver.fulfill(yougetJson)
                    }.catch {
                        resolver.reject($0)
                }
            case .kingkong:
                let roomId = Int(url.lastPathComponent) ?? -1
                getKingKongInfo(roomId).done {
                    yougetJson.title = $0.title
                    $0.streamItems.forEach {
                        yougetJson.streams[$0.title] = Stream(url: $0.url)
                    }
                    resolver.fulfill(yougetJson)
                }.catch {
                    resolver.reject($0)
                }
            default:
                resolver.reject(VideoGetError.notSupported)
            }
        }
    }
    
    func prepareDanmakuFile(_ url: URL) -> Promise<()> {
        return Promise { resolver in
            guard Preferences.shared.enableDanmaku else {
                resolver.fulfill(())
                return
            }
            if url.host == "www.bilibili.com" {
                var cid = 0
                Bilibili().getVideoList(url.absoluteString).get { vInfo in
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
            } else {
                resolver.fulfill(())
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
            case .douyu:
                getDouyuHtml(url.absoluteString).map {
                    Int($0.roomId) ?? -1
                    }.then {
                        self.douyuBetard($0)
                    }.done {
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
            case .kingkong:
                getKingKongInfo(roomId).done {
                    resolver.fulfill($0)
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
    
    deinit {
        douyuWebview.stopLoading()
        douyuWebviewObserver?.invalidate()
    }
}



extension VideoGet {
    
    // MARK: - BiliLive
    func getBiliLiveRoomId(_ url: URL) -> Promise<(BilibiliInfo)> {
        let roomID = url.lastPathComponent
        return Promise { resolver in
            AF.request("https://api.live.bilibili.com/room/v1/Room/get_info?room_id=\(roomID)").response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data ?? Data())
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
            AF.request("https://api.live.bilibili.com/live_user/v1/UserInfo/get_anchor_in_room?roomid=\(roomId)").response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data ?? Data())
                    var info = BilibiliInfo()
                    info.name = try json.value(for: "data.info.uname")
                    info.userCover = try json.value(for: "data.info.face")
                    resolver.fulfill(info)
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
                let roomInfoData = response.text?.subString(from: "var TT_ROOM_DATA = ", to: ";var").data(using: .utf8) ?? Data()
                let profileInfoData = response.text?.subString(from: "var TT_PROFILE_INFO = ", to: ";var").data(using: .utf8) ?? Data()
                
                let hyPlayerConfigStr: String? = {
                    guard let text = response.text else { return nil }
                    var str = text.subString(from: "var hyPlayerConfig = ", to: "window.TT_LIVE_TIMING")
                    guard let index = str.lastIndex(of: ";") else { return nil }
                    str.removeSubrange(index ..< str.endIndex)
                    return str
                }()
                
                let playerInfoData = hyPlayerConfigStr?.data(using: .utf8) ?? Data()

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
    func getBilibili(_ url: URL) -> Promise<(String, [(Int, String, String)], String)> {
        
        let headers = HTTPHeaders(["Referer": "https://www.bilibili.com/",
                                   "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:38.0) Gecko/20100101 Firefox/38.0 Iceweasel/38.2.1"])
        
        return Promise { resolver in
            AF.request(url.absoluteString, headers: headers).response { response in
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
                    let acceptQuality: [Int] = try playInfoJson.value(for: "data.accept_quality")
                    let acceptDescription: [String] = try playInfoJson.value(for: "data.accept_description")
                    
                    var descriptionDic = [Int: String]()
                    acceptQuality.enumerated().forEach {
                        descriptionDic[$0.element] = acceptDescription[$0.offset]
                    }
                    
                    struct VideoInfo: Unmarshaling {
                        var url: String
                        var id: Int
                        var description: String = ""
                        init(object: MarshaledObject) throws {
                            url = try object.value(for: "baseUrl")
                            id = try object.value(for: "id")
                        }
                    }
                    
                    struct AudioInfo: Unmarshaling {
                        var url: String
                        var bandwidth: Int
                        init(object: MarshaledObject) throws {
                            url = try object.value(for: "baseUrl")
                            bandwidth = try object.value(for: "bandwidth")
                        }
                    }
                    
                    var videos: [VideoInfo] = try playInfoJson.value(for: "data.dash.video")
                    let audios: [AudioInfo]? = try playInfoJson.value(for: "data.dash.audio")
                    
                    videos.enumerated().forEach {
                        videos[$0.offset].description = descriptionDic[$0.element.id] ?? "unkonwn"
                    }
                    
                    var visVideos = [VideoInfo]()
                    videos.forEach {
                        if !visVideos.map({ $0.id }).contains($0.id) {
                            visVideos.append($0)
                        }
                    }
                    videos = visVideos
                    
                    if let p = url.query?.replacingOccurrences(of: "p=", with: ""),
                        let pInt = Int(p),
                        pInt - 1 > 0, pInt - 1 < pages.count {
                        title += " - P\(pInt) - \(pages[pInt - 1].part)"
                    }
                    
                    guard audios != nil, videos.count > 0 else {
                        resolver.fulfill((title, videos.map({ ($0.id, $0.description, $0.url) }), ""))
                        return
                    }
                    
                    guard let audioUrl = audios?.max(by: { $0.bandwidth > $1.bandwidth }),
                        videos.count > 0 else {
                        resolver.reject(VideoGetError.notFindUrls)
                        return
                    }
                    
                    resolver.fulfill((title, videos.map({ ($0.id, $0.description, $0.url) }), audioUrl.url))
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    func downloadDMFile(_ cid: Int) -> Promise<()> {
        return Promise { resolver in
            
            AF.request("https://comment.bilibili.com/\(cid).xml").response { response in
                
                if let error = response.error {
                    resolver.reject(error)
                }
                guard let resourcePath = Bundle.main.resourcePath else {
                    resolver.reject(VideoGetError.prepareDMFailed)
                    return
                }
                let danmakuFilePath = resourcePath + "/danmaku/iina-plus-danmaku.xml"
                FileManager.default.createFile(atPath: danmakuFilePath, contents: response.data, attributes: nil)
                Log("Saved DM in \(danmakuFilePath)")
                resolver.fulfill(())
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
    
// MARK: - KingKong
    func getKingKongInfo(_ roomID: Int) -> Promise<(KingKongLiveInfo)> {
        let url = "https://api.kingkongapp.com/webapi/v1/room/info?room_id=\(roomID)"
        return Promise { resolver in
            AF.request(url).response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data ?? Data())
                    let info = try KingKongLiveInfo(object: json)
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
}
