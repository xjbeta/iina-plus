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
    var title: String = ""
    var streams: [String: Stream] = [:]
    
    var videos: [(key: String, value: Stream)] {
        get {
            return streams.sorted {
                $0.value.quality > $1.value.quality
            }
        }
    }
    
    var audio = ""
    
    var site: LiveSupportList = .unsupported
    var id = -1
    
    var duration = -1

    init(object: MarshaledObject) throws {
        let titleStr: String? = try? object.value(for: "title")
        title = titleStr ?? ""
        streams = try object.value(for: "streams")
    }
    
    init(url: String) {
        streams = ["url": Stream(url: url)]
    }
}

struct Stream: Unmarshaling {
    var quality: Int = -1
    var rate: Int = -1
    var url: String?
    var videoProfile: String?
    var size: Int64?
    var src: [String] = []
    
    init(object: MarshaledObject) throws {
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
