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

struct BiliLiveInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var avatar: String = ""
    var isLiving = false
    var roomId: Int = -1
    var cover: String = ""
    
    var site: SupportSites = .biliLive
    
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
    let qualityDescriptions: [QualityDescription]
    let streams: [BiliLiveStream]

    struct QualityDescription: Unmarshaling {
        let qn: Int
        let desc: String
        init(object: MarshaledObject) throws {
            qn = try object.value(for: "qn")
            desc = try object.value(for: "desc")
        }
    }
    
    struct BiliLiveStream: Unmarshaling {
        let protocolName: String
        let formats: [Format]
        init(object: MarshaledObject) throws {
            protocolName = try object.value(for: "protocol_name")
            formats = try object.value(for: "format")
        }
    }
    
    struct Format: Unmarshaling {
        let formatName: String
        let codecs: [Codec]
        init(object: MarshaledObject) throws {
            formatName = try object.value(for: "format_name")
            codecs = try object.value(for: "codec")
        }
    }
    
    struct Codec: Unmarshaling {
        let codecName: String
        let currentQn: Int
        let acceptQns: [Int]
        let baseUrl: String
        let urlInfos: [UrlInfo]
        init(object: MarshaledObject) throws {
            codecName = try object.value(for: "codec_name")
            currentQn = try object.value(for: "current_qn")
            acceptQns = try object.value(for: "accept_qn")
            baseUrl = try object.value(for: "base_url")
            urlInfos = try object.value(for: "url_info")
        }
        
        func urls() -> [String] {
            urlInfos.map {
                $0.host + baseUrl + $0.extra
            }
        }
    }
    
    struct UrlInfo: Unmarshaling {
        let host: String
        let extra: String
        let streamTtl: Int
        init(object: MarshaledObject) throws {
            host = try object.value(for: "host")
            extra = try object.value(for: "extra")
            streamTtl = try object.value(for: "stream_ttl")
        }
    }
    
    init(object: MarshaledObject) throws {
        qualityDescriptions = try object.value(for: "data.playurl_info.playurl.g_qn_desc")
        streams = try object.value(for: "data.playurl_info.playurl.stream")
    }
    
    func write(to yougetJson: YouGetJSON) -> YouGetJSON {
        var json = yougetJson
        
        let codecs = streams.flatMap {
            $0.formats.flatMap {
                $0.codecs
            }
        }
        
//        if let codec = codecs.last(where: { $0.codecName == "hevc" }) ?? codecs.first {
        if let codec = codecs.first {
            qualityDescriptions.filter {
                codec.acceptQns.contains($0.qn)
            }.forEach {
                var s = Stream(url: "")
                s.quality = $0.qn
                if codec.currentQn == $0.qn {
                    var urls = codec.urls()
                    s.url = urls.removeFirst()
                    s.src = urls
                }
                json.streams[$0.desc] = s
            }
        }
        
        return json
    }
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

struct DouyuInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var avatar: String
    var isLiving = false
    var cover: String = ""
    var site: SupportSites = .douyu
    
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
    let site = SupportSites.douyu
    let index: Int
    let title: String
    let id: Int
    let coverUrl: URL?
}

struct DouyuEventRoom: Unmarshaling {
    let onlineRoomId: String
    let text: String
    init(object: MarshaledObject) throws {
        onlineRoomId = try object.value(for: "props.onlineRoomId")
        text = try object.value(for: "props.text")
    }
}

struct DouyuH5Play: Unmarshaling {
    let roomId: Int
    let rtmpUrl: String
    let rtmpLive: String
    let rate: Int
    let multirates: [Rate]
    
    let flvUrl: String
    let xsString: String?
    let cdnUrl: String?
    
    var p2pUrls = [String]()
    
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
    
    struct P2pMeta: Unmarshaling {
        let domain: String
        let delay: Int
        let secret: String
        let time: String
        
