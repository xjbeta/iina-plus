//
//  Douyu.swift
//  IINA+
//
//  Created by xjbeta on 4/22/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa
import Alamofire
import Marshal
import CryptoSwift
import WebKit

actor Douyu: SupportSiteProtocol {
	func liveInfo(_ url: String) async throws -> any LiveInfo {
		let rid = try await getDouyuHtml(url).roomId
		let id = Int(rid) ?? -1
		let info = try await douyuBetard(id)
		return info
	}
    
	func decodeUrl(_ url: String) async throws -> YouGetJSON {
		// Best-effort session renewal; never affects parsing.
		await renewSessionIfNeeded()

		let html = try await getDouyuHtml(url)
		guard let rid = Int(html.roomId) else {
			throw VideoGetError.douyuNotFoundRoomId
		}
        
		let info = try await douyuBetard(rid)
		let urls = try await getDouyuUrl(rid)
		
		var yougetJson = YouGetJSON(rawUrl: url)
		yougetJson.id = rid
		yougetJson.title = info.title
		let proxyURL = "http://127.0.0.1:\(Preferences.shared.dmPort)/douyu/\(rid).flv"
		urls.forEach { name, decodedStream in
			var stream = decodedStream
			stream.url = "\(proxyURL)?rate=\(stream.rate)&line=0"
			stream.src = decodedStream.src.enumerated().map {
				"\(proxyURL)?rate=\(stream.rate)&line=\($0.offset + 1)"
			}
			yougetJson.streams[name] = stream
		}
		return yougetJson
	}
	
    
    func getDouyuHtml(_ url: String) async throws -> (roomId: String, roomIds: [String], isLiving: Bool, pageId: String) {
        
		let text = try await AF.request(url).serializingString().value
		
        func extractRoomInfoJSON(from input: String) -> String? {
            guard let roomInfoRange = input.range(of: "\\\"roomInfo\\\"") else {
                return nil
            }
            
            let suffix = input[roomInfoRange.upperBound...]
            guard let openBraceIndex = suffix.firstIndex(of: "{") else {
                return nil
            }
            
            let searchRange = input[openBraceIndex...]
            var braceCount = 0
            var foundEnd = false
            var endIndex = openBraceIndex
            
            for index in searchRange.indices {
                let char = searchRange[index]
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                    if braceCount == 0 {
                        endIndex = index
                        foundEnd = true
                        break
                    }
                }
            }
            
            if foundEnd {
                let result = input[openBraceIndex...endIndex]
                return String(result)
            }
            
            return nil
        }
        
        var jsonText = extractRoomInfoJSON(from: text)
        
        jsonText = jsonText?.replacingOccurrences(of: "\\\"", with: "\"")
        jsonText = jsonText?.replacingOccurrences(of: "\\\"", with: "\"")
        
        guard let jsonData = jsonText?.data(using: .utf8) else { throw VideoGetError.douyuNotFoundRoomId }
        
        let json: JSONObject = try JSONParser.JSONObjectWithData(jsonData)
        let roomId: Int = try json.value(for: "room.room_id")
        let isLiving: Bool = try json.value(for: "room.show_status") == 1
        
		return ("\(roomId)", [], isLiving, "")
    }
    
    func douyuBetard(_ rid: Int) async throws -> DouyuInfo {
		let data = try await AF.request("https://www.douyu.com/betard/\(rid)").serializingData().value
		let json: JSONObject = try JSONParser.JSONObjectWithData(data)
		return try DouyuInfo(object: json)
    }
    
    
