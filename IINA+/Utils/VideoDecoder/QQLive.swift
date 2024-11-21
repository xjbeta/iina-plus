//
//  QQLive.swift
//  IINA+
//
//  Created by xjbeta on 6/9/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa
import Alamofire
import Marshal

actor QQLive: SupportSiteProtocol {
	lazy var pSession: Session = {
		let configuration = URLSessionConfiguration.af.default
		let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1"
		configuration.headers.add(.userAgent(ua))
		return Session(configuration: configuration)
	}()
	
	func liveInfo(_ url: String) async throws -> any LiveInfo {
		try await roomInfo(url)
	}
	
	func decodeUrl(_ url: String) async throws -> YouGetJSON {
		let info = try await mInfo(url)
		var re = YouGetJSON(rawUrl: url)
		re.title = info.title
		re.streams["Default"] = .init(url: info.url.https())
		return re
	}
	
	func roomInfo(_ url: String) async throws -> QQLiveInfo {
		var s = try await AF.request(url).serializingString().value
		s = s.subString(from: #"__NEXT_DATA__"#, to: "</script>")
			.subString(from: ">")
		
		guard let data = s.data(using: .utf8) else { throw VideoGetError.notFountData }
		
		let json: JSONObject = try JSONParser.JSONObjectWithData(data)
		return try QQLiveInfo(object: json)
	}
    
    func mInfo(_ url: String) async throws -> QQLiveMInfo {
		let url = url.replacingOccurrences(of: "https://live.qq.com", with: "https://m.live.qq.com")
		
		var s = try await pSession.request(url).serializingString().value
		s = s.subString(from: "window.$ROOM_INFO = ", to: ";</script>")
		
		guard let data = s.data(using: .utf8) else { throw VideoGetError.notFountData }
		
		let json: JSONObject = try JSONParser.JSONObjectWithData(data)
		return try QQLiveMInfo(object: json)
    }
}

struct QQLiveInfo: Unmarshaling, LiveInfo {
	var title: String = ""
	var name: String = ""
	var avatar: String
	var isLiving = false
	var cover: String = ""
	var site: SupportSites = .qqLive
	
	var roomID: String = ""
	
	init(object: MarshaledObject) throws {
		
		let roomInfoPath = "props.initialState.roomInfo.roomInfo.room_info"
		
		title = try object.value(for: "\(roomInfoPath).room_name")
		name = try object.value(for: "\(roomInfoPath).nickname")
		isLiving = "\(try object.any(for: "\(roomInfoPath).is_live"))" == "1"
		cover = try object.value(for: "\(roomInfoPath).room_src_square")
		roomID = try object.value(for: "\(roomInfoPath).room_id")
		
		let uid: String = try object.value(for: "\(roomInfoPath).owner_uid")
		let avatarCDN: String = try object.value(for: "runtimeConfig.AVATAR_CDN")
		avatar = "https:" + avatarCDN + "/avatar.php?uid=\(uid)&size=middle&force=1"
		
	}
}
	

struct QQLiveMInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var avatar: String
    var isLiving = false
    var cover: String = ""
    var site: SupportSites = .qqLive
    
	var roomID: String = ""
	
    var url: String
    
    init(object: MarshaledObject) throws {
		
        title = try object.value(for: "room_name")
        name = try object.value(for: "nickname")
        isLiving = "\(try object.any(for: "show_status"))" == "1"
        cover = try object.value(for: "room_src")
		roomID = try object.value(for: "room_id")
		
		avatar = try object.value(for: "owner_avatar")
		
        url = try object.value(for: "rtmp_url") + "/" + object.value(for: "rtmp_live")
    }
}
