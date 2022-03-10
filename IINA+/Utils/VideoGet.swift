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
import SwiftSoup

class VideoGet: NSObject {
    let douyin = DouYin()
    

    lazy var pSession: Session = {
        let configuration = URLSessionConfiguration.af.default
        let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1"
        configuration.headers.add(.userAgent(ua))
        return Session(configuration: configuration)
    }()
    
    
    func bilibiliUrlFormatter(_ url: String) -> Promise<String> {
        let site = SupportSites(url: url)
        
        switch site {
        case .bilibili, .bangumi:
            return .value(BilibiliUrl(url: url)!.fUrl)
        case .b23:
            return Promise { resolver in
                AF.request(url).response {
                    guard let url = $0.response?.url?.absoluteString,
                          let u = BilibiliUrl(url: url)?.fUrl else {
                        resolver.reject(VideoGetError.invalidLink)
                        return
                    }
                    resolver.fulfill(u)
                }
            }
        default:
            return .value(url)
        }
    }
    
    func decodeUrl(_ url: String) -> Promise<YouGetJSON> {
        
        var yougetJson = YouGetJSON(url:"")
        yougetJson.streams.removeAll()
        guard let url = URL(string: url) else {
            return .init(error: VideoGetError.notSupported)
        }
        let site = SupportSites(url: url.absoluteString)
        
        yougetJson.site = site
        
        switch site {
        case .biliLive:
            return getBiliLiveRoomId(url).get {
                yougetJson.title = $0.title
                yougetJson.id = $0.roomId
            }.then {
                self.getBiliLiveJSON("\($0.roomId)")
            }.map {
                $0.write(to: yougetJson)
            }
        case .douyu:
            var roomId = 0
            var roomTitle = ""
            var jsContext: JSContext!
            return getDouyuHtml(url.absoluteString).get {
                guard let rid = Int($0.roomId) else {
                    throw VideoGetError.douyuNotFoundRoomId
                }
                roomId = rid
                jsContext = $0.jsContext
            }.then { _ in
                self.douyuBetard(roomId)
            }.get {
                roomTitle = $0.title
            }.then { _ in
                self.getDouyuUrl(roomId, jsContext: jsContext)
            }.map {
                yougetJson.title = roomTitle
                $0.forEach {
                    yougetJson.streams[$0.0] = $0.1
                }
                yougetJson.id = roomId
                return yougetJson
            }
        case .huya:
            return getHuyaInfoM(url).map {
                yougetJson.title = $0.0.title
                $0.1.enumerated().forEach {
                    yougetJson.streams[$0.element.0] = $0.element.1
                }
                return yougetJson
            }
        case .eGame:
            return getEgameMInfo(url).map {
                yougetJson.title = $0.title
                $0.streamInfos.enumerated().forEach {
                    var s = Stream(url: $0.element.playUrl)
                    s.quality = 999 - $0.offset
                    yougetJson.streams[$0.element.desc] = s
                }
                return yougetJson
            }
        case .bilibili:
            return getBilibili(url)
        case .bangumi:
            return getBangumi(url)
        case .cc163:
            return getCC163Ccid(url).then {
                self.getCC163ChannelID($0)
            }.then {
                self.getCC163Videos($0)
            }.compactMap {
                $0.first
            }.map {
                $0.write(to: yougetJson)
            }
        case .douyin:
            return douyin.getInfo(url).compactMap {
                ($0 as? DouYinInfo)?.write(to: yougetJson)
            }
        default:
            return .init(error: VideoGetError.notSupported)
        }
    }
    
    func prepareDanmakuFile(yougetJSON: YouGetJSON, id: String) -> Promise<()> {
        let pref = Preferences.shared
        
        guard Processes.shared.iinaArchiveType() != .normal,
              pref.enableDanmaku,
              pref.livePlayer == .iina,
              [.bilibili, .bangumi, .local].contains(yougetJSON.site),
              yougetJSON.id != -1 else {
                  Log("Ignore Danmaku download.")
                  return .value(())
        }
  
//        return self.downloadDMFile(yougetJSON.id, id: id)
        
        
        return self.downloadDMFileV2(
            cid: yougetJSON.id,
            length: yougetJSON.duration,
            id: id)
    }
    
