//
//  Bilibili.swift
//  iina+
//
//  Created by xjbeta on 2018/8/6.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import Alamofire
import Marshal

actor Bilibili: SupportSiteProtocol {
	
    let biliShare = BilibiliShare()
    let bangumi = Bangumi()
    
	func liveInfo(_ url: String) async throws -> any LiveInfo {
		let isBangumi = SupportSites(url: url) == .bangumi
		
		if isBangumi {
            return try await bangumi.liveInfo(url)
		} else {
			let data = try await getBilibiliHTMLDatas(url)
			
			let initialStateJson: JSONObject = try JSONParser.JSONObjectWithData(data.initialStateData)
			
			var info = BilibiliInfo()
			info.title = try initialStateJson.value(for: "videoData.title")
			info.cover = try initialStateJson.value(for: "videoData.pic")
			info.cover = info.cover.https()
			info.name = try initialStateJson.value(for: "videoData.owner.name")
			info.isLiving = true
			
			return info
		}
	}
	
	func decodeUrl(_ url: String) async throws -> YouGetJSON {
		var re: YouGetJSON!
		if SupportSites(url: url) == .bangumi {
            re = try await bangumi.decodeUrl(url)
		} else {
			re = try await getBilibili(url)
		}
		
		let ss = re.streams.filter {
			$0.value.url != nil && $0.value.url != ""
		}.max {
			$0.value.quality < $1.value.quality
		}
		
		if let ss {
			re.streams.filter {
				$0.value.quality > ss.value.quality
			}.forEach {
				re.streams[$0.key] = nil
			}
		}
		return re
	}
    
// MARK: - Bilibili Video
    
    func getBilibili(_ url: String) async throws -> YouGetJSON {
        
        await biliShare.setBilibiliQuality()

		func r1() async throws -> YouGetJSON {
			let json = try await bilibiliPrepareID(url)
            return try await biliShare.bilibiliPlayUrl(yougetJson: json)
		}
		
		func r2() async throws -> YouGetJSON {
			let datas = try await getBilibiliHTMLDatas(url)
			return try await decodeBilibiliDatas(
				url,
				playInfoData: datas.playInfoData,
				initialStateData: datas.initialStateData)
		}
		
		let preferHTML = Preferences.shared.bilibiliHTMLDecoder
		
		do {
			return try await preferHTML ? r2() : r1()
		} catch let error {
			Log("\(error), fallback")
			return try await preferHTML ? r1() : r2()
		}
    }
    
	func getBilibiliHTMLDatas(_ url: String) async throws -> (playInfoData: Data, initialStateData: Data) {
        let headers = HTTPHeaders(["Referer": "https://www.bilibili.com/",
                                   "User-Agent": biliShare.bilibiliUA])

		let re = try await AF.request(url, headers: headers).serializingString().value
		
		let playinfoStrig = {
			var s = re.subString(from: "window.__playinfo__=", to: "</script>")
			if s == "" {
				s = re.subString(from: "const playurlSSRData = ", to: "\n")
			}
			return s
		}()
		
		let playInfoData = playinfoStrig.data(using: .utf8) ?? Data()
		let initialStateData = re.subString(from: "window.__INITIAL_STATE__=", to: ";(function()").data(using: .utf8) ?? Data()
		
		return (playInfoData, initialStateData)
    }
    
    func decodeBilibiliDatas(_ url: String,
                             playInfoData: Data,
                             initialStateData: Data) async throws -> YouGetJSON {
        var yougetJson = YouGetJSON(rawUrl: url)
        
		let playInfoJson: JSONObject = try JSONParser.JSONObjectWithData(playInfoData)
		let initialStateJson: JSONObject = try JSONParser.JSONObjectWithData(initialStateData)
		
		var title: String = try initialStateJson.value(for: "videoData.title")
		
		struct Page: Unmarshaling {
			let page: Int
			let part: String
			let cid: Int
			
			init(object: MarshaledObject) throws {
				page = try object.value(for: "page")
				part = try object.value(for: "part")
				cid = try object.value(for: "cid")
			}
		}
		let pages: [Page] = try initialStateJson.value(for: "videoData.pages")
		yougetJson.id = try initialStateJson.value(for: "videoData.cid")
//                let bvid: String = try initialStateJson.value(for: "videoData.bvid")
		
		if let p = URL(string: url)?.query?.replacingOccurrences(of: "p=", with: ""),
		   let pInt = Int(p),
		   pInt - 1 > 0, pInt - 1 < pages.count {
			let page = pages[pInt - 1]
			title += " - P\(pInt) - \(page.part)"
			yougetJson.id = page.cid
		}
		
		yougetJson.title = title
		yougetJson.duration = try initialStateJson.value(for: "videoData.duration")

		if let playInfo: BilibiliPlayInfo = try? playInfoJson.value(for: "data") {
			yougetJson = playInfo.write(to: yougetJson)
			return yougetJson
		} else if let info: BilibiliSimplePlayInfo = try? playInfoJson.value(for: "data") {
			yougetJson = info.write(to: yougetJson)
			return yougetJson
		} else {
			throw VideoGetError.notFindUrls
		}
    }
    
    func bilibiliPrepareID(_ url: String) async throws -> YouGetJSON {
        guard let bUrl = BilibiliUrl(url: url) else {
			throw VideoGetError.invalidLink
        }
        var json = YouGetJSON(rawUrl: url)
        
        json.site = .bilibili
        let eps = try await getVideoList(url)
        let list = eps.flatMap({ $0.1 })
        var selector = list.first
        if let s = selector, s.isCollection {
            selector = list.first(where: { $0.bvid == bUrl.id })
        } else {
            selector = list.first(where: { $0.index == bUrl.p })
        }
        guard let s = selector else { throw VideoGetError.notFountData }
        
        json.id = Int(s.id) ?? -1
        json.bvid = s.bvid
        json.title = s.title
        json.duration = Int(s.duration)
        return json
    }
    
    
// MARK: - Bilibili Account API
    
    enum BilibiliApiError: Error {
        case biliCSRFNotFound
    }
    
    func isLogin() async throws -> (Bool, String) {
		let data = try await AF.request("https://api.bilibili.com/x/web-interface/nav").serializingData().value
		let json: JSONObject = try JSONParser.JSONObjectWithData(data)
		let isLogin: Bool = try json.value(for: "data.isLogin")
		NotificationCenter.default.post(name: .biliStatusChanged, object: nil, userInfo: ["isLogin": isLogin])
		var name = ""
		if isLogin {
			name = try json.value(for: "data.uname")
		}
		
		return (isLogin, name)
    }
    
    func logout() async throws {
        guard let url = URL(string: "https://www.bilibili.com"),
              let biliCSRF = HTTPCookieStorage.shared.cookies(for: url)?.first(where: { $0.name == "bili_jct" })?.value else {
            
            throw BilibiliApiError.biliCSRFNotFound
        }
		let _ = try await AF.request("https://passport.bilibili.com/login/exit/v2", method: .post, parameters: ["biliCSRF": biliCSRF]).serializingData().value
    }
    
	func getUid() async throws -> Int {
		let data = try await AF.request("https://api.bilibili.com/x/web-interface/nav").serializingData().value
		let json: JSONObject = try JSONParser.JSONObjectWithData(data)
		return try json.value(for: "data.mid")
    }
    
    func dynamicList(_ uid: Int,
                     _ action: BilibiliDynamicAction = .init😅,
                     _ dynamicID: Int = -1) async throws -> [BilibiliCard] {
        
        var http: DataRequest
        let headers = HTTPHeaders(["referer": "https://www.bilibili.com/"])
        
        
        switch action {
        case .init😅:
            http = AF.request("https://api.vc.bilibili.com/dynamic_svr/v1/dynamic_svr/dynamic_new?uid=\(uid)&type=8", headers: headers)
        case .history:
            http = AF.request("https://api.vc.bilibili.com/dynamic_svr/v1/dynamic_svr/dynamic_history?uid=\(uid)&offset_dynamic_id=\(dynamicID)&type=8", headers: headers)
        case .new:
            http = AF.request("https://api.vc.bilibili.com/dynamic_svr/v1/dynamic_svr/dynamic_new?uid=\(uid)&current_dynamic_id=\(dynamicID)&type=8", headers: headers)
        }
        
		let data = try await http.serializingData().value
		let json: JSONObject = try JSONParser.JSONObjectWithData(data)
		let cards: [BilibiliCard]? = try? json.value(for: "data.cards")
		return cards ?? []
    }
    
    func getPvideo(_ aid: Int) async throws -> BilibiliPvideo {
		let data = try await AF.request("https://api.bilibili.com/x/player/videoshot?aid=\(aid)&index=1").serializingData().value
		let json: JSONObject = try JSONParser.JSONObjectWithData(data)
		return try BilibiliPvideo(object: json)
    }
    
    func getVideoList(_ url: String) async throws -> [(String, [BiliVideoSelector])] {
        var aid = -1
        var bvid = ""
        
        let pathComponents = URL(string: url)?.pathComponents ?? []
        guard pathComponents.count >= 3 else {
            throw VideoGetError.cantFindIdForDM
        }
        let idP = pathComponents[2]
        if idP.starts(with: "av"), let id = Int(idP.replacingOccurrences(of: "av", with: "")) {
            aid = id
        } else if idP.starts(with: "BV") {
            bvid = idP
        } else {
			throw VideoGetError.cantFindIdForDM
        }
        
        var r: DataRequest
        if aid != -1 {
            r = AF.request("https://api.bilibili.com/x/web-interface/view?aid=\(aid)")
        } else if bvid != "" {
            r = AF.request("https://api.bilibili.com/x/web-interface/view?bvid=\(bvid)")
        } else {
			throw VideoGetError.cantFindIdForDM
        }
		
		let data = try await r.serializingData().value
		
		let json: JSONObject = try JSONParser.JSONObjectWithData(data)
		
		if let collection: BilibiliVideoCollection = try json.value(for: "data.ugc_season"), collection.episodes.count > 0 {
			return collection.episodes
		} else {
			var infos: [BiliVideoSelector] = try json.value(for: "data.pages")
			let bvid: String = try json.value(for: "data.bvid")
			
			if infos.count == 1 {
				infos[0].title = try json.value(for: "data.title")
			}
			infos.enumerated().forEach {
				infos[$0.offset].bvid = bvid
			}
			return [("", infos)]
		}
    }
}



