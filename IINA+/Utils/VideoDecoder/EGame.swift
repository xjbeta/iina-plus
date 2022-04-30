//
//  EGame.swift
//  IINA+
//
//  Created by xjbeta on 4/22/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa
import PromiseKit
import Alamofire
import PMKAlamofire
import JavaScriptCore
import Marshal

class EGame: NSObject, SupportSiteProtocol {
    func liveInfo(_ url: String) -> Promise<LiveInfo> {
        getEgameMInfo(url).map {
            $0 as LiveInfo
        }
    }
    
    func decodeUrl(_ url: String) -> Promise<YouGetJSON> {
        getEgameMInfo(url).map {
            var yougetJson = YouGetJSON(rawUrl: url)
            yougetJson.title = $0.title
            $0.streamInfos.enumerated().forEach {
                var s = Stream(url: $0.element.playUrl)
                s.quality = 999 - $0.offset
                yougetJson.streams[$0.element.desc] = s
            }
            return yougetJson
        }
    }
    

    func getEgameInfo(_ url: String) -> Promise<(EgameInfo, [EgameUrl])> {
        AF.request(url).responseString().map {
            var jsString = $0.string.subString(from: "window.__NUXT__=", to: "</script>")
            
            jsString = "jsonObj=" + jsString
            
            let jsContext = JSContext()
            jsContext?.evaluateScript(jsString)
            let result = jsContext?.evaluateScript("JSON.stringify(jsonObj)")
            
            let jsonData = result?.toString()?.data(using: .utf8) ?? Data()
            
            let json: JSONObject = try JSONParser.JSONObjectWithData(jsonData)
            let info: EgameInfo = try EgameInfo(object: json)
            
            var urls: [EgameUrl] = try json.value(for: "state.live-info.liveInfo.videoInfo.streamInfos")
            let urlsBak: [EgameUrl] = try json.value(for: "state.live-info.liveBaseInfo.streamInfo.streamInfos")
            
            urlsBak.forEach { bak in
                guard let i = urls.firstIndex(where: {
                    $0.levelType == bak.levelType
                    && $0.desc == bak.desc
                }) else {
                    return
                }
                urls[i].src.append(bak.playUrl)
            }
            
            return (info, urls)
        }
    }
    
    func getEgameMInfo(_ url: String) -> Promise<(EgameMInfo)> {
        let pcs = url.pathComponents
        guard pcs.count > 1,
              let rid = Int(pcs[2]) else {
                  return .init(error: VideoGetError.invalidLink)
              }
        let u = "https://m.egame.qq.com/live?anchorid=\(rid)"
        
        return AF.request(u).responseString().map {
            guard let data = $0.string.subString(from: "try {            window.serverData = ", to: ";\r\n").data(using: .utf8) else {
                throw VideoGetError.egameFunctionNotFound
            }
            
            let json: JSONObject = try JSONParser.JSONObjectWithData(data)
            return try EgameMInfo(object: json)
        }
    }
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
