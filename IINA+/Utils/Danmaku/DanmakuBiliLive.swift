//
//  DanmakuBiliLive.swift
//  IINA+
//
//  Created by xjbeta on 2023/8/20.
//  Copyright © 2023 xjbeta. All rights reserved.
//

import Cocoa
import Marshal
import Alamofire
import SDWebImage

extension Danmaku {
	
	struct BiliLiveMsgV2: Decodable {
		var dm: String
		enum CodingKeys: String, CodingKey {
			case dm = "dm_v2"
		}
	}
	
	struct BiliLiveInteractiveGameMsg: Unmarshaling {
		static let cmdString = "LIVE_INTERACTIVE_GAME"
		
		let cmd: String
		let dm: String?
		
		init(object: MarshaledObject) throws {
			cmd = try object.value(for: "cmd")
			dm = try? object.value(for: "data.msg")
		}
	}
	
	struct BiliLiveExtraMsg: Unmarshaling {
		let content: String
		let emots: [String: BiliLiveEmoticon]
		let emoticonUnique: String?
		
		init(object: MarshaledObject) throws {
			content = try object.value(for: "content")
			let ems: [String: BiliLiveEmoticon]? = try? object.value(for: "emots")
			emots = ems ?? [:]
			emoticonUnique = try? object.value(for: "emoticon_unique")
		}
	}
	
	struct BiliLiveEmoticon: Unmarshaling {
		var emoji: String = ""
		var url: String
		var width: Int = 0
		var height: Int = 0
//		var identity: Int = 0
		let emoticonUnique: String
		var emoticonId: Int = 0
		
		var emoticonData: Data?
		
		init(_ emoticonUnique: String, url: String) {
			self.emoticonUnique = emoticonUnique
			self.url = url
		}
		
		init(object: MarshaledObject) throws {
			emoji = try object.value(for: "emoji")
			let u: String = try object.value(for: "url")
			url = u.https()
			width = try object.value(for: "width")
			height = try object.value(for: "height")
//			identity = try object.value(for: "identity")
			emoticonUnique = try object.value(for: "emoticon_unique")
			emoticonId = try object.value(for: "emoticon_id")
		}
		
		func comment() -> DanmakuComment? {
			guard let base64 = emoticonData?.base64EncodedString(),
					base64.count > 0 else { return nil }
			
			let ext = NSString(string: url.lastPathComponent).pathExtension
			
			let size = {
				switch width {
				case _ where width > 200:
					return 200
//				case _ where width < 150:
//					return 150
				default:
					return width
				}
			}() / 2
			
			return DanmakuComment(
				text: "",
				imageSrc: "data:image/\(ext);base64," + base64,
				imageWidth: size)
		}
	}
	
	
	func bililiveRid(_ roomID: String) async throws -> String {
		let url = "https://api.live.bilibili.com/room/v1/Room/get_info?room_id=\(roomID)"
		let data = try await AF.request(url).serializingData().value
		let json = try JSONParser.JSONObjectWithData(data)
		let id: Int = try json.value(for: "data.room_id")
		return "\(id)"
	}
	
