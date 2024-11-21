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
		let ccid = try await getCC163Ccid(url)
		let cid = try await getCC163ChannelID(ccid)
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
			guard let ccid = (info as? CC163ChannelInfo)?.ccid else {
				throw VideoGetError.notFountData
			}
			
			return "\(ccid)"
        }
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

struct CC163VideoSelector: VideoSelector {
    let site = SupportSites.cc163
    let index: Int
    let title: String
    let ccid: String
    let isLiving: Bool
    let url: String
    let id: String
    let coverUrl: URL? = nil
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
        } else {
            ccid = try object.value(for: "ccid")
            isLiving = true
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
