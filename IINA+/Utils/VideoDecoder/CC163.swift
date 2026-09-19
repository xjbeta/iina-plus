//
//  CC163.swift
//  IINA+
//
//  Created by xjbeta on 4/22/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa
import Alamofire
import Marshal
import SwiftSoup

actor CC163: SupportSiteProtocol {
    
    // ds common config id, hardcoded in the official SPA, do not randomize
    private static let dsCommonAppConfigId = "67b32cdd1801fc391a6c2657"
    
	func liveInfo(_ url: String) async throws -> any LiveInfo {
		if url.pathComponents.count == 4,
		   url.pathComponents[2] == "ccid" {
			var info = BilibiliInfo()
			info.site = .cc163
			info.isLiving = true
			return info
		} else {
			let info = try await getCC163Info(url)
			return info
		}
	}
	
	func decodeUrl(_ url: String) async throws -> YouGetJSON {
		let cid: Int
		if let channelID = cc163ChannelID(url) {
			cid = channelID
		} else if let ds = DS163Glive(url: url) {
			if let channelID = ds.channelID {
				cid = channelID
			} else if let ccid = ds.ccid {
				cid = try await getCC163ChannelID(ccid)
			} else if let appKey = ds.appKey {
				let info = try await getCC163Info(url)
				guard let ccid = (info as? CC163ChannelInfo)?.ccid else {
					throw VideoGetError.notFountData
				}
				cid = try await getCC163ChannelID("\(ccid)")
			} else {
				throw VideoGetError.invalidLink
			}
		} else {
			let ccid = try await getCC163Ccid(url)
			cid = try await getCC163ChannelID(ccid)
		}
		let videos = try await getCC163Videos(cid)
		guard let v = videos.first else { throw VideoGetError.notFountData }
		let json = v.write(to: YouGetJSON(rawUrl: url))
		return json
	}
    
    
    func getCC163Info(_ url: String) async throws -> LiveInfo {
		let state = try await getCC163State(url)
		if let i = state.info {
			return i
		} else if let cid = state.list.first?.cid {
			return try await getCC163ZtState(cid: "\(cid)")
		} else {
			throw VideoGetError.invalidLink
		}
    }
    
    func getCC163State(_ url: String) async throws -> (info: LiveInfo?, list: [CC163ChannelInfo]) {
		
		// ds.163.com/glive: single room (?ccRoomid=/?ccChannelid= or ?ccid=), list (?appKey=)
		if let ds = DS163Glive(url: url) {
			if let channelID = ds.channelID {
				let info = try await getCC163ZtState(cid: "\(channelID)")
				return (info, [])
			}
			if let ccid = ds.ccid {
				let channelID = try await getCC163ChannelID(ccid)
				let info = try await getCC163ZtState(cid: "\(channelID)")
				return (info, [])
			}
			if let appKey = ds.appKey {
				let target = try await cc163AppKeyTargetURL(appKey)
				let list = try await getCC163AppKeyRooms(target)
				guard let first = list.first else {
					throw VideoGetError.notFountData
				}
				return (first, list)
			}
			throw VideoGetError.invalidLink
		}
		
		// cc.163.com/{roomId}/{channelId} now redirects to the ds.163.com SPA
		if let channelID = cc163ChannelID(url) {
			let info = try await getCC163ZtState(cid: "\(channelID)")
			return (info, [])
		}
		
		// cc.163.com/ccid/{ccid} is the app's canonical room link, not a real page
		let pcs = url.pathComponents
		if pcs.count == 4, pcs[2] == "ccid" {
			let channelID = try await getCC163ChannelID(pcs[3])
			let info = try await getCC163ZtState(cid: "\(channelID)")
			return (info, [])
		}
		
		let re = try await AF.request(url).serializingString().value
		
		guard let jsonData = re.subString(from: "__NEXT_DATA__", to: "</script>").subString(from: ">").data(using: .utf8) else {
			throw VideoGetError.notFountData
		}
		let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(jsonData)
		
		if let _: String = try? jsonObj.value(for: "query.domain") {
			let list = try self.getCC163ZtRoomList(jsonObj)
			guard list.count > 0 else {
				throw VideoGetError.notFountData
			}
			
			if let cid = list.first!.cid {
				let info = try await getCC163ZtState(cid: "\(cid)")
				return (info, list)
			} else {
				return (list.first, list)
			}
		} else if let cid: String = try? jsonObj.value(for: "query.subcId") {
			let info = try await getCC163ZtState(cid: cid)
			return (info, [])
		} else {
			let info = try CC163Info(object: jsonObj)
			return (info, [])
		}
    }
    
    func getCC163ZtRoomList(_ json: JSONObject) throws -> [CC163ChannelInfo] {
    
        
        let fallback: [String: Any] = try json.value(for: "props.pageProps.fallback")
        
        let value = fallback.first {
            $0.key.contains("format=json")
        }?.value as? [String: Any]
        
        let obj = try (
            value?["module_infos"] as? [[String: Any]]
        )?.first {
            try $0.value(for: "module_type") == "living"
        }
        
        guard let obj = obj,
              let data = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted) else {
            return []
        }
         
        let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(data)
        return try jsonObj.value(for: "content")
    }
    
    func getCC163ZtState(cid: String) async throws -> LiveInfo {
		let u = "https://cc.163.com/live/channel/?channelids=\(cid)"
		let data = try await AF.request(u).serializingData().value
		let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(data)
		
		let infos: [CC163ChannelInfo] = try jsonObj.value(for: "data")
	
		guard let info = infos.first else {
			throw VideoGetError.notFountData
		}
		guard info.isLiving else {
			throw VideoGetError.isNotLiving
		}
		return info
    }
    
    func getCC163(_ ccid: String) async throws -> [String] {
		let u = "https://vapi.cc.163.com/video_play_url/\(ccid)"
		let data = try await AF.request(u).serializingData().value
		let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(data)
		
		var re = [String]()
		re.append(try jsonObj.value(for: "videourl"))
		re.append(try jsonObj.value(for: "bakvideourl"))
		
		return re
    }
    
    func getCC163Ccid(_ url: String) async throws -> String {
        let pcs = url.pathComponents
        if pcs.count == 4,
           pcs[2] == "ccid" {
            return pcs[3]
        } else {
			let info = try await getCC163Info(url)
			// single-room page -> CC163Info, channel list -> CC163ChannelInfo
			if let channelInfo = info as? CC163ChannelInfo {
				return "\(channelInfo.ccid)"
			}
			if let roomInfo = info as? CC163Info {
				return roomInfo.ccid
			}
			throw VideoGetError.notFountData
        }
    }
    
    private func cc163ChannelID(_ url: String) -> Int? {
        // use URLComponents.path: String.pathComponents keeps "?a=1" in the last segment
        guard let comps = URLComponents(string: url) else { return nil }
        let segs = comps.path.split(separator: "/").map(String.init)
        guard segs.count == 2,
              let _ = Int(segs[0]),
              let channelID = Int(segs[1]) else { return nil }
        return channelID
    }
    
    private struct DS163Glive {
        let ccid: String?
        let appKey: String?
        /// cc.163.com 301 target form: ?ccRoomid=..&ccChannelid=..
        let channelID: Int?
        
        init?(url: String) {
            guard let comps = URLComponents(string: url),
                  comps.host == "ds.163.com",
                  comps.path == "/glive" || comps.path == "/glive/" else { return nil }
            let items = comps.queryItems ?? []
            func query(_ name: String) -> String? {
                items.first { $0.name == name }?.value
            }
            ccid = query("ccid")
            appKey = query("appKey")
            channelID = query("ccChannelid").flatMap { Int($0) }
        }
    }
    
    // resolve appKey -> cc.163.com target page from the ds commonAppConfig
    private func cc163AppKeyTargetURL(_ appKey: String) async throws -> String {
        let u = "https://inf-act.ds.163.com/v1/act-web/pageConf/commonAppConfig"
        let data = try await AF.request(u,
                                        method: .post,
                                        parameters: ["id": Self.dsCommonAppConfigId],
                                        encoding: JSONEncoding.default).serializingData().value
        let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(data)
        let items: [[String: Any]] = try jsonObj.value(for: "result.itemList")
        guard let entry = items.first(where: { ($0["name"] as? String) == "直播入口列表" }),
              let list = entry["itemList"] as? [[String: Any]],
              let match = list.first(where: { ($0["name"] as? String) == appKey }),
              let content = match["content"] as? String else {
            throw VideoGetError.notSupported
        }
        return content
    }
    
    private func getCC163AppKeyRooms(_ targetURL: String, depth: Int = 0) async throws -> [CC163ChannelInfo] {
        // cap redirect hops: a looping redirect_url would spin forever
        guard depth < 3 else { throw VideoGetError.notFountData }
        
        let re = try await AF.request(targetURL).serializingString().value
        guard let jsonData = re.subString(from: "__NEXT_DATA__", to: "</script>").subString(from: ">").data(using: .utf8) else {
            throw VideoGetError.notFountData
        }
        let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(jsonData)
        
        if let _: String = try? jsonObj.value(for: "query.domain") {
            return try getCC163ZtRoomList(jsonObj)
        }
        if let lives: [CC163ChannelInfo] = try? jsonObj.value(for: "props.pageProps.gametypeData.lives") {
            return lives
        }
        // room page: follow the server-side redirect first (e.g. d90 -> NBPL event page)
        if let ccid: String = try? jsonObj.value(for: "query.ccid") {
            if let redirectURL: String = try? jsonObj.value(for: "props.pageProps.roomInfoInitData.redirect_url") {
                return try await getCC163AppKeyRooms(redirectURL, depth: depth + 1)
            }
            if let channelID = try? await getCC163ChannelID(ccid) {
                do {
                    if let info = try await getCC163ZtState(cid: "\(channelID)") as? CC163ChannelInfo {
                        return [info]
                    }
                } catch {
                    // keep isNotLiving so the UI reports it instead of "no data"
                    if let e = error as? VideoGetError, case .isNotLiving = e { throw e }
                }
            }
        }
        if let cid: String = try? jsonObj.value(for: "query.subcId") {
            do {
                if let info = try await getCC163ZtState(cid: cid) as? CC163ChannelInfo {
                    return [info]
                }
            } catch {
                if let e = error as? VideoGetError, case .isNotLiving = e { throw e }
            }
        }
        throw VideoGetError.notFountData
    }
    
	func getCC163ChannelID(_ ccid: String) async throws -> Int {
		let u = "https://api.cc.163.com/v1/activitylives/anchor/lives?anchor_ccid=\(ccid)"
		let data = try await AF.request(u).serializingData().value
		let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(data)
		return try jsonObj.value(for: "data.\(ccid).channel_id")
    }
    
    func getCC163Videos(_ channelID: Int) async throws -> [CC163NewVideos] {
		let u = "https://cc.163.com/live/channel/?channelids=\(channelID)"
		let data = try await AF.request(u).serializingData().value
		let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(data)
		return try jsonObj.value(for: "data")
    }
}