	func bililiveToken(_ rid: String) async throws -> String {
		let url = "https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo?id=\(rid)&type=0"
		let data = try await AF.request(url).serializingData().value
		let json = try JSONParser.JSONObjectWithData(data)
		
		return try json.value(for: "data.token")
	}
	
	
	func bililiveEmoticons(_ rid: String) async throws -> [BiliLiveEmoticon] {
		var emoticons = [BiliLiveEmoticon]()
		let url = "https://api.live.bilibili.com/xlive/web-ucenter/v2/emoticon/GetEmoticons?platform=pc&room_id=\(rid)"
		let data = try await AF.request(url).serializingData().value
		let json = try JSONParser.JSONObjectWithData(data)
		
		struct BiliLiveEmoticonData: Unmarshaling {
			let emoticons: [BiliLiveEmoticon]
			let pkgId: Int
			let pkgName: String
			init(object: MarshaledObject) throws {
				emoticons = try object.value(for: "emoticons")
				pkgId = try object.value(for: "pkg_id")
				pkgName = try object.value(for: "pkg_name")
			}
		}
		
		let emoticonData: [BiliLiveEmoticonData] = try json.value(for: "data.data")
		
		emoticonData.forEach {
			if $0.pkgName == "emoji" {
				let emojis = $0.emoticons.map {
					var emot = $0
					emot.width = 75
					emot.height = 75
					return emot
				}
				emoticons.append(contentsOf: emojis)
			} else {
				emoticons.append(contentsOf: $0.emoticons)
			}
		}
		
		await withTaskGroup(of: (Int, Data?).self) { group in
			emoticons.enumerated().forEach { e in
				group.addTask {
					async let data = self.loadBililiveEmoticon(e.element)
					return await (e.offset, data)
				}
			}
			
			for await e in group {
				emoticons[e.0].emoticonData = e.1
			}
		}
		return emoticons
	}
	
	func loadBililiveEmoticon(_ emoticon: BiliLiveEmoticon) async -> Data? {
		let key = "BiliLive_Emoticons_" + emoticon.emoticonUnique
		if let image = SDImageCache.shared.imageFromCache(forKey: key) {
			return image.sd_imageData()
		} else if let data = try? await AF.request(emoticon.url).serializingData().value {
			await SDImageCache.shared.store(NSImage(data: data), forKey: key)
			return data
		} else {
			return nil
		}
	}
	
	/*
	func testedBilibiliAPI() {
		let p = ["aid": 31027408,
				 "appkey": "1d8b6e7d45233436",
				 "build": 5310000,
				 "mobi_app": "android",
				 "oid": 54186450,
				 "plat":2,
				 "platform": "android",
				 "ps": 0,
				 "ts": 1536407932,
				 "type": 1,
				 "sign": 0] as [String : Any]
		AF.request("https://api.bilibili.com/x/v2/dm/list.so", parameters: p).response { re in
			let data = re.data
			let head = data.subdata(in: 0..<4)
			let endIndex = Int(CFSwapInt32(head.withUnsafeBytes { (ptr: UnsafePointer<UInt32>) in ptr.pointee })) + 4
			let d1 = data.subdata(in: 4..<endIndex)
			
			let d2 = data.subdata(in: endIndex..<data.endIndex)
			
			let d3 = try! d2.gunzipped()
			
			let str1 = String(data: d1, encoding: .utf8)
			let str2 = String(data: d3, encoding: .utf8)
			
			//            FileManager.default.createFile(atPath: "/Users/xjbeta/Downloads/d1", contents: d1, attributes: nil)
			//
			//            FileManager.default.createFile(atPath: "/Users/xjbeta/Downloads/d2", contents: d3, attributes: nil)
			
		}
	}
 
	 */
	
	
	func decodeBiliLiveDM(_ data: Data) -> DanmakuComment? {
		let decoder = JSONDecoder()
		
		if let msg = try? decoder.decode(BiliLiveMsgV2.self, from: data),
		   msg.dm != "",
		   let data = Data(base64Encoded: msg.dm) {
			
			do {
				let re = try BilibiliDm_Community_Service_Dm_Live_Dm(serializedBytes: data)
				
				if re.bizScene == .survive {
					return nil
				}
				
				if re.dmType == .emoticon,
				   let emoticon = re.emoticons.first?.value {
					//		emoticons {
					//		  key: "哇"
					//		  value {
					//			unique: "room_47867_14602"
					//			url: "http://i0.hdslb.com/bfs/garb/b2836ddf5c7e2bbcb9d7e80a84ae17ac102003eb.png"
					//			is_dynamic: true
					//			in_player_area: 1
					//			bulge_display: 1
					//			height: 162
					//			width: 162
					//		  }
					//		}
					return biliLiveEmoticonDM(
						url: emoticon.url,
						unique: emoticon.unique,
						width: .init(emoticon.width),
						height: .init(emoticon.height))
				}
				return DanmakuComment(text: re.text)
			} catch let error {
				print(error)
			}
		} else if let dm = biliLiveDM(data) {
			return dm
//		} else if let obj = try? JSONParser.JSONObjectWithData(data),
//				  let msg = try? BiliLiveInteractiveGameMsg(object: obj),
//				  msg.cmd == BiliLiveInteractiveGameMsg.cmdString,
//				  let dm = msg.dm {
//			return DanmakuComment(text: dm)
		} else {
			/*
			 guard let s = String(data: data, encoding: .utf8) else {
				 print(data)
				 return nil
			 }
			 
			 if [
				 "INTERACT_WORD",
				 "SEND_GIFT",
				 "ONLINE_RANK_COUNT",
				 "LIKE_INFO_V3_",
				 "WATCHED_CHANGE",
				 "ENTRY_EFFECT",
				 "POPULAR_RANK_CHANGED",
				 "ONLINE_RANK_V2",
				 "ONLINE_RANK_TOP3",
				 "AREA_RANK_CHANGED",
				 "WIDGET_GIFT_STAR_PROCESS",
				 "LIVE_INTERACTIVE_GAME"
			 ].contains(where: s.contains) {
				 return nil
			 }
			 print(s)
			 */
			return nil
		}
		
		return nil
	}
	
