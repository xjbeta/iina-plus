//
//  DouYin.swift
//  IINA+
//
//  Created by xjbeta on 2/19/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa
import WebKit
import SwiftSoup
import Alamofire
import Marshal

actor DouYin: SupportSiteProtocol {
    
    // MARK: - DY Init
    
    @MainActor
	lazy var cookiesManager = DouyinCookiesManager()
	
	func liveInfo(_ url: String) async throws -> any LiveInfo {
		let info = try await getEnterContent(url)
		return info
	}
	
	func decodeUrl(_ url: String) async throws -> YouGetJSON {
		let info = try await liveInfo(url)
		var json = YouGetJSON(rawUrl: url)
		
		if let info = info as? DouYinEnterData.DouYinLiveInfo {
			json = info.write(to: json)
		} else if let info = info as? DouYinInfo {
			json = info.write(to: json)
		} else {
			throw VideoGetError.notFindUrls
		}
		
		return json
	}
    
	
	func getEnterContent(_ url: String) async throws -> LiveInfo {
		var headers = try await cookiesManager.headers()
		headers.add(name: "referer", value: url)
		
		guard let pc = NSURL(string: url)?.pathComponents,
			  pc.count >= 2,
			  pc[0] == "/" else {
			throw VideoGetError.invalidLink
		}
		
		let rid = try {
			if let _ = Int(pc[1]) {
				return pc[1]
			} else if pc.count >= 4, pc[2] == "live", let _ = Int(pc[3]) {
				return pc[3]
			} else {
				throw VideoGetError.invalidLink
			}
		}()
		
		let u = "https://live.douyin.com/webcast/room/web/enter/?aid=6383&app_name=douyin_web&live_id=1&device_platform=web&language=en-US&cookie_enabled=true&browser_language=en-US&browser_platform=Mac&browser_name=Safari&browser_version=16&web_rid=\(rid)&enter_source=&is_need_double_stream=true"

		
		do {
			let data = try await AF.request(u, headers: headers).serializingData().value
			let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(data)
			let enterData = try DouYinEnterData(object: jsonObj)
			
			if let info = enterData.infos.first {
				return info
			} else if let info = try? DouYinEnterData2(object: jsonObj) {
				return info
			} else {
				throw VideoGetError.notFountData
			}
		} catch {
			switch error {
			case AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength):
				Log("douyin inputDataNilOrZeroLength")
			default:
				break
			}
			throw error
		}
	}
	
    /*
    func getContent(_ url: String) async throws -> LiveInfo {
		var headers = try await cookiesManager.headers()
		headers.add(name: "referer", value: url)
        
		let text = try await AF.request(url, headers: headers).serializingString().value
		guard let json = getJSON(text) else {
			throw VideoGetError.notFountData
		}
		
		let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(json)
		
		if let re = try? DouYinInfo(object: jsonObj) {
			return re
		} else {
			let info: DouYinInfo = try jsonObj.value(for: "app")
			return info
		}
    }
    
	func getJSON(_ text: String) -> Data? {
		if text.contains("RENDER_DATA") {
//			return try? SwiftSoup
//				.parse(text)
//				.getElementById("RENDER_DATA")?
//				.data()
//				.removingPercentEncoding?
//				.data(using: .utf8)

			return text.subString(
				from: "<script id=\"RENDER_DATA\" type=\"application/json\">",
				to: "</script>")
			.removingPercentEncoding?
			.data(using: .utf8)
		} else {
			guard let s = text.split(separator: "\n").map(String.init).last else {
				return nil
			}
			
			var re = s.components(separatedBy: "self.__pace_f.push")
				.map {
					$0.subString(to: "</script>")
				}
				.compactMap { str -> String? in
					var s = str
					guard let f = s.firstIndex(of: "{"),
						  let e = s.lastIndex(of: "}")
					else { return nil }
					
					s.removeSubrange(e..<s.endIndex)
					s.removeSubrange(s.startIndex..<f)
					s += "}"
					
					s = s.replacingOccurrences(of: "\\\"", with: "\"")
					s = s.replacingOccurrences(of: "\\\"", with: "\"")
					if let sRange = s.range(of: "\"state\"") {
						s.replaceSubrange(sRange, with: "\"initialState\"")
					}
					return s
				}
			
			guard re.count > 0 else { return nil }
			
			re = re.filter {
				$0.contains("web_rid")
			}

			return re.first?.data(using: .utf8)
		}
	}
	*/
}

struct DouYinInfo: Unmarshaling, LiveInfo {
    var title: String
    var name: String
    var avatar: String
    var cover: String
    var isLiving: Bool
    var site = SupportSites.douyin
    
    var roomId: String
    var webRid: String
    var urls = [String: String]()
    
    
    init(object: MarshaledObject) throws {
        if let rid: String = try? object.value(for: "initialState.roomStore.roomInfo.roomId") {
            roomId = rid
        } else {
            roomId = try object.value(for: "initialState.roomStore.roomInfo.room.id_str")
        }
        webRid = try object.value(for: "initialState.roomStore.roomInfo.web_rid")
        
        title = try object.value(for: "initialState.roomStore.roomInfo.room.title")
        let status: Int = try object.value(for: "initialState.roomStore.roomInfo.room.status")
        isLiving = status == 2
        
        let flvUrls: [String: String]? = try? object.value(for: "initialState.roomStore.roomInfo.room.stream_url.flv_pull_url")
        urls = flvUrls ?? [:]
        
        /*
        let hlsUrls: [String: String] = try object.value(for: "initialState.roomStore.roomInfo.room.stream_url.hls_pull_url_map")
         */
        //        name = try object.value(for: "initialState.roomStore.roomInfo.room.stream_url.live_core_sdk_data.anchor.nickname")
        
        name = try object.value(for: "initialState.roomStore.roomInfo.anchor.nickname")
        
        let covers: [String]? = try object.value(for: "initialState.roomStore.roomInfo.room.cover.url_list")
        cover = covers?.first ?? ""
        
        let avatars: [String] = try object.value(for: "initialState.roomStore.roomInfo.anchor.avatar_thumb.url_list")
        avatar = avatars.first ?? ""
    }
    