//    https://butterfly.douyucdn.cn/api/page/loadPage?name=pageData2&pageId=1149&view=0
    func getDouyuEventRoomNames(_ pageId: String) async throws -> [DouyuEventRoom] {
        
		let url = "https://butterfly.douyucdn.cn/api/page/loadPage?name=pageData2&pageId=\(pageId)&view=0"
		
		let string = try await AF.request(url).serializingString().value
		
		guard let data = self.douyuRoomJsonFormatter(string)?.data(using: .utf8) else {
			throw VideoGetError.douyuNotFoundSubRooms
		}
		
		let json: JSONObject = try JSONParser.JSONObjectWithData(data)
		return (try json.value(for: "children")).filter {
			$0.roomId != ""
		}
    }
    
    func getDouyuEventRoomOnlineStatus(_ pageId: String) async throws -> [String: Bool] {
        
        struct RoomOnlineStatus: Decodable {
            let data: [String: Bool]
        }
        
		let url = "https://www.douyu.com/japi/carnival/c/roomActivity/getRoomOnlineStatus?pageId=\(pageId)"
		return try await AF.request(url).serializingDecodable(RoomOnlineStatus.self).value.data
    }
    
    func getDouyuUrl(_ roomID: Int, rate: Int = 0, cdn: String = "") async throws -> [(String, Stream)] {
        try await getDouyuPlayback(roomID, rate: rate, cdn: cdn).streams
    }

    func getDouyuPlayback(_ roomID: Int, rate: Int = 0, cdn: String = "") async throws -> (streams: [(String, Stream)], cdns: [String], selectedCDN: String) {
        let time = Int(Date().timeIntervalSince1970)
        let didStr: String = {
            let time = UInt32(NSDate().timeIntervalSinceReferenceDate)
            srand48(Int(time))
            let random = "\(drand48())"
            return random.md5()
        }()
        
        let enc = try await getEncryption(didStr)
        
        
        let auth = enc.auth("\(roomID)", ts: time)
        
        let pars = ["enc_data": enc.encData,
                     "tt": "\(time)",
                     "did": didStr,
                     "auth": auth,
                     "cdn": cdn,
                     "rate": "\(rate)",
                     "hevc": "1",
                     "fa": "0",
                     "ive": "0"]
        
        
		let url = "https://www.douyu.com/lapi/live/getH5PlayV1/\(roomID)"
		let data = try await AF.request(url, method: .post, parameters: pars).serializingData().value
        
		let json: JSONObject = try JSONParser.JSONObjectWithData(data)
		
		var play = try DouyuH5Play(object: json)
		if let p2pPlay = try? await douyuCDNs(play) {
			play = p2pPlay
		}
		
		let streams = play.multirates.map { r -> (String, Stream) in
			var s = Stream(url: "")
			s.quality = r.bit
			s.rate = r.rate
			
			var urls = play.p2pUrls
			urls.append(play.flvUrl)
			
			// Server only issues the stream matching data.rate; rate 0 (original) falls back to that stream when the room has Blu-ray 4M.
			let hasUrl = r.rate == play.rate || r.rate == rate
			if hasUrl, urls.count > 0 {
				s.url = urls.removeFirst()
				s.src = urls
			}
			return (r.name, s)
		}
        return (streams, play.cdnNames, play.selectedCDN)
    }
    
    func getEncryption(_ did: String) async throws -> DouyuEncryption {
        let url = "https://www.douyu.com/wgapi/livenc/liveweb/websec/getEncryption?did=\(did)"
        let data = try await AF.request(url).serializingData().value
        let json: JSONObject = try JSONParser.JSONObjectWithData(data)
        
        let error: Int = try json.value(for: "error")
        guard error == 0 else {
            throw VideoGetError.douyuSignError
        }
        
        let enc = try DouyuEncryption(object: json)
        return enc
    }
    
    func douyuCDNs(_ info: DouyuH5Play) async throws -> DouyuH5Play {
        guard let url = info.cdnUrl else {
            return info
        }
        
		let data = try await AF.request(url).serializingData().value
		let json: JSONObject = try JSONParser.JSONObjectWithData(data)
		
		let sugs: [String] = try json.value(for: "sug")
		let baks: [String] = try json.value(for: "bak")
		var info = info
		info.initP2pUrls(sugs + baks)
		return info
    }
    
    // MARK: - Login
    
    func isLogin() async throws -> (Bool, String) {
        guard let url = URL(string: "https://www.douyu.com"),
              let cookies = HTTPCookieStorage.shared.cookies(for: url) else {
            return (false, "")
        }
        // Session is identified by the httpOnly dy_auth/acf_auth cookies.
        let hasSession = cookies.contains { $0.name == "dy_auth" || $0.name == "acf_auth" }
        // Prefer the nickname cookie, falling back to the uid.
        let displayName = cookies.first { $0.name == "acf_nickname" }?.value
            .removingPercentEncoding ?? ""
        let uid = cookies.first { $0.name == "acf_uid" }?.value ?? ""
        let name = displayName.isEmpty ? uid : displayName
        return (hasSession && !uid.isEmpty, name)
    }
    
    func logout() async throws {
        // Invalidate the server-side session, then clear local and WebView douyu cookies.
        if let url = URL(string: "https://passport.douyu.com/sso/logout") {
            _ = try? await AF.request(url, parameters: ["client_id": "1",
                                                        "callback_url": "https://www.douyu.com/"]).serializingString().value
        }
        (HTTPCookieStorage.shared.cookies ?? []).forEach {
            if $0.domain.contains("douyu.com") {
                HTTPCookieStorage.shared.deleteCookie($0)
            }
        }
        let httpCookieStore = await MainActor.run {
            WKWebsiteDataStore.default().httpCookieStore
        }
        let webCookies = await httpCookieStore.allCookies()
        for cookie in webCookies where cookie.domain.contains("douyu.com") {
            await httpCookieStore.deleteCookie(cookie)
        }
    }
    
    // MARK: - Session renewal
    
    // Visiting the passport login page while logged in re-issues the session cookies via Set-Cookie.
    func renewSessionIfNeeded() async {
        do {
            guard try await isLogin().0 else { return }
            guard let url = URL(string: "https://www.douyu.com"),
                  let dyAuth = HTTPCookieStorage.shared.cookies(for: url)?
                      .first(where: { $0.name == "dy_auth" }),
                  let expires = dyAuth.expiresDate else { return }
            // Renew only within 3 days of expiry.
            guard expires.timeIntervalSinceNow < 3 * 86_400 else { return }
            
            let before = expires
            do {
                _ = try await AF.request("https://passport.douyu.com/index/login?client_id=1")
                    .serializingData().value
                let after = HTTPCookieStorage.shared.cookies(for: url)?
                    .first(where: { $0.name == "dy_auth" })?.expiresDate ?? before
                Log("Douyu session renewed: \(before) -> \(after)")
            } catch let error {
                Log("Douyu session renewal failed: \(error)")
            }
        } catch let error {
            Log("Douyu session renewal check failed: \(error)")
        }
    }
    
    func douyuRoomJsonFormatter(_ text: String) -> String? {
		guard let index = text.index(of: #""NewPcBasicSwitchRoomAdvance""#)?.utf16Offset(in: text) else {
            return nil
        }
        
        let sIndex = text.indexes(of: "{").map({$0.utf16Offset(in: text)})
        let eIndex = text.indexes(of: "}").map({$0.utf16Offset(in: text)})
        
        let indexList = (sIndex.map {
            ($0, 1)
        } + eIndex.map {
            ($0, -1)
        }).sorted { i1, i2 in
            i1.0 < i2.0
        }
        
        // Find "{"
        var c2 = 0
        guard var i2 = indexList.lastIndex(where: { $0.0 < index }) else {
            return nil
        }
        
        c2 += indexList[i2].1
        while c2 != 1 {
            i2 -= 1
            guard i2 >= 0 else {
                return nil
            }
            c2 += indexList[i2].1
        }
        let startIndex = text.index(text.startIndex, offsetBy: indexList[i2].0)
        
        // Find "}"
        var c1 = 0
        guard var i1 = indexList.firstIndex(where: { $0.0 > index }) else {
            return nil
        }
        
        c1 += indexList[i1].1
        while c1 != -1 {
            i1 += 1
            guard indexList.count > i1 else {
                return nil
            }
            c1 += indexList[i1].1
        }
        
        let endIndex = text.index(startIndex, offsetBy: indexList[i1].0 - indexList[i2].0)
        
        return String(text[startIndex...endIndex])
    }
}

