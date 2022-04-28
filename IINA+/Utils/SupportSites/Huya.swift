//
//  Huya.swift
//  IINA+
//
//  Created by xjbeta on 4/22/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa
import PromiseKit
import Alamofire
import PMKAlamofire
import Marshal

class Huya: NSObject, SupportSiteProtocol {
    
    lazy var pSession: Session = {
        let configuration = URLSessionConfiguration.af.default
        let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1"
        configuration.headers.add(.userAgent(ua))
        return Session(configuration: configuration)
    }()
    
    func liveInfo(_ url: String) -> Promise<LiveInfo> {
        getHuyaInfoM(url).map {
            $0.0
        }
    }
    
    func decodeUrl(_ url: String) -> Promise<YouGetJSON> {
        getHuyaInfoM(url).map {
            var yougetJson = YouGetJSON(rawUrl: url)
            yougetJson.title = $0.0.title
            $0.1.enumerated().forEach {
                yougetJson.streams[$0.element.0] = $0.element.1
            }
            return yougetJson
        }
    }
    
    // MARK: - Huya
    
    func getHuyaInfo(_ url: String) -> Promise<(HuyaInfo, [(String, Stream)])> {
//        https://github.com/zhangn1985/ykdl/blob/master/ykdl/extractors/huya/live.py
        AF.request(url).responseString().map {
            let text = $0.string
            
            let hyPlayerConfigStr: String? = {
                var str = text.subString(from: "var hyPlayerConfig = ", to: "window.TT_LIVE_TIMING")
                guard let index = str.lastIndex(of: ";") else { return nil }
                str.removeSubrange(index ..< str.endIndex)
                return str
            }()
            
            guard let roomInfoData = text.subString(from: "var TT_ROOM_DATA = ", to: ";var").data(using: .utf8),
                  let profileInfoData = text.subString(from: "var TT_PROFILE_INFO = ", to: ";var").data(using: .utf8),
                  let playerInfoData = hyPlayerConfigStr?.data(using: .utf8) else {
                throw VideoGetError.notFindUrls
            }
            
            
            var roomInfoJson: JSONObject = try JSONParser.JSONObjectWithData(roomInfoData)
            let profileInfoJson: JSONObject = try JSONParser.JSONObjectWithData(profileInfoData)
            let playerInfoJson: JSONObject = try JSONParser.JSONObjectWithData(playerInfoData)
            
            roomInfoJson.merge(profileInfoJson) { (current, _) in current }
            let info: HuyaInfo = try HuyaInfo(object: roomInfoJson)
            
            if !info.isLiving {
                return (info, [])
            }
            

            
            let streamStr: String = try playerInfoJson.value(for: "stream")
            
            guard let streamData = Data(base64Encoded: streamStr) else {
                throw VideoGetError.notFindUrls
            }
            
            let streamJSON: JSONObject = try JSONParser.JSONObjectWithData(streamData)
            
            let huyaStream: HuyaStream = try HuyaStream(object: streamJSON)
        
            var urls = [String]()
            
            if info.isSeeTogetherRoom {
                urls = huyaStream.data.first?.urlsBak ?? []
            } else {
                urls = huyaStream.data.first?.urls ?? []
            }
            
            guard urls.count > 0 else {
                throw VideoGetError.notFindUrls
            }
            
            let re = huyaStream.vMultiStreamInfo.enumerated().map { info -> (String, Stream) in
                    
                let u = urls.first!.replacingOccurrences(of: "ratio=0", with: "ratio=\(info.element.iBitRate)")
                var s = Stream(url: u)
                
                if info.element.iBitRate == 0,
                   info.offset == 0 {
                    s.quality = huyaStream.vMultiStreamInfo.map {
                        $0.iBitRate
                    }.max() ?? 999999999
                    s.quality += 1
                } else {
                    s.quality = info.element.iBitRate
                }
                return (info.element.sDisplayName, s)
            }
            return (info, re)
        }
    }
    
    func getHuyaInfoM(_ url: String) -> Promise<(HuyaInfoM, [(String, Stream)])> {
        pSession.request(url).responseString().map {
            guard let jsonData = $0.string.subString(from: "<script> window.HNF_GLOBAL_INIT = ", to: " </script>").data(using: .utf8)
            else {
                throw VideoGetError.notFindUrls
            }
            let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(jsonData)
            
            let info: HuyaInfoM = try HuyaInfoM(object: jsonObj)
                  
            return (info, info.urls)
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
