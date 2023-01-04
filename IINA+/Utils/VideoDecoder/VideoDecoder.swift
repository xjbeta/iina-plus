//
//  VideoDecoder.swift
//  iina+
//
//  Created by xjbeta on 2018/10/28.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import Alamofire
import PromiseKit
import Marshal
import CommonCrypto
import JavaScriptCore
import WebKit
import SwiftSoup

class VideoDecoder: NSObject {
    lazy var douyin = DouYin()
    lazy var huya = Huya()
    lazy var douyu = Douyu()
    lazy var cc163 = CC163()
    lazy var biliLive = BiliLive()
    lazy var bilibili = Bilibili()
    lazy var qqLive = QQLive()
    
    
    func bilibiliUrlFormatter(_ url: String) -> Promise<String> {
        let site = SupportSites(url: url)
        
        switch site {
        case .bilibili, .bangumi:
            return .value(BilibiliUrl(url: url)!.fUrl)
        case .b23:
            return Promise { resolver in
                AF.request(url).response {
                    guard let url = $0.response?.url?.absoluteString,
                          let u = BilibiliUrl(url: url)?.fUrl else {
                        resolver.reject(VideoGetError.invalidLink)
                        return
                    }
                    resolver.fulfill(u)
                }
            }
        default:
            return .value(url)
        }
    }
    
    func decodeUrl(_ url: String) -> Promise<YouGetJSON> {
        switch SupportSites(url: url) {
        case .biliLive:
            return biliLive.decodeUrl(url)
        case .douyu:
            return douyu.decodeUrl(url)
        case .huya:
            return huya.decodeUrl(url)
        case .bilibili, .bangumi:
            return bilibili.decodeUrl(url)
        case .cc163:
            return cc163.decodeUrl(url)
        case .douyin:
            return douyin.decodeUrl(url)
        case .qqLive:
            return qqLive.decodeUrl(url)
        default:
            return .init(error: VideoGetError.notSupported)
        }
    }
    
    func prepareDanmakuFile(yougetJSON: YouGetJSON, id: String) -> Promise<()> {
        let pref = Preferences.shared
        
        guard Processes.shared.iinaArchiveType() != .normal,
              pref.enableDanmaku,
              pref.livePlayer == .iina,
              [.bilibili, .bangumi, .local].contains(yougetJSON.site),
              yougetJSON.id != -1 else {
                  Log("Ignore Danmaku download.")
                  return .value(())
        }
  
//        return self.downloadDMFile(yougetJSON.id, id: id)
        
        
        return self.downloadDMFileV2(
            cid: yougetJSON.id,
            length: yougetJSON.duration,
            id: id)
    }
    
    func liveInfo(_ url: String, _ checkSupport: Bool = true) -> Promise<LiveInfo> {
        let site = SupportSites(url: url)
        switch site {
        case .biliLive:
            return biliLive.liveInfo(url)
        case .douyu:
            return douyu.liveInfo(url)
        case .huya:
            return huya.liveInfo(url)
        case .bilibili, .bangumi:
            return bilibili.liveInfo(url)
        case .cc163:
            return cc163.liveInfo(url)
        case .douyin:
            return douyin.liveInfo(url)
        case .qqLive:
            return qqLive.liveInfo(url)
        default:
            if checkSupport {
                return .init(error: VideoGetError.notSupported)
            } else {
                var info = BiliLiveInfo()
                info.isLiving = true
                
                return .value(info)
            }
        }
    }
    
    func prepareVideoUrl(_ json: YouGetJSON, _ key: String) -> Promise<YouGetJSON> {
        
        guard json.id != -1 else {
            return .value(json)
        }
        
        switch json.site {
        case .bilibili, .bangumi:
            guard let stream = json.streams[key],
                  stream.url == "" else {
                return .value(json)
            }
            let qn = stream.quality
            
            return bilibili.bilibiliPlayUrl(yougetJson: json, false, true, qn)
        case .biliLive:
            guard let stream = json.streams[key],
                  stream.quality != -1 else {
                return .value(json)
            }
            let qn = stream.quality
            
            if stream.src.count > 0 {
                return .value(json)
            } else {
                return biliLive.getBiliLiveJSON(json, qn)
            }
        case .douyu:
            guard let stream = json.streams[key],
                  stream.quality != -1 else {
                return .value(json)
            }
            let rate = stream.rate
            if stream.url != "" {
                return .value(json)
            } else {
                let id = json.id
                return douyu.getDouyuHtml("https://www.douyu.com/\(id)").then {
                    self.douyu.getDouyuUrl(id, rate: rate, jsContext: $0.jsContext)
                }.map {
                    let url = $0.first {
                        $0.1.rate == rate
                    }?.1.url
                    var re = json
                    re.streams[key]?.url = url
                    return re
                }
            }
        default:
            return .value(json)
        }
    }
}