struct BilibiliCard: Unmarshaling, Sendable, Hashable {
    var aid: Int = 0
    var bvid: String = ""
    var dynamicId: Int = 0
    var title: String = ""
    var picUrl: String = ""
    var name: String = ""
    var duration: TimeInterval = 0
    var views: Int = 0
    var videos: Int = 0
    
    init(object: any Marshal.MarshaledObject) throws {
        dynamicId = try object.value(for: "desc.dynamic_id")
        bvid = try object.value(for: "desc.bvid")
        let jsonStr: String = try object.value(for: "card")
        if let data = jsonStr.data(using: .utf8) {
            let json: JSONObject = try JSONParser.JSONObjectWithData(data)
            aid = try json.value(for: "aid")
            title = try json.value(for: "title")
            let picUrl: String = try json.value(for: "pic")
            self.picUrl = picUrl.https()
            duration = try json.value(for: "duration")
            name = try json.value(for: "owner.name")
            views = try json.value(for: "stat.view")
            videos = try json.value(for: "videos")
        }
    }
}

enum BilibiliDynamicAction {
    case init😅, new, history
}

struct BilibiliPvideo: Unmarshaling, Sendable, Hashable {
    var images: [String] = []
    var xLen: Int = 0
    var yLen: Int = 0
    var xSize: Int = 0
    var ySize: Int = 0
    var imagesCount: Int = 0
    