struct CC163Info: Unmarshaling, LiveInfo {
    var title: String
    var name: String
    var avatar: String
    var cover: String
    var isLiving: Bool
    var ccid: String
    var site: SupportSites
    
    init(object: MarshaledObject) throws {
        site = .cc163
        title = try object.value(for: "props.pageProps.roomInfoInitData.live.title")
        name = try object.value(for: "props.pageProps.roomInfoInitData.micfirst.nickname")
        avatar = try object.value(for: "props.pageProps.roomInfoInitData.micfirst.purl")
		avatar = avatar.https()
        cover = avatar
        let living: Bool? = try? object.value(for: "props.pageProps.roomInfoInitData.is_show_live_rcm")
        
        ccid = try object.value(for: "query.ccid")
        
        isLiving = living ?? false
    }
}

struct CC163ZTInfo {
    var name: String = ""
    var ccid: String = ""
    var channel: String = ""
    var cid: String = ""
    var index: String = ""
    var roomid: String = ""
    var isLiving: Bool = false
}

struct CC163ChannelInfo: Unmarshaling, LiveInfo {
    var title: String
    var name: String
    var avatar: String
    var cover: String
    var isLiving: Bool
    var site: SupportSites
    
    var ccid: Int
    var cid: Int?

    var channel: String
    
