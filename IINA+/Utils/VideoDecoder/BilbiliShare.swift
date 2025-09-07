//
//  BilbiliShare.swift
//  IINA+
//
//  Created by xjbeta on 2024/11/19.
//  Copyright © 2024 xjbeta. All rights reserved.
//

import Foundation
import Alamofire
import Marshal
import CommonCrypto
import CryptoSwift

actor BilibiliShare {
    
    let bangumiUA = "Mozilla/5.0 (X11; Linux x86_64; rv:38.0) Gecko/20100101 Firefox/38.0 Iceweasel/38.2.1"
    let bilibiliUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5.1 Safari/605.1.15"
    
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
        
        let headers = HTTPHeaders(["Referer": "https://www.bilibili.com/",
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
    
    
    // https://github.com/SocialSisterYi/bilibili-API-collect/blob/f1001353f83e12e018ae6bc42fa73654986eb544/docs/misc/sign/wbi.md#swift
    
    func biliWbiSign(param: String, wbiImg: String, wbiSub: String) -> String {
        func getMixinKey(orig: String) -> String {
            String(mixinKeyEncTab.map { orig[orig.index(orig.startIndex, offsetBy: $0)] }.prefix(32))
        }
        
        func encWbi(params: [String: Any], imgKey: String, subKey: String) -> [String: Any] {
            var params = params
            let mixinKey = getMixinKey(orig: imgKey + subKey)
            let currTime = Int(Date().timeIntervalSince1970)
            params["wts"] = currTime
            
            let query = params.sorted {
                $0.key < $1.key
            }.map { (key, value) -> String in
                let stringValue: String
                
                if let doubleValue = value as? Double, doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
                    stringValue = String(Int(doubleValue))
                } else {
                    stringValue = String(describing: value)
                }
                
                let filteredValue = stringValue.filter { !"!'()*".contains($0) }
                
                return "\(key)=\(filteredValue)"
            }.joined(separator: "&")
            
            let wbiSign = (query + mixinKey).md5()
            params["w_rid"] = wbiSign
            
            return params
        }
        
        let mixinKeyEncTab = [
            46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49,
            33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40,
            61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11,
            36, 20, 34, 44, 52
        ]
        
        let spdParam = param.components(separatedBy: "&")
        var spdDicParam = [String: String]()
        for pair in spdParam {
            let components = pair.components(separatedBy: "=")
            if components.count == 2 {
                spdDicParam[components[0]] = components[1]
            }
        }
        
        let signedParams = encWbi(params: spdDicParam, imgKey: wbiImg, subKey: wbiSub)
        return signedParams.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
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
