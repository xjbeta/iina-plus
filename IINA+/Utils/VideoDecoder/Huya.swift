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
	
	private var huyaUid = 0
    
    func liveInfo(_ url: String) -> Promise<LiveInfo> {
        getHuyaInfoM(url).map {
            $0.0
        }
    }
    
    func decodeUrl(_ url: String) -> Promise<YouGetJSON> {
		getHuyaInfo(url)
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
			if self.huyaUid == 0 {
				self.huyaUid = Int.random(in: Int(1e12)..<Int(1e13))
			}
			
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
    
    func getHuyaInfoM(_ url: String) -> Promise<(HuyaInfoM, [(String, Stream)])> {
        pSession.request(url).responseString().map {
            guard let jsonData = $0.string.subString(from: "<script> window.HNF_GLOBAL_INIT = ", to: " </script>").data(using: .utf8)
            else {
                throw VideoGetError.notFindUrls
            }
            let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(jsonData)
            
            let info: HuyaInfoM = try HuyaInfoM(object: jsonObj)
                  
            return (info, info.urls)
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
			
			func now() -> Int {
				Int(Date().timeIntervalSince1970 * 1000)
			}
		
			let seqid = uid + now()
			let sid = now()
			
			guard let convertUid = rotUid(uid),
				  let wsSecret = wsSecret(sFlvAntiCode, convertUid: convertUid, seqid: seqid, streamName: sStreamName) else { return "" }
			
			let newAntiCode: String = {
				var s = sFlvAntiCode.split(separator: "&")
					.filter {
						!$0.contains("fm=") &&
						!$0.contains("wsSecret=")
					}
				s.append("wsSecret=\(wsSecret)")
				return s.joined(separator: "&")
			}()
			
			
			return sFlvUrl.replacingOccurrences(of: "http://", with: "https://")
			+ "/"
			+ sStreamName
			+ "."
			+ sFlvUrlSuffix
			+ "?"
			+ newAntiCode
			+ "&ver=1"
			+ "&seqid=\(seqid)"
			+ "&ratio=0"
			+ "&dMod=mseh-32"
			+ "&sdkPcdn=1_1"
			+ "&u=\(convertUid)"
			+ "&t=100"
			+ "&sv=2401310322"
			+ "&sdk_sid=\(sid)"
			+ "&https=1"
//			+ "&codec=av1"
		}
		
		private func turnStr(_ e: Int, _ t: Int, _ i: Int) -> String {
			var s = String(e, radix: t)
			while s.count < i {
				s = "0" + s
			}
			return s
		}

		private func rotUid(_ t: Int) -> Int? {
			let i = 8
			
			let s = turnStr(t, 2, 64)
			let si = s.index(s.startIndex, offsetBy: 32)
			let a = s[s.startIndex..<si]
			let r = s[si..<s.endIndex]
			
			let ri = r.index(r.startIndex, offsetBy: i)
			let n1 = r[ri..<r.index(ri, offsetBy: 32 - i)]
			let n2 = r[r.startIndex..<ri]
			
			let n = n1 + n2
			
			return Int(a + n, radix: 2)
		}
		
		private func wsSecret(_ antiCode: String,
							  convertUid: Int,
							  seqid: Int,
							  streamName: String) -> String? {
			
			let d = antiCode.components(separatedBy: "&").reduce([String: String]()) { (re, str) -> [String: String] in
				var r = re
				let kv = str.components(separatedBy: "=")
				guard kv.count == 2 else { return r }
				r[kv[0]] = kv[1]
				return r
			}
			
			guard let fm = d["fm"]?.removingPercentEncoding,
				  let fmData = Data(base64Encoded: fm),
				  var u = String(data: fmData, encoding: .utf8),
				  let l = d["wsTime"] else { return nil }
			
			let s = "\(seqid)|huya_live|100".md5()
			
			u = u.replacingOccurrences(of: "$0", with: "\(convertUid)")
			u = u.replacingOccurrences(of: "$1", with: streamName)
			u = u.replacingOccurrences(of: "$2", with: s)
			u = u.replacingOccurrences(of: "$3", with: l)

			return u.md5()
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
    
    
    var urls: [(String, Stream)]
    
    
    struct StreamInfo: Unmarshaling {
        let sFlvUrl: String
        let sStreamName: String
        let sFlvUrlSuffix: String
        let sFlvAntiCode: String
        
        let sCdnType: String
        
        var url: String? {
            get {
                let u = sFlvUrl
                + "/"
                + sStreamName
                + "."
                + sFlvUrlSuffix
                + "?"
                + sFlvAntiCode
                
//                return formatURL(u)
                
                
                return huyaUrlFormatter(u)
            }
        }
        
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
        
        
        let defaultCDN: String = try object.value(for: "roomInfo.tLiveInfo.tLiveStreamInfo.sDefaultLiveStreamLine")
        
        let streamInfos: [StreamInfo] = try object.value(for: "roomInfo.tLiveInfo.tLiveStreamInfo.vStreamInfo.value")

        let bitRateInfos: [BitRateInfo] = try object.value(for: "roomInfo.tLiveInfo.tLiveStreamInfo.vBitRateInfo.value")
        
        let urls = streamInfos.sorted { i1, i2 -> Bool in
			i1.sCdnType == defaultCDN
		}.sorted { i1, i2 -> Bool in
			!i1.sFlvUrl.contains("txdirect.flv.huya.com")
		}.compactMap {
            $0.url
        }
        
        guard urls.count > 0 else {
            self.urls = []
            return
        }
        
        self.urls = bitRateInfos.map {
            ($0.sDisplayName, $0.iBitRate)
        }.map { (name, rate) -> (String, Stream) in
            var us = urls.map {
                $0 + "&ratio=\(rate)"
            }
            var s = Stream(url: us.removeFirst())
            s.src = us
            s.quality = rate == 0 ? 9999999 : rate
            return (name, s)
        }
    }
}

fileprivate func huyaUrlFormatter(_ u: String) -> String? {
    let ib = u.split(separator: "?").map(String.init)
    guard ib.count == 2 else { return nil }
    let i = ib[0]
    let b = ib[1]
    guard let s = i.components(separatedBy: "/").last?.subString(to: ".") else { return nil }
    let d = b.components(separatedBy: "&").reduce([String: String]()) { (re, str) -> [String: String] in
        var r = re
        let kv = str.components(separatedBy: "=")
        guard kv.count == 2 else { return r }
        r[kv[0]] = kv[1]
        return r
    }
    
    let n = "\(Int(Date().timeIntervalSince1970 * 10000000))"
    
    guard let fm = d["fm"]?.removingPercentEncoding,
          let fmData = Data(base64Encoded: fm),
          var u = String(data: fmData, encoding: .utf8),
          let l = d["wsTime"] else { return nil }
    
    u = u.replacingOccurrences(of: "$0", with: "0")
    u = u.replacingOccurrences(of: "$1", with: s)
    u = u.replacingOccurrences(of: "$2", with: n)
    u = u.replacingOccurrences(of: "$3", with: l)

    let m = u.md5()

    let y = b.split(separator: "&").map(String.init).filter {
        $0.contains("txyp=") ||
            $0.contains("fs=") ||
            $0.contains("sphdcdn=") ||
            $0.contains("sphdDC=") ||
            $0.contains("sphd=")
    }.joined(separator: "&")
    
    let url = "\(i)?wsSecret=\(m)&wsTime=\(l)&seqid=\(n)&\(y)&ratio=0&u=0&t=100&sv="
        
        .replacingOccurrences(of: "http://", with: "https://")
    return url
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
