//
//  YouGetJSON.swift
//  iina+
//
//  Created by xjbeta on 2018/7/5.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Foundation
import Marshal

struct YouGetJSON: Unmarshaling, Codable {
    let uuid = UUID().uuidString
    var bvid = ""
    
    var title: String = ""
    var streams: [String: Stream] = [:]
    var audio = ""
    var id = -1
    var duration = -1
    
    
    var videos: [(key: String, value: Stream)] {
        get {
            return streams.sorted {
                $0.value.quality > $1.value.quality
            }
        }
    }

    var site: SupportSites = .unsupported
    
    var mpvOptions: [String] {
        get {
            // Fix title
            let t = title.replacingOccurrences(of: "\"", with: "''")
            var args = ["\(MPVOption.Miscellaneous.forceMediaTitle)=\(t)"]
            switch site {
            case .bilibili, .bangumi:
                args.append(contentsOf: [
                    "\(MPVOption.ProgramBehavior.ytdl)=no",
                    "\(MPVOption.Network.referrer)=https://www.bilibili.com/"
                ])
                if audio != "" {
                    args.append("\(MPVOption.Audio.audioFile)=\(audio)")
                }
            default:
                args.append(contentsOf: ["\(MPVOption.ProgramBehavior.ytdl)=no"])
            }
            return args
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case title, streams, audio, id, duration
    }

    init(object: MarshaledObject) throws {
        let titleStr: String? = try? object.value(for: "title")
        title = titleStr ?? ""
        streams = try object.value(for: "streams")
    }
    
    init(url: String) {
        streams = ["url": Stream(url: url)]
    }
    
    func iinaUrl(_ key: String, _ isDanmaku: Bool = true) -> String? {
        isDanmaku ? danmakuUrl(key) : iinaDefaultUrl(key)
    }
    
    func danmakuUrl(_ key: String) -> String? {
        guard let url = videoUrl(key) else {
            return nil
        }
        
        let u = "iina://iina-plus.base64?"
        var args = mpvOptions.map {
            "mpv_" + $0
        }
        args.insert("url=\(url)", at: 0)
        if Preferences.shared.enableDanmaku {
            args.append("danmaku")
            args.append("uuid=\(uuid)")
        }
        args.append("dmPort=\(Preferences.shared.dmPort)")
        args.append("directly")
        
        let str = args.joined(separator: "👻")
        let base64Str = str.data(using: .utf8)?.base64EncodedString() ?? ""
        return u + base64Str
    }
    
    func iinaDefaultUrl(_ key: String) -> String? {
        guard let url = videoUrl(key) else {
            return nil
        }
        
        let u = "iina://open?"
        var args = mpvOptions.map {
            "mpv_" + $0
        }
        args.insert("url=\(url)", at: 0)
        args = args.compactMap { kvs -> String? in
            let kv = kvs.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else {
                return kvs
            }
            
            guard let v = kv[1].addingPercentEncoding(withAllowedCharacters: Processes.shared.urlQueryValueAllowed) else { return nil }
            let k = kv[0]
            return "\(k)=\(v)"
        }
        
        return u + args.joined(separator: "&")
    }
    
    func videoUrl(_ key: String) -> String? {
        switch site {
        case .bilibili, .bangumi:
            return streams[key]?.url
        case .local:
            return streams.first?.value.url
        default:
            if let content = m3uContent(key: key) {
                return saveToTemp(content, name: "\(uuid).m3u")
            }
        }
        
        return nil
    }
    
    func m3uContent(key: String) -> Data? {
        guard let stream = streams[key],
              stream.url != nil else { return nil }
        
        var content = "#EXTM3U"
        let title = title
        
        content.append("\n#EXTINF:-1 ,\(title)\n")
        content.append(stream.url!)
        
        stream.src.enumerated().forEach {
            let tt = title + " - " + "备用\($0.offset + 1)"
            content.append("\n#EXTINF:-1 ,\(tt)\n")
            content.append($0.element)
        }

        return content.data(using: .utf8)
    }
    
    func saveToTemp(_ data: Data, name: String) -> String {
        
        let fm = FileManager.default
        var path = NSTemporaryDirectory()
        path.append("IINA-PLUS/")
        
        if !fm.fileExists(atPath: path) {
            try? fm.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
        }
        
        path.append(name)
        
        if fm.fileExists(atPath: path) {
            try? fm.removeItem(atPath: path)
        }
        
        fm.createFile(atPath: path, contents: data, attributes: nil)
        
        return path
    }
}

struct Stream: Unmarshaling, Codable {
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
