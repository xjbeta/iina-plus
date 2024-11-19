//
//  VideoDecoder.swift
//  iina+
//
//  Created by xjbeta on 2018/10/28.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import Alamofire
import Marshal
import CommonCrypto
@preconcurrency import JavaScriptCore
import SwiftSoup

actor VideoDecoder {
    lazy var douyin = DouYin()
    lazy var huya = Huya()
    lazy var douyu = Douyu()
    lazy var cc163 = CC163()
    lazy var biliLive = BiliLive()
    lazy var bilibili = Bilibili()
    lazy var qqLive = QQLive()
	
	let enableDash = false
    
    
    func bilibiliUrlFormatter(_ url: String) async throws -> String {
        let site = SupportSites(url: url)
        
        switch site {
        case .bilibili, .bangumi:
            return BilibiliUrl(url: url)!.fUrl
        case .b23:
			let res = await AF.request(url).serializingData().response
			guard let url = res.response?.url?.absoluteString,
					let u = BilibiliUrl(url: url)?.fUrl else {
				throw VideoGetError.invalidLink
			}
			return u
        default:
            return url
        }
    }
    
    func decodeUrl(_ url: String) async throws -> YouGetJSON {
        switch SupportSites(url: url) {
        case .biliLive:
			try await biliLive.decodeUrl(url)
        case .douyu:
			try await douyu.decodeUrl(url)
        case .huya:
			try await huya.decodeUrl(url)
        case .bilibili, .bangumi:
			try await bilibili.decodeUrl(url)
        case .cc163:
			try await cc163.decodeUrl(url)
        case .douyin:
			try await douyin.decodeUrl(url)
        case .qqLive:
			try await qqLive.decodeUrl(url)
        default:
            throw VideoGetError.notSupported
        }
    }
    
    func liveInfo(_ url: String, _ checkSupport: Bool = true) async throws -> LiveInfo {
        let site = SupportSites(url: url)
        switch site {
        case .biliLive:
			return try await biliLive.liveInfo(url)
        case .douyu:
			return try await douyu.liveInfo(url)
        case .huya:
			return try await huya.liveInfo(url)
        case .bilibili, .bangumi:
			return try await bilibili.liveInfo(url)
        case .cc163:
			return try await cc163.liveInfo(url)
        case .douyin:
			return try await douyin.liveInfo(url)
        case .qqLive:
			return try await qqLive.liveInfo(url)
        default:
            if checkSupport {
                throw VideoGetError.notSupported
            } else {
                var info = BiliLiveInfo()
                info.isLiving = true
				return info
            }
        }
    }
	
	func prepareDanmakuFile(yougetJSON: YouGetJSON, id: String) async throws {
		let pref = Preferences.shared
		
		guard await Processes.shared.iina.archiveType != .normal,
			  pref.enableDanmaku,
			  pref.livePlayer == .iina,
			  [.bilibili, .bangumi, .local].contains(yougetJSON.site),
			  yougetJSON.id != -1 else {
				  Log("Ignore Danmaku download.")
				  return
		}
  
//        return self.downloadDMFile(yougetJSON.id, id: id)
		
		try await downloadDMFileV2(
			cid: yougetJSON.id,
			length: yougetJSON.duration,
			id: id)
	}
    
	func prepareVideoUrl(_ json: YouGetJSON, _ key: String) async throws -> YouGetJSON {
		
		guard json.id != -1 else {
			return json
		}
		
		switch json.site {
		case .bilibili, .bangumi:
			func registerDash(_ json: YouGetJSON) async -> YouGetJSON {
				guard enableDash,
					  let stream = json.streams[key],
					  let content = stream.dashContent else {
					return json
				}
				var json = json
				json.streams[key]?.dashUrl = await Processes.shared.httpServer.registerDash(json.bvid, content: content)
				return json
			}
			
			guard let stream = json.streams[key],
				  stream.url == "" else {
				return await registerDash(json)
			}
			
			let qn = stream.quality
            let json = try await bilibili.biliShare.bilibiliPlayUrl(yougetJson: json, json.site == .bangumi, qn)
			return await registerDash(json)
		case .biliLive:
			guard let stream = json.streams[key],
				  stream.quality != -1 else {
				return json
			}
			let qn = stream.quality
			
			if let url = stream.url,
			   url != "" {
				return json
			} else {
				var re = try await biliLive.getBiliLiveJSON(json, qn, with: .roomPlayInfo)
				
				func results() -> YouGetJSON? {
					if let stream = re.streams[key],
					   let url = stream.url,
					   url != "" {
						return re
					} else {
						return nil
					}
				}
				
				if let re = results() {
					return re
				}
				
				re = try await biliLive.getBiliLiveJSON(json, qn, with: .playUrl)
				
				if let re = results() {
					return re
				}
				
				throw VideoGetError.needLogin
			}
		case .douyu:
			guard let stream = json.streams[key],
				  stream.quality != -1 else {
				return json
			}
			let rate = stream.rate
			if stream.url != "" {
				return json
			} else {
				let id = json.id
				let html = try await douyu.getDouyuHtml("https://www.douyu.com/\(id)")
				let urls = try await douyu.getDouyuUrl(id, rate: rate, jsContext: html.jsContext)
				let url = urls.first {
					$0.1.rate == rate
				}?.1.url
				var re = json
				re.streams[key]?.url = url
				return re
			}
		default:
			return json
		}
	}
}