    func write(to yougetJson: YouGetJSON) -> YouGetJSON {
        var json = yougetJson
        json.title = title
        
        
        urls.map {
            ($0.key, $0.value.https())
        }.sorted { v0, v1 in
            v0.0 < v1.0
        }.enumerated().forEach {
            var stream = Stream(url: $0.element.1)
            stream.quality = 999 - $0.offset
            json.streams[$0.element.0] = stream
        }
        
        return json
    }
}

struct DouYinEnterData: Unmarshaling {
	var infos: [DouYinLiveInfo]
	
	struct DouYinLiveInfo: Unmarshaling, LiveInfo {
		var title: String
		var name: String
		var avatar: String
		var cover: String
		var isLiving: Bool
		var site = SupportSites.douyin
		
		var urls: [String: String]
		var roomId: String
		
		var qualities: [Qualitie]
		
		init(object: MarshaledObject) throws {
			title = try object.value(for: "title")
			
			name = (try? object.value(for: "owner.nickname")) ?? ""
			let avatars: [String] = (try? object.value(for: "owner.avatar_thumb.url_list")) ?? []
			avatar = avatars.first ?? ""
			let covers: [String] = (try? object.value(for: "cover.url_list")) ?? []
			cover = covers.first ?? ""
			
			
			let status: Int = try object.value(for: "status")
			isLiving = status == 2
						
			roomId = try object.value(for: "id_str")
			
			qualities = (try? object.value(for: "stream_url.live_core_sdk_data.pull_data.options.qualities")) ?? []
			
			guard let streamData: String = try? object.value(for: "stream_url.live_core_sdk_data.pull_data.stream_data"),
				  let data = streamData.data(using: .utf8) else {
//				#warning("FULL_HD1 only hls")
				urls = (try? object.value(for: "stream_url.flv_pull_url")) ?? [:]
				return
			}
			let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(data)
			
			qualities = [
				.init(name: "原画", level: 4, sdkKey: "origin"),
				.init(name: "超清", level: 3, sdkKey: "hd"),
				.init(name: "高清", level: 2, sdkKey: "sd"),
				.init(name: "标清", level: 1, sdkKey: "ld"),
			]
			
			var urls = [String: String]()
			qualities.forEach { q in
				urls[q.sdkKey] = try? jsonObj.value(for: "data.\(q.sdkKey).main.flv")
			}
			self.urls = urls
		}
		
		func write(to yougetJson: YouGetJSON) -> YouGetJSON {
			var json = yougetJson
			json.title = title

			urls.map {
				($0.key, $0.value.https())
			}.sorted { v0, v1 in
				v0.0 < v1.0
			}.enumerated().forEach {
				let ku = $0.element
				let u = ku.1
				var stream = Stream(url: u)
				
				if let q = qualities.first(where: { $0.sdkKey == ku.0 }),
				   !q.disable {
					stream.quality = 900 + q.level
					json.streams[q.name] = stream
				} else if let fn = URL(string: u)?.lastPathComponent,
						  let q = qualities.filter({ fn.subString(from: "_", to: ".").contains($0.sdkKey == "origin" ? "or" : $0.sdkKey) }).max(by: { $0.level < $1.level }),
						  !q.disable {
					stream.quality = 900 + q.level
					json.streams[q.name] = stream
				} else {
					stream.quality = 666 - $0.offset
					json.streams[$0.element.0] = stream
				}
			}

			return json
		}
	}
	
	struct Qualitie: Unmarshaling {
		let name: String
		let level: Int
		let sdkKey: String
		let disable: Bool
		
		init(name: String, level: Int, sdkKey: String, disable: Bool = false) {
			self.name = name
			self.level = level
			self.sdkKey = sdkKey
			self.disable = disable
		}
		
		init(object: MarshaledObject) throws {
			level = try object.value(for: "level")
			sdkKey = try object.value(for: "sdk_key")
			disable = try object.value(for: "disable")
			if sdkKey == "origin" {
				name = "原画"
			} else {
				name = try object.value(for: "name")
			}
		}
	}
	
	
	init(object: MarshaledObject) throws {
		infos = try object.value(for: "data.data")
		
		let name: String = try object.value(for: "data.user.nickname")
		let avatars: [String] = try object.value(for: "data.user.avatar_thumb.url_list")
		let avatar = avatars.first ?? ""
		
		self.infos = infos.map {
			var info = $0
			if !info.isLiving {
				info.name = name
				info.avatar = avatar
			}
			return info
		}
		
	}
}


struct DouYinEnterData2: Unmarshaling, LiveInfo {
	var title: String
	var name: String
	var avatar: String
	var cover: String
	var isLiving: Bool
	var site = SupportSites.douyin
	
	init(object: MarshaledObject) throws {
		title = "直播已结束"
		name = try object.value(for: "data.user.nickname")
		
		let avatars: [String] = (try? object.value(for: "data.user.avatar_thumb.url_list")) ?? []
		
		avatar = avatars.first ?? ""
		cover = ""
		isLiving = false
	}
}
