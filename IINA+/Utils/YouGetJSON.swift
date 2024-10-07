//
//  YouGetJSON.swift
//  iina+
//
//  Created by xjbeta on 2018/7/5.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Foundation
import Marshal

enum PluginOptionsType: Int {
    case ws, xmlFile, none
}

struct DanmakuPluginOptions: Encodable {
    let rawUrl: String
    let mpvScript: String
    let port: Int
	let urls: [String]
    var type: Int = PluginOptionsType.none.rawValue
    
    let qualitys: [String]
    let lines: [String]
    let currentQuality: Int
    let currentLine: Int
    
    var xmlPath: String?
	
	var edl: String?
    
    init(rawUrl: String,
         mpvScript: String,
		 urls: [String],
         qualitys: [String],
         lines: [String],
         currentQuality: Int,
         currentLine: Int,
         port: Int) {
        self.rawUrl = rawUrl
        self.mpvScript = mpvScript
		self.urls = urls
        self.qualitys = qualitys
        self.lines = lines
        self.currentQuality = currentQuality
        self.currentLine = currentLine
        
        self.port = port
    }
}

enum IINAUrlType: String {
    case normal, danmaku, plugin, none
}

struct YouGetJSON: Unmarshaling, Codable {
    var rawUrl: String = ""
    
    
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
	
	var mpvDashOptions: [String] {
		var args = mpvOptions
		switch site {
		case .bilibili, .bangumi:
			args.removeAll {
				$0.starts(with: MPVOption.ProgramBehavior.ytdl)
				|| $0.starts(with: MPVOption.Audio.audioFile)
			}
			args.append("\(MPVOption.ProgramBehavior.ytdl)=yes")
		default:
			break
		}
		return args
	}
    
