//
//  Huya.swift
//  IINA+
//
//  Created by xjbeta on 4/22/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa
import Alamofire
import Marshal
import SwiftSoup

actor Huya: SupportSiteProtocol {
    
    lazy var pSession: Session = {
        let configuration = URLSessionConfiguration.af.default
        let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1"
        configuration.headers.add(.userAgent(ua))
        return Session(configuration: configuration)
    }()
	
	// T.a.uid
	private let huyaUid = (Int(Date().timeIntervalSince1970 * 1000) % Int(1e10) * Int(1e3) + Int.random(in: Int(1e2)..<Int(1e3))) % 4294967295
    
	func liveInfo(_ url: String) async throws -> any LiveInfo {
		try await getHuyaInfoMP(url)
	}
	
	func decodeUrl(_ url: String) async throws -> YouGetJSON {
		let info = try await getHuyaInfoMP(url)
		return info.videos(url, uid: huyaUid)
	}
    
    // MARK: - Huya
    
    struct HuyaRoomList {
        var current: String
        var list = [HuyaVideoSelector]()
    }
    
    
    // href, name
    func getHuyaRoomList(_ url: String) async throws -> HuyaRoomList {
		let text = try await AF.request(url).serializingString().value
		var re = HuyaRoomList(current: "")
		
		try SwiftSoup.parse(text).getElementsByClass("match-nav").first()?.children().enumerated().forEach {
			
			if try $0.element.attr("class") == "on" {
				re.current = try $0.element.attr("href")
			}
			
			try re.list.append(.init(
				id: $0.element.attr("href"),
				index: $0.offset,
				title: $0.element.text(),
				url: "https://www.huya.com/\($0.element.attr("href"))",
				isLiving: $0.element.getChildNodes().contains(where: { try $0.attr("class") == "live" })
			))
		}
		return re
    }
	
	func getHuyaInfo(_ url: String) async throws -> HuyaStream.GameLiveInfo {
		let obj = try await getPlayerConfig(url)
		let stream = try HuyaStream(object: obj)
		
		guard let data = stream.data.first else {
			throw VideoGetError.notFountData
		}
		var info = data.liveInfo
		info.isLiving = data.streamInfoList.count > 0
		
		return info
	}
    
    func getHuyaVideos(_ url: String) async throws -> YouGetJSON {
		let obj = try await getPlayerConfig(url)
		let info = try HuyaStream(object: obj)
		let yougetJson = YouGetJSON(rawUrl: url)
		return info.write(to: yougetJson, uid: huyaUid)
    }
	
	func getPlayerConfig(_ url: String) async throws -> JSONObject {
		let text = try await AF.request(url).serializingString().value
		
		let hyPlayerConfigStr: String? = {
			var str = text.subString(from: "var hyPlayerConfig = ", to: "window.TT_LIVE_TIMING")
			
			if let range = str.range(of: "stream:") {
				str.removeSubrange(str.startIndex..<range.upperBound)
				let c1 = str.indexes(of: "{")
				let c2 = str.indexes(of: "}")
				
				if c2.count > c1.count {
					str = String(str[str.startIndex...c2[c1.count-1]])
				}
			}
			return str
		}()
		
		guard let data = hyPlayerConfigStr?.data(using: .utf8) else {
			throw VideoGetError.notFountData
		}
		
		let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(data)
		return jsonObj
	}
    
    func getHuyaInfoM(_ url: String) async throws -> HuyaInfoM {
		let s = try await pSession.request(url).serializingString().value
		guard let jsonData = s.subString(from: "<script> window.HNF_GLOBAL_INIT = ", to: " </script>").data(using: .utf8) else {
			throw VideoGetError.notFindUrls
		}
		let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(jsonData)
		let info: HuyaInfoM = try HuyaInfoM(object: jsonObj)
		return info
    }
	
	func getHuyaInfoMP(_ url: String) async throws -> HuyaInfoMP {
		let ucs = url.pathComponents
		guard ucs.count >= 3 else {
			throw VideoGetError.invalidLink
		}
		let rid = ucs[2]
		
		if let rid = Int(rid) {
			return try await getHuyaInfoMP(rid)
		} else {
			let rid = try await getHuyaInfo(url).rid
			return try await getHuyaInfoMP(rid)
		}
	}
	
	func getHuyaInfoMP(_ rid: Int) async throws -> HuyaInfoMP {
		let u = "https://mp.huya.com/cache.php?m=Live&do=profileRoom&roomid=\(rid)"
		let data = try await pSession.request(u).serializingData().value
		let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(data)
		return try HuyaInfoMP(object: jsonObj)
	}
}

