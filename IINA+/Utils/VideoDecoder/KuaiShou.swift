//
//  KuaiShou.swift
//  IINA+
//
//  Created by xjbeta on 2023/3/1.
//  Copyright © 2023 xjbeta. All rights reserved.
//

import Cocoa
import PromiseKit
import Alamofire
import PMKAlamofire
import Marshal

class KuaiShou: NSObject, SupportSiteProtocol {
    lazy var session: Session = {
        let configuration = URLSessionConfiguration.af.default
        let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.3 Safari/605.1.15"
        configuration.headers.add(.userAgent(ua))
        return Session(configuration: configuration)
    }()
    
    
    func liveInfo(_ url: String) -> Promise<LiveInfo> {
        getInfo(url).map {
            $0
        }
    }
    
    func decodeUrl(_ url: String) -> Promise<YouGetJSON> {
        getInfo(url).map {
            $0.write(to: YouGetJSON(url: url))
        }
    }
    
    func getInfo(_ url: String) -> Promise<KuaiShouInfo> {
        AF.request(url).responseString().map {
            $0.string
                .subString(from: "window.__INITIAL_STATE__=", to: ";(")
                .data(using: .utf8) ?? Data()
        }.map {
            let obj = try JSONParser.JSONObjectWithData($0)
            let info = try KuaiShouInfo(object: obj)
            return info
        }
    }
}

struct KuaiShouInfo: Unmarshaling, LiveInfo {

    var title: String = ""
    var name: String = ""
    var avatar: String = ""
    var cover: String = ""
    
    var isLiving: Bool = false
    
    var site: SupportSites = .kuaiShou
    
    var representations: [Representation] = []
    
    init(object: Marshal.MarshaledObject) throws {
        name = try object.value(for: "liveroom.author.name")
        avatar = try object.value(for: "liveroom.author.avatar")
        title = try object.value(for: "liveroom.liveStream.caption")
        cover = try object.value(for: "liveroom.liveStream.coverUrl")
        isLiving = try object.value(for: "liveroom.isLiving")
        
        let playUrls: [PlayUrl] = try object.value(for: "liveroom.liveStream.playUrls")
        
        representations = playUrls.first?.representations ?? []
    }
    
    struct PlayUrl: Unmarshaling {
        var representations: [Representation]
        
        init(object: Marshal.MarshaledObject) throws {
            representations = try object.value(for: "adaptationSet.representation")
        }
    }
    
    struct Representation: Unmarshaling {
        var bitrate: Int
        var level: Int
        var name: String
        var url: String
        
        init(object: Marshal.MarshaledObject) throws {
            bitrate = try object.value(for: "bitrate")
            level = try object.value(for: "level")
            name = try object.value(for: "name")
            url = try object.value(for: "url")
        }
    }
    
    func write(to yougetJson: YouGetJSON) -> YouGetJSON {
        var json = yougetJson
        json.title = title
        
        representations.forEach {
            var stream = Stream(url: $0.url)
            stream.quality = $0.bitrate
            json.streams[$0.name] = stream
        }
        
        return json
    }
}