    func liveInfo(_ url: String, _ checkSupport: Bool = true) -> Promise<LiveInfo> {
        
        guard let url = URL(string: url) else {
            return .init(error: VideoGetError.notSupported)
        }
        let site = SupportSites(url: url.absoluteString)
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
            return getHuyaInfoM(url).map {
                $0.0
            }
        case .eGame:
            return getEgameMInfo(url).map {
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
                info.site = .bangumi
                info.title = $0.mediaInfo.title
                info.cover = $0.mediaInfo.squareCover
                info.isLiving = true
                return info
            }
        case .cc163:
            if url.pathComponents.count == 4,
               url.pathComponents[1] == "ccid" {
                var info = BilibiliInfo()
                info.site = .cc163
                info.isLiving = true
                return .value(info)
            } else {
                return getCC163Info(url)
            }
        case .douyin:
            return douyin.getInfo(url)
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
    
    func prepareVideoUrl(_ json: YouGetJSON, _ row: Int) -> Promise<YouGetJSON> {
        
        guard json.id != -1 else {
            return .value(json)
        }
        
        switch json.site {
        case .bilibili, .bangumi:
            let key = json.videos[row].key
            guard let stream = json.streams[key],
                  stream.url == "" else {
                return .value(json)
            }
            let qn = stream.quality
            
            return bilibiliPlayUrl(yougetJson: json, false, true, qn)
        case .biliLive:
            let key = json.videos[row].key
            guard let stream = json.streams[key],
                  stream.quality != -1 else {
                return .init(error: VideoGetError.notFountData)
            }
            let qn = stream.quality
            
            if stream.src.count > 0 {
                return .value(json)
            } else {
                return getBiliLiveJSON("\(json.id)", qn).map {
                    $0.write(to: json)
                }
            }
        case .douyu:
            let key = json.videos[row].key
            guard let stream = json.streams[key],
                  stream.quality != -1 else {
                return .init(error: VideoGetError.notFountData)
            }
            let rate = stream.rate
            if stream.url != "" {
                return .value(json)
            } else {
                let id = json.id
                return getDouyuHtml("https://www.douyu.com/\(id)").then {
                    self.getDouyuUrl(id, rate: rate, jsContext: $0.jsContext)
                }.map {
                    let url = $0.first {
                        $0.1.rate == rate
                    }?.1.url
                    var re = json
                    re.streams[key]?.url = url
                    return re
                }
            }
        default:
            return .value(json)
        }
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
    
    func getBiliLiveJSON(_ roomID: String, _ quality: Int = 20000) -> Promise<(BiliLivePlayUrl)> {
        Promise { resolver in
            let u = "https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo?room_id=\(roomID)&protocol=0,1&format=0,1,2&codec=0,1&qn=\(quality)&platform=web&ptype=8"
            
            AF.request(u).response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data ?? Data())
                    let playUrl: BiliLivePlayUrl = try BiliLivePlayUrl(object: json)
                    resolver.fulfill(playUrl)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    // MARK: - Douyu
    func getDouyuHtml(_ url: String) -> Promise<(roomId: String, roomIds: [String], isLiving: Bool, pageId: String, jsContext: JSContext)> {
        return Promise { resolver in
            AF.request(url).response { response in
                if let error = response.error {
                    resolver.reject(error)
                    return
                }
                
                guard let text = response.text else {
                    resolver.reject(VideoGetError.notFountData)
                    return
                }
                
                let showStatus = text.subString(from: "$ROOM.show_status =", to: ";") == "1"
                let roomId = text.subString(from: "$ROOM.room_id =", to: ";").replacingOccurrences(of: " ", with: "")
                
                guard roomId != "", let jsContext = self.douyuJSContext(text) else {
                    resolver.reject(VideoGetError.douyuNotFoundRoomId)
                    return
                }
                
                var roomIds = [String]()
                var pageId = ""
                let roomIdsStr = text.subString(from: "window.room_ids=[", to: "],")
                
                if roomIdsStr != "" {
                    roomIds = roomIdsStr.replacingOccurrences(of: "\"", with: "").split(separator: ",").map(String.init)
                    pageId = text.subString(from: "\"pageId\":", to: ",")
                }

                resolver.fulfill((roomId, roomIds, showStatus, pageId, jsContext))
            }
        }
    }
    
    func douyuJSContext(_ text: String) -> JSContext? {
        var text = text
        
        let start = #"<script type="text/javascript">"#
        let end = #"</script>"#
        
        var scriptTexts = [String]()
        
        while text.contains(start) {
            let js = text.subString(from: start, to: end)
            scriptTexts.append(js)
            text = text.subString(from: start)
        }
        
        guard let context = JSContext(),
              let cryptoPath = Bundle.main.path(forResource: "crypto-js", ofType: "js"),
              let cryptoData = FileManager.default.contents(atPath: cryptoPath),
              let cryptoJS = String(data: cryptoData, encoding: .utf8)?.subString(from: #"}(this, function () {"#, to: #"return CryptoJS;"#),
              let signJS = scriptTexts.first(where: { $0.contains("ub98484234") })
        else {
            return nil
        }
        context.name = "DouYin Sign"
        context.evaluateScript(cryptoJS)
        context.evaluateScript(signJS)
        
        return context
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
    func getDouyuEventRoomNames(_ pageId: String) -> Promise<[DouyuEventRoom]> {
        return Promise { resolver in
            AF.request("https://butterfly.douyucdn.cn/api/page/loadPage?name=pageData2&pageId=\(pageId)&view=0").response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                
                guard let data = self.douyuRoomJsonFormatter(response.text ?? "")?.data(using: .utf8) else {
                    resolver.reject(VideoGetError.douyuNotFoundRoomId)
                    return
                }
                
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(data)
                    let rooms: [DouyuEventRoom] = try json.value(for: "children")
                    resolver.fulfill(rooms)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    func getDouyuUrl(_ roomID: Int, rate: Int = 0, jsContext: JSContext) -> Promise<[(String, Stream)]> {
        let time = Int(Date().timeIntervalSince1970)
        let didStr: String = {
            let time = UInt32(NSDate().timeIntervalSinceReferenceDate)
            srand48(Int(time))
            let random = "\(drand48())"
            return MD5(random) ?? ""
        }()
        
        
        guard let sign = jsContext.evaluateScript("ub98484234(\(roomID), '\(didStr)', \(time))").toString(),
              let v = jsContext.evaluateScript("vdwdae325w_64we").toString()
        else {
            return .init(error: VideoGetError.douyuSignError)
        }
        
        return Promise { resolver in
            let pars = ["v": v,
                        "did": didStr,
                        "tt": time,
                        "sign": sign.subString(from: "sign="),
                        "cdn": "ali-h5",
                        "rate": "\(rate)",
                        "ver": "Douyu_221111905",
                        "iar": "0",
                        "ive": "0"] as [String : Any]
            AF.request("https://www.douyu.com/lapi/live/getH5Play/\(roomID)", method: .post, parameters: pars).response { response in
            
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data ?? Data())
                    let play = try DouyuH5Play(object: json)
                    
                    resolver.fulfill(play)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }.then {
            self.douyuCDNs($0)
        }.map { play in
            play.multirates.map { rate -> (String, Stream) in
                var s = Stream(url: "")
                s.quality = rate.bit
                s.rate = rate.rate
                
                var urls = play.p2pUrls
                urls.append(play.flvUrl)
                
                if rate.rate == play.rate, urls.count > 0 {
                    s.url = urls.removeFirst()
                    s.src = urls
                }
                return (rate.name, s)
            }
        }
    }
    
    func douyuCDNs(_ info: DouyuH5Play) -> Promise<DouyuH5Play> {
        guard let url = info.cdnUrl else {
            return .value(info)
        }
        
        return Promise { resolver in
            AF.request(url).response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                guard let data = response.data else {
                    resolver.reject(VideoGetError.notFountData)
                    return
                }
                
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(data)
                    
                    let sugs: [String] = try json.value(for: "sug")
                    let baks: [String] = try json.value(for: "bak")
                    var info = info
                    info.initP2pUrls(sugs + baks)
                    resolver.fulfill(info)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    // MARK: - Huya
    
    func getHuyaInfo(_ url: URL) -> Promise<(HuyaInfo, [(String, Stream)])> {
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
                
                guard let text = response.text,
                    let roomInfoData = text.subString(from: "var TT_ROOM_DATA = ", to: ";var").data(using: .utf8),
                      let profileInfoData = text.subString(from: "var TT_PROFILE_INFO = ", to: ";var").data(using: .utf8),
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
                    
                    guard urls.count > 0 else {
                        resolver.reject(VideoGetError.notFindUrls)
                        return
                    }
                    
                    let re = huyaStream.vMultiStreamInfo.enumerated().map { info -> (String, Stream) in
                            
                        let u = urls.first!.replacingOccurrences(of: "ratio=0", with: "ratio=\(info.element.iBitRate)")
                        var s = Stream(url: u)
                        
                        if info.element.iBitRate == 0,
                           info.offset == 0 {
                            s.quality = huyaStream.vMultiStreamInfo.map {
                                $0.iBitRate
                            }.max() ?? 999999999
                            s.quality += 1
                        } else {
                            s.quality = info.element.iBitRate
                        }
                        return (info.element.sDisplayName, s)
                    }
                    
                    resolver.fulfill((info, re))
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    func getHuyaInfoM(_ url: URL) -> Promise<(HuyaInfoM, [(String, Stream)])> {
        return Promise { resolver in
            pSession.request(url.absoluteString).response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                guard let text = response.text,
                      let jsonData = text.subString(from: "<script> window.HNF_GLOBAL_INIT = ", to: " </script>").data(using: .utf8)
                else {
                    resolver.reject(VideoGetError.notFindUrls)
                    return
                }
                
                do {
                    let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(jsonData)
                    
                    let info: HuyaInfoM = try HuyaInfoM(object: jsonObj)
                          
                    resolver.fulfill((info, info.urls))
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
                    
                    var urls: [EgameUrl] = try json.value(for: "state.live-info.liveInfo.videoInfo.streamInfos")
                    let urlsBak: [EgameUrl] = try json.value(for: "state.live-info.liveBaseInfo.streamInfo.streamInfos")
                    
                    urlsBak.forEach { bak in
                        guard let i = urls.firstIndex(where: {
                            $0.levelType == bak.levelType
                            && $0.desc == bak.desc
                        }) else {
                            return
                        }
                        urls[i].src.append(bak.playUrl)
                    }
                    
                    resolver.fulfill((info, urls))
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    func getEgameMInfo(_ url: URL) -> Promise<(EgameMInfo)> {
        let pcs = url.pathComponents
        guard pcs.count > 1,
              let rid = Int(pcs[1]) else {
                  return .init(error: VideoGetError.invalidLink)
              }
        let u = "https://m.egame.qq.com/live?anchorid=\(rid)"
        
        return Promise { resolver in
            AF.request(u).response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                
                guard let str = response.text?.subString(from: "try {            window.serverData = ", to: ";\r\n"),
                      let data = str.data(using: .utf8)
                else {
                    resolver.reject(VideoGetError.egameFunctionNotFound)
                    return
                }
                
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(data)
                    let info = try EgameMInfo(object: json)
                    resolver.fulfill(info)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    // MARK: - Bilibili
    func getBilibili(_ url: URL) -> Promise<(YouGetJSON)> {
        setBilibiliQuality()
        
        let isDM = Processes.shared.iinaArchiveType() != .normal
        
        let r1 = bilibiliPrepareID(url).then {
            self.bilibiliPlayUrl(yougetJson: $0, isDM)
        }
        
        let r2 = getBilibiliHTMLDatas(url).then {
            self.decodeBilibiliDatas(
                url,
                playInfoData: $0.playInfoData,
                initialStateData: $0.initialStateData)
        }
        
        return Promise { resolver in
            r1.done {
                resolver.fulfill($0)
            }.catch { error in
                r2.done {
                    resolver.fulfill($0)
                }.catch { _ in
                    resolver.reject(error)
                }
            }
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
                    let page: Int
                    let part: String
                    let cid: Int
                    
                    init(object: MarshaledObject) throws {
                        page = try object.value(for: "page")
                        part = try object.value(for: "part")
                        cid = try object.value(for: "cid")
                    }
                }
                let pages: [Page] = try initialStateJson.value(for: "videoData.pages")
                yougetJson.id = try initialStateJson.value(for: "videoData.cid")
                let bvid: String = try initialStateJson.value(for: "videoData.bvid")
                
                if let p = url.query?.replacingOccurrences(of: "p=", with: ""),
                   let pInt = Int(p),
                   pInt - 1 > 0, pInt - 1 < pages.count {
                    let page = pages[pInt - 1]
                    title += " - P\(pInt) - \(page.part)"
                    yougetJson.id = page.cid
                }
                
                yougetJson.title = title
                yougetJson.duration = try initialStateJson.value(for: "videoData.duration")

                if let playInfo: BilibiliPlayInfo = try? playInfoJson.value(for: "data") {
                    yougetJson = playInfo.write(to: yougetJson)
                    resolver.fulfill(yougetJson)
                } else if let info: BilibiliSimplePlayInfo = try? playInfoJson.value(for: "data") {
                    yougetJson = info.write(to: yougetJson)
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
        cookieProperties[HTTPCookiePropertyKey.value] = "125" as String
        cookieProperties[HTTPCookiePropertyKey.domain] = ".bilibili.com" as String
        cookieProperties[HTTPCookiePropertyKey.path] = "/" as String
        let cookie = HTTPCookie(properties: cookieProperties)
        HTTPCookieStorage.shared.setCookie(cookie!)
        
    }
    
    enum BilibiliFnval: Int {
        case flv = 0
        case mp4 = 1
        case dashH265 = 16
        case hdr = 64
        case dash4K = 128
        case dolbyAudio = 256
        case dolbyVideo = 512
        case dash8K = 1024
    }
     
    func bilibiliPlayUrl(yougetJson: YouGetJSON,
                         _ isDM: Bool = true,
                         _ isBangumi: Bool = false,
                         _ qn: Int = 132) -> Promise<(YouGetJSON)> {
        var yougetJson = yougetJson
        let cid = yougetJson.id
        
        var allowFlv = true
        var dashSymbol = true
        var inner = false
        
        if !isDM {
            allowFlv = true
            dashSymbol = false
            inner = false
        }
        
        let fnval = allowFlv ? dashSymbol ? inner ? BilibiliFnval.dashH265.rawValue : BilibiliFnval.dash8K.rawValue + BilibiliFnval.dolbyVideo.rawValue + BilibiliFnval.dolbyAudio.rawValue + BilibiliFnval.dash4K.rawValue + BilibiliFnval.hdr.rawValue + BilibiliFnval.dashH265.rawValue : BilibiliFnval.flv.rawValue : BilibiliFnval.mp4.rawValue
        
        
        var u = isBangumi ?
        "https://api.bilibili.com/pgc/player/web/playurl?" :
        "https://api.bilibili.com/x/player/playurl?"
        
        u += "cid=\(cid)&qn=\(qn)&otype=json&bvid=\(yougetJson.bvid)&fnver=0&fnval=\(fnval)&fourk=1"
        
        let headers = HTTPHeaders(
            ["Referer": "https://www.bilibili.com/",
             "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:38.0) Gecko/20100101 Firefox/38.0 Iceweasel/38.2.1"])
        
        return Promise { resolver in
            AF.request(u, headers: headers).response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                guard let data = response.data else {
                    resolver.reject(VideoGetError.notFountData)
                    return
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(data)
                    
                    let code: Int = try json.value(for: "code")
                    if code == -10403 {
                        resolver.reject(VideoGetError.needVip)
                        return
                    }
                    
                    let key = isBangumi ? "result" : "data"
                    
                    
                    if let info: BilibiliPlayInfo = try? json.value(for: key) {
                        yougetJson = info.write(to: yougetJson)
                    } else {
                        let info: BilibiliSimplePlayInfo = try json.value(for: key)
                        yougetJson = info.write(to: yougetJson)
                    }
                    
                    resolver.fulfill(yougetJson)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }

    // MARK: - Bangumi
    
    func getBangumi(_ url: URL) -> Promise<(YouGetJSON)> {
        setBilibiliQuality()
        
        let isDM = Processes.shared.iinaArchiveType() != .normal
        return bilibiliPrepareID(url).then {
            self.bilibiliPlayUrl(yougetJson: $0, isDM, true)
        }
        
    }
    
    func bilibiliPrepareID(_ url: URL) -> Promise<(YouGetJSON)> {
        let bilibili = Bilibili()
        guard let bUrl = BilibiliUrl(url: url.absoluteString) else {
            return .init(error: VideoGetError.invalidLink)
        }
        var json = YouGetJSON(url:"")
        json.streams.removeAll()
        
        switch bUrl.urlType {
        case .video:
            json.site = .bilibili
            return bilibili.getVideoList(url).compactMap { list -> YouGetJSON? in
                guard let s = list.first(where: { $0.index == bUrl.p }) else {
                    return nil
                }
                json.id = s.id
                json.bvid = s.bvid
                json.title = s.title
                json.duration = Int(s.duration)
                return json
            }
        case .bangumi:
            json.site = .bangumi
            return bilibili.getBangumiList(url).compactMap { list -> YouGetJSON? in
                
                var ep: BangumiInfo.BangumiEp? {
                    if bUrl.id.prefix(2) == "ss" {
                        return list.epList.first
                    } else {
                        return list.epList.first(where: { $0.id == Int(bUrl.id.dropFirst(2)) })
                    }
                }
                
                guard let s = ep else {
                    return nil
                }
                json.bvid = s.bvid
                json.id = s.cid
                if list.epList.count == 1 {
                    json.title = list.title
                } else {
                    let title = [json.title,
                                 s.title,
                                 s.longTitle].filter {
                        $0 != ""
                    }.joined(separator: " - ")
                    json.title = title
                }
                
                json.duration = s.duration
                return json
            }
        default:
            return .init(error: VideoGetError.invalidLink)
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
        
        print("downloadDMFileV2", c)
        
        guard c < 1500 else {
            return .value(())
        }
        
        return when(fulfilled: s.map {
            getDanmakuContent(cid: cid, index: $0)
        }).done {
            
            let element = try XMLElement(xmlString: #"<?xml version="1.0" encoding="UTF-8"?><i><chatserver>chat.bilibili.tv</chatserver><chatid>170102</chatid></i>"#)

            let doc = XMLDocument(rootElement: element)

            Array($0.joined()).map { dm -> String in
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
                
                s2 = s2.replacingOccurrences(of: "`", with: "&apos;")
                
                return "<d p=\"\(s1)\">\(s2)</d>"
            }.forEach {
                if let node = try? XMLElement(xmlString: $0) {
                    element.addChild(node)
                } else {
                    Log("Invalid Bangumi Line: \($0)")
                }
            }
            
            self.saveDMFile(doc.xmlData, with: id)
        }
    }
    
    func saveDMFile(_ data: Data?, with id: String) {
        guard let path = dmPath(id) else { return }

        FileManager.default.createFile(atPath: path, contents: data, attributes: nil)
        Log("Saved DM in \(path)")
    }
    
    func dmPath(_ id: String) -> String? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
            var filesURL = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return nil
        }
        let folderName = "WebFiles"
        
        filesURL.appendPathComponent(bundleIdentifier)
        filesURL.appendPathComponent(folderName)
        let fileName = "danmaku" + "-" + id + ".xml"
        
        filesURL.appendPathComponent(fileName)
        return filesURL.path
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
    
    // MARK: - CC163
    
    func getCC163Info(_ url: URL) -> Promise<LiveInfo> {
        return Promise { resolver in
            getCC163State(url.absoluteString).done {
                if let i = $0.info {
                    resolver.fulfill(i)
                } else if let cid = $0.list.first?.cid {
                    self.getCC163ZtState(cid: cid).done {
                        resolver.fulfill($0)
                    }.catch {
                        resolver.reject($0)
                    }
                } else {
                    resolver.reject(VideoGetError.invalidLink)
                }
            }.catch {
                resolver.reject($0)
            }
        }
    }
    
    func getCC163State(_ url: String) -> Promise<(info: LiveInfo?, list: [CC163ZTInfo])> {
        return Promise { resolver in
            AF.request(url).response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                let json = response.text?.subString(from: "__NEXT_DATA__", to: "</script>").subString(from: ">")
                
                let jsonData = json?.data(using: .utf8) ?? Data()
                
                do {
                    let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(jsonData)
                    
                    if let domain: String = try? jsonObj.value(for: "query.domain") {
                        let list = try self.getCC163ZtRoomList(response.text ?? "")
                        resolver.fulfill((nil, list))
                    } else if let cid: String = try? jsonObj.value(for: "query.subcId") {
                        self.getCC163ZtState(cid: cid).done {
                            resolver.fulfill(($0, []))
                        }.catch {
                            resolver.reject($0)
                        }
                    } else {
                        let info = try CC163Info(object: jsonObj)
                        resolver.fulfill((info, []))
                    }
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    func getCC163ZtRoomList(_ text: String) throws -> [CC163ZTInfo] {
        return try SwiftSoup.parse(text)
            .getElementsByClass("channel_list").first()?
            .children().map {
                
                CC163ZTInfo(
                    name: try $0.children().first()?.children().first()?.text() ?? "",
                    ccid: try $0.attr("ccid"),
                    channel: try ($0.attr("channel").starts(with: "https:") ? $0.attr("channel") : "https:" + $0.attr("channel")),
                    cid: try $0.attr("cid"),
                    index: try $0.attr("index"),
                    roomid: try $0.attr("roomid"),
                    isLiving:  $0.children().first()?.children().hasClass("icon-live") ?? false)
            }.filter {
                $0.ccid != "" && $0.roomid != ""
            } ?? []
    }
    
    func getCC163ZtState(cid: String) -> Promise<LiveInfo> {
        
        let url = "https://cc.163.com/live/channel/?channelids=\(cid)"

        return Promise { resolver in
            AF.request(url).response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data ?? Data())
                    let infos: [CC163ChannelInfo] = try json.value(for: "data")
                
                    guard let info = infos.first else {
                        resolver.reject(VideoGetError.notFountData)
                        return
                    }
                    guard info.isLiving else {
                        resolver.reject(VideoGetError.isNotLiving)
                        return
                    }
                    resolver.fulfill(info)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    func getCC163(_ ccid: String) -> Promise<[String]> {
        let url = "https://vapi.cc.163.com/video_play_url/\(ccid)"
        
        return Promise { resolver in
            AF.request(url).response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                let json = response.text
                let jsonData = json?.data(using: .utf8) ?? Data()
                
                do {
                    let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(jsonData)
                    
                    var re = [String]()
                    re.append(try jsonObj.value(for: "videourl"))
                    re.append(try jsonObj.value(for: "bakvideourl"))
                    
                    resolver.fulfill(re)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    func getCC163Ccid(_ url: URL) -> Promise<(String)> {
        let pcs = url.pathComponents
        if pcs.count == 4,
           pcs[1] == "ccid" {
            return .value((pcs[2]))
        } else {
            return getCC163Info(url).compactMap {
                $0 as? CC163Info
            }.map {
                $0.ccid
            }
        }
    }
    
    func getCC163ChannelID(_ ccid: String) -> Promise<(Int)> {
        let url = "https://api.cc.163.com/v1/activitylives/anchor/lives?anchor_ccid=\(ccid)"
        return Promise { resolver in
            AF.request(url).response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let jsonData = response.data ?? Data()
                    let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(jsonData)
                    let id: Int = try jsonObj.value(for: "data.\(ccid).channel_id")
                    
                    resolver.fulfill(id)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    func getCC163Videos(_ channelID: Int) -> Promise<[CC163NewVideos]> {
        let url = "https://cc.163.com/live/channel/?channelids=\(channelID)"
        
        return Promise { resolver in
            AF.request(url).response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let jsonData = response.data ?? Data()
                    let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(jsonData)
                    let videos: [CC163NewVideos] = try jsonObj.value(for: "data")
                
                    resolver.fulfill(videos)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    // MARK: - MD5
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
    
    func douyuRoomJsonFormatter(_ text: String) -> String? {
        guard let index = text.index(of: #""NewPcBasicSwitchRoomAdvance""#)?.utf16Offset(in: text) else {
            return nil
        }
        
        let sIndex = text.indexes(of: "{").map({$0.utf16Offset(in: text)})
        let eIndex = text.indexes(of: "}").map({$0.utf16Offset(in: text)})
        
        let indexList = (sIndex.map {
            ($0, 1)
        } + eIndex.map {
            ($0, -1)
        }).sorted { i1, i2 in
            i1.0 < i2.0
        }
        
        // Find "{"
        var c2 = 0
        guard var i2 = indexList.lastIndex(where: { $0.0 < index }) else {
            return nil
        }
        
        c2 += indexList[i2].1
        while c2 != 1 {
            i2 -= 1
            guard i2 >= 0 else {
                return nil
            }
            c2 += indexList[i2].1
        }
        let startIndex = text.index(text.startIndex, offsetBy: indexList[i2].0)
        
        // Find "}"
        var c1 = 0
        guard var i1 = indexList.firstIndex(where: { $0.0 > index }) else {
            return nil
        }
        
        c1 += indexList[i1].1
        while c1 != -1 {
            i1 += 1
            guard indexList.count > i1 else {
                return nil
            }
            c1 += indexList[i1].1
        }
        
        let endIndex = text.index(startIndex, offsetBy: indexList[i1].0 - indexList[i2].0)
        
        return String(text[startIndex...endIndex])
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
