//
//  Bilibili.swift
//  iina+
//
//  Created by xjbeta on 2018/8/6.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import SwiftHTTP
import Marshal
import PromiseKit

@objc(BilibiliCard)
class BilibiliCard: NSObject, Unmarshaling {
    var aid: Int = 0
    var dynamicId: Int = 0
    @objc var title: String = ""
    @objc var pic: NSImage?
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
        let jsonStr: String = try object.value(for: "card")
        if let data = jsonStr.data(using: .utf8) {
            let json: JSONObject = try JSONParser.JSONObjectWithData(data)
            aid = try json.value(for: "aid")
    
            title = try json.value(for: "title")
            let picUrl: String = try json.value(for: "pic")
            if let url = URL(string: picUrl) {
                pic = NSImage(contentsOf: url)
            }
    
            duration = try json.value(for: "duration")
            name = try json.value(for: "owner.name")
            views = try json.value(for: "stat.view")
            videos = try json.value(for: "videos")
        }
    }
}

enum BilibiliDynamicAction {
    case `init`, new, history
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
            let url = URL(string: iamgeStr.replacingOccurrences(of: "http://", with: "https://")),
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

struct BilibiliSimpleVideoInfo: Unmarshaling, VideoSelector {
    var cid: Int = 0
    var page: Int = 0
    var part: String = ""
    var duration: TimeInterval = 0
    
    var site: LiveSupportList {
        get {
            return .bilibili
        }
    }
    var index: Int {
        get {
            return page
        }
    }
    var title: String {
        get {
            return part
        }
    }
    
    init(object: MarshaledObject) throws {
        cid = try object.value(for: "cid")
        page = try object.value(for: "page")
        part = try object.value(for: "part")
        duration = try object.value(for: "duration")
    }
}

class Bilibili: NSObject {
    
    func isLogin() -> Promise<(Bool, String)> {
        return Promise { resolver in
            HTTP.GET("https://api.bilibili.com/x/web-interface/nav") { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data)
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
            HTTP.GET("https://account.bilibili.com/login?act=exit") { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                resolver.fulfill(())
            }
        }
    }
    
    func getUid() -> Promise<Int> {
        return Promise { resolver in
            HTTP.GET("https://api.bilibili.com/x/web-interface/nav") { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data)
                    let uid: Int = try json.value(for: "data.mid")
                    resolver.fulfill(uid)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    func dynamicList(_ uid: Int,
                     _ action: BilibiliDynamicAction = .init,
                     _ dynamicID: Int = -1) -> Promise<[BilibiliCard]> {
        
        return Promise { resolver in
            var http: HTTP? = nil
            let headers = ["referer": "https://www.bilibili.com/"]
            
            switch action {
            case .init:
                http = HTTP.GET("https://api.vc.bilibili.com/dynamic_svr/v1/dynamic_svr/dynamic_new?uid=\(uid)&type=8", headers: headers)
            case .history:
                http = HTTP.GET("https://api.vc.bilibili.com/dynamic_svr/v1/dynamic_svr/dynamic_history?uid=\(uid)&offset_dynamic_id=\(dynamicID)&type=8", headers: headers)
            case .new:
                http = HTTP.GET("https://api.vc.bilibili.com/dynamic_svr/v1/dynamic_svr/dynamic_new?uid=\(uid)&current_dynamic_id=\(dynamicID)&type=8", headers: headers)
            default: break
            }
            
            http?.onFinish = { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data)
                    let cards: [BilibiliCard] = try json.value(for: "data.cards")
                    resolver.fulfill(cards)
                } catch let error {
                    resolver.reject(error)
                }
            }
            http?.run()
        }
    }
    
    func getPvideo(_ aid: Int) -> Promise<BilibiliPvideo> {
        return Promise { resolver in
            HTTP.GET("https://api.bilibili.com/pvideo?aid=\(aid)") { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data)
                    var pvideo = try BilibiliPvideo.init(object: json)
                    pvideo.cropImages()
                    resolver.fulfill(pvideo)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    func getVideoList(_ aid: Int) -> Promise<[BilibiliSimpleVideoInfo]> {
        return Promise { resolver in
            HTTP.GET("https://api.bilibili.com/x/player/pagelist?aid=\(aid)") { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                do {
                    let json: JSONObject = try JSONParser.JSONObjectWithData(response.data)
                    let infos: [BilibiliSimpleVideoInfo] = try json.value(for: "data")
                    resolver.fulfill(infos)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
}