    enum CropImagesError: Error {
        case zeroImagesCount
    }
    
    init(object: MarshaledObject) throws {
        let imageStrs: [String] = try object.value(for: "data.image")

        let indexs: [Int] = try object.value(for: "data.index")
        imagesCount = indexs.count
        // limit image count for performance
        if imagesCount > 100 {
            imagesCount = 100
        } else if imagesCount == 0 {
            throw CropImagesError.zeroImagesCount
        }

        if let imageStr = imageStrs.first {
            images = ["https:" + imageStr]
        }
        
        xLen = try object.value(for: "data.img_x_len")
        yLen = try object.value(for: "data.img_y_len")
        xSize = try object.value(for: "data.img_x_size")
        ySize = try object.value(for: "data.img_y_size")
    }
}

protocol BilibiliVideoSelector: VideoSelector {
    var bvid: String { get set }
    var duration: Int { get set }
}

struct BiliVideoSelector: Unmarshaling, BilibiliVideoSelector {
    var url: String = ""
    var isLiving: Bool = false
    
    var bvid = ""
    var isCollection = false
    
    // epid
    let id: String
    var index: Int
    let part: String
    var duration: Int
    var title: String
    let longTitle: String
    let coverUrl: URL?
//    let badge: Badge?
    let site: SupportSites
    
