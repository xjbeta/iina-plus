//
//  VideoGetStructs.swift
//  iina+
//
//  Created by xjbeta on 2018/11/1.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import Marshal

protocol LiveInfo {
    var title: String { get }
    var name: String { get }
    var avatar: String { get }
    var cover: String { get }
    var isLiving: Bool { get }
    
    var site: SupportSites { get }
}

protocol VideoSelector {
    var site: SupportSites { get }
    var index: Int { get }
    var title: String { get }
    var id: Int { get }
    var coverUrl: URL? { get }
}

struct BilibiliInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var avatar: String = ""
    var isLiving = false
    var cover: String = ""
    
    var site: SupportSites = .bilibili
    
    init() {
    }
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "title")
        name = try object.value(for: "info.uname")
        avatar = try object.value(for: "info.face")
        isLiving = "\(try object.any(for: "live_status"))" == "1"
    }
}




// MARK: - Bilibili

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
        
        init(object: MarshaledObject) throws {
            url = try object.value(for: "baseUrl")
            id = try object.value(for: "id")
            bandwidth = try object.value(for: "bandwidth")
            backupUrl = (try? object.value(for: "backupUrl")) ?? []
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
        
        var newVideos = [VideoInfo]()
        
        videos.enumerated().forEach {
            var video = $0.element
            let des = descriptionDic[video.id] ?? "unkonwn"
            video.index = $0.offset
//             ignore low bandwidth video
            if !newVideos.map({ $0.id }).contains(video.id) {
                video.description = des
                newVideos.append(video)
            }
        }
        self.videos = newVideos
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