        init(object: MarshaledObject) throws {
            domain = try object.value(for: "xp2p_domain")
            delay = try object.value(for: "xp2p_txDelay")
            secret = try object.value(for: "xp2p_txSecret")
            time = try object.value(for: "xp2p_txTime")
        }
    }
    
    init(object: MarshaledObject) throws {
        roomId = try object.value(for: "data.room_id")
        rtmpUrl = try object.value(for: "data.rtmp_url")
        rtmpLive = try object.value(for: "data.rtmp_live")
        multirates = try object.value(for: "data.multirates")
        rate = try object.value(for: "data.rate")
        
        flvUrl = rtmpUrl + "/" + rtmpLive
        
        guard let meta: P2pMeta = try? object.value(for: "data.p2pMeta") else {
            xsString = nil
            cdnUrl = nil
            return
        }
        
        var newRL = rtmpLive.replacingOccurrences(of: "flv", with: "xs").split(separator: "&").map(String.init)
        
        newRL.append(contentsOf: [
            "delay=\(meta.delay)",
            "txSecret=\(meta.secret)",
            "txTime=\(meta.time)",
//            "playid=1646460800000-3082600000",
            "uuid=\(UUID().uuidString)"
        ])
        
        xsString = "\(meta.domain)/live/" + newRL.joined(separator: "&")
        cdnUrl = "https://\(meta.domain)/\(rtmpLive.subString(to: ".")).xs"
    }
    
    mutating func initP2pUrls(_ urls: [String]) {
        guard let str = xsString else { return }
        p2pUrls = urls.map {
            "https://\($0)/" + str
        }
    }
}

struct HuyaInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var avatar: String
    var isLiving = false
    var rid: Int
    var cover: String = ""
    var site: SupportSites = .huya
    
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
                return huyaUrlFormatter(u.replacingOccurrences(of: "&amp;", with: "&"))?.replacingOccurrences(of: "http://", with: "https://")
            }
        }
    }
    
    init(object: MarshaledObject) throws {
        data = try object.value(for: "data")
        vMultiStreamInfo = try object.value(for: "vMultiStreamInfo")
    }
    
}

struct HuyaInfoM: Unmarshaling, LiveInfo {

    var title: String = ""
    var name: String = ""
    var avatar: String
    var isLiving = false
    var rid: Int
    var cover: String = ""
    var site: SupportSites = .huya
    
    var isSeeTogetherRoom = false
    
    
    var urls: [(String, Stream)]
    
    
    struct StreamInfo: Unmarshaling {
        let sFlvUrl: String
        let sStreamName: String
        let sFlvUrlSuffix: String
        let sFlvAntiCode: String
        
        let sCdnType: String
        
        var url: String? {
            get {
                let u = sFlvUrl
                + "/"
                + sStreamName
                + "."
                + sFlvUrlSuffix
                + "?"
                + sFlvAntiCode
                
//                return formatURL(u)
                
                
                return huyaUrlFormatter(u)
            }
        }
        
        init(object: MarshaledObject) throws {
            sFlvUrl = try object.value(for: "sFlvUrl")
            sStreamName = try object.value(for: "sStreamName")
            sFlvUrlSuffix = try object.value(for: "sFlvUrlSuffix")
            sFlvAntiCode = try object.value(for: "sFlvAntiCode")
            
            sCdnType = try object.value(for: "sCdnType")
        }
        

    }
    
    struct BitRateInfo: Unmarshaling {
        let sDisplayName: String
        let iBitRate: Int
        