struct DouyuInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var avatar: String
    var isLiving = false
    var cover: String = ""
    var site: SupportSites = .douyu
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "room.room_name")
        name = try object.value(for: "room.nickname")
        avatar = try object.value(for: "room.avatar.big")
        isLiving = "\(try object.any(for: "room.show_status"))" == "1"
//        isLiving = try object.value(for: "room.show_status") == 1 && object.value(for: "room.videoLoop") != 0
        
        cover = try object.value(for: "room.room_pic")
    }
}

struct DouyuEncryption: Unmarshaling {
    let key: String
    let randStr: String
    let encTime: Int
    let expireAt: Int
    let encData: String
    let isSpecial: Int
    
    init(object: MarshaledObject) throws {
        key = try object.value(for: "data.key")
        randStr = try object.value(for: "data.rand_str")
        encTime = try object.value(for: "data.enc_time")
        expireAt = try object.value(for: "data.expire_at")
        encData = try object.value(for: "data.enc_data")
        isSpecial = try object.value(for: "data.is_special")
    }
    
    func auth(_ rid: String, ts: Int) -> String {
        var u = randStr
        
        for _ in 0..<encTime {
            u = (u + key).md5()
        }
        
        let o = (isSpecial == 1) ? "" : "\(rid)\(ts)"
        
        return (u + key + o).md5()
    }
}