/*
struct HuyaInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var avatar: String
    var isLiving = false
    var rid: Int
    var cover: String = ""
    var site: SupportSites = .huya
    
    var isSeeTogetherRoom = false
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "introduction")
        name = try object.value(for: "nick")
        avatar = try object.value(for: "avatar")
        avatar = avatar.https()
        isLiving = "\(try object.any(for: "isOn"))" == "1"
        cover = try object.value(for: "screenshot")
        cover = cover.https()
        
		rid = try object.value(for: "profileRoom")
		
        let gameHostName: String = try object.value(for: "gameHostName")
        
        isSeeTogetherRoom = gameHostName == "seeTogether"
    }
}
 */


struct HuyaStream: Unmarshaling {
	var data: [HuyaInfoData]
	var vMultiStreamInfo: [StreamInfo]
	
	private let bitrateMap = [
		4100: 17200,
		4200: 17100,
		4300: 17300,
		14100: 14200,
		20100: 19200
	]
	
	init(object: MarshaledObject) throws {
		data = try object.value(for: "data")
		vMultiStreamInfo = try object.value(for: "vMultiStreamInfo")
	}
	
	func write(to yougetJson: YouGetJSON, uid: Int) -> YouGetJSON {
		var yougetJson = yougetJson
		
		if let infoData = data.first {
			yougetJson.title = infoData.liveInfo.title
			
			let urls = infoData.streamInfoList.map {
				$0.url(uid)
			}
			
			vMultiStreamInfo.enumerated().forEach {
				var rate = $0.element.iBitRate
				
				let isFakeHdr = 16384 == (16384 & $0.element.iCompatibleFlag)
				if isFakeHdr {
					rate = bitrateMap[rate] ?? rate
				}
				
				var us = urls.map {
					if rate != 0 {
						$0.replacingOccurrences(of: "&ratio=0", with: "&ratio=\(rate)")
					} else {
						$0.replacingOccurrences(of: "&ratio=0", with: "")
					}
				}
				
				var s = Stream(url: us.removeFirst())
				s.src = us
				s.quality = 9999 - $0.offset
				yougetJson.streams[$0.element.sDisplayName] = s
			}
		}
		
		return yougetJson
	}
	
	struct StreamInfo: Unmarshaling {
		var sDisplayName: String
		var iBitRate: Int
		var iCodecType: Int
		var iCompatibleFlag: Int
		var iHEVCBitRate: Int
		
		init(object: MarshaledObject) throws {
			sDisplayName = try object.value(for: "sDisplayName")
			iBitRate = try object.value(for: "iBitRate")
			iCodecType = try object.value(for: "iCodecType")
			iCompatibleFlag = try object.value(for: "iCompatibleFlag")
			iHEVCBitRate = try object.value(for: "iHEVCBitRate")
		}
	}
	
	struct HuyaInfoData: Unmarshaling {
		var liveInfo: GameLiveInfo
		var streamInfoList: [GameStreamInfo]
		
		init(object: MarshaledObject) throws {
			liveInfo = try object.value(for: "gameLiveInfo")
			streamInfoList = try object.value(for: "gameStreamInfoList")
		}
	}
	
	struct GameLiveInfo: Unmarshaling, LiveInfo {
		
		var title: String = ""
		var name: String = ""
		var isLiving = false
		var avatar: String
		var rid: Int
		var cover: String = ""
		var site: SupportSites = .huya
		let uid: Int
		