	func biliLiveDM(_ data: Data) -> DanmakuComment? {
		guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let cmd = json["cmd"] as? String,
			  cmd.starts(with: "DANMU_MSG")
		else {
			return nil
		}
		
		guard let info = json["info"] as? [Any],
			  info.count > 0,
			  let dms = info[0] as? [Any],
			  dms.count > 15 else {
			return nil
		}
		
		if let dm = dms[13] as? [String: Any],
		   let unique = dm["emoticon_unique"] as? String,
//		   let width = dm["width"] as? Int,
//		   let height = dm["height"] as? Int,
		   let url = dm["url"] as? String {
			
			return biliLiveEmoticonDM(
				url: url,
				unique: unique,
				width: 180,
				height: 180)
		} else if let dm = dms[15] as? [String: Any],
		   let extra = dm["extra"],
		   let str = extra as? String,
		   let data = str.data(using: .utf8),
		   let obj = try? JSONParser.JSONObjectWithData(data),
		   let msg = try? BiliLiveExtraMsg(object: obj) {
			
			guard !msg.emots.isEmpty else {
				if let unique = msg.emoticonUnique,
				   let emoticon = self.bililiveEmoticons.first(where: { $0.emoticonUnique == unique }) {
					return emoticon.comment()
				} else {
					return DanmakuComment(text: msg.content)
				}
			}
			
			let emot = msg.emots.values.first!
			
			return biliLiveEmoticonDM(
				url: emot.url,
				unique: emot.emoticonUnique,
				width: emot.width,
				height: emot.height)
		} else if let msg = info[1] as? String {
			return DanmakuComment(text: msg)
		} else {
			return nil
		}
	}
	
	func biliLiveEmoticonDM(url: String,
							unique: String,
							width: Int,
							height: Int) -> DanmakuComment? {
		
		if let emoticon = self.bililiveEmoticons.first(where: { $0.emoticonUnique == unique }) {
			return emoticon.comment()
		}
		
		let url = url.https()
		var emoticon = BiliLiveEmoticon(unique, url: url)
		
		emoticon.width = width
		emoticon.height = height
		
		if let image = SDImageCache.shared.imageFromCache(forKey: "BiliLive_Emoticons_" + emoticon.emoticonUnique) {
			emoticon.emoticonData = image.sd_imageData()
			self.bililiveEmoticons.append(emoticon)
			
			return emoticon.comment()
		} else {
			let emot = emoticon
			Task {
				let data = await self.loadBililiveEmoticon(emot)
				guard let i = bililiveEmoticons.firstIndex(where: { $0.emoticonUnique == unique }) else { return }
				bililiveEmoticons[i].emoticonData = data
			}
			self.bililiveEmoticons.append(emoticon)
			return nil
		}
	}
	
}
