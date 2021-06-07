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
    
    var site: LiveSupportList { get }
}

protocol VideoSelector {
    var site: LiveSupportList { get }
    var index: Int { get }
    var title: String { get }
    var id: Int { get }
    var coverUrl: URL? { get }
}

struct BiliLiveInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var avatar: String = ""
    var isLiving = false
    var roomId: Int = -1
    var cover: String = ""
    
    var site: LiveSupportList = .biliLive
    
    init() {
    }
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "title")
        name = try object.value(for: "info.uname")
        avatar = try object.value(for: "info.face")
        isLiving = "\(try object.any(for: "live_status"))" == "1"
    }
}

struct BiliLivePlayUrl: Unmarshaling {
    let currentQuality: Int
    let acceptQuality: [String]
    let currentQn: Int
    let qualityDescription: [QualityDescription]
    let durl: [Durl]
    
    struct QualityDescription: Unmarshaling {
        let qn: Int
        let desc: String
        init(object: MarshaledObject) throws {
            qn = try object.value(for: "qn")
            desc = try object.value(for: "desc")
        }
    }
    
    struct Durl: Unmarshaling {
        var url: String
        init(object: MarshaledObject) throws {
            url = try object.value(for: "url")
        }
    }
    
    init(object: MarshaledObject) throws {
        currentQuality = try object.value(for: "data.current_quality")
        acceptQuality = try object.value(for: "data.accept_quality")
        currentQn = try object.value(for: "data.current_qn")
        qualityDescription = try object.value(for: "data.quality_description")
        durl = try object.value(for: "data.durl")
    }
}

struct BilibiliInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var avatar: String = ""
    var isLiving = false
    var cover: String = ""
    
    var site: LiveSupportList = .bilibili
    
    init() {
    }
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "title")
        name = try object.value(for: "info.uname")
        avatar = try object.value(for: "info.face")
        isLiving = "\(try object.any(for: "live_status"))" == "1"
    }
}

struct DouyuInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var avatar: String
    var isLiving = false
    var cover: String = ""
    var site: LiveSupportList = .douyu
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "room.room_name")
        name = try object.value(for: "room.nickname")
        avatar = try object.value(for: "room.avatar.big")
        isLiving = "\(try object.any(for: "room.show_status"))" == "1"
//        isLiving = try object.value(for: "room.show_status") == 1 && object.value(for: "room.videoLoop") != 0
        
        cover = try object.value(for: "room.room_pic")
    }
}

struct DouyuVideoSelector: VideoSelector {
    let site = LiveSupportList.douyu
    let index: Int
    let title: String
    let id: Int
    let coverUrl: URL?
}

struct DouyuH5Play: Unmarshaling {
    let roomId: Int
    let rtmpUrl: String
    let rtmpLive: String
    let rate: Int
    let multirates: [Rate]
    
    let url: String
    
    struct Rate: Unmarshaling {
        let name: String
        let rate: Int
        let highBit: Int
        let bit: Int
        
        init(object: MarshaledObject) throws {
            name = try object.value(for: "name")
            rate = try object.value(for: "rate")
            highBit = try object.value(for: "highBit")
            bit = try object.value(for: "bit")
        }
    }
    
    init(object: MarshaledObject) throws {
        roomId = try object.value(for: "data.room_id")
        rtmpUrl = try object.value(for: "data.rtmp_url")
        rtmpLive = try object.value(for: "data.rtmp_live")
        multirates = try object.value(for: "data.multirates")
        rate = try object.value(for: "data.rate")
        
        url = rtmpUrl + "/" + rtmpLive
    }
}

struct HuyaInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var avatar: String
    var isLiving = false
    var rid: Int
    var cover: String = ""
    var site: LiveSupportList = .huya
    
    var isSeeTogetherRoom = false
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "introduction")
        name = try object.value(for: "nick")
        avatar = try object.value(for: "avatar")
        avatar = avatar.replacingOccurrences(of: "http://", with: "https://")
        isLiving = "\(try object.any(for: "isOn"))" == "1"
        cover = try object.value(for: "screenshot")
        cover = cover.replacingOccurrences(of: "http://", with: "https://")
        
        let str: String = try object.value(for: "profileRoom")
        rid = Int(str) ?? -1
        let gameHostName: String = try object.value(for: "gameHostName")
        
        isSeeTogetherRoom = gameHostName == "seeTogether"
    }
}