		var isSeeTogetherRoom = false
		let isSecret: Int
		
		
		init(object: MarshaledObject) throws {
			let name1: String = try object.value(for: "roomName")
			let name2: String = try object.value(for: "introduction")
			
			title = name1 == "" ? name2 : name1
			name = try object.value(for: "nick")
			
			avatar = try object.value(for: "avatar180")
			avatar = avatar.https()
			rid = try object.value(for: "profileRoom")
			cover = try object.value(for: "screenshot")
			cover = cover.https()
			
			if let uid: Int = try? object.value(for: "uid") {
				self.uid = uid
			} else if let uid: String = try? object.value(for: "uid"),
					  let iuid = Int(uid) {
				self.uid = iuid
			} else {
				throw MarshalError.keyNotFound(key: "huya.GameLiveInfo.uid")
			}
			
			isSecret = try object.value(for: "isSecret")
			let gameHostName: String = try object.value(for: "gameHostName")
			isSeeTogetherRoom = gameHostName == "seeTogether"
		}
	}
	
	struct GameStreamInfo: Unmarshaling {
		var sStreamName: String
		var sFlvUrl: String
		var sFlvUrlSuffix: String
		var sFlvAntiCode: String
		
		init(object: MarshaledObject) throws {
			sStreamName = try object.value(for: "sStreamName")
			sFlvUrl = try object.value(for: "sFlvUrl")
			sFlvUrlSuffix = try object.value(for: "sFlvUrlSuffix")
			sFlvAntiCode = try object.value(for: "sFlvAntiCode")
		}
		
		func url(_ uid: Int) -> String {
			HuyaUrl.format(uid, sStreamName: sStreamName, sFlvUrl: sFlvUrl, sFlvUrlSuffix: sFlvUrlSuffix, sFlvAntiCode: sFlvAntiCode)
		}
	}
}


struct HuyaInfoM: Unmarshaling, LiveInfo {

    var title: String = ""
    var name: String = ""
    var avatar: String
    var isLiving = false
    var rid: Int
    var cover: String = ""
    var site: SupportSites = .huya
    
    var isSeeTogetherRoom = false
    
	
	let defaultCDN: String
	let streamInfos: [StreamInfo]
	let bitRateInfos: [BitRateInfo]
    
    struct StreamInfo: Unmarshaling {
        let sFlvUrl: String
        let sStreamName: String
        let sFlvUrlSuffix: String
        let sFlvAntiCode: String
        
        let sCdnType: String
        
        init(object: MarshaledObject) throws {
            sFlvUrl = try object.value(for: "sFlvUrl")
            sStreamName = try object.value(for: "sStreamName")
            sFlvUrlSuffix = try object.value(for: "sFlvUrlSuffix")
            sFlvAntiCode = try object.value(for: "sFlvAntiCode")
            
            sCdnType = try object.value(for: "sCdnType")
        }
    }
    
    struct BitRateInfo: Unmarshaling {
        let sDisplayName: String
        let iBitRate: Int
        
        init(object: MarshaledObject) throws {
            sDisplayName = try object.value(for: "sDisplayName")
            iBitRate = try object.value(for: "iBitRate")
        }
    }
    
    
    init(object: MarshaledObject) throws {
        name = try object.value(for: "roomInfo.tProfileInfo.sNick")
        
		avatar = try object.value(for: "roomInfo.tProfileInfo.sAvatar180")
        avatar = avatar.https()
        
        let state: Int = try object.value(for: "roomInfo.eLiveStatus")
        isLiving = state == 2
        
        
        let titleInfoKey = isLiving ? "tLiveInfo" : "tReplayInfo"
        let titleKey = ["sIntroduction", "sRoomName"]
        
        let titles: [String] = try titleKey.map {
            "roomInfo.\(titleInfoKey).\($0)"
        }.map {
            try object.value(for: $0)
        }
        
        title = titles.first {
            $0 != ""
        } ?? name
        
        rid = try object.value(for: "roomInfo.tProfileInfo.lProfileRoom")
        cover = try object.value(for: "roomInfo.tLiveInfo.sScreenshot")
        
        
		defaultCDN = try object.value(for: "roomInfo.tLiveInfo.tLiveStreamInfo.sDefaultLiveStreamLine")
        
		streamInfos = try object.value(for: "roomInfo.tLiveInfo.tLiveStreamInfo.vStreamInfo.value")

		bitRateInfos = try object.value(for: "roomInfo.tLiveInfo.tLiveStreamInfo.vBitRateInfo.value")
    }
	
