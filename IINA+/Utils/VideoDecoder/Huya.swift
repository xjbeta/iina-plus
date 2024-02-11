//
//  Huya.swift
//  IINA+
//
//  Created by xjbeta on 4/22/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa
import PromiseKit
import Alamofire
import PMKAlamofire
import Marshal
import SwiftSoup

class Huya: NSObject, SupportSiteProtocol {
    
    lazy var pSession: Session = {
        let configuration = URLSessionConfiguration.af.default
        let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1"
        configuration.headers.add(.userAgent(ua))
        return Session(configuration: configuration)
    }()
	
	private let huyaUid = Int.random(in: Int(1e12)..<Int(1e13))
    
    func liveInfo(_ url: String) -> Promise<LiveInfo> {
		getHuyaInfoM(url).map {
			$0
		}
    }
    
    func decodeUrl(_ url: String) -> Promise<YouGetJSON> {
		getHuyaInfoM(url).map {
			var yougetJson = YouGetJSON(rawUrl: url)
			yougetJson.title = $0.title
			return $0.write(to: yougetJson, uid: self.huyaUid)
		}
    }
    
    // MARK: - Huya
    
    struct HuyaRoomList {
        var current: String
        var list = [HuyaVideoSelector]()
    }
    
    
    // href, name
    func getHuyaRoomList(_ url: String) -> Promise<HuyaRoomList> {
        AF.request(url).responseString().map {
            var re = HuyaRoomList(current: "")
            try SwiftSoup.parse($0.string).getElementsByClass("match-nav").first()?.children().enumerated().forEach {
                
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
    }
    
    func getHuyaInfo(_ url: String) -> Promise<YouGetJSON> {
        AF.request(url).responseString().map {

            let text = $0.string
            
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
			let info = try HuyaStream(object: jsonObj)
			
			let yougetJson = YouGetJSON(rawUrl: url)
			
			return info.write(to: yougetJson, uid: self.huyaUid)
			
        }
    }
    
    func getHuyaInfoM(_ url: String) -> Promise<HuyaInfoM> {
        pSession.request(url).responseString().map {
            guard let jsonData = $0.string.subString(from: "<script> window.HNF_GLOBAL_INIT = ", to: " </script>").data(using: .utf8)
            else {
                throw VideoGetError.notFindUrls
            }
            let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(jsonData)
            
            let info: HuyaInfoM = try HuyaInfoM(object: jsonObj)
                  
            return info
        }
    }
}

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
        avatar = avatar.replacingOccurrences(of: "http://", with: "https://")
        isLiving = "\(try object.any(for: "isOn"))" == "1"
        cover = try object.value(for: "screenshot")
        cover = cover.replacingOccurrences(of: "http://", with: "https://")
        
		rid = try object.value(for: "profileRoom")
		
        let gameHostName: String = try object.value(for: "gameHostName")
        
        isSeeTogetherRoom = gameHostName == "seeTogether"
    }
}


struct HuyaStream: Unmarshaling {
	var data: [HuyaInfoData]
	var vMultiStreamInfo: [StreamInfo]
	
	init(object: MarshaledObject) throws {
		data = try object.value(for: "data")
		vMultiStreamInfo = try object.value(for: "vMultiStreamInfo")
	}
	
	func write(to yougetJson: YouGetJSON, uid: Int) -> YouGetJSON {
		var yougetJson = yougetJson
		
		if let infoData = data.first {
			yougetJson.title = infoData.liveInfo.roomName
			
			let urls = infoData.streamInfoList.map {
				$0.url(uid)
			}
			
			vMultiStreamInfo.forEach {
				let rate = $0.iBitRate
				
				var us = urls.map {
					$0.replacingOccurrences(of: "&ratio=0", with: "&ratio=\(rate)")
				}
				
				var s = Stream(url: us.removeFirst())
				s.src = us
				s.quality = rate == 0 ? 9999999 : rate
				yougetJson.streams[$0.sDisplayName] = s
			}
		}
		
		return yougetJson
	}
	
	struct StreamInfo: Unmarshaling {
		var sDisplayName: String
		var iBitRate: Int
		var iHEVCBitRate: Int
		
		init(object: MarshaledObject) throws {
			sDisplayName = try object.value(for: "sDisplayName")
			iBitRate = try object.value(for: "iBitRate")
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
	
	struct GameLiveInfo: Unmarshaling {
		
		let roomName: String
		let uid: Int
		let isSecret: Int
		let screenshot: String
		let nick: String
		let avatar180: String
		
		init(object: MarshaledObject) throws {
			roomName = try object.value(for: "roomName")
			uid = try object.value(for: "uid")
			isSecret = try object.value(for: "isSecret")
			screenshot = try object.value(for: "screenshot")
			nick = try object.value(for: "nick")
			avatar180 = try object.value(for: "avatar180")
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
        
        let ava: String = try object.value(for: "roomInfo.tProfileInfo.sAvatar180")
        avatar = ava.replacingOccurrences(of: "http://", with: "https://")
        
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
		var yougetJson = yougetJson
		
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
