//
//  QQLive.swift
//  IINA+
//
//  Created by xjbeta on 6/9/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa
import PromiseKit
import Alamofire
import PMKAlamofire
import Marshal

class QQLive: NSObject, SupportSiteProtocol {
    func liveInfo(_ url: String) -> Promise<LiveInfo> {
        roomInfo(url).map {
            $0 as LiveInfo
        }
    }
    
    func decodeUrl(_ url: String) -> Promise<YouGetJSON> {
        roomInfo(url).map {
            var re = YouGetJSON(rawUrl: url)
            re.title = $0.title
            re.streams["Default"] = .init(url: $0.url)
            return re
        }
    }
    
    func roomInfo(_ url: String) -> Promise<QQLiveInfo> {
        // https://github.com/streamlink/streamlink/blob/master/src/streamlink/plugins/qq.py
        guard url.pathComponents.count > 2 else {
            return .init(error: VideoGetError.notSupported)
        }
        
        return AF.request("https://live.qq.com/api/h5/room?room_id=\(url.pathComponents[2])").responseData().map {
            let json: JSONObject = try JSONParser.JSONObjectWithData($0.data)
            return try QQLiveInfo(object: json)
        }
    }

}

struct QQLiveInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var avatar: String
    var isLiving = false
    var cover: String = ""
    var site: SupportSites = .qqLive
    
    var url: String
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "data.room_name")
        name = try object.value(for: "data.nickname")
        avatar = try object.value(for: "data.owner_avatar")
        isLiving = "\(try object.any(for: "data.show_status"))" == "1"
        cover = try object.value(for: "data.room_src_square")
        url = try object.value(for: "data.rtmp_url") + "/" + object.value(for: "data.rtmp_live")
    }
}