        init(object: MarshaledObject) throws {
            sDisplayName = try object.value(for: "sDisplayName")
            iBitRate = try object.value(for: "iBitRate")
        }
    }
    
    
    
    
    init(object: MarshaledObject) throws {
        name = try object.value(for: "roomInfo.tProfileInfo.sNick")
        
        let ava: String = try object.value(for: "roomInfo.tProfileInfo.sAvatar180")
        avatar = ava.replacingOccurrences(of: "http://", with: "https://")
        
        let state: Int = try object.value(for: "roomInfo.eLiveStatus")
        isLiving = state == 2
        
        
        let titleInfoKey = isLiving ? "tLiveInfo" : "tReplayInfo"
        let titleKey = ["sIntroduction", "sRoomName"]
        
        let titles: [String] = try titleKey.map {
            "roomInfo.\(titleInfoKey).\($0)"
        }.map {
            try object.value(for: $0)
        }
        
        title = titles.first {
            $0 != ""
        } ?? name
        
        rid = try object.value(for: "roomInfo.tProfileInfo.lProfileRoom")
        cover = try object.value(for: "roomInfo.tLiveInfo.sScreenshot")
        
        
        let defaultCDN: String = try object.value(for: "roomInfo.tLiveInfo.tLiveStreamInfo.sDefaultLiveStreamLine")
        
        let streamInfos: [StreamInfo] = try object.value(for: "roomInfo.tLiveInfo.tLiveStreamInfo.vStreamInfo.value")

        let bitRateInfos: [BitRateInfo] = try object.value(for: "roomInfo.tLiveInfo.tLiveStreamInfo.vBitRateInfo.value")
        
        let urls = streamInfos.sorted { i1, i2 -> Bool in
            i1.sCdnType == defaultCDN
        }.compactMap {
            $0.url
        }
        
        guard urls.count > 0 else {
            self.urls = []
            return
        }
        
        self.urls = bitRateInfos.map {
            ($0.sDisplayName, $0.iBitRate)
        }.map { (name, rate) -> (String, Stream) in
            var us = urls.map {
                $0 + "&ratio=\(rate)"
            }
            var s = Stream(url: us.removeFirst())
            s.src = us
            s.quality = rate == 0 ? 9999999 : rate
            return (name, s)
        }
    }
}

fileprivate func huyaUrlFormatter(_ u: String) -> String? {
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
        
        .replacingOccurrences(of: "http://", with: "https://")
    return url
}


fileprivate func huyaUrlFormatter2(_ u: String) -> String? {
    guard var uc = URLComponents(string: u) else {
        return nil
    }

    uc.scheme = "https"
    
    if let fm = uc.queryItems?.first(where: {
        $0.name == "fm"
    })?.value {
//        fm
        
        
        
        
    }
    
    uc.queryItems?.removeAll {
        $0.name == "fm"
    }

    //Number((Date.now() % 1e10 * 1e3 + (1e3 * Math.random() | 0)) % 4294967295)
    
    let date = Int(Date().timeIntervalSince1970 * 1000)
    
    let uuid = (date % Int(1e10) + Int.random(in: 1...999)) % 4294967295

    let uid = 1462391016094
    let seqid = date + uid

    let newItems: [URLQueryItem] = [
        .init(name: "seqid", value: "\(seqid)"),
        .init(name: "ver", value: "1"),
        .init(name: "uid", value: "\(uid)"),
        .init(name: "uuid", value: "\(uuid)"),
        .init(name: "sv", value: "2110131611"),
    ]

    uc.queryItems?.append(contentsOf: newItems)

    
    return uc.url?.absoluteString
}

struct EgameUrl: Unmarshaling {
    var playUrl: String
    var desc: String
    var levelType: Int
    
    var src = [String]()
    
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
    
    var site: SupportSites = .eGame
    
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

struct EgameMInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var avatar: String
    var isLiving = false
    var pid = ""
    var anchorId: Int
    var lastTm = 0
    var streamInfos: [StreamInfo]
    
    var site: SupportSites = .eGame
    
    var cover: String = ""
    
    struct StreamInfo: Unmarshaling {
        let playUrl: String
        let desc: String
        init(object: MarshaledObject) throws {
            let u: String = try object.value(for: "playUrl")
            playUrl = u.replacingOccurrences(of: "&amp;", with: "&")
            desc = try object.value(for: "desc")
        }
    }
    
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "liveInfo.data.videoInfo.title")
        name = try object.value(for: "liveInfo.data.profileInfo.nickName")
        avatar = try object.value(for: "liveInfo.data.profileInfo.faceUrl")
        avatar = avatar.replacingOccurrences(of: "http://", with: "https://")
        let liveStatus: Int = try object.value(for: "liveInfo.data.profileInfo.isLive")
        isLiving = liveStatus == 1
        pid = try object.value(for: "liveInfo.data.videoInfo.pid")
        anchorId = try object.value(for: "liveInfo.data.videoInfo.anchorId")
        
        streamInfos = try object.value(for: "liveInfo.data.videoInfo.streamInfos")
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

