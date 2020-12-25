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
    var userCover: String { get }
    var isLiving: Bool { get }
}

protocol VideoSelector {
    var site: LiveSupportList { get }
    var index: Int { get }
    var title: String { get }
    var id: Int { get }
    var coverUrl: URL? { get }
}

struct BilibiliInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var userCover: String = ""
    var isLiving = false
    var roomId: Int = -1
    
    init() {
    }
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "title")
        name = try object.value(for: "info.uname")
        userCover = try object.value(for: "info.face")
        isLiving = "\(try object.any(for: "live_status"))" == "1"
    }
}


struct DouyuInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var userCover: String
    var isLiving = false
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "room.room_name")
        name = try object.value(for: "room.nickname")
        userCover = try object.value(for: "room.avatar.big")
        isLiving = "\(try object.any(for: "room.show_status"))" == "1"
//        isLiving = try object.value(for: "room.show_status") == 1 && object.value(for: "room.videoLoop") != 0
    }
}

struct DouyuVideoSelector: VideoSelector {
    let site = LiveSupportList.douyu
    let index: Int
    let title: String
    let id: Int
    let coverUrl: URL?
}

struct HuyaInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var userCover: String
    var isLiving = false
    var rid: Int
    
    var isSeeTogetherRoom = false
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "introduction")
        name = try object.value(for: "nick")
        userCover = try object.value(for: "avatar")
        userCover = userCover.replacingOccurrences(of: "http://", with: "https://")
        isLiving = "\(try object.any(for: "isOn"))" == "1"
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
        
        init(object: MarshaledObject) throws {
            sDisplayName = try object.value(for: "sDisplayName")
            iBitRate = try object.value(for: "iBitRate")
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
    var userCover: String
    var isLiving = false
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "title")
        name = try object.value(for: "nick")
        userCover = try object.value(for: "avatar")
        isLiving = "\(try object.any(for: "status"))" == "2"
    }
}

struct LongZhuInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var userCover: String
    var isLiving = false
    
    init(object: MarshaledObject) throws {
        if let title: String = try object.value(for: "live.title") {
            self.title = title
            isLiving = true
        } else {
            self.title = try object.value(for: "defaultTitle")
            isLiving = false
        }
        name = try object.value(for: "username")
        userCover = try object.value(for: "avatar")
        userCover = userCover.replacingOccurrences(of: "http://", with: "https://")
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
    var userCover: String
    var isLiving = false
    var pid = ""
    var anchorId: Int
    var lastTm = 0
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "state.live-info.liveInfo.videoInfo.title")
        name = try object.value(for: "state.live-info.liveInfo.profileInfo.nickName")
        userCover = try object.value(for: "state.live-info.liveInfo.profileInfo.faceUrl")
        userCover = userCover.replacingOccurrences(of: "http://", with: "https://")
        let liveStatus: Int = try object.value(for: "state.live-info.liveInfo.profileInfo.isLive")
        isLiving = liveStatus == 1
        pid = try object.value(for: "state.live-info.liveInfo.videoInfo.pid")
        anchorId = try object.value(for: "state.live-info.liveInfo.videoInfo.anchorId")
    }
}



// MARK: - Bilibili

struct BilibiliPlayInfo: Unmarshaling {
    let videos: [VideoInfo]
    let audios: [AudioInfo]?
    
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
        init(object: MarshaledObject) throws {
            url = try object.value(for: "url")
            backupUrls = try object.value(for: "backup_url")
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
    }
}

struct BilibiliSimplePlayInfo: Unmarshaling {
    let url: String?
    var description: String = ""
    
    init(object: MarshaledObject) throws {
        let durl: [BilibiliPlayInfo.Durl] = try object.value(for: "durl")
        url = durl.first?.url
        
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

// MARK: - LangPlay

struct LangPlayInfo: Unmarshaling, LiveInfo {
    var title: String
    var name: String
    var userCover: String
    var isLiving: Bool
    
    var roomID: String
    var liveID: String
    var liveKey: String
    
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
        userCover = try object.value(for: "data.live_info.avatar")
        userCover = userCover.replacingOccurrences(of: "http://", with: "https://")
        let liveStatus: Int = try object.value(for: "data.live_info.live_status")
        isLiving = liveStatus == 1
        streamItems = try object.value(for: "data.live_info.stream_items")
        
        liveID = try object.value(for: "data.live_info.live_id")
        roomID = try object.value(for: "data.live_info.room_id")
        liveKey = try object.value(for: "data.live_info.live_key")
    }
}