	func write(to yougetJson: YouGetJSON, uid: Int) -> YouGetJSON {
		let yougetJson = yougetJson
		
		// HuyaUrl.format not work for m
		return yougetJson
		/*
		let urls = streamInfos.sorted { i1, i2 -> Bool in
			i1.sCdnType == defaultCDN
		}.sorted { i1, i2 -> Bool in
			!i1.sFlvUrl.contains("txdirect.flv.huya.com")
		}.compactMap {
			HuyaUrl.format(
				uid,
				sStreamName: $0.sStreamName,
				sFlvUrl: $0.sFlvUrl,
				sFlvUrlSuffix: $0.sFlvUrlSuffix,
				sFlvAntiCode: $0.sFlvAntiCode)
		}
		
		guard urls.count > 0 else {
			return yougetJson
		}
		
		bitRateInfos.map {
			($0.sDisplayName, $0.iBitRate)
		}.forEach { (name, rate) in
			var us = urls.map {
				$0.replacingOccurrences(of: "&ratio=0", with: "&ratio=\(rate)")
			}
			var s = Stream(url: us.removeFirst())
			s.src = us
			s.quality = rate == 0 ? 9999999 : rate
			
			yougetJson.streams[name] = s
		}
		
		return yougetJson
		 */
	}
}

struct HuyaInfoMP: Unmarshaling, LiveInfo {
	
	var title: String
	var name: String
	var avatar: String
	var cover: String
	var isLiving: Bool
	var site: SupportSites = .huya
	
	var streamInfos: [HuyaInfoM.StreamInfo]
	var bitRateInfos: [HuyaInfoM.BitRateInfo]
	
	init(object: any Marshal.MarshaledObject) throws {
		let name1: String = try object.value(for: "data.liveData.roomName")
		let name2: String = try object.value(for: "data.liveData.introduction")
		
		title = name1 == "" ? name2 : name1
		
		name = try object.value(for: "data.liveData.nick")
		avatar = try object.value(for: "data.liveData.avatar180")
		avatar = avatar.https()
		cover = try object.value(for: "data.liveData.screenshot")
		cover = cover.https()
		
		let liveStatus: String = try object.value(for: "data.liveStatus")
		isLiving = liveStatus == "ON"
		
		if isLiving {
			streamInfos = try object.value(for: "data.stream.baseSteamInfoList")
			
			let bitRateInfoString: String = try object.value(for: "data.liveData.bitRateInfo")
			guard let data = bitRateInfoString.data(using: .utf8) else {
				throw VideoGetError.notFountData
			}
			let jsonObj: [JSONObject] = try JSONParser.JSONArrayWithData(data)
			bitRateInfos = try jsonObj.map(HuyaInfoM.BitRateInfo.init)
		} else {
			streamInfos = []
			bitRateInfos = []
		}
	}
	
	
	func videos(_ url: String, uid: Int) -> YouGetJSON {
		var yougetJson = YouGetJSON(rawUrl: url)
		yougetJson.title = title
		
		let urls = streamInfos
//			.sorted { i1, i2 -> Bool in
//			i1.sCdnType == defaultCDN
//		}
			.sorted { i1, i2 -> Bool in
			!i1.sFlvUrl.contains("txdirect.flv.huya.com")
		}.compactMap {
			HuyaUrl.format(
				uid,
				sStreamName: $0.sStreamName,
				sFlvUrl: $0.sFlvUrl,
				sFlvUrlSuffix: $0.sFlvUrlSuffix,
				sFlvAntiCode: $0.sFlvAntiCode)
		}
		
		guard urls.count > 0 else {
			return yougetJson
		}
		
		bitRateInfos.map {
			($0.sDisplayName, $0.iBitRate)
		}.forEach { (name, rate) in
			var us = urls.map {
				$0.replacingOccurrences(of: "&ratio=0", with: "&ratio=\(rate)")
			}
			var s = Stream(url: us.removeFirst())
			s.src = us
			s.quality = rate == 0 ? 9999999 : rate
			
			yougetJson.streams[name] = s
		}
		
		return yougetJson
	}
}


struct HuyaVideoSelector: VideoSelector {
    var id: String
    var coverUrl: URL?
    
    let site = SupportSites.huya
    let index: Int
    let title: String
    let url: String
    let isLiving: Bool
}
