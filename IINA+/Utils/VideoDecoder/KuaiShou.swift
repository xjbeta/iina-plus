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
import WebKit

class KuaiShou: NSObject, SupportSiteProtocol {

	enum KuaiShouError: Error {
		case invalidLink
		case nilReferer
		case apiLimited
		case unknown
	}
	
	
	var cookies = ""
	var cookiesDate: Date?
	
	var prepareTask: Promise<()>?
	var webView: WKWebView?
	var webViewLoadingObserver: NSKeyValueObservation?
	
	
	var refererStorage = [String: String]()
	var reinitLimit = [String: Int]()
	
    func liveInfo(_ url: String) -> Promise<LiveInfo> {
		if cookies.count == 0,
		   cookiesDate == nil {
			if prepareTask == nil {
				prepareTask = prepareCookies().ensure {
					self.prepareTask = nil
				}
			}
			return prepareTask!.then {
				self.getInfo(url).map { $0 }
			}
		} else {
			return self.getInfo(url).map { $0 }
		}
    }
    
    func decodeUrl(_ url: String) -> Promise<YouGetJSON> {
		getInfo(url).map {
			$0.write(to: YouGetJSON(rawUrl: url))
		}
    }
	
	func deleteCookies() {
		HTTPCookieStorage.shared.cookies?.filter {
			$0.domain.contains("kuaishou")
		}.forEach(HTTPCookieStorage.shared.deleteCookie)
	}

	func prepareCookies() -> Promise<()> {
		.init { resolver in
			webView = WKWebView()
			deleteCookies()
			
			webViewLoadingObserver?.invalidate()
			webViewLoadingObserver = webView?.observe(\.isLoading) { webView, _ in
				guard !webView.isLoading, let url = webView.url else { return }
				
				if url.absoluteString.contains("about") {
					webView.load(.init(url: .init(string: "https://live.kuaishou.com")!))
				} else {
					self.webView?.evaluateJavaScript("document.cookie").done {
						
						self.cookies = $0 as! String
						self.cookiesDate = Date()
						Log("KuaiShou cookies: \(self.cookies)")
						
						self.webView = nil
						self.webViewLoadingObserver?.invalidate()
						self.webViewLoadingObserver = nil
						resolver.fulfill(())
					}.catch {
						resolver.reject($0)
					}
				}
			}
			
			webView?.load(.init(url: .init(string: "https://livev.m.chenzhongtech.com/about/")!))
		}
	}
	
	func getEid(_ url: String) -> String? {
		guard let uc = URLComponents(string: url),
			  uc.path.starts(with: "/u/") else {
			return nil
		}
		
		return String(uc.path.dropFirst(3))
	}
	
    func getInfo(_ url: String) -> Promise<KuaiShouInfo> {
		guard let eid = getEid(url) else {
			return .init(error: KuaiShouError.invalidLink)
		}
		
		let pars: Parameters = [
			"eid": eid,
			"clientType": "WEB_OUTSIDE_SHARE_H5",
			"shareMethod": "card",
			"source": 6
		]
	
		let headers: HTTPHeaders = [
			.userAgent("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"),
			.init(name: "Origin", value: "https://livev.m.chenzhongtech.com"),
			.init(name: "Cookie", value: self.cookies),
			.init(name: "Accept-Encoding", value: "gzip, deflate, br"),
			.init(name: "Accept-Language", value: "zh-Hans;q=1.0")
		]
		
		var isInitRequest = false

		return {
			guard refererStorage[eid] != nil else {
				isInitRequest = true
				self.reinitLimit[eid] = 0
				return loadReferer(eid, headers: headers)
			}
			return Promise { resolver in
				let ref = self.refererStorage[eid]!
				
				var headers = headers
				
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
				
				let limit = self.reinitLimit[eid] ?? 0
				let date = self.cookiesDate ?? Date()
				
				if result == 1 {
					let info = try KuaiShouInfo(object: obj)
					resolver.fulfill(info)
				} else if result == 2,
						  isInitRequest,
						  
						  limit < 3,
						  
						  let date = self.cookiesDate,
						  date.timeIntervalSinceNow > -30 {
					Log("KuaiShou API Limited, try to reinit \(eid)")
					self.reinitLimit[eid] = limit + 1
					
					after(seconds: 1).then {
						self.getInfo(url)
					}.done {
						self.reinitLimit[eid] = 0
						resolver.fulfill($0)
					}.catch {
						resolver.reject($0)
					}
				} else if limit < -15 || (limit <= -2 &&
										  date.timeIntervalSinceNow < -300) {
					
					Log("KuaiShou API Limited, reload cookies")
					self.reinitLimit[eid] = nil
					
					if self.prepareTask == nil {
						self.cookies = ""
						self.cookiesDate = nil
						
						self.prepareTask = self.prepareCookies().ensure {
							self.prepareTask = nil
						}
					}
					
					self.prepareTask!.then {
						self.getInfo(url)
					}.done {
						resolver.fulfill($0)
					}.catch {
						resolver.reject($0)
					}
				} else if result == 2 {
					self.reinitLimit[eid] = limit - 1
					Log("KuaiShou API Limited, result \(result), \(eid)")
					resolver.reject(KuaiShouError.apiLimited)
				} else {
					Log("KuaiShou API failed, result \(result), \(eid)")
					resolver.reject(KuaiShouError.unknown)
				}
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
			
			var headers = headers
			
			self.refererStorage[eid] = ref
			headers.add(name: "Referer", value: ref)
			return headers
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
		let t: String? = try object.value(for: "liveStream.caption")
		
        title = try t ?? object.value(for: "shareInfo.shareSubTitle")
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