extension VideoDecoder {
    



    
    // MARK: - Bilibili Danmaku
    func downloadDMFile(_ cid: Int, id: String) -> Promise<()> {
        return Promise { resolver in
            AF.request("https://comment.bilibili.com/\(cid).xml").response { response in
                if let error = response.error {
                    resolver.reject(error)
                }
                self.saveDMFile(response.data, with: id)
                resolver.fulfill(())
            }
        }
    }
    
    
    func downloadDMFileV2(cid: Int, length: Int, id: String) -> Promise<()> {
        
//        segment_index  6min
        
        let c = Int(ceil(Double(length) / 360))
        let s = c > 1 ? Array(1...c) : [1]
        
        print("downloadDMFileV2", c)
        
        guard c < 1500 else {
            return .value(())
        }
        
        return when(fulfilled: s.map {
            getDanmakuContent(cid: cid, index: $0)
        }).done {
            
            let element = try XMLElement(xmlString: #"<?xml version="1.0" encoding="UTF-8"?><i><chatserver>chat.bilibili.tv</chatserver><chatid>170102</chatid></i>"#)

            let doc = XMLDocument(rootElement: element)

            Array($0.joined()).map { dm -> String in
                let s1 = ["\(Double(dm.progress) / 1000)",
                          "\(dm.mode)",
                          "\(dm.fontsize)",
                          "\(dm.color)",
                          "\(dm.ctime)",
                          "\(dm.pool)",
                          "\(dm.midHash)",
                          "\(dm.id)"].joined(separator: ",")
                var s2 = dm.content
                        
                s2 = s2.replacingOccurrences(of: "<", with: "&lt;")
                s2 = s2.replacingOccurrences(of: ">", with: "&gt;")
                s2 = s2.replacingOccurrences(of: "&", with: "&amp;")
                s2 = s2.replacingOccurrences(of: "'", with: "&apos;")
                s2 = s2.replacingOccurrences(of: "\"", with: "&quot;")
                
                s2 = s2.replacingOccurrences(of: "`", with: "&apos;")
                
                return "<d p=\"\(s1)\">\(s2)</d>"
            }.forEach {
                if let node = try? XMLElement(xmlString: $0) {
                    element.addChild(node)
                } else {
                    Log("Invalid Bangumi Line: \($0)")
                }
            }
            
            self.saveDMFile(doc.xmlData, with: id)
        }
    }
    
    func saveDMFile(_ data: Data?, with id: String) {
        guard let path = dmPath(id) else { return }
        var p = path
        p.deleteLastPathComponent()
        try? FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: data, attributes: nil)
        Log("Saved DM in \(path)")
    }
    
    func dmPath(_ id: String) -> String? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
            var filesURL = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return nil
        }
        let folderName = "WebFiles"
        
        filesURL.appendPathComponent(bundleIdentifier)
        filesURL.appendPathComponent(folderName)
        let fileName = "danmaku" + "-" + id + ".xml"
        
        filesURL.appendPathComponent(fileName)
        return filesURL.path
    }
    
    func getDanmakuContent(cid: Int, index: Int) -> Promise<([DanmakuElem])> {
        return Promise { resolver in
            let u = "https://api.bilibili.com/x/v2/dm/web/seg.so?type=1&oid=\(cid)&segment_index=\(index)"
            
            AF.request(u).response { response in
                if let error = response.error {
                    resolver.reject(error)
                    return
                }

                guard let d = response.data else {
                    resolver.fulfill([])
                    return
                }
                
                do {
                    let re = try DmSegMobileReply(serializedData: d)
                    resolver.fulfill(re.elems)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
}

enum VideoGetError: Error {
    case invalidLink
    
    case douyuUrlError
    case douyuSignError
    case douyuNotFoundRoomId
    case douyuNotFoundSubRooms
    case douyuRoomIdsCountError
    
    case isNotLiving
    case notFindUrls
    case notSupported
    
    case cantFindIdForDM
    
    case prepareDMFailed
    
    case cantWatch
    case notFountData
    case needVip
    case needPassWork
}
