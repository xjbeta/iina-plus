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
		guard let uc = URLComponents.init(string: url),
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
		
		var headers: HTTPHeaders = [
			.userAgent("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"),
		]
		
		return AF.request(url, headers: headers).responseData().done {
			guard let ref = $0.response.response?.url?.absoluteString else {
				throw KuaiShouError.nilReferer
			}
			headers.add(name: "Referer", value: ref)
		}.then {
			AF.request(
				"https://livev.m.chenzhongtech.com/rest/k/live/byUser?kpn=GAME_ZONE",
				method: .post,
				parameters: pars,
				encoding: JSONEncoding.default,
				headers: headers).responseData()
		}.map {
			let obj = try JSONParser.JSONObjectWithData($0.data)
			let result: Int = try obj.value(for: "result")
			guard result == 1 else { throw KuaiShouError.apiLimited }
			let info = try KuaiShouInfo(object: obj)
			return info
		}
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
