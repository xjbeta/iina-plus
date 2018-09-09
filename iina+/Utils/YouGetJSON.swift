//
//  YouGetJSON.swift
//  iina+
//
//  Created by xjbeta on 2018/7/5.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Foundation
import Marshal

struct YouGetJSON: Unmarshaling {
    
    var site: String = ""
    var title: String = ""
    var url: String?
    var streams: [String: Stream] = [:]

    init(object: MarshaledObject) throws {
        site = try object.value(for: "site")
        let titleStr: String? = try? object.value(for: "title")
        title = titleStr ?? ""
        url = try? object.value(for: "url")
        streams = try object.value(for: "streams")
    }
    
    init(url: String) {
        streams = ["url": Stream(url: url)]
    }
}

struct Stream: Unmarshaling {
    var container: String = ""
    var itag: String = ""
    var mime: String = ""
    var quality: String = ""
    var s: String = ""
    var sig: String = ""
    var type: String = ""
    var url: String?
    var videoProfile: String?
    var size: Int64?
    var src: [String] = []
    
    init(object: MarshaledObject) throws {
        container = try object.value(for: "container")
        let srcArray: [String]? = try? object.value(for: "src")
        src = srcArray ?? []
        url = try? object.value(for: "url")
        videoProfile = try? object.value(for: "video_profile")
        size = try? object.value(for: "size")
    }
    
    init(url: String) {
        self.url = url
    }
}