    var mpvOptions: [String] {
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
		case .biliLive:
			args.append(contentsOf: [
				"\(MPVOption.ProgramBehavior.ytdl)=no",
				"\(MPVOption.Network.referrer)=https://live.bilibili.com/"
			])
		case .huya:
			args.append(contentsOf: [
				"\(MPVOption.ProgramBehavior.ytdl)=no",
				"\(MPVOption.Network.referrer)=https://www.huya.com/",
				"\(MPVOption.Network.userAgent)=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3.1 Safari/605.1.15"
			])
		default:
			args.append(contentsOf: ["\(MPVOption.ProgramBehavior.ytdl)=no"])
		}
		return args
    }
    
    enum CodingKeys: String, CodingKey {
        case title, streams, audio, id, duration
    }

    init(object: MarshaledObject) throws {
        let titleStr: String? = try? object.value(for: "title")
        title = titleStr ?? ""
        streams = try object.value(for: "streams")
    }
    
    init(rawUrl: String) {
        streams = [:]
        self.rawUrl = rawUrl
        self.site = SupportSites(url: rawUrl)
    }
    
    init(url: String) {
        streams = ["url": Stream(url: url)]
    }
    
    func iinaURLScheme(_ key: String, type: IINAUrlType) -> String? {
        switch type {
		case .plugin:
			return iinaPluginUrl(key)
		case .normal:
			return iinaDefaultUrl(key)
        case .danmaku:
            return danmakuUrl(key)
		case .none:
			return nil
        }
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
        
        
        let newUUID = [uuid, rawUrl].joined(separator: "👻").toHexString()
        
        if Preferences.shared.enableDanmaku {
            args.append("danmaku")
            args.append("uuid=\(newUUID)")
        }
        args.append("dmPort=\(Preferences.shared.dmPort)")
        args.append("directly")
        
        let str = args.joined(separator: "👻")
        let base64Str = str.data(using: .utf8)?.base64EncodedString() ?? ""
        return u + base64Str
    }
    
	func iinaPluginUrl(_ key: String) -> String? {
		guard let argsStr = iinaPlusArgsString(key) else {
			return nil
		}
		
		let u = "iina://open?"
		
		var args = [
			"new_window=1",
			"url=-",
			"mpv_\(MPVOption.ProgramBehavior.scriptOpts)=iinaPlusArgs=\(argsStr)"
		]
		args = args.compactMap { kvs -> String? in
			let kv = kvs.split(separator: "=", maxSplits: 1).map(String.init)
			guard kv.count == 2 else {
				return kvs
			}
			
			guard let v = kv[1].addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) else { return nil }
			let k = kv[0]
			return "\(k)=\(v)"
		}
		
		return u + args.joined(separator: "&")
	}
	
    func iinaDefaultUrl(_ key: String) -> String? {
        guard let url = videoUrl(key, forDash: true),
			  let argsStr = iinaPlusArgsString(key) else {
            return nil
        }
        
        let u = "iina://open?"
		let opts = url.contains(".mpd") ? mpvDashOptions : mpvOptions
        var args = opts.map {
            "mpv_" + $0
        }
        args.insert("url=\(url)", at: 0)
		args.append("mpv_\(MPVOption.ProgramBehavior.scriptOpts)=iinaPlusArgs=\(argsStr)")
		
        args = args.compactMap { kvs -> String? in
            let kv = kvs.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else {
                return kvs
            }
            
            guard let v = kv[1].addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) else { return nil }
            let k = kv[0]
            return "\(k)=\(v)"
        }
        
        return u + args.joined(separator: "&")
    }
    
	func videoUrl(_ key: String, forDash: Bool = false) -> String? {
        switch site {
		case .bilibili where forDash, .bangumi where forDash:
			return streams[key]?.dashUrl
        case .bilibili, .bangumi, .biliLive:
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
    
    func iinaPlusArgsString(_ key: String) -> String? {
        let urls: [String] = {
            var urls = [String]()
            if let u = streams[key]?.url {
                urls.append(u)
            }
            if let us = streams[key]?.src {
                urls.append(contentsOf: us)
            }
            return urls
        }()
        
        let qualitys = videos.map {
            $0.key
        }
        let lineCount: Int = urls.count
        
        var opts = DanmakuPluginOptions(
            rawUrl: rawUrl,
			mpvScript: mpvOptionsToScriptValue(mpvOptions),
			urls: urls,
            qualitys: qualitys,
            lines: (0..<lineCount).map {
                "Line \($0 + 1)"
            },
            currentQuality: qualitys.firstIndex(of: key) ?? 0,
            currentLine: 0,
            port: Preferences.shared.dmPort)

//		opts.edl = edl(key: key)
		
        if Preferences.shared.enableDanmaku {
            opts.type = PluginOptionsType.ws.rawValue
        }
		
        if let dmPath = VideoDecoder.dmPath(uuid),
            FileManager.default.fileExists(atPath: dmPath) {
            opts.type = PluginOptionsType.xmlFile.rawValue
            opts.xmlPath = dmPath
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(opts) else {
            return nil
        }
        
        return data.toHexString()
    }
	
	func edl(key: String) -> String? {
//		mpv.set("stream-open-filename", opts.edl);
		guard let stream = streams[key],
			  stream.url != nil else { return nil }
		
		var edl = "edl://"
		
		func appendUrl(_ url: String) {
			edl += "!new_stream;!no_clip;!no_chapters;"
			edl += "%\(url.count)%"
			edl += url
			edl += ";"
		}
		
		appendUrl(stream.url!)
		
		if audio != "" {
			appendUrl(audio)
		}
		
		return edl
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
    
    func mpvOptionsToScriptValue(_ opts: [String]) -> String {
        
        var re = ""
        let args = opts.compactMap { kvs -> (String, String)? in
            let kv = kvs.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else {
                return nil
            }
            return (kv[0], kv[1])
        }
        args.enumerated().forEach {
            // force-media-title="xxx",ytdl="no",referrer="xxxx",audio-file="xxx"
            
            re += $0.element.0
            re += "="
            re += "\""
            re += $0.element.1
            re += "\""
            
            if $0.offset < (args.count - 1) {
                re += ","
            }
        }
        
        return re
    }
}

struct Stream: Unmarshaling, Codable {
    var quality: Int = -1
    var rate: Int = -1
    var url: String?
    var videoProfile: String?
    var size: Int64?
    var src: [String] = []
	
	var dashContent: String?
	var dashUrl: String?
	
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