    struct Badge {
        let badge: String
        let badgeColor: NSColor
        let badgeType: Int
    }
    
    init(object: MarshaledObject) throws {
        let cid: Int = try object.value(for: "cid")
        id = "\(cid)"
        
        if let pic: String = try? object.value(for: "arc.pic") {
            coverUrl = .init(string: pic)
            duration = (try? object.value(for: "arc.duration")) ?? 0
            bvid = try object.value(for: "bvid")
            index = 0
            title = try object.value(for: "title")
            isCollection = true
            part = ""
        } else {
            index = try object.value(for: "page")
            part = try object.value(for: "part")
            duration = (try? object.value(for: "duration")) ?? 0
            title = part
            coverUrl = nil
    //        badge = nil
        }
        longTitle = ""
        site = .bilibili
    }
    
	init(ep: BangumiEpList.BangumiEp) {
        id = "\(ep.id)"
        index = -1
        part = ""
        duration = 0
        title = ep.title
        longTitle = ep.longTitle
        coverUrl = nil
//        ep.badgeColor
//        badge = .init(badge: ep.badge,
//                      badgeColor: .red,
//                      badgeType: ep.badgeType)
        site = .bangumi
    }
}

struct BilibiliVideoCollection: Unmarshaling {
    let id: Int
    let title: String
    let cover: URL?
    let mid: Int
    let epCount: Int
    let isPaySeason: Bool
    let episodes: [(String, [BiliVideoSelector])]
    
    init(object: MarshaledObject) throws {
        id = try object.value(for: "id")
        title = try object.value(for: "title")
        cover = .init(string: try object.value(for: "cover"))
        mid = try object.value(for: "mid")
        epCount = try object.value(for: "ep_count")
        isPaySeason = try object.value(for: "is_pay_season")
        
        let s: [Section] = try object.value(for: "sections")
        episodes = s.map {
            ($0.title, $0.episodes)
        }
    }
    
    struct Section: Unmarshaling {
        let id: Int
        let title: String
        let episodes: [BiliVideoSelector]
        
        init(object: MarshaledObject) throws {
            id = try object.value(for: "id")
            title = try object.value(for: "title")
            var eps: [BiliVideoSelector] = try object.value(for: "episodes")
            eps.enumerated().forEach {
                eps[$0.offset].index = $0.offset + 1
            }
            episodes = eps
        }
    }
}

struct BilibiliUrl {
    var p = 1
    var id = ""
    var urlType = UrlType.unknown
    
    var fUrl: String {
        get {
            var u = "https://www.bilibili.com/"
            
            switch urlType {
            case .video:
                u += "video/\(id)"
            case .bangumi:
                u += "bangumi/play/\(id)"
            default:
                return ""
            }
            
            if p > 1 {
                u += "?p=\(p)"
            }
            return u
        }
    }
    
    enum UrlType: String {
        case video, bangumi, unknown
    }
    
    init?(url: String) {
        guard url != "",
              let u = URL(string: url),
              u.host == "www.bilibili.com" || u.host == "bilibili.com",
              let uc = URLComponents(string: url) else {
                  return nil
              }
        
        let pcs = u.pathComponents
        
        guard let id = pcs.first(where: {
            $0.starts(with: "av")
            || $0.starts(with: "BV")
            || $0.starts(with: "ep")
            || $0.starts(with: "ss")
        }) else {
            return nil
        }
        self.id = id
        
        if pcs.contains(UrlType.video.rawValue) {
            urlType = .video
        } else if pcs.contains(UrlType.bangumi.rawValue) {
            urlType = .bangumi
        } else {
            urlType = .unknown
        }
        
        let pStr = uc.queryItems?.first {
            $0.name == "p"
        }?.value ?? "1"
        p = Int(pStr) ?? 1
    }
    
}