struct HuyaStream: Unmarshaling {
    var data: [HuyaUrl]
    var vMultiStreamInfo: [StreamInfo]
    
    struct StreamInfo: Unmarshaling {
        var sDisplayName: String
        var iBitRate: Int
        var iHEVCBitRate: Int
        
        init(object: MarshaledObject) throws {
            sDisplayName = try object.value(for: "sDisplayName")
            iBitRate = try object.value(for: "iBitRate")
            iHEVCBitRate = try object.value(for: "iHEVCBitRate")
        }
    }
    
    struct HuyaUrl: Unmarshaling {
        var urls: [String] = []
        var urlsBak: [String] = []
        
        struct StreamInfo: Unmarshaling {
            var sStreamName: String
            var sFlvUrl: String
            var newCFlvAntiCode: String
            var sFlvAntiCode: String
            
            init(object: MarshaledObject) throws {
                sStreamName = try object.value(for: "sStreamName")
                sFlvUrl = try object.value(for: "sFlvUrl")
                newCFlvAntiCode = try object.value(for: "newCFlvAntiCode")
                sFlvAntiCode = try object.value(for: "sFlvAntiCode")
            }
        }
        init(object: MarshaledObject) throws {
            func urlFormatter(_ u: String) -> String? {
                let ib = u.split(separator: "?").map(String.init)
                guard ib.count == 2 else { return nil }
                let i = ib[0]
                let b = ib[1]
                guard let s = i.components(separatedBy: "/").last?.subString(to: ".") else { return nil }
                let d = b.components(separatedBy: "&").reduce([String: String]()) { (re, str) -> [String: String] in
                    var r = re
                    let kv = str.components(separatedBy: "=")
                    guard kv.count == 2 else { return r }
                    r[kv[0]] = kv[1]
                    return r
                }
                
                let n = "\(Int(Date().timeIntervalSince1970 * 10000000))"
                
                guard let fm = d["fm"]?.removingPercentEncoding,
                      let fmData = Data(base64Encoded: fm),
                      var u = String(data: fmData, encoding: .utf8),
                      let l = d["wsTime"] else { return nil }
                
                u = u.replacingOccurrences(of: "$0", with: "0")
                u = u.replacingOccurrences(of: "$1", with: s)
                u = u.replacingOccurrences(of: "$2", with: n)
                u = u.replacingOccurrences(of: "$3", with: l)
            
                let m = u.md5()

                let y = b.split(separator: "&").map(String.init).filter {
                    $0.contains("txyp=") ||
                        $0.contains("fs=") ||
                        $0.contains("sphdcdn=") ||
                        $0.contains("sphdDC=") ||
                        $0.contains("sphd=")
                }.joined(separator: "&")
                
                let url = "\(i)?wsSecret=\(m)&wsTime=\(l)&seqid=\(n)&\(y)&ratio=0&u=0&t=100&sv="
                return url
            }
            
            let streamInfos: [StreamInfo] = try object.value(for: "gameStreamInfoList")
            
            
            urls = streamInfos.compactMap { i -> String? in
                let u = i.sFlvUrl + "/" + i.sStreamName + ".flv?" + i.newCFlvAntiCode + "&ratio=0"
                return u
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "http://", with: "https://")
                    .replacingOccurrences(of: "https://tx.flv.huya.com/huyalive/", with: "https://tx.flv.huya.com/src/")
            }
            
            
            urlsBak = streamInfos.compactMap { i -> String? in
                let u = i.sFlvUrl + "/" + i.sStreamName + ".flv?" + i.sFlvAntiCode
                return urlFormatter(u.replacingOccurrences(of: "&amp;", with: "&"))?.replacingOccurrences(of: "http://", with: "https://")
            }
        }
    }
    
    init(object: MarshaledObject) throws {
        data = try object.value(for: "data")
        vMultiStreamInfo = try object.value(for: "vMultiStreamInfo")
    }
    
}

struct QuanMinInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var avatar: String
    var isLiving = false
    var cover: String = ""
    
    var site: LiveSupportList = .quanmin
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "title")
        name = try object.value(for: "nick")
        avatar = try object.value(for: "avatar")
        isLiving = "\(try object.any(for: "status"))" == "2"
    }
}

