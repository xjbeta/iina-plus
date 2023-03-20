//
//  KuaiShou.swift
//  IINA+
//
//  Created by xjbeta on 2023/3/1.
//  Copyright © 2023 xjbeta. All rights reserved.
//

import Cocoa
import PromiseKit
import Alamofire
import PMKAlamofire
import Marshal

class KuaiShou: NSObject, SupportSiteProtocol {

	enum KuaiShouError: Error {
		case invalidLink
		case nilReferer
		case apiLimited
	}
	
	let initUA = 1000
	let reloadTimes = 50
	
	var cookieStorage = [String: String]()
	var refererStorage = [String: String]()
	var uaStorage = [String: Int]()
	
    func liveInfo(_ url: String) -> Promise<LiveInfo> {
        getInfo(url).map {
            $0
        }
    }
    
    func decodeUrl(_ url: String) -> Promise<YouGetJSON> {
        getInfo(url).map {
            $0.write(to: YouGetJSON(rawUrl: url))
        }
    }
	
    func getInfo(_ url: String) -> Promise<KuaiShouInfo> {
		guard let uc = URLComponents(string: url),
			  uc.path.starts(with: "/u/") else {
			return .init(error: KuaiShouError.invalidLink)
		}
		
		let eid = String(uc.path.dropFirst(3))
		
		let pars: Parameters = [
			"eid": eid,
			"clientType": "WEB_OUTSIDE_SHARE_H5",
			"shareMethod": "card",
			"source": 6
		]
		

		if uaStorage[eid] == nil {
			uaStorage[eid] = initUA
		}
		
		let headers: HTTPHeaders = [
			.userAgent("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1 EID/\(eid).\(uaStorage[eid]!)"),
			.init(name: "Origin", value: "https://livev.m.chenzhongtech.com"),
			.init(name: "Cookie", value: ""),
			.init(name: "Accept-Encoding", value: "gzip, deflate, br"),
			.init(name: "Accept-Language", value: "zh-Hans;q=1.0")
		]
		
		var isInitRequest = false
		
		return {
			guard cookieStorage[eid] != nil && refererStorage[eid] != nil else {
				return loadReferer(eid, headers: headers)
			}
			isInitRequest = true
			return Promise { resolver in
				let cookie = self.cookieStorage[eid]!
				let ref = self.refererStorage[eid]!
				
				var headers = headers
				
				headers.add(name: "Cookie", value: cookie)
				headers.add(name: "Referer", value: ref)
				
				resolver.fulfill(headers)
			}
		}().then {
			AF.request(
				"https://livev.m.chenzhongtech.com/rest/k/live/byUser?kpn=GAME_ZONE",
				method: .post,
				parameters: pars,
				encoding: JSONEncoding.default,
				headers: $0).responseData()
		}.then { re in
			Promise { resolver in
				let obj = try JSONParser.JSONObjectWithData(re.data)
				let result: Int = try obj.value(for: "result")
				
				if result == 1 {
					let info = try KuaiShouInfo(object: obj)
					resolver.fulfill(info)
				} else if result == 2,
						  isInitRequest {
					Log("KuaiShou API Limited, try to reinit \(eid)")
					self.getInfo(url).done {
						resolver.fulfill($0)
					}.catch {
						resolver.reject($0)
					}
				} else {
					Log("KuaiShou API Limited, result \(result), \(eid)")
					resolver.reject(KuaiShouError.apiLimited)
				}
			}
		}.ensure {
			let i = (self.uaStorage[eid] ?? self.initUA) + 1
			self.uaStorage[eid] = i
			
			if (i % self.reloadTimes) == 0 {
				self.cookieStorage[eid] = nil
				self.refererStorage[eid] = nil
			}
		}
    }
	
	func loadReferer(_ eid: String, headers: HTTPHeaders) -> Promise<HTTPHeaders> {
		AF.request(
			"https://live.kuaishou.com/u/\(eid)",
			headers: headers
		).responseData().map {
			guard let response = $0.response.response,
				  let ref = response.url?.absoluteString else {
				throw KuaiShouError.nilReferer
			}
			
			self.saveCookies(response, eid: eid)
			
			var headers = headers
			
			headers.add(name: "Cookie", value: self.cookieStorage[eid] ?? "")
			
			self.refererStorage[eid] = ref
			headers.add(name: "Referer", value: ref)
			return headers
		}
	}
	
	func saveCookies(_ response: HTTPURLResponse?, eid: String) {
		guard let res = response else { return }
		let cookie = HTTPCookie.cookies(withResponseHeaderFields: res.headers.dictionary, for: .init(string: "chenzhongtech.com")!)
			.map {
			$0.name + "=" + $0.value
		}.joined(separator: "; ")
		
		cookieStorage[eid] = cookie
	}
}

struct KuaiShouInfo: Unmarshaling, LiveInfo {

    var title: String = ""
    var name: String = ""
    var avatar: String = ""
    var cover: String = ""
    
    var isLiving: Bool = false
    
    var site: SupportSites = .kuaiShou
    
    var playUrls: [PlayUrl] = []
    
    init(object: Marshal.MarshaledObject) throws {
        name = try object.value(for: "liveStream.user.user_name")
        avatar = try object.value(for: "liveStream.user.headurl")
        title = try object.value(for: "liveStream.caption")
        cover = try object.value(for: "liveStream.coverUrl")
        isLiving = try object.value(for: "liveStream.living")
		playUrls = try object.value(for: "liveStream.multiResolutionHlsPlayUrls")
    }
    
    struct PlayUrl: Unmarshaling {
		var name: String
		var level: Int
		var urls: [String]
        
        init(object: Marshal.MarshaledObject) throws {
			name = try object.value(for: "name")
			level = try object.value(for: "level")
			let urls: [Url] = try object.value(for: "urls")
			self.urls = urls.map {
				$0.url
			}
        }
    }
    
    struct Url: Unmarshaling {
        var url: String
        init(object: Marshal.MarshaledObject) throws {
            url = try object.value(for: "url")
        }
    }
    
    func write(to yougetJson: YouGetJSON) -> YouGetJSON {
        var json = yougetJson
        json.title = title
        
		playUrls.forEach {
			guard let url = $0.urls.first else { return }
			var stream = Stream(url: url)
			stream.quality = $0.level
			json.streams[$0.name] = stream
		}
		
        return json
    }
}