// MARK: - CC163

struct CC163Info: Unmarshaling, LiveInfo {
    var title: String
    var name: String
    var avatar: String
    var cover: String
    var isLiving: Bool
    var ccid: String
    var site: SupportSites
    
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
    let site = SupportSites.cc163
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
    var site: SupportSites
    
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


struct CC163NewVideos: Unmarshaling {
    let title: String
    let videos: [String: VideoItem]
    
    struct VideoItem: Unmarshaling {
        let vbr: Int
        let urls: [String]
        
        init(object: MarshaledObject) throws {
            vbr = try object.value(for: "vbr")
            let cdnItems: [String: Any] = try object.value(for: "cdn")
            
            urls = Array(cdnItems.compactMapValues({ $0 as? String }).values)
        }
    }
    
    init(object: MarshaledObject) throws {
        videos = try object.value(for: "quickplay.resolution")
        title = try object.value(for: "title")
    }
    
    func write(to yougetJson: YouGetJSON) -> YouGetJSON {
        var json = yougetJson
        json.title = title
        
        videos.filter {
            $0.value.urls.count > 0
        }.forEach {
            let video = $0.value
            var stream = Stream(url: video.urls.first!)
            stream.quality = video.vbr
            stream.src = Array(video.urls.dropFirst())
            json.streams[$0.key] = stream
        }
        
        return json
    }
}

// MARK: - DouYin
struct DouYinInfo: Unmarshaling, LiveInfo {
    var title: String
    var name: String
    var avatar: String
    var cover: String
    var isLiving: Bool
    var site = SupportSites.douyin
    
    var roomId: String
    var webRid: String
    var urls = [String: String]()
    
    
    init(object: MarshaledObject) throws {
        roomId = try object.value(for: "initialState.roomStore.roomInfo.roomId")
        webRid = try object.value(for: "initialState.roomStore.roomInfo.web_rid")
        
        title = try object.value(for: "initialState.roomStore.roomInfo.room.title")
        let status: Int = try object.value(for: "initialState.roomStore.roomInfo.room.status")
        isLiving = status == 2
        
        let flvUrls: [String: String]? = try? object.value(for: "initialState.roomStore.roomInfo.room.stream_url.flv_pull_url")
        urls = flvUrls ?? [:]
        
        /*
        let hlsUrls: [String: String] = try object.value(for: "initialState.roomStore.roomInfo.room.stream_url.hls_pull_url_map")
         */
        //        name = try object.value(for: "initialState.roomStore.roomInfo.room.stream_url.live_core_sdk_data.anchor.nickname")
        
        name = try object.value(for: "initialState.roomStore.roomInfo.anchor.nickname")
        
        let covers: [String]? = try object.value(for: "initialState.roomStore.roomInfo.room.cover.url_list")
        cover = covers?.first ?? ""
        
        let avatars: [String] = try object.value(for: "initialState.roomStore.roomInfo.anchor.avatar_thumb.url_list")
        avatar = avatars.first ?? ""
    }
    
    func write(to yougetJson: YouGetJSON) -> YouGetJSON {
        var json = yougetJson
        json.title = title
        
        
        urls.map {
            ($0.key, $0.value.replacingOccurrences(of: "http://", with: "https://"))
        }.sorted { v0, v1 in
            v0.0 < v1.0
        }.enumerated().forEach {
            var stream = Stream(url: $0.element.1)
            stream.quality = 999 - $0.offset
            json.streams[$0.element.0] = stream
        }
        
        return json
    }
}