struct LongZhuInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var avatar: String
    var isLiving = false
    var cover: String = ""
    var site: LiveSupportList = .longzhu
    
    init(object: MarshaledObject) throws {
        if let title: String = try object.value(for: "live.title") {
            self.title = title
            isLiving = true
        } else {
            self.title = try object.value(for: "defaultTitle")
            isLiving = false
        }
        name = try object.value(for: "username")
        avatar = try object.value(for: "avatar")
        avatar = avatar.replacingOccurrences(of: "http://", with: "https://")
    }
}


struct EgameUrl: Unmarshaling {
    var playUrl: String
    var desc: String
    var levelType: Int
    
    init(object: MarshaledObject) throws {
        playUrl = try object.value(for: "playUrl")
        desc = try object.value(for: "desc")
        levelType = try object.value(for: "levelType")
    }
}

struct EgameInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var avatar: String
    var isLiving = false
    var pid = ""
    var anchorId: Int
    var lastTm = 0
    
    var site: LiveSupportList = .eGame
    
    var cover: String = ""
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "state.live-info.liveInfo.videoInfo.title")
        name = try object.value(for: "state.live-info.liveInfo.profileInfo.nickName")
        avatar = try object.value(for: "state.live-info.liveInfo.profileInfo.faceUrl")
        avatar = avatar.replacingOccurrences(of: "http://", with: "https://")
        let liveStatus: Int = try object.value(for: "state.live-info.liveInfo.profileInfo.isLive")
        isLiving = liveStatus == 1
        pid = try object.value(for: "state.live-info.liveInfo.videoInfo.pid")
        anchorId = try object.value(for: "state.live-info.liveInfo.videoInfo.anchorId")
        cover = try object.value(for: "state.live-info.liveBaseInfo.programInfo.highCoverUrl")
        cover = cover.replacingOccurrences(of: "http://", with: "https://")
    }
}



// MARK: - Bilibili

struct BilibiliPlayInfo: Unmarshaling {
    let videos: [VideoInfo]
    let audios: [AudioInfo]?
    let duration: Int
    
    struct VideoInfo: Unmarshaling {
        let url: String
        let id: Int
        let bandwidth: Int
        var description: String = ""
        init(object: MarshaledObject) throws {
            url = try object.value(for: "baseUrl")
            id = try object.value(for: "id")
            bandwidth = try object.value(for: "bandwidth")
        }
    }
    
    struct AudioInfo: Unmarshaling {
        let url: String
        let bandwidth: Int
        init(object: MarshaledObject) throws {
            url = try object.value(for: "baseUrl")
            bandwidth = try object.value(for: "bandwidth")
        }
    }
    
    struct Durl: Unmarshaling {
        let url: String
        let backupUrls: [String]
        let length: Int
        init(object: MarshaledObject) throws {
            url = try object.value(for: "url")
            backupUrls = try object.value(for: "backup_url")
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
        
        videos.forEach {
            var video = $0
            let des = descriptionDic[$0.id] ?? "unkonwn"
            
            // ignore low bandwidth video
            if !newVideos.map({ $0.id }).contains($0.id) {
                video.description = des
                newVideos.append(video)
            }
        }
        self.videos = newVideos
        duration = try object.value(for: "dash.duration")
    }
}

struct BilibiliSimplePlayInfo: Unmarshaling {
    let url: String?
    var description: String = ""
    var duration: Int?
    
    init(object: MarshaledObject) throws {
        let durl: [BilibiliPlayInfo.Durl] = try object.value(for: "durl")
        url = durl.first?.url
        
        if let l = durl.first?.length {
            duration = l / 1000
        }
        
        let acceptQuality: [Int] = try object.value(for: "accept_quality")
        let acceptDescription: [String] = try object.value(for: "accept_description")
        
        var descriptionDic = [Int: String]()
        acceptQuality.enumerated().forEach {
            descriptionDic[$0.element] = acceptDescription[$0.offset]
        }
        
        let quality: Int = try object.value(for: "quality")
        
        description = descriptionDic[quality] ?? "unkonwn"
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
        let badge: String
        let badgeType: Int
        let badgeColor: String
        let epStatus: Int
        let aid: Int
        let bvid: String
        let cid: Int
        let title: String
        let longTitle: String
        let cover: String
        
        init(object: MarshaledObject) throws {
            id = try object.value(for: "id")
            badge = try object.value(for: "badge")
            badgeType = try object.value(for: "badgeType")
            badgeColor = (try? object.value(for: "badgeColor")) ?? ""
            epStatus = try object.value(for: "epStatus")
            aid = try object.value(for: "aid")
            bvid = (try? object.value(for: "bvid")) ?? ""
            cid = try object.value(for: "cid")
            title = try object.value(for: "title")
            longTitle = try object.value(for: "longTitle")
            let u: String = try object.value(for: "cover")
            cover = "https:" + u
        }
    }
}


// MARK: - LangPlay

struct LangPlayInfo: Unmarshaling, LiveInfo {
    var title: String
    var name: String
    var avatar: String
    var isLiving: Bool
    var cover: String = ""
    
