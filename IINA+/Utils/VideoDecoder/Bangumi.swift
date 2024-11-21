//
//  Bangumi.swift
//  IINA+
//
//  Created by xjbeta on 2024/11/19.
//  Copyright © 2024 xjbeta. All rights reserved.
//

import Foundation
import Alamofire
import Marshal

actor Bangumi: SupportSiteProtocol {
    
    let biliShare = BilibiliShare()
    
    struct BangumiID {
        let epId: Int
        let seasonId: Int
    }
    
    func liveInfo(_ url: String) async throws -> any LiveInfo {
        let list = try await getBangumiList(url)
        
        guard let ep = list.episodes.first else { throw VideoGetError.notFountData }
        
        var info = BilibiliInfo()
        info.site = .bangumi
        info.title = ep.titles()
        info.cover = ep.cover
        info.isLiving = true
        return info
    }
    
    func decodeUrl(_ url: String) async throws -> YouGetJSON {
        try await getBangumi(url)
    }
    
    func getBangumi(_ url: String) async throws -> YouGetJSON {
        await biliShare.setBilibiliQuality()
        
        let json = try await bilibiliPrepareID(url)
        
        return try await biliShare.bilibiliPlayUrl(yougetJson: json, true)
    }
    
    func bilibiliPrepareID(_ url: String) async throws -> YouGetJSON {
        guard let bUrl = BilibiliUrl(url: url) else {
            throw VideoGetError.invalidLink
        }
        var json = YouGetJSON(rawUrl: url)
        
        json.site = .bangumi
        let list = try await getBangumiList(url)
        var ep: BangumiEpList.BangumiEp? {
            if bUrl.id.prefix(2) == "ss" {
                return list.episodes.first
            } else {
                return list.episodes.first(where: { $0.id == Int(bUrl.id.dropFirst(2)) })
            }
        }
        guard let s = ep else { throw VideoGetError.notFountData }

        json.bvid = s.bvid
        json.id = s.cid
        if list.episodes.count == 1 {
            json.title = list.episodes.first?.title ?? list.episodes.first?.longTitle ?? ""
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
    
    func getBilibiliHTMLDatas(_ url: String, isBangumi: Bool = false) async throws -> (playInfoData: Data, initialStateData: Data, bangumiData: Data) {
        let headers = HTTPHeaders(["Referer": "https://www.bilibili.com/",
                                   "User-Agent": biliShare.bangumiUA])

        let re = try await AF.request(url, headers: headers).serializingString().value
        
        let playinfoStrig = {
            var s = re.subString(from: "window.__playinfo__=", to: "</script>")
            if s == "" {
                s = re.subString(from: "const playurlSSRData = ", to: "\n")
            }
            return s
        }()
        
        let playInfoData = playinfoStrig.data(using: .utf8) ?? Data()
        let initialStateData = re.subString(from: "window.__INITIAL_STATE__=", to: ";(function()").data(using: .utf8) ?? Data()
        let bangumiData = re.subString(from: "<script id=\"__NEXT_DATA__\" type=\"application/json\">", to: "</script>").data(using: .utf8) ?? Data()
        
        return (playInfoData, initialStateData, bangumiData)
    }
    
    
    func getBangumiId(_ url: String) async throws -> BangumiID {
        let data = try await getBilibiliHTMLDatas(url, isBangumi: true).initialStateData
        let json: JSONObject = try JSONParser.JSONObjectWithData(data)
        let epid: Int = try json.value(for: "epInfo.ep_id")
        let sid: Int = try json.value(for: "mediaInfo.season_id")
        return BangumiID(epId: epid, seasonId: sid)
    }
    
    func getBangumiList(_ url: String, ids: BangumiID? = nil) async throws -> BangumiEpList {
        var bid: BangumiID! = ids
        if bid == nil {
            bid = try await getBangumiId(url)
        }
        
        let u = "https://api.bilibili.com/pgc/view/web/ep/list?season_id=\(bid.seasonId)"
        let data = try await AF.request(u).serializingData().value
        let json: JSONObject = try JSONParser.JSONObjectWithData(data)
        let list = try BangumiEpList(object: json)
        return list
    }
}

struct BangumiEpList: Unmarshaling {
    let episodes: [BangumiEp]
    let section: [BangumiSections]
    
    struct BangumiEp: Unmarshaling {
        let id: Int
        let aid: Int
        let bvid: String
        let cid: Int
        let title: String
        let longTitle: String
        let cover: String
        let duration: Int
        let fullTitle: String
        
        init(object: MarshaledObject) throws {
            id = try object.value(for: "id")
            aid = try object.value(for: "aid")
            bvid = (try? object.value(for: "bvid")) ?? ""
            cid = try object.value(for: "cid")
            title = try object.value(for: "title")
            longTitle = try object.value(for: "long_title")
            let u: String = try object.value(for: "cover")
            cover = u.https()
            
            let d: Int? = try? object.value(for: "duration")
            duration = d ?? 0 / 1000
            
            fullTitle = try object.value(for: "share_copy")
        }
        
        func titles() -> String {
            if fullTitle.isEmpty {
                return [title, longTitle].filter({ $0 != "" }).joined(separator: " ")
            } else {
                return fullTitle
            }
        }
    }
    
    struct BangumiSections: Unmarshaling {
        let id: Int
        let title: String
        let type: Int
        let episodes: [BangumiEp]
        
        init(object: MarshaledObject) throws {
            id = try object.value(for: "id")
            title = try object.value(for: "title")
            type = try object.value(for: "type")
            episodes = try object.value(for: "episodes")
        }
    }
    
    init(object: MarshaledObject) throws {
        episodes = try object.value(for: "result.episodes")
        section = (try? object.value(for: "result.section")) ?? []
    }
    
    var epVideoSelectors: [BiliVideoSelector] {
        get {
            var list = episodes.map(BiliVideoSelector.init)
            list.enumerated().forEach {
                list[$0.offset].index = $0.offset + 1
            }
            return list
        }
    }
}



/*
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
*/
