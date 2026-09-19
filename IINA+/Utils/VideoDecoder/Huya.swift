//
//  Huya.swift
//  IINA+
//
//  Created by xjbeta on 4/22/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa
import Alamofire
import SwiftSoup
import HuyaKit

actor Huya: SupportSiteProtocol {
    
	func liveInfo(_ url: String) async throws -> any LiveInfo {
		try await getHuyaInfo(url)
	}
	
    func decodeUrl(_ url: String) async throws -> YouGetJSON {
		try await getHuyaVideos(url)
	}
    
    // MARK: - Huya
    
    struct HuyaRoomList {
        var current: String
        var list = [VideoTreeNode]()
    }
    
    
    // href, name
    func getHuyaRoomList(_ url: String) async throws -> HuyaRoomList {
		let text = try await AF.request(url).serializingString().value
		var re = HuyaRoomList(current: "")
		
		try SwiftSoup.parse(text).getElementsByClass("match-nav").first()?.children().enumerated().forEach {
			
			if try $0.element.attr("class") == "on" {
				re.current = try $0.element.attr("href")
			}
			
			try re.list.append(VideoTreeNode(
				site: .huya,
				index: $0.offset,
				title: $0.element.text(),
				id: $0.element.attr("href"),
				url: "https://www.huya.com/\($0.element.attr("href"))",
				isLiving: $0.element.getChildNodes().contains(where: { try $0.attr("class") == "live" })
			))
		}
		return re
    }
	
	func getHuyaInfo(_ url: String) async throws -> HuyaStream.GameLiveInfo {
		let stream = try await getHuyaStream(url)
		
		guard let data = stream.data.first else {
			throw VideoGetError.notFountData
		}
		var info = data.liveInfo
		info.isLiving = data.streamInfoList.count > 0
		
		return info
	}
    
    func getHuyaVideos(_ url: String) async throws -> YouGetJSON {
		let stream = try await getHuyaStream(url)
		let yougetJson = YouGetJSON(rawUrl: url)
		return stream.write(to: yougetJson)
    }
	
	func getHuyaStream(_ url: String) async throws -> HuyaStream {
		let ucs = url.pathComponents
		guard ucs.count >= 3 else {
			throw VideoGetError.invalidLink
		}
		
		if let rid = Int(ucs[2]) {
			return try await HuyaStream.fetch(roomId: "\(rid)")
		}
		
		// Non-numeric path (e.g. /lpl): one fetch, the rid comes with the stream
		return try await HuyaStream.fetch(url: url)
	}
}

// MARK: - HuyaStream app extensions

extension HuyaStream {
	func write(to yougetJson: YouGetJSON) -> YouGetJSON {
		var yougetJson = yougetJson
		
		if let infoData = data.first {
			yougetJson.title = infoData.liveInfo.title
			yougetJson.id = infoData.liveInfo.rid
			
			let isLiving = infoData.streamInfoList.count > 0
			guard isLiving, infoData.liveInfo.rid > 0 else {
				return yougetJson
			}
			
			// Local proxy (.slice -> FLV); path token = uuid, matched by
			// startPrewarm(uuid:roomId:rate:)（选档在 prewarm 时确定 codecType）
			let port = Preferences.shared.dmPort
			let huyaUrl = "http://127.0.0.1:\(port)/huya/\(yougetJson.uuid).flv"
			
			// One entry per resolution: quality = server iBitRate (0 = 原画/HEVC),
			// qualityIndex = position in the playable list (menu order follows it,
			// e.g. lpl 2K before 蓝光10M); same-name pairs keep the playable
			// variant: 265 只在有等效码率(iHEVCBitRate>0)时优先，否则(0 码率胶囊)
			// 保留 H.264 档（否则拉不到可解码率）
			//
			// 档位来源统一为 playableStreamInfo（API 档位列表去掉全部 HDR 档）——
			// 与服务端选档同源，避免菜单里能选到一个服务端会拒绝的 HDR 档
			let gears = playableStreamInfo
			var best = [String: StreamInfo]()
			for info in gears {
				if let cur = best[info.sDisplayName] {
					if cur.iCodecType == 0, info.iCodecType != 0, info.iHEVCBitRate > 0 {
						best[info.sDisplayName] = info
					}
				} else {
					best[info.sDisplayName] = info
				}
			}
			var seen = Set<String>()
			for (idx, info) in gears.enumerated() {
				guard best[info.sDisplayName]?.iCodecType == info.iCodecType,
					  seen.insert(info.sDisplayName).inserted else { continue }
				var s = Stream(url: huyaUrl)
				s.quality = info.iBitRate
				s.qualityIndex = idx
				yougetJson.streams[info.sDisplayName] = s
			}
		}
		
		return yougetJson
	}
}

extension HuyaStream.GameLiveInfo: LiveInfo {
	var site: SupportSites { .huya }
}

