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

struct BilibiliVideoSelector: Unmarshaling, VideoSelector {
    
    var bvid = ""
    
    // epid
    let id: Int
    var index: Int
    let part: String
    let duration: TimeInterval
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
        index = try object.value(for: "page")
        part = try object.value(for: "part")
        let d: Double? = try? object.value(for: "duration")
        duration = d ?? 0
        title = part
        longTitle = ""
        coverUrl = nil
//        badge = nil
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

struct BangumiList: Unmarshaling {
    let title: String
    let epList: [BangumiInfo.BangumiEp]
    let sections: [BangumiInfo.BangumiSections]
    
    var epVideoSelectors: [BilibiliVideoSelector] {
        get {
            var list = epList.map(BilibiliVideoSelector.init)
            list.enumerated().forEach {
                list[$0.offset].index = $0.offset + 1
            }
            return list
        }
    }
    
    var selectionVideoSelectors: [BilibiliVideoSelector] {
        get {
            var list = sections.compactMap {
                $0.epList.first
            }.map(BilibiliVideoSelector.init)
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


class Bilibili: NSObject {
    
    enum BilibiliApiError: Error {
        case biliCSRFNotFound
    }
    
    func isLogin() -> Promise<(Bool, String)> {
        return Promise { resolver in
            AF.request("https://api.bilibili.com/x/web-interface/nav").response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data ?? Data())
                    let isLogin: Bool = try json.value(for: "data.isLogin")
                    NotificationCenter.default.post(name: .biliStatusChanged, object: nil, userInfo: ["isLogin": isLogin])
                    var name = ""
                    if isLogin {
                        name = try json.value(for: "data.uname")
                    }
                    
                    resolver.fulfill((isLogin, name))
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    func logout() -> Promise<()> {
        return Promise { resolver in
            guard let url = URL(string: "https://www.bilibili.com"),
                  let biliCSRF = HTTPCookieStorage.shared.cookies(for: url)?.first(where: { $0.name == "bili_jct" })?.value else {
                
                resolver.reject(BilibiliApiError.biliCSRFNotFound)
                return
            }
            
            AF.request("https://passport.bilibili.com/login/exit/v2", method: .post, parameters: ["biliCSRF": biliCSRF]).response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                resolver.fulfill(())
            }
        }
    }
    
    func getUid() -> Promise<Int> {
        return Promise { resolver in
            AF.request("https://api.bilibili.com/x/web-interface/nav").response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data ?? Data())
                    let uid: Int = try json.value(for: "data.mid")
                    resolver.fulfill(uid)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    func dynamicList(_ uid: Int,
                     _ action: BilibiliDynamicAction = .init😅,
                     _ dynamicID: Int = -1) -> Promise<[BilibiliCard]> {
        
        return Promise { resolver in
            var http: DataRequest? = nil
            let headers = HTTPHeaders(["referer": "https://www.bilibili.com/"])
            
            
            switch action {
            case .init😅:
                http = AF.request("https://api.vc.bilibili.com/dynamic_svr/v1/dynamic_svr/dynamic_new?uid=\(uid)&type=8", headers: headers)
            case .history:
                http = AF.request("https://api.vc.bilibili.com/dynamic_svr/v1/dynamic_svr/dynamic_history?uid=\(uid)&offset_dynamic_id=\(dynamicID)&type=8", headers: headers)
            case .new:
                http = AF.request("https://api.vc.bilibili.com/dynamic_svr/v1/dynamic_svr/dynamic_new?uid=\(uid)&current_dynamic_id=\(dynamicID)&type=8", headers: headers)
            }
            
            http?.response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data ?? Data())
                    let cards: [BilibiliCard] = try json.value(for: "data.cards")
                    resolver.fulfill(cards)
                } catch MarshalError.keyNotFound {
                    resolver.fulfill([])
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    func getPvideo(_ aid: Int) -> Promise<BilibiliPvideo> {
        return Promise { resolver in
            AF.request("https://api.bilibili.com/pvideo?aid=\(aid)").response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data ?? Data())
                    var pvideo = try BilibiliPvideo(object: json)
                    pvideo.cropImages()
                    resolver.fulfill(pvideo)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    func getVideoList(_ url: URL) -> Promise<[BilibiliVideoSelector]> {
        
        return Promise { resolver in
            var aid = -1
            var bvid = ""
            let pathComponents = url.pathComponents
            
            guard pathComponents.count >= 3 else {
                resolver.reject(VideoGetError.cantFindIdForDM)
                return
            }
            let idP = pathComponents[2]
            if idP.starts(with: "av"), let id = Int(idP.replacingOccurrences(of: "av", with: "")) {
                aid = id
            } else if idP.starts(with: "BV") {
                bvid = idP
            } else {
                resolver.reject(VideoGetError.cantFindIdForDM)
                return
            }
            
            var r: DataRequest
            if aid != -1 {
                r = AF.request("https://api.bilibili.com/x/web-interface/view?aid=\(aid)")
            } else if bvid != "" {
                r = AF.request("https://api.bilibili.com/x/web-interface/view?bvid=\(bvid)")
            } else {
                resolver.reject(VideoGetError.cantFindIdForDM)
                return
            }
            
            r.response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data ?? Data())
                    var infos: [BilibiliVideoSelector] = try json.value(for: "data.pages")
                    let bvid: String = try json.value(for: "data.bvid")
                    
                    if infos.count == 1 {
                        infos[0].title = try json.value(for: "data.title")
                    }
                    infos.enumerated().forEach {
                        infos[$0.offset].bvid = bvid
                    }
                    
                    resolver.fulfill(infos)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    func getBangumiList(_ url: URL,
                        initialStateData: Data? = nil) -> Promise<(BangumiList)> {
        return VideoGet().getBilibiliHTMLDatas(url).map {
            let stateJson: JSONObject = try JSONParser.JSONObjectWithData($0.initialStateData)
            let state = try BangumiList(object: stateJson)
            return state
        }
    }
}