struct DouyuEventRoom: Unmarshaling {
    let roomId: String
    let text: String
    init(object: MarshaledObject) throws {
        if let rid: String = try? object.value(for: "props.onlineRoomId") {
            roomId = rid
        } else if let rid: String = try? object.value(for: "props.liveRoomId") {
            roomId = rid
        } else {
            roomId = ""
            text = ""
            return
        }
        
        text = try object.value(for: "props.text")
    }
}

struct DouyuH5Play: Unmarshaling {
    let roomId: Int
    let rtmpUrl: String
    let rtmpLive: String
    let rate: Int
    let multirates: [Rate]
    let selectedCDN: String
    let cdnNames: [String]
    
    let flvUrl: String
    let xsString: String?
    let cdnUrl: String?
    
    var p2pUrls = [String]()
    
    struct Rate: Unmarshaling {
        let name: String
        let rate: Int
        let highBit: Int
        let bit: Int
        
        init(object: MarshaledObject) throws {
            name = try object.value(for: "name")
            rate = try object.value(for: "rate")
            highBit = try object.value(for: "highBit")
            bit = try object.value(for: "bit")
        }
    }

    struct CDN: Unmarshaling {
        let cdn: String

        init(object: MarshaledObject) throws {
            cdn = try object.value(for: "cdn")
        }
    }
    
    struct P2pMeta: Unmarshaling {
        let domain: String
        let delay: Int
        let secret: String
        let time: String
        
        init(object: MarshaledObject) throws {
            domain = try object.value(for: "xp2p_domain")
            delay = try object.value(for: "xp2p_txDelay")
            secret = try object.value(for: "xp2p_txSecret")
            time = try object.value(for: "xp2p_txTime")
        }
    }
    
    init(object: MarshaledObject) throws {
        roomId = try object.value(for: "data.room_id")
        rtmpUrl = try object.value(for: "data.rtmp_url")
        rtmpLive = try object.value(for: "data.rtmp_live")
        multirates = try object.value(for: "data.multirates")
        rate = try object.value(for: "data.rate")
        selectedCDN = (try? object.value(for: "data.rtmp_cdn")) ?? ""
        let cdns: [CDN] = (try? object.value(for: "data.cdnsWithName")) ?? []
        cdnNames = cdns.map(\.cdn)
        
        flvUrl = rtmpUrl + "/" + rtmpLive
        
        guard let meta: P2pMeta = try? object.value(for: "data.p2pMeta") else {
            xsString = nil
            cdnUrl = nil
            return
        }
        
        var newRL = rtmpLive.replacingOccurrences(of: "flv", with: "xs").split(separator: "&").map(String.init)
        
        newRL.append(contentsOf: [
            "delay=\(meta.delay)",
            "txSecret=\(meta.secret)",
            "txTime=\(meta.time)",
//            "playid=1646460800000-3082600000",
            "uuid=\(UUID().uuidString)"
        ])
        
        xsString = "\(meta.domain)/live/" + newRL.joined(separator: "&")
        cdnUrl = "https://\(meta.domain)/\(rtmpLive.subString(to: ".")).xs"
    }
    
    mutating func initP2pUrls(_ urls: [String]) {
        guard let str = xsString else { return }
        p2pUrls = urls.map {
            "https://\($0)/" + str
        }
    }
}
