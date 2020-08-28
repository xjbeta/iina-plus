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
        isLiving = try object.value(for: "room.show_status") == 1 && object.value(for: "room.videoLoop") == 0
    }
}

struct DouyuVideoList: VideoSelector {
    let site = LiveSupportList.douyu
    let index: Int
    let title: String
    let roomId: Int
}

struct HuyaInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var userCover: String
    var isLiving = false
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "introduction")
        name = try object.value(for: "nick")
        userCover = try object.value(for: "avatar")
        userCover = userCover.replacingOccurrences(of: "http://", with: "https://")
        isLiving = "\(try object.any(for: "isOn"))" == "1"
    }
}


struct HuyaUrl: Unmarshaling {
    var urls: [String]
    struct StreamInfo: Unmarshaling {
        var sStreamName: String
        
        var sFlvUrl: String
        var sFlvUrlSuffix: String
        var sFlvAntiCode: String
        
        var sHlsUrl: String
        var sHlsUrlSuffix: String
        var sHlsAntiCode: String
        
        var sP2pUrl: String
        var sP2pUrlSuffix: String
        var sP2pAntiCode: String
        
        
        
        init(object: MarshaledObject) throws {
            sStreamName = try object.value(for: "sStreamName")
            
            sFlvUrl = try object.value(for: "sFlvUrl")
            sFlvUrlSuffix = try object.value(for: "sFlvUrlSuffix")
            var flvStr: String = try object.value(for: "sFlvAntiCode")
            flvStr = flvStr.replacingOccurrences(of: "&amp;", with: "&")
            sFlvAntiCode = flvStr
            
            sHlsUrl = try object.value(for: "sHlsUrl")
            sHlsUrlSuffix = try object.value(for: "sHlsUrlSuffix")
            var hlsStr: String = try object.value(for: "sHlsAntiCode")
            hlsStr = hlsStr.replacingOccurrences(of: "&amp;", with: "&")
            sHlsAntiCode = hlsStr
            
            sP2pUrl = try object.value(for: "sP2pUrl")
            sP2pUrlSuffix = try object.value(for: "sP2pUrlSuffix")
            var p2pStr: String = try object.value(for: "sP2pAntiCode")
            p2pStr = p2pStr.replacingOccurrences(of: "&amp;", with: "&")
            sP2pAntiCode = p2pStr
        }
    }
    init(object: MarshaledObject) throws {
        let streamInfos: [StreamInfo] = try object.value(for: "gameStreamInfoList")
//https://github.com/wbt5/real-url/blob/183d14aff80fee1dceee27f97ae3c816a900ce52/huya.py#L13
//        def live(e):
//        i, b = e.split('?')
//        r = i.split('/')
//        s = re.sub(r'.(flv|m3u8)', '', r[-1])
//        c = b.split('&', 3)
//        c = [i for i in c if i != '']
//        n = {i.split('=')[0]: i.split('=')[1] for i in c}
//        fm = urllib.parse.unquote(n['fm'])
//        u = base64.b64decode(fm).decode('utf-8')
//        p = u.split('_')[0]
//        f = str(int(time.time() * 1e7))
//        l = n['wsTime']
//        t = '0'
//        h = '_'.join([p, t, s, f, l])
//        m = hashlib.md5(h.encode('utf-8')).hexdigest()
//        y = c[-1]
//        url = "{}?wsSecret={}&wsTime={}&u={}&seqid={}&{}".format(i, m, l, t, f, y)
//        return url
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
            
            
            
            guard let fm = d["fm"]?.removingPercentEncoding, let fmData = Data(base64Encoded: fm) else { return nil }
            let u = String(data: fmData, encoding: .utf8)
            guard let p = u?.components(separatedBy: "_").first else { return nil }
            
            let f = "\(Int(Date().timeIntervalSince1970 * 10000000))"
            guard let l = d["wsTime"] else { return nil }
            let t = "0"
            let h = [p, t, s, f, l].joined(separator: "_")
            
            let m = h.md5()
            guard let y = b.split(separator: "&", maxSplits: 3, omittingEmptySubsequences: false).map(String.init).last else { return nil }
            let url = "\(i)?wsSecret=\(m)&wsTime=\(l)&u=\(t)&seqid=\(f)&\(y)"
            return url
        }
        
        urls =
            streamInfos.map {
            $0.sFlvUrl + "/" + $0.sStreamName + "." + $0.sFlvUrlSuffix + "?" + $0.sFlvAntiCode
            }.compactMap {
                urlFormatter($0)
        }
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

struct BilibiliVideo: Unmarshaling {
    var videos: [String: String]
    var audios: [String]
    
    
    struct DashObject: Unmarshaling {
        var id: Int
        var url: String
        var backupUrl: [String]
        init(object: MarshaledObject) throws {
            id = try object.value(for: "id")
            url = try object.value(for: "baseUrl")
            backupUrl = try object.value(for: "backupUrl")
        }
    }
    
    init(object: MarshaledObject) throws {
        
        let acceptDescription: [String] = try object.value(for: "accept_description")
        let acceptQuality: [Int] = try object.value(for: "accept_quality")
        
        let video: [DashObject] = try object.value(for: "dash.video")
        let audio: [DashObject] = try object.value(for: "dash.audio")
        
        var videos: [String: String] = [:]
        
        video.forEach {
            guard let index = acceptQuality.firstIndex(of: $0.id),
                index > 0,
                index < acceptDescription.count else {
                    return
            }
            let des = acceptDescription[index]
            videos[des] = $0.url
        }
        self.videos = videos
        audios = audio.map {
            $0.url
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
    
    struct LangPlayVideo: Unmarshaling, VideoSelector {
        var site: LiveSupportList {
            return .langPlay
        }
        var index: Int
        var title: String
        var url: String
        init(object: MarshaledObject) throws {
            title = try object.value(for: "title")
            index = try object.value(for: "id")
            url = try object.value(for: "video")
        }
    }
    
    var streamItems: [LangPlayVideo]
    
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
