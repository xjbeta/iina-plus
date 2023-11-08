//
//  DanmakuBiliLive.swift
//  IINA+
//
//  Created by xjbeta on 2023/8/20.
//  Copyright © 2023 xjbeta. All rights reserved.
//

import Cocoa
import Marshal
import PromiseKit
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
	
	struct BiliLiveEmoticon: Unmarshaling {
		var emoji: String = ""
		var url: String
		var width: Int = 0
		var height: Int = 0
		var identity: Int = 0
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
			url = u.replacingOccurrences(of: "http://", with: "https://")
			width = try object.value(for: "width")
			height = try object.value(for: "height")
			identity = try object.value(for: "identity")
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
				case _ where width < 150:
					return 150
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
	
	
	func bililiveRid(_ roomID: String) -> Promise<(String)> {
		return Promise { resolver in
			AF.request("https://api.live.bilibili.com/room/v1/Room/get_info?room_id=\(roomID)").response {
				do {
					let json = try JSONParser.JSONObjectWithData($0.data ?? Data())
					let id: Int = try json.value(for: "data.room_id")
					resolver.fulfill("\(id)")
				} catch let error {
					resolver.reject(error)
				}
			}
		}
	}
	
	func bililiveToken(_ rid: String) -> Promise<(String)> {
		return Promise { resolver in
			AF.request("https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo?id=\(rid)&type=0").response {
				do {
					let json = try JSONParser.JSONObjectWithData($0.data ?? Data())
					let token: String = try json.value(for: "data.token")
					resolver.fulfill(token)
				} catch let error {
					resolver.reject(error)
				}
			}
		}
	}
	
	
	func bililiveEmoticons(_ rid: String) -> Promise<([BiliLiveEmoticon])> {
		var emoticons = [BiliLiveEmoticon]()
		
		return AF.request("https://api.live.bilibili.com/xlive/web-ucenter/v2/emoticon/GetEmoticons?platform=pc&room_id=\(rid)").responseData().get {
			
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
			
			let json = try JSONParser.JSONObjectWithData($0.data)
			let emoticonData: [BiliLiveEmoticonData] = try json.value(for: "data.data")
			emoticons = emoticonData.flatMap {
				$0.emoticons
			}
		}.then { _ in
			when(fulfilled: emoticons.enumerated().map { e in
				self.loadBililiveEmoticon(e.element).done {
					emoticons[e.offset].emoticonData = $0
				}
			})
		}.map {
			emoticons
		}
	}
	
	func loadBililiveEmoticon(_ emoticon: BiliLiveEmoticon) -> Promise<Data?> {
		let key = "BiliLive_Emoticons_" + emoticon.emoticonUnique
		if let image = SDImageCache.shared.imageFromCache(forKey: key) {
			return .value(image.sd_imageData())
		} else {
			return AF.request(emoticon.url).responseData().get {
				SDImageCache.shared.store(NSImage(data: $0.data), forKey: key)
			}.map {
				$0.data
			}
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
		
		
		if let msg = try? decoder.decode(BiliLiveMsgV2.self, from: data) {
			guard let data = Data(base64Encoded: msg.dm) else { return nil }
			
			do {
				let re = try BilibiliDm_Community_Service_Dm_Live_Dm(serializedData: data)
				
				if re.bizScene == .survive {
					return nil
				}
				
				if re.dmType == .emoticon,
				   let emoticon = re.emoticons.first {
					return biliLiveEmoticonDM(emoticon)
				}
				return DanmakuComment(text: re.text)
			} catch let error {
				print(error)
			}
		} else if let obj = try? JSONParser.JSONObjectWithData(data),
				  let msg = try? BiliLiveInteractiveGameMsg(object: obj),
				  msg.cmd == BiliLiveInteractiveGameMsg.cmdString,
				  let dm = msg.dm {
			return DanmakuComment(text: dm)
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
			 ].contains(where: s.contains) {
				 return nil
			 }
			 print(s)
			 */
			return nil
		}
		
		return nil
	}
	
	
	func biliLiveEmoticonDM(_ emot: BilibiliDm_Community_Service_Dm_Live_emots) -> DanmakuComment? {
		
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
		
		
		if let emoticon = self.bililiveEmoticons.first(where: { $0.emoticonUnique == emot.value.unique }) {
			return emoticon.comment()
		}
		
		let url = emot.value.url.replacingOccurrences(of: "http://", with: "https://")
		var emoticon = BiliLiveEmoticon(emot.value.unique, url: url)
		
		emoticon.width = Int(emot.value.width)
		emoticon.height = Int(emot.value.height)
		
		if let image = SDImageCache.shared.imageFromCache(forKey: "BiliLive_Emoticons_" + emoticon.emoticonUnique) {
			emoticon.emoticonData = image.sd_imageData()
			self.bililiveEmoticons.append(emoticon)
			
			return emoticon.comment()
		} else {
			loadBililiveEmoticon(emoticon).done {
				guard let i = self.bililiveEmoticons.firstIndex(where: { $0.emoticonUnique == emot.value.unique }) else { return }
				self.bililiveEmoticons[i].emoticonData = $0
			}.cauterize()
			self.bililiveEmoticons.append(emoticon)
			return nil
		}
	}
	
}
