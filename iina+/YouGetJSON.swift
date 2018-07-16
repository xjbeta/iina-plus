//
//  YouGetJSON.swift
//  iina+
//
//  Created by xjbeta on 2018/7/5.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Foundation

class YouGetJSON: NSObject, Decodable {
    
    var site: String = ""
    var title: String = ""
    var url: String?
    var streams: [String: YouGetStream] = [:]
    private enum CodingKeys: String, CodingKey {
        case site,
        title,
        url,
        streams
    }
    
    required convenience init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        site = try values.decode(String.self, forKey: .site)
        title = try values.decode(String.self, forKey: .title)
        url = try values.decodeIfPresent(String.self, forKey: .url)
        streams = try values.decode([String: YouGetStream].self, forKey: .streams)
    }
}

class YouGetStream: NSObject, Decodable {
    var container: String = ""
    var itag: String = ""
    var mime: String = ""
    var quality: String = ""
    var s: String = ""
    var sig: String = ""
    var type: String = ""
    var url: String?
    var size: String = ""
    var src: [String] = []
    
    

    private enum CodingKeys: String, CodingKey {
        case container,
        itag,
        mime,
        quality,
        s,
        sig,
        type,
        url,
        size,
        src
    }
    
    required convenience init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        container = try values.decode(String.self, forKey: .container)
        src = try values.decodeIfPresent([String].self, forKey: .src) ?? []
        url = try values.decodeIfPresent(String.self, forKey: .url)
    }
}