    init(object: MarshaledObject) throws {
        site = .cc163
        
        name = try object.optionalAny(for: "nickname") as? String ?? object.value(for: "name")
        channel = object.optionalAny(for: "living_channel") as? String ?? ""
        
        if let isLiving: Bool = try? object.value(for: "is_living") {
            self.isLiving = isLiving
            
            if let id: Int = try? object.value(for: "ccid") {
                ccid = id
            } else {
                ccid = try object.value(for: "channelid")
                cid = ccid
            }
            
        } else if let nolive: Int = try? object.value(for: "nolive"),
           nolive == 1 {
            ccid = try object.value(for: "roomid")
            isLiving = false
        } else if let status: Int = try? object.value(for: "status") {
            isLiving = status == 1
            ccid = try object.value(for: "ccid")
        } else {
            ccid = try object.value(for: "ccid")
            isLiving = true
        }
        
        // nolive rooms have no ccid (it holds roomid, often 0)
        if channel.isEmpty, ccid > 0 {
            channel = "https://cc.163.com/ccid/\(ccid)"
        }
        

        if isLiving {
            title = try object.value(for: "title")
            cover = try object.value(for: "cover")
            cover = cover.https()
            avatar = (try? object.value(for: "purl")) ?? ""
            avatar = avatar.https()
        } else {
            title = (try? object.value(for: "title")) ?? name
            cover = ""
            avatar = ""
        }
    }
}