    var roomID: String
    var liveID: String
    var liveKey: String
    
    var site: LiveSupportList = .langPlay
    
    struct LangPlayVideoSelector: Unmarshaling, VideoSelector {
        let id: Int
        let coverUrl: URL?
        let site = LiveSupportList.langPlay
        let index: Int
        let title: String
        let url: String
        init(object: MarshaledObject) throws {
            title = try object.value(for: "title")
            index = try object.value(for: "id")
            url = try object.value(for: "video")
            id = -1
            coverUrl = nil
        }
    }
    
    var streamItems: [LangPlayVideoSelector]
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "data.live_info.room_title")
        name = try object.value(for: "data.live_info.nickname")
        avatar = try object.value(for: "data.live_info.avatar")
        avatar = avatar.replacingOccurrences(of: "http://", with: "https://")
        let liveStatus: Int = try object.value(for: "data.live_info.live_status")
        isLiving = liveStatus == 1
        streamItems = try object.value(for: "data.live_info.stream_items")
        
        liveID = try object.value(for: "data.live_info.live_id")
        roomID = try object.value(for: "data.live_info.room_id")
        liveKey = try object.value(for: "data.live_info.live_key")
        
        cover = "https://play-web-assets.lang.live/public/live/screenshot/" + liveID   
    }
}

// MARK: - CC163

struct CC163Info: Unmarshaling, LiveInfo {
    var title: String
    var name: String
    var avatar: String
    var cover: String
    var isLiving: Bool
    var ccid: String
    var site: LiveSupportList
    
    init(object: MarshaledObject) throws {
        site = .cc163
        title = try object.value(for: "props.pageProps.roomInfoInitData.live.title")
        name = try object.value(for: "props.pageProps.roomInfoInitData.micfirst.nickname")
        avatar = try object.value(for: "props.pageProps.roomInfoInitData.micfirst.purl")
        avatar = avatar.replacingOccurrences(of: "http://", with: "https://")
        cover = avatar
        let living: Bool? = try? object.value(for: "props.pageProps.roomInfoInitData.is_show_live_rcm")
        
        ccid = try object.value(for: "query.ccid")
        
        isLiving = living ?? false
    }
}

struct CC163ZTInfo {
    var name: String = ""
    var ccid: String = ""
    var channel: String = ""
    var cid: String = ""
    var index: String = ""
    var roomid: String = ""
    var isLiving: Bool = false
}

struct CC163VideoSelector: VideoSelector {
    let site = LiveSupportList.cc163
    let index: Int
    let title: String
    let ccid: String
    let isLiving: Bool
    let url: String
    let id: Int = -1
    let coverUrl: URL? = nil
}

struct CC163ChannelInfo: Unmarshaling, LiveInfo {
    var title: String
    var name: String
    var avatar: String
    var cover: String
    var isLiving: Bool
    var site: LiveSupportList
    
    var ccid: Int

    init(object: MarshaledObject) throws {
        site = .cc163
        title = try object.value(for: "title")
        name = try object.value(for: "nickname")
        cover = try object.value(for: "cover")
        cover = cover.replacingOccurrences(of: "http://", with: "https://")
        
        if let nolive: Int = try? object.value(for: "nolive"),
           nolive == 1 {
            ccid = try object.value(for: "roomid")
            avatar = cover
            isLiving = false
        } else {
            ccid = try object.value(for: "ccid")
            avatar = try object.value(for: "purl")
            avatar = avatar.replacingOccurrences(of: "http://", with: "https://")
            isLiving = true
        }
    }
}
