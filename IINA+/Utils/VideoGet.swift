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
    lazy var douyin = DouYin()
    lazy var huya = Huya()
    lazy var douyu = Douyu()
    lazy var eGame = EGame()
    lazy var cc163 = CC163()
    
    
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
        yougetJson.rawUrl = url
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
            return douyu.decodeUrl(url.absoluteString)
        case .huya:
            return huya.decodeUrl(url.absoluteString)
        case .eGame:
            return eGame.decodeUrl(url.absoluteString)
        case .bilibili:
            return getBilibili(url)
        case .bangumi:
            return getBangumi(url)
        case .cc163:
            return cc163.decodeUrl(url.absoluteString)
        case .douyin:
            return douyin.decodeUrl(url.absoluteString)
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
            return douyu.liveInfo(url.absoluteString)
        case .huya:
            return huya.liveInfo(url.absoluteString)
        case .eGame:
            return eGame.liveInfo(url.absoluteString)
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
            return cc163.liveInfo(url.absoluteString)
        case .douyin:
            return douyin.liveInfo(url.absoluteString)
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
    
    func prepareVideoUrl(_ json: YouGetJSON, _ key: String) -> Promise<YouGetJSON> {
        
        guard json.id != -1 else {
            return .value(json)
        }
        
        switch json.site {
        case .bilibili, .bangumi:
            guard let stream = json.streams[key],
                  stream.url == "" else {
                return .value(json)
            }
            let qn = stream.quality
            
            return bilibiliPlayUrl(yougetJson: json, false, true, qn)
        case .biliLive:
            guard let stream = json.streams[key],
                  stream.quality != -1 else {
                return .value(json)
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
            guard let stream = json.streams[key],
                  stream.quality != -1 else {
                return .value(json)
            }
            let rate = stream.rate
            if stream.url != "" {
                return .value(json)
            } else {
                let id = json.id
                return douyu.getDouyuHtml("https://www.douyu.com/\(id)").then {
                    self.douyu.getDouyuUrl(id, rate: rate, jsContext: $0.jsContext)
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
        yougetJson.rawUrl = url.absoluteString
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
        json.rawUrl = url.absoluteString
        
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
