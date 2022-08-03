//
//  Bilibili.swift
//  iina+
//
//  Created by xjbeta on 2018/8/6.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import Alamofire
import Marshal
import PromiseKit
import PMKAlamofire

class Bilibili: NSObject, SupportSiteProtocol {
    func liveInfo(_ url: String) -> Promise<LiveInfo> {
        if SupportSites(url: url) == .bangumi {
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
        } else {
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
        }
    }
    
    func decodeUrl(_ url: String) -> Promise<YouGetJSON> {
        if SupportSites(url: url) == .bangumi {
            return getBangumi(url)
        } else {
            return getBilibili(url)
        }
    }
    
// MARK: - Bilibili
    
    func getBilibili(_ url: String) -> Promise<(YouGetJSON)> {
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
    
    func getBilibiliHTMLDatas(_ url: String) -> Promise<((playInfoData: Data, initialStateData: Data))> {
        let headers = HTTPHeaders(
            ["Referer": "https://www.bilibili.com/",
             "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:38.0) Gecko/20100101 Firefox/38.0 Iceweasel/38.2.1"])
        
        return AF.request(url, headers: headers).responseString().map {
            let playInfoData = $0.string.subString(from: "window.__playinfo__=", to: "</script>").data(using: .utf8) ?? Data()
            let initialStateData = $0.string.subString(from: "window.__INITIAL_STATE__=", to: ";(function()").data(using: .utf8) ?? Data()
            return (playInfoData, initialStateData)
        }
    }
    
    func decodeBilibiliDatas(_ url: String,
                             playInfoData: Data,
                             initialStateData: Data) -> Promise<(YouGetJSON)> {
        var yougetJson = YouGetJSON(rawUrl: url)
        
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
//                let bvid: String = try initialStateJson.value(for: "videoData.bvid")
                
                if let p = URL(string: url)?.query?.replacingOccurrences(of: "p=", with: ""),
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
        case dashAV1 = 2048
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
        
        let fnval = allowFlv ? dashSymbol ? inner ? BilibiliFnval.dashH265.rawValue : BilibiliFnval.dashAV1.rawValue + BilibiliFnval.dash8K.rawValue + BilibiliFnval.dolbyVideo.rawValue + BilibiliFnval.dolbyAudio.rawValue + BilibiliFnval.dash4K.rawValue + BilibiliFnval.hdr.rawValue + BilibiliFnval.dashH265.rawValue : BilibiliFnval.flv.rawValue : BilibiliFnval.mp4.rawValue
        
        
        var u = isBangumi ?
        "https://api.bilibili.com/pgc/player/web/playurl?" :
        "https://api.bilibili.com/x/player/playurl?"
        
        u += "cid=\(cid)&bvid=\(yougetJson.bvid)&qn=\(qn)&fnver=0&fnval=\(fnval)&fourk=1"
        
        let headers = HTTPHeaders(
            ["Referer": "https://www.bilibili.com/",
             "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:38.0) Gecko/20100101 Firefox/38.0 Iceweasel/38.2.1"])
        
        
        return AF.request(u, headers: headers).responseData().map {
            let json: JSONObject = try JSONParser.JSONObjectWithData($0.data)
            
            let code: Int = try json.value(for: "code")
            if code == -10403 {
                throw VideoGetError.needVip
            }
            
            let key = isBangumi ? "result" : "data"
            
            
            if let info: BilibiliPlayInfo = try? json.value(for: key) {
                yougetJson = info.write(to: yougetJson)
            } else {
                let info: BilibiliSimplePlayInfo = try json.value(for: key)
                yougetJson = info.write(to: yougetJson)
            }
            
            return yougetJson
        }
    }
    
    
    // MARK: - Bangumi
    
    func getBangumi(_ url: String) -> Promise<(YouGetJSON)> {
        setBilibiliQuality()
        
        let isDM = Processes.shared.iinaArchiveType() != .normal
        return bilibiliPrepareID(url).then {
            self.bilibiliPlayUrl(yougetJson: $0, isDM, true)
        }
        
    }
    
    func bilibiliPrepareID(_ url: String) -> Promise<(YouGetJSON)> {
        guard let bUrl = BilibiliUrl(url: url) else {
            return .init(error: VideoGetError.invalidLink)
        }
        var json = YouGetJSON(rawUrl: url)
        
        switch bUrl.urlType {
        case .video:
            json.site = .bilibili
            return getVideoList(url).compactMap { list -> YouGetJSON? in
                var selector = list.first
                if let s = selector, s.isCollection {
                    selector = list.first(where: { $0.bvid == bUrl.id })
                } else {
                    selector = list.first(where: { $0.index == bUrl.p })
                }
                guard let s = selector else { return nil }
                
                json.id = s.id
                json.bvid = s.bvid
                json.title = s.title
                json.duration = Int(s.duration)
                return json
            }
        case .bangumi:
            json.site = .bangumi
            return getBangumiList(url).compactMap { list -> YouGetJSON? in
                
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
    
    
// MARK: - Other API
    
    
    enum BilibiliApiError: Error {
        case biliCSRFNotFound
    }
    
    func isLogin() -> Promise<(Bool, String)> {
        AF.request("https://api.bilibili.com/x/web-interface/nav").responseData().map {
            let json: JSONObject = try JSONParser.JSONObjectWithData($0.data)
            let isLogin: Bool = try json.value(for: "data.isLogin")
            NotificationCenter.default.post(name: .biliStatusChanged, object: nil, userInfo: ["isLogin": isLogin])
            var name = ""
            if isLogin {
                name = try json.value(for: "data.uname")
            }
            
            return (isLogin, name)
        }
    }
    
    func logout() -> Promise<()> {
        guard let url = URL(string: "https://www.bilibili.com"),
              let biliCSRF = HTTPCookieStorage.shared.cookies(for: url)?.first(where: { $0.name == "bili_jct" })?.value else {
            
            return .init(error: BilibiliApiError.biliCSRFNotFound)
        }
        return AF.request("https://passport.bilibili.com/login/exit/v2", method: .post, parameters: ["biliCSRF": biliCSRF]).responseData().map { _ in }
    }
    
    func getUid() -> Promise<Int> {
        AF.request("https://api.bilibili.com/x/web-interface/nav").responseData().map {
            let json: JSONObject = try JSONParser.JSONObjectWithData($0.data)
            return try json.value(for: "data.mid")
        }
    }
    
    func dynamicList(_ uid: Int,
                     _ action: BilibiliDynamicAction = .init😅,
                     _ dynamicID: Int = -1) -> Promise<[BilibiliCard]> {
        
        var http: DataRequest
        let headers = HTTPHeaders(["referer": "https://www.bilibili.com/"])
        
        
        switch action {
        case .init😅:
            http = AF.request("https://api.vc.bilibili.com/dynamic_svr/v1/dynamic_svr/dynamic_new?uid=\(uid)&type=8", headers: headers)
        case .history:
            http = AF.request("https://api.vc.bilibili.com/dynamic_svr/v1/dynamic_svr/dynamic_history?uid=\(uid)&offset_dynamic_id=\(dynamicID)&type=8", headers: headers)
        case .new:
            http = AF.request("https://api.vc.bilibili.com/dynamic_svr/v1/dynamic_svr/dynamic_new?uid=\(uid)&current_dynamic_id=\(dynamicID)&type=8", headers: headers)
        }
        
        return http.responseData().map {
            do {
                let json: JSONObject = try JSONParser.JSONObjectWithData($0.data)
                let cards: [BilibiliCard] = try json.value(for: "data.cards")
                return cards
            } catch MarshalError.keyNotFound {
                return []
            } catch let error {
                throw error
            }
        }
    }
    
    func getPvideo(_ aid: Int) -> Promise<BilibiliPvideo> {
        AF.request("https://api.bilibili.com/pvideo?aid=\(aid)").responseData().map {
            let json: JSONObject = try JSONParser.JSONObjectWithData($0.data)
            var pvideo = try BilibiliPvideo(object: json)
            pvideo.cropImages()
            return pvideo
        }
    }
    
    func getVideoList(_ url: String) -> Promise<[BiliVideoSelector]> {
        var aid = -1
        var bvid = ""
        
        let pathComponents = URL(string: url)?.pathComponents ?? []
        guard pathComponents.count >= 3 else {
            return .init(error: VideoGetError.cantFindIdForDM)
        }
        let idP = pathComponents[2]
        if idP.starts(with: "av"), let id = Int(idP.replacingOccurrences(of: "av", with: "")) {
            aid = id
        } else if idP.starts(with: "BV") {
            bvid = idP
        } else {
            return .init(error: VideoGetError.cantFindIdForDM)
        }
        
        var r: DataRequest
        if aid != -1 {
            r = AF.request("https://api.bilibili.com/x/web-interface/view?aid=\(aid)")
        } else if bvid != "" {
            r = AF.request("https://api.bilibili.com/x/web-interface/view?bvid=\(bvid)")
        } else {
            return .init(error: VideoGetError.cantFindIdForDM)
        }
        
        return r.responseData().map {
            let json: JSONObject = try JSONParser.JSONObjectWithData($0.data)
            
            if let collection: BilibiliVideoCollection = try json.value(for: "data.ugc_season"), collection.episodes.count > 0 {
                return collection.episodes
            } else {
                var infos: [BiliVideoSelector] = try json.value(for: "data.pages")
                let bvid: String = try json.value(for: "data.bvid")
                
                if infos.count == 1 {
                    infos[0].title = try json.value(for: "data.title")
                }
                infos.enumerated().forEach {
                    infos[$0.offset].bvid = bvid
                }
                return infos
            }
        }
    }
    
    func getBangumiList(_ url: String,
                        initialStateData: Data? = nil) -> Promise<(BangumiList)> {
        getBilibiliHTMLDatas(url).map {
            let stateJson: JSONObject = try JSONParser.JSONObjectWithData($0.initialStateData)
            let state = try BangumiList(object: stateJson)
            return state
        }
    }
}




@objc(BilibiliCard)
class BilibiliCard: NSObject, Unmarshaling {
    var aid: Int = 0
    var bvid: String = ""
    var dynamicId: Int = 0
    @objc var title: String = ""
    @objc var pic: NSImage?
    @objc var picUrl: String = ""
    @objc var name: String = ""
    @objc var duration: TimeInterval = 0
    @objc var views: Int = 0
    @objc var videos: Int = 0
//    var pubdate = 1533581945
    
    
    override init() {
        super.init()
    }
    
    required init(object: MarshaledObject) throws {
        dynamicId = try object.value(for: "desc.dynamic_id")
        bvid = try object.value(for: "desc.bvid")
        let jsonStr: String = try object.value(for: "card")
        if let data = jsonStr.data(using: .utf8) {
            let json: JSONObject = try JSONParser.JSONObjectWithData(data)
            aid = try json.value(for: "aid")
            title = try json.value(for: "title")
            let picUrl: String = try json.value(for: "pic")
            self.picUrl = picUrl
            duration = try json.value(for: "duration")
            name = try json.value(for: "owner.name")
            views = try json.value(for: "stat.view")
            videos = try json.value(for: "videos")
        }
    }
}

enum BilibiliDynamicAction {
    case init😅, new, history
}

struct BilibiliPvideo: Unmarshaling {
    var images: [NSImage] = []
    var pImages: [NSImage] = []
    var xLen: Int = 0
    var yLen: Int = 0
    var xSize: Int = 0
    var ySize: Int = 0
    var imagesCount: Int = 0
    
    enum CropImagesError: Error {
        case zeroImagesCount
    }
    
    init(object: MarshaledObject) throws {
        let imageStrs: [String] = try object.value(for: "data.image")
//        images = imageStrs.compactMap { str -> NSImage? in
//            if let url = URL(string: str.replacingOccurrences(of: "http://", with: "https://")) {
//                return NSImage(contentsOf: url)
//            } else {
//                return nil
//            }
//        }
        let indexs: [Int] = try object.value(for: "data.index")
        imagesCount = indexs.count
        // limit image count for performance
        if imagesCount > 100 {
            imagesCount = 100
        } else if imagesCount == 0 {
            throw CropImagesError.zeroImagesCount
        }
        if let iamgeStr = imageStrs.first,
            let url = URL(string: "https:" + iamgeStr),
            let image = NSImage(contentsOf: url) {
            images = [image]
        }
        
        xLen = try object.value(for: "data.img_x_len")
        yLen = try object.value(for: "data.img_y_len")
        xSize = try object.value(for: "data.img_x_size")
        ySize = try object.value(for: "data.img_y_size")
    }
    
    mutating func cropImages() {
        var pImages: [NSImage] = []
        var limitCount = 0
        images.forEach { image in
            var xIndex = 0
            var yIndex = 0
            
            if limitCount < imagesCount {
                while yIndex < yLen {
                    while xIndex < xLen {
                        let rect = NSRect(x: xIndex * xSize, y: yIndex * ySize, width: xSize, height: ySize)
                        
                        if let croppedImage = crop(image, with: rect) {
                            pImages.append(croppedImage)
                        }
                        limitCount += 1
                        if limitCount == imagesCount {
                            xIndex = 10
                            yIndex = 10
                        }
                        xIndex += 1
                        if xIndex == xLen {
                            xIndex = 0
                            yIndex += 1
                        }
                    }
                }
            }
        }
        self.pImages = pImages
    }
    
    func crop(_ image: NSImage, with rect: NSRect) -> NSImage? {
        guard let croppedImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.cropping(to: rect) else {
            return nil
        }
        let reImage = NSImage(cgImage: croppedImage, size: rect.size)
        return reImage
    }
}

protocol BilibiliVideoSelector: VideoSelector {
    var bvid: String { get set }
    var duration: Int { get set }
}

struct BiliVideoSelector: Unmarshaling, BilibiliVideoSelector {
    var bvid = ""
    var isCollection = false
    
    // epid
    let id: Int
    var index: Int
    let part: String
    var duration: Int
    var title: String
    let longTitle: String
    let coverUrl: URL?
//    let badge: Badge?
    let site: SupportSites
    
    struct Badge {
        let badge: String
        let badgeColor: NSColor
        let badgeType: Int
    }
    
    init(object: MarshaledObject) throws {
        id = try object.value(for: "cid")
        
        if let pic: String = try? object.value(for: "arc.pic") {
            coverUrl = .init(string: pic)
            duration = (try? object.value(for: "arc.duration")) ?? 0
            bvid = try object.value(for: "bvid")
            index = 0
            title = try object.value(for: "title")
            isCollection = true
            part = ""
        } else {
            index = try object.value(for: "page")
            part = try object.value(for: "part")
            duration = (try? object.value(for: "duration")) ?? 0
            title = part
            coverUrl = nil
    //        badge = nil
        }
        longTitle = ""
        site = .bilibili
    }
    
    init(ep: BangumiInfo.BangumiEp) {
        id = ep.id
        index = -1
        part = ""
        duration = 0
        title = ep.title
        longTitle = ep.longTitle
        coverUrl = nil
//        ep.badgeColor
//        badge = .init(badge: ep.badge,
//                      badgeColor: .red,
//                      badgeType: ep.badgeType)
        site = .bangumi
    }
}

struct BilibiliVideoCollection: Unmarshaling {
    let id: Int
    let title: String
    let cover: URL?
    let mid: Int
    let epCount: Int
    let isPaySeason: Bool
    let episodes: [BiliVideoSelector]
    
    init(object: MarshaledObject) throws {
        id = try object.value(for: "id")
        title = try object.value(for: "title")
        cover = .init(string: try object.value(for: "cover"))
        mid = try object.value(for: "mid")
        epCount = try object.value(for: "ep_count")
        isPaySeason = try object.value(for: "is_pay_season")
        
        let s: [Section] = try object.value(for: "sections")
        episodes = s.first?.episodes ?? []
    }
    
    struct Section: Unmarshaling {
        let id: Int
        let title: String
        let episodes: [BiliVideoSelector]
        
        init(object: MarshaledObject) throws {
            id = try object.value(for: "id")
            title = try object.value(for: "title")
            var eps: [BiliVideoSelector] = try object.value(for: "episodes")
            eps.enumerated().forEach {
                eps[$0.offset].index = $0.offset + 1
            }
            episodes = eps
        }
    }
}

struct BangumiList: Unmarshaling {
    let title: String
    let epList: [BangumiInfo.BangumiEp]
    let sections: [BangumiInfo.BangumiSections]
    
    var epVideoSelectors: [BiliVideoSelector] {
        get {
            var list = epList.map(BiliVideoSelector.init)
            list.enumerated().forEach {
                list[$0.offset].index = $0.offset + 1
            }
            return list
        }
    }
    
    var selectionVideoSelectors: [BiliVideoSelector] {
        get {
            var list = sections.compactMap {
                $0.epList.first
            }.map(BiliVideoSelector.init)
            list.enumerated().forEach {
                list[$0.offset].index = $0.offset + 1
            }
            return list
        }
    }
    
    init(object: MarshaledObject) throws {
        epList = try object.value(for: "epList")
        sections = try object.value(for: "sections")
        title = try object.value(for: "h1Title")
    }
}

struct BilibiliUrl {
    var p = 1
    var id = ""
    var urlType = UrlType.unknown
    
    var fUrl: String {
        get {
            var u = "https://www.bilibili.com/"
            
            switch urlType {
            case .video:
                u += "video/\(id)"
            case .bangumi:
                u += "bangumi/play/\(id)"
            default:
                return ""
            }
            
            if p > 1 {
                u += "?p=\(p)"
            }
            return u
        }
    }
    
    enum UrlType: String {
        case video, bangumi, unknown
    }
    
    init?(url: String) {
        guard url != "",
              let u = URL(string: url),
              u.host == "www.bilibili.com" || u.host == "bilibili.com",
              let uc = URLComponents(string: url) else {
                  return nil
              }
        
        let pcs = u.pathComponents
        
        guard let id = pcs.first(where: {
            $0.starts(with: "av")
            || $0.starts(with: "BV")
            || $0.starts(with: "ep")
            || $0.starts(with: "ss")
        }) else {
            return nil
        }
        self.id = id
        
        if pcs.contains(UrlType.video.rawValue) {
            urlType = .video
        } else if pcs.contains(UrlType.bangumi.rawValue) {
            urlType = .bangumi
        } else {
            urlType = .unknown
        }
        
        let pStr = uc.queryItems?.first {
            $0.name == "p"
        }?.value ?? "1"
        p = Int(pStr) ?? 1
    }
    
}


struct BilibiliPlayInfo: Unmarshaling {
    let videos: [VideoInfo]
    let audios: [AudioInfo]?
    let duration: Int
    
    struct VideoInfo: Unmarshaling {
        var index = -1
        let url: String
        let id: Int
        let bandwidth: Int
        var description: String = ""
        let backupUrl: [String]
        let codecs: String
        
        init(object: MarshaledObject) throws {
            url = try object.value(for: "baseUrl")
            id = try object.value(for: "id")
            bandwidth = try object.value(for: "bandwidth")
            backupUrl = (try? object.value(for: "backupUrl")) ?? []
            codecs = try object.value(for: "codecs")
        }
    }
    
    struct AudioInfo: Unmarshaling {
        let url: String
        let bandwidth: Int
        let backupUrl: [String]
        
        init(object: MarshaledObject) throws {
            url = try object.value(for: "baseUrl")
            bandwidth = try object.value(for: "bandwidth")
            backupUrl = (try? object.value(for: "backupUrl")) ?? []
        }
    }
    
    struct Durl: Unmarshaling {
        let url: String
        let backupUrls: [String]
        let length: Int
        init(object: MarshaledObject) throws {
            url = try object.value(for: "url")
            let urls: [String]? = try object.value(for: "backup_url")
            backupUrls = urls ?? []
            length = try object.value(for: "length")
        }
    }
    
    init(object: MarshaledObject) throws {
        let videos: [VideoInfo] = try object.value(for: "dash.video")
        audios = try? object.value(for: "dash.audio")
        
        let acceptQuality: [Int] = try object.value(for: "accept_quality")
        let acceptDescription: [String] = try object.value(for: "accept_description")
        
        var descriptionDic = [Int: String]()
        acceptQuality.enumerated().forEach {
            descriptionDic[$0.element] = acceptDescription[$0.offset]
        }
        
        var newVideos = [Int: VideoInfo]()
        
        var vs = videos.filter {
            switch Preferences.shared.bilibiliCodec {
            case 0:
                return $0.codecs.starts(with: "av01") || $0.codecs.starts(with: "av1")
            case 1:
                return $0.codecs.starts(with: "hev")
            default:
                return $0.codecs.starts(with: "avc")
            }
        }
        
        if vs.count == 0 {
            vs = videos.filter {
                $0.codecs.starts(with: "avc")
            }
        }
        
        vs.enumerated().forEach {
            var video = $0.element
            let des = descriptionDic[video.id] ?? "unkonwn"
            video.index = $0.offset
            video.description = des
            newVideos[video.id] = video
        }
        
        self.videos = newVideos.map {
            $0.value
        }
        duration = try object.value(for: "dash.duration")
    }
    
    func write(to yougetJson: YouGetJSON) -> YouGetJSON {
        var yougetJson = yougetJson
        yougetJson.duration = duration
        
        videos.enumerated().forEach {
            var stream = Stream(url: $0.element.url)
//            stream.quality = $0.element.bandwidth
            stream.quality = 999 - $0.element.index
            stream.src = $0.element.backupUrl
            yougetJson.streams[$0.element.description] = stream
        }
        
        if let audios = audios,
           let audio = audios.max(by: { $0.bandwidth > $1.bandwidth }) {
            yougetJson.audio = audio.url
        }
        
        return yougetJson
    }
}

struct BilibiliSimplePlayInfo: Unmarshaling {
    let duration: Int
    let descriptions: [Int: String]
    let quality: Int
    let durl: [BilibiliPlayInfo.Durl]
    
    init(object: MarshaledObject) throws {
        let acceptQuality: [Int] = try object.value(for: "accept_quality")
        let acceptDescription: [String] = try object.value(for: "accept_description")
        
        var descriptionDic = [Int: String]()
        acceptQuality.enumerated().forEach {
            descriptionDic[$0.element] = acceptDescription[$0.offset]
        }
        descriptions = descriptionDic
        
        quality = try object.value(for: "quality")
        durl = try object.value(for: "durl")
        let timelength: Int = try object.value(for: "timelength")
        duration = Int(timelength / 1000)
    }
    
    func write(to yougetJson: YouGetJSON) -> YouGetJSON {
        var yougetJson = yougetJson
        yougetJson.duration = duration
        var dic = descriptions
        if yougetJson.streams.count == 0 {
            dic = dic.filter {
                $0.key <= quality
            }
        }
        
        dic.forEach {
            var stream = yougetJson.streams[$0.value] ?? Stream(url: "")
            if $0.key == quality,
                let durl = durl.first {
                stream.url = durl.url
                stream.src = durl.backupUrls
            }
            stream.quality = $0.key
            yougetJson.streams[$0.value] = stream
        }
        
        return yougetJson
    }
}

struct BangumiPlayInfo: Unmarshaling {
    let session: String
    let isPreview: Bool
    let vipType: Int
    let durl: [BangumiPlayDurl]
    let format: String
    let supportFormats: [BangumiVideoFormat]
    let acceptQuality: [Int]
    let quality: Int
    let hasPaid: Bool
    let vipStatus: Int
    
    init(object: MarshaledObject) throws {
        session = try object.value(for: "session")
        isPreview = try object.value(for: "data.is_preview")
        vipType = try object.value(for: "data.vip_type")
        durl = try object.value(for: "data.durl")
        format = try object.value(for: "data.format")
        supportFormats = try object.value(for: "data.support_formats")
        acceptQuality = try object.value(for: "data.accept_quality")
        quality = try object.value(for: "data.quality")
        hasPaid = try object.value(for: "data.has_paid")
        vipStatus = try object.value(for: "data.vip_status")
    }
    
    struct BangumiPlayDurl: Unmarshaling {
        let size: Int
        let length: Int
        let url: String
        let backupUrl: [String]
        init(object: MarshaledObject) throws {
            size = try object.value(for: "size")
            length = try object.value(for: "length")
            url = try object.value(for: "url")
            backupUrl = try object.value(for: "backup_url")
        }
    }
    
    struct BangumiVideoFormat: Unmarshaling {
        let needLogin: Bool
        let format: String
        let description: String
        let needVip: Bool
        let quality: Int
        init(object: MarshaledObject) throws {
            needLogin = (try? object.value(for: "need_login")) ?? false
            format = try object.value(for: "format")
            description = try object.value(for: "description")
            needVip = (try? object.value(for: "need_vip")) ?? false
            quality = try object.value(for: "quality")
        }
    }
}

struct BangumiInfo: Unmarshaling {
    let title: String
    let mediaInfo: BangumiMediaInfo
    let epList: [BangumiEp]
    let epInfo: BangumiEp
    let sections: [BangumiSections]
    let isLogin: Bool
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "mediaInfo.title")
//        title = try object.value(for: "h1Title")
        mediaInfo = try object.value(for: "mediaInfo")
        epList = try object.value(for: "epList")
        epInfo = try object.value(for: "epInfo")
        sections = try object.value(for: "sections")
        isLogin = try object.value(for: "isLogin")
    }
    
    struct BangumiMediaInfo: Unmarshaling {
        let id: Int
        let ssid: Int?
        let title: String
        let squareCover: String
        let cover: String
        
        init(object: MarshaledObject) throws {
            
            id = try object.value(for: "id")
            ssid = try? object.value(for: "ssid")
            title = try object.value(for: "title")
            squareCover = "https:" + (try object.value(for: "squareCover"))
            cover = "https:" + (try object.value(for: "cover"))
        }
    }
    
    struct BangumiSections: Unmarshaling {
        let id: Int
        let title: String
        let type: Int
        let epList: [BangumiEp]
        init(object: MarshaledObject) throws {
            id = try object.value(for: "id")
            title = try object.value(for: "title")
            type = try object.value(for: "type")
            epList = try object.value(for: "epList")
        }
    }

    struct BangumiEp: Unmarshaling {
        let id: Int
//        let badge: String
//        let badgeType: Int
//        let badgeColor: String
        let epStatus: Int
        let aid: Int
        let bvid: String
        let cid: Int
        let title: String
        let longTitle: String
        let cover: String
        let duration: Int
        
        init(object: MarshaledObject) throws {
            id = try object.value(for: "id")
//            badge = try object.value(for: "badge")
//            badgeType = try object.value(for: "badgeType")
//            badgeColor = (try? object.value(for: "badgeColor")) ?? ""
            epStatus = try object.value(for: "epStatus")
            aid = try object.value(for: "aid")
            bvid = (try? object.value(for: "bvid")) ?? ""
            cid = try object.value(for: "cid")
            title = try object.value(for: "title")
            longTitle = try object.value(for: "longTitle")
            let u: String = try object.value(for: "cover")
            cover = "https:" + u
            let d: Int? = try? object.value(for: "duration")
            duration = d ?? 0 / 1000
        }
    }
}