extension VideoDecoder {
    
    // MARK: - Bilibili Danmaku
    func downloadDMFile(_ cid: Int, id: String) async throws {
		let data = try await AF.request("https://comment.bilibili.com/\(cid).xml").serializingData().value
		VideoDecoder.saveDMFile(data, with: id)
    }
    
    
    func downloadDMFileV2(cid: Int, length: Int, id: String) async throws {
        
//        segment_index  6min
        
        let c = Int(ceil(Double(length) / 360))
        let s = c > 1 ? Array(1...c) : [1]
        
        print("downloadDMFileV2", c)
        
        guard c < 1500 else {
            return
        }
		
		let dms = try await withThrowingTaskGroup(of: [DanmakuElem].self) { group in
			for i in s {
				group.addTask {
					try await self.getDanmakuContent(cid: cid, index: i)
				}
			}
			
			var re = [DanmakuElem]()
			
			for try await e in group {
				re.append(contentsOf: e)
			}
			
			return re
		}
		
		let element = try XMLElement(xmlString: #"<?xml version="1.0" encoding="UTF-8"?><i><chatserver>chat.bilibili.tv</chatserver><chatid>170102</chatid></i>"#)
		
		let doc = XMLDocument(rootElement: element)
		
		dms.map { dm -> String in
			let s1 = ["\(Double(dm.progress) / 1000)",
					  "\(dm.mode)",
					  "\(dm.fontsize)",
					  "\(dm.color)",
					  "\(dm.ctime)",
					  "\(dm.pool)",
					  "\(dm.midHash)",
					  "\(dm.id)"].joined(separator: ",")
			var s2 = dm.content
			
			s2 = s2.replacingOccurrences(of: "<", with: "&lt;")
			s2 = s2.replacingOccurrences(of: ">", with: "&gt;")
			s2 = s2.replacingOccurrences(of: "&", with: "&amp;")
			s2 = s2.replacingOccurrences(of: "'", with: "&apos;")
			s2 = s2.replacingOccurrences(of: "\"", with: "&quot;")
			
			s2 = s2.replacingOccurrences(of: "`", with: "&apos;")
			
			return "<d p=\"\(s1)\">\(s2)</d>"
		}.forEach {
			if let node = try? XMLElement(xmlString: $0) {
				element.addChild(node)
			} else {
				Log("Invalid Bangumi Line: \($0)")
			}
		}
		
		VideoDecoder.saveDMFile(doc.xmlData, with: id)
    }
    
    static func saveDMFile(_ data: Data?, with id: String) {
		guard let path = VideoDecoder.dmPath(id) else { return }
        var p = path
        p.deleteLastPathComponent()
        try? FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: data, attributes: nil)
        Log("Saved DM in \(path)")
    }
    
    static func dmPath(_ id: String) -> String? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
            var filesURL = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return nil
        }
        let folderName = "WebFiles"
        
        filesURL.appendPathComponent(bundleIdentifier)
        filesURL.appendPathComponent(folderName)
        let fileName = "danmaku" + "-" + id + ".xml"
        
        filesURL.appendPathComponent(fileName)
        return filesURL.path
    }
    
    func getDanmakuContent(cid: Int, index: Int) async throws -> [DanmakuElem] {
		let u = "https://api.bilibili.com/x/v2/dm/web/seg.so?type=1&oid=\(cid)&segment_index=\(index)"
		
		let data = try await AF.request(u).serializingData().value
		return try DmSegMobileReply(serializedBytes: data).elems
    }
}

enum VideoGetError: Error {
    case invalidLink
    
    case douyuUrlError
    case douyuSignError
    case douyuNotFoundRoomId
    case douyuNotFoundSubRooms
    case douyuRoomIdsCountError
    
    case isNotLiving
    case notFindUrls
    case notSupported
    
    case cantFindIdForDM
    
    case prepareDMFailed
    
    case cantWatch
    case notFountData
    case needVip
	case needLogin
    case needPassWork
}
