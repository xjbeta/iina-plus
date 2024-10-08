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

class Bilibili: NSObject, SupportSiteProtocol {
	
	let bilibiliUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5.1 Safari/605.1.15"
	
	let bangumiUA = "Mozilla/5.0 (X11; Linux x86_64; rv:38.0) Gecko/20100101 Firefox/38.0 Iceweasel/38.2.1"
	
	struct BangumiID {
		let epId: Int
		let seasonId: Int
	}
	
	func liveInfo(_ url: String) async throws -> any LiveInfo {
		let isBangumi = SupportSites(url: url) == .bangumi
		
		if isBangumi {
			let ids = try await getBangumiId(url)
			let list = try await getBangumiList(url, ids: ids)
			
			guard let ep = list.episodes.first(where: {
				$0.id == ids.epId
			}) else { throw VideoGetError.notFountData }
			
			var info = BilibiliInfo()
			info.site = .bangumi
			info.title = ep.titles()
			info.cover = ep.cover
			info.isLiving = true
			return info
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
			re = try await getBangumi(url)
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
    
// MARK: - Bilibili
    
    func getBilibili(_ url: String) async throws -> YouGetJSON {
        setBilibiliQuality()

		func r1() async throws -> YouGetJSON {
			let json = try await bilibiliPrepareID(url)
			return try await bilibiliPlayUrl(yougetJson: json)
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
    
	func getBilibiliHTMLDatas(_ url: String, isBangumi: Bool = false) async throws -> (playInfoData: Data, initialStateData: Data, bangumiData: Data) {
        let headers = HTTPHeaders(
            ["Referer": "https://www.bilibili.com/",
			 "User-Agent": isBangumi ? bangumiUA : bilibiliUA])

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
		let bangumiData = re.subString(from: "<script id=\"__NEXT_DATA__\" type=\"application/json\">", to: "</script>").data(using: .utf8) ?? Data()
		
		return (playInfoData, initialStateData, bangumiData)
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
    
    func setBilibiliQuality() {
        // https://github.com/xioxin/biliATV/issues/24
        var cookieProperties = [HTTPCookiePropertyKey: String]()
        cookieProperties[HTTPCookiePropertyKey.name] = "CURRENT_QUALITY" as String
        cookieProperties[HTTPCookiePropertyKey.value] = "125" as String
        cookieProperties[HTTPCookiePropertyKey.domain] = ".bilibili.com" as String
        cookieProperties[HTTPCookiePropertyKey.path] = "/" as String
        let cookie = HTTPCookie(properties: cookieProperties)
        HTTPCookieStorage.shared.setCookie(cookie!)
    }
    
    enum BilibiliFnval: Int {
        case flv = 0
        case mp4 = 1
        case dashH265 = 16
        case hdr = 64
        case dash4K = 128
        case dolbyAudio = 256
        case dolbyVideo = 512
        case dash8K = 1024
        case dashAV1 = 2048
    }
     
    func bilibiliPlayUrl(yougetJson: YouGetJSON,
                         _ isBangumi: Bool = false,
                         _ qn: Int = 132) async throws -> YouGetJSON {
        var yougetJson = yougetJson
        let cid = yougetJson.id
        
        let allowFlv = true
		let dashSymbol = true
		let inner = false
        
        let fnval = allowFlv ? dashSymbol ? inner ? BilibiliFnval.dashH265.rawValue : BilibiliFnval.dashAV1.rawValue + BilibiliFnval.dash8K.rawValue + BilibiliFnval.dolbyVideo.rawValue + BilibiliFnval.dolbyAudio.rawValue + BilibiliFnval.dash4K.rawValue + BilibiliFnval.hdr.rawValue + BilibiliFnval.dashH265.rawValue : BilibiliFnval.flv.rawValue : BilibiliFnval.mp4.rawValue
        
        
        var u = isBangumi ?
        "https://api.bilibili.com/pgc/player/web/playurl?" :
        "https://api.bilibili.com/x/player/playurl?"
        
        u += "cid=\(cid)&bvid=\(yougetJson.bvid)&qn=\(qn)&fnver=0&fnval=\(fnval)&fourk=1"
        
        let headers = HTTPHeaders(
            ["Referer": "https://www.bilibili.com/",
			 "User-Agent": isBangumi ? bangumiUA : bilibiliUA])
        
        
		let data = try await AF.request(u, headers: headers).serializingData().value
		
		let json: JSONObject = try JSONParser.JSONObjectWithData(data)
		
		let code: Int = try json.value(for: "code")
		if code == -10403 {
			throw VideoGetError.needVip
		}
		
		let key = isBangumi ? "result" : "data"
		
		
		do {
			let info: BilibiliPlayInfo = try json.value(for: key)
			yougetJson = info.write(to: yougetJson)
		} catch {
			Log("Bilibili fallback simple play info \(error)")
			let info: BilibiliSimplePlayInfo = try json.value(for: key)
			yougetJson = info.write(to: yougetJson)
		}
		
		return yougetJson
    }
    
    
    // MARK: - Bangumi
    
    func getBangumi(_ url: String) async throws -> YouGetJSON {
        setBilibiliQuality()
        
		let json = try await bilibiliPrepareID(url)
		
        return try await bilibiliPlayUrl(yougetJson: json, true)
    }
    
    func bilibiliPrepareID(_ url: String) async throws -> YouGetJSON {
        guard let bUrl = BilibiliUrl(url: url) else {
			throw VideoGetError.invalidLink
        }
        var json = YouGetJSON(rawUrl: url)
        
        switch bUrl.urlType {
        case .video:
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
        case .bangumi:
            json.site = .bangumi
			let list = try await getBangumiList(url)
			var ep: BangumiEpList.BangumiEp? {
				if bUrl.id.prefix(2) == "ss" {
					return list.episodes.first
				} else {
					return list.episodes.first(where: { $0.id == Int(bUrl.id.dropFirst(2)) })
				}
			}
			guard let s = ep else { throw VideoGetError.notFountData }

			json.bvid = s.bvid
			json.id = s.cid
			if list.episodes.count == 1 {
				json.title = list.episodes.first?.title ?? list.episodes.first?.longTitle ?? ""
			} else {
				let title = [json.title,
							 s.title,
							 s.longTitle].filter {
					$0 != ""
				}.joined(separator: " - ")
				json.title = title
			}
			
			json.duration = s.duration
			return json
        default:
            throw VideoGetError.invalidLink
        }
    }
    
    
// MARK: - Other API
    
    
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
		let data = try await AF.request("https://api.bilibili.com/pvideo?aid=\(aid)").serializingData().value
		let json: JSONObject = try JSONParser.JSONObjectWithData(data)
		var pvideo = try BilibiliPvideo(object: json)
		pvideo.cropImages()
		return pvideo
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
	
	func getBangumiId(_ url: String) async throws -> BangumiID {
		let data = try await getBilibiliHTMLDatas(url, isBangumi: true).playInfoData
		let json: JSONObject = try JSONParser.JSONObjectWithData(data)
		let epid: Int = try json.value(for: "result.play_view_business_info.episode_info.ep_id")
		let sid: Int = try json.value(for: "result.play_view_business_info.season_info.season_id")
		return BangumiID(epId: epid, seasonId: sid)
	}
    
	func getBangumiList(_ url: String, ids: BangumiID? = nil) async throws -> BangumiEpList {
		
		let ids = try await {
			if let ids {
				ids
			} else {
				try await getBangumiId(url)
			}
		}()
		
		let u = "https://api.bilibili.com/pgc/view/web/ep/list?season_id=\(ids.seasonId)"
		let data = try await AF.request(u).serializingData().value
		
		let json: JSONObject = try JSONParser.JSONObjectWithData(data)
		let list = try BangumiEpList(object: json)
		return list
    }
}




@objc(BilibiliCard)
class BilibiliCard: NSObject, Unmarshaling {
    var aid: Int = 0
    var bvid: String = ""
    var dynamicId: Int = 0
    @objc var title: String = ""
    @objc var pic: NSImage?
    @objc var picUrl: String = ""
    @objc var name: String = ""
    @objc var duration: TimeInterval = 0
    @objc var views: Int = 0
    @objc var videos: Int = 0
//    var pubdate = 1533581945
    
    
    override init() {
        super.init()
    }
    
    required init(object: MarshaledObject) throws {
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

struct BilibiliPvideo: Unmarshaling {
    var images: [NSImage] = []
    var pImages: [NSImage] = []
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
//        images = imageStrs.compactMap { str -> NSImage? in
//            if let url = URL(string: str.https()) {
//                return NSImage(contentsOf: url)
//            } else {
//                return nil
//            }
//        }
        let indexs: [Int] = try object.value(for: "data.index")
        imagesCount = indexs.count
        // limit image count for performance
        if imagesCount > 100 {
            imagesCount = 100
        } else if imagesCount == 0 {
            throw CropImagesError.zeroImagesCount
        }
        if let iamgeStr = imageStrs.first,
            let url = URL(string: "https:" + iamgeStr),
            let image = NSImage(contentsOf: url) {
            images = [image]
        }
        
        xLen = try object.value(for: "data.img_x_len")
        yLen = try object.value(for: "data.img_y_len")
        xSize = try object.value(for: "data.img_x_size")
        ySize = try object.value(for: "data.img_y_size")
    }
    
    mutating func cropImages() {
        var pImages: [NSImage] = []
        var limitCount = 0
        images.forEach { image in
            var xIndex = 0
            var yIndex = 0
            
            if limitCount < imagesCount {
                while yIndex < yLen {
                    while xIndex < xLen {
                        let rect = NSRect(x: xIndex * xSize, y: yIndex * ySize, width: xSize, height: ySize)
                        
                        if let croppedImage = crop(image, with: rect) {
                            pImages.append(croppedImage)
                        }
                        limitCount += 1
                        if limitCount == imagesCount {
                            xIndex = 10
                            yIndex = 10
                        }
                        xIndex += 1
                        if xIndex == xLen {
                            xIndex = 0
                            yIndex += 1
                        }
                    }
                }
            }
        }
        self.pImages = pImages
    }
    
    func crop(_ image: NSImage, with rect: NSRect) -> NSImage? {
        guard let croppedImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.cropping(to: rect) else {
            return nil
        }
        let reImage = NSImage(cgImage: croppedImage, size: rect.size)
        return reImage
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


struct BilibiliPlayInfo: Unmarshaling {
	let dash: BilibiliDash
	var qualityDescription = [Int: String]()
	
    struct Durl: Unmarshaling {
        let url: String
        let backupUrls: [String]
        let length: Int
        init(object: MarshaledObject) throws {
            url = try object.value(for: "url")
            let urls: [String]? = try object.value(for: "backup_url")
            backupUrls = urls ?? []
            length = try object.value(for: "length")
        }
    }
    
    init(object: MarshaledObject) throws {
		dash = try object.value(for: "dash")
		
        let acceptQuality: [Int] = try object.value(for: "accept_quality")
        let acceptDescription: [String] = try object.value(for: "accept_description")
        
        var descriptionDic = [Int: String]()
        acceptQuality.enumerated().forEach {
            descriptionDic[$0.element] = acceptDescription[$0.offset]
        }
		
		qualityDescription = descriptionDic
    }
    
    func write(to yougetJson: YouGetJSON) -> YouGetJSON {
        var yougetJson = yougetJson
		yougetJson.duration = dash.duration
		yougetJson.audio = dash.preferAudio()?.url ?? ""
        
		qualityDescription.forEach {
			let id = $0.key
			guard let video = dash.preferVideo(id) else {
				var s = Stream(url: "")
				s.quality = id
				yougetJson.streams[$0.value] = s
				return
			}
			
			var stream = Stream(url: video.url)
			stream.src = video.backupUrl
			stream.quality = $0.key
			stream.dashContent = dash.dashContent($0.key)
			yougetJson.streams[$0.value] = stream
		}
		
        return yougetJson
    }
}

struct BilibiliSimplePlayInfo: Unmarshaling {
    let duration: Int
    let descriptions: [Int: String]
    let quality: Int
    let durl: [BilibiliPlayInfo.Durl]
    
    init(object: MarshaledObject) throws {
        let acceptQuality: [Int] = try object.value(for: "accept_quality")
        let acceptDescription: [String] = try object.value(for: "accept_description")
        
        var descriptionDic = [Int: String]()
        acceptQuality.enumerated().forEach {
            descriptionDic[$0.element] = acceptDescription[$0.offset]
        }
        descriptions = descriptionDic
        
        quality = try object.value(for: "quality")
        durl = try object.value(for: "durl")
        let timelength: Int = try object.value(for: "timelength")
        duration = Int(timelength / 1000)
    }
    
    func write(to yougetJson: YouGetJSON) -> YouGetJSON {
        var yougetJson = yougetJson
        yougetJson.duration = duration
        var dic = descriptions
        if yougetJson.streams.count == 0 {
            dic = dic.filter {
                $0.key <= quality
            }
        }
        
        dic.forEach {
            var stream = yougetJson.streams[$0.value] ?? Stream(url: "")
            if $0.key == quality,
                let durl = durl.first {
                var urls = durl.backupUrls
                urls.append(durl.url)
                urls = MBGA.update(urls)
                
                stream.url = urls.removeFirst()
                stream.src = urls
            }
            stream.quality = $0.key
            yougetJson.streams[$0.value] = stream
        }
        
        return yougetJson
    }
}

struct BangumiEpList: Unmarshaling {
	let episodes: [BangumiEp]
	let section: [BangumiSections]
	
	struct BangumiEp: Unmarshaling {
		let id: Int
		let aid: Int
		let bvid: String
		let cid: Int
		let title: String
		let longTitle: String
		let cover: String
		let duration: Int
		let fullTitle: String
		
		init(object: MarshaledObject) throws {
			id = try object.value(for: "id")
			aid = try object.value(for: "aid")
			bvid = (try? object.value(for: "bvid")) ?? ""
			cid = try object.value(for: "cid")
			title = try object.value(for: "title")
			longTitle = try object.value(for: "long_title")
			let u: String = try object.value(for: "cover")
			cover = u.https()
			
			let d: Int? = try? object.value(for: "duration")
			duration = d ?? 0 / 1000
			
			fullTitle = try object.value(for: "share_copy")
		}
		
		func titles() -> String {
			if fullTitle.isEmpty {
				return [title, longTitle].filter({ $0 != "" }).joined(separator: " ")
			} else {
				return fullTitle
			}
		}
	}
	
	struct BangumiSections: Unmarshaling {
		let id: Int
		let title: String
		let type: Int
		let episodes: [BangumiEp]
		
		init(object: MarshaledObject) throws {
			id = try object.value(for: "id")
			title = try object.value(for: "title")
			type = try object.value(for: "type")
			episodes = try object.value(for: "episodes")
		}
	}
	
	init(object: MarshaledObject) throws {
		episodes = try object.value(for: "result.episodes")
		section = try object.value(for: "result.section")
	}
	
	var epVideoSelectors: [BiliVideoSelector] {
		get {
			var list = episodes.map(BiliVideoSelector.init)
			list.enumerated().forEach {
				list[$0.offset].index = $0.offset + 1
			}
			return list
		}
	}
}

/*
struct BangumiList: Unmarshaling {
    let title: String
    let epList: [BangumiInfo.BangumiEp]
    let sections: [BangumiInfo.BangumiSections]

    var epVideoSelectors: [BiliVideoSelector] {
        get {
            var list = epList.map(BiliVideoSelector.init)
            list.enumerated().forEach {
                list[$0.offset].index = $0.offset + 1
            }
            return list
        }
    }

    var selectionVideoSelectors: [BiliVideoSelector] {
        get {
            var list = sections.compactMap {
                $0.epList.first
            }.map(BiliVideoSelector.init)
            list.enumerated().forEach {
                list[$0.offset].index = $0.offset + 1
            }
            return list
        }
    }

    init(object: MarshaledObject) throws {
        epList = try object.value(for: "epList")
        sections = try object.value(for: "sections")
        title = try object.value(for: "h1Title")
    }
}

struct BangumiPlayInfo: Unmarshaling {
    let session: String
    let isPreview: Bool
    let vipType: Int
    let durl: [BangumiPlayDurl]
    let format: String
    let supportFormats: [BangumiVideoFormat]
    let acceptQuality: [Int]
    let quality: Int
    let hasPaid: Bool
    let vipStatus: Int
    
    init(object: MarshaledObject) throws {
        session = try object.value(for: "session")
        isPreview = try object.value(for: "data.is_preview")
        vipType = try object.value(for: "data.vip_type")
        durl = try object.value(for: "data.durl")
        format = try object.value(for: "data.format")
        supportFormats = try object.value(for: "data.support_formats")
        acceptQuality = try object.value(for: "data.accept_quality")
        quality = try object.value(for: "data.quality")
        hasPaid = try object.value(for: "data.has_paid")
        vipStatus = try object.value(for: "data.vip_status")
    }
    
    struct BangumiPlayDurl: Unmarshaling {
        let size: Int
        let length: Int
        let url: String
        let backupUrl: [String]
        init(object: MarshaledObject) throws {
            size = try object.value(for: "size")
            length = try object.value(for: "length")
            url = try object.value(for: "url")
            backupUrl = try object.value(for: "backup_url")
        }
    }
    
    struct BangumiVideoFormat: Unmarshaling {
        let needLogin: Bool
        let format: String
        let description: String
        let needVip: Bool
        let quality: Int
        init(object: MarshaledObject) throws {
            needLogin = (try? object.value(for: "need_login")) ?? false
            format = try object.value(for: "format")
            description = try object.value(for: "description")
            needVip = (try? object.value(for: "need_vip")) ?? false
            quality = try object.value(for: "quality")
        }
    }
}

struct BangumiInfo: Unmarshaling {
    let title: String
    let mediaInfo: BangumiMediaInfo
    let epList: [BangumiEp]
    let epInfo: BangumiEp
    let sections: [BangumiSections]
    let isLogin: Bool
    
    init(object: MarshaledObject) throws {
        title = try object.value(for: "mediaInfo.title")
//        title = try object.value(for: "h1Title")
        mediaInfo = try object.value(for: "mediaInfo")
        epList = try object.value(for: "epList")
        epInfo = try object.value(for: "epInfo")
        sections = try object.value(for: "sections")
        isLogin = try object.value(for: "isLogin")
    }
    
    struct BangumiMediaInfo: Unmarshaling {
        let id: Int
        let ssid: Int?
        let title: String
        let squareCover: String
        let cover: String
        
        init(object: MarshaledObject) throws {
            
            id = try object.value(for: "id")
            ssid = try? object.value(for: "ssid")
            title = try object.value(for: "title")
            squareCover = "https:" + (try object.value(for: "squareCover"))
            cover = "https:" + (try object.value(for: "cover"))
        }
    }
    
    struct BangumiSections: Unmarshaling {
        let id: Int
        let title: String
        let type: Int
        let epList: [BangumiEp]
        init(object: MarshaledObject) throws {
            id = try object.value(for: "id")
            title = try object.value(for: "title")
            type = try object.value(for: "type")
            epList = try object.value(for: "epList")
        }
    }

    struct BangumiEp: Unmarshaling {
        let id: Int
//        let badge: String
//        let badgeType: Int
//        let badgeColor: String
        let epStatus: Int
        let aid: Int
        let bvid: String
        let cid: Int
        let title: String
        let longTitle: String
        let cover: String
        let duration: Int
        
        init(object: MarshaledObject) throws {
            id = try object.value(for: "id")
//            badge = try object.value(for: "badge")
//            badgeType = try object.value(for: "badgeType")
//            badgeColor = (try? object.value(for: "badgeColor")) ?? ""
            epStatus = try object.value(for: "epStatus")
            aid = try object.value(for: "aid")
            bvid = (try? object.value(for: "bvid")) ?? ""
            cid = try object.value(for: "cid")
            title = try object.value(for: "title")
            longTitle = try object.value(for: "longTitle")
            let u: String = try object.value(for: "cover")
            cover = "https:" + u
            let d: Int? = try? object.value(for: "duration")
            duration = d ?? 0 / 1000
        }
    }
}
*/