protocol CC163Video {
    var vbr: Int { get }
    var urls: [String] { get set }
}

struct CC163NewVideos: Unmarshaling {
    let title: String
    let videos: [String: CC163Video]
    
    struct VideoItem: CC163Video, Unmarshaling {
        let vbr: Int
        var urls: [String]
        
        init(object: MarshaledObject) throws {
            vbr = try object.value(for: "vbr")
            let cdnItems: [String: Any] = try object.value(for: "cdn")
            
            urls = Array(cdnItems.compactMapValues({ $0 as? String }).values)
        }
    }
    
    struct StramItem: CC163Video, Unmarshaling {
        let vbr: Int
        var urls: [String]
        
        let streamname: String
        
        init(object: MarshaledObject) throws {
            vbr = try object.value(for: "vbr")
            streamname = try object.value(for: "streamname")
            let cdns: [String: String] = try object.value(for: "CDN_FMT")
            urls = [

            ]
            
            if let v = cdns["ali"] {
                urls.append("https://alipullhdlptscopy.cc.netease.com/pushstation/\(streamname).flv?\(v)")
            }
            
            if let v = cdns["ks"] {
                urls.append("https://kspullhdlptscopy.cc.netease.com/pushstation/\(streamname).flv?\(v)")
            }
        }
    }
    
    init(object: MarshaledObject) throws {
        videos = try {
            if let re: [String: VideoItem] = try? object.value(for: "quickplay.resolution") {
                return re
            } else {
                let re: [String: StramItem] = try object.value(for: "stream_list")
                return re
            }
        }()
        title = try object.value(for: "title")
    }
    
    func write(to yougetJson: YouGetJSON) -> YouGetJSON {
        var json = yougetJson
        json.title = title
        
        videos.filter {
            $0.value.urls.count > 0
        }.forEach {
            let video = $0.value
            var stream = Stream(url: video.urls.first!)
            stream.quality = video.vbr
            stream.src = Array(video.urls.dropFirst())
            json.streams[$0.key] = stream
        }
        
        return json
    }
}
