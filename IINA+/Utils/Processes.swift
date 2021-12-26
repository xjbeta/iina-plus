//
//  YouGet.swift
//  iina+
//
//  Created by xjbeta on 2018/7/5.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Foundation
import Marshal
import PromiseKit
import Cocoa

class Processes: NSObject {
    
    static let shared = Processes()
    let videoGet = VideoGet()
    var decodeTask: Process?
    var videoGetTasks: [(Promise<YouGetJSON>, cancel: () -> Void)] = []
    
    fileprivate override init() {
    }
    
    var urlQueryValueAllowed: CharacterSet = {
        let generalDelimitersToEncode = ":#[]@?/" // does not include "?" or "/" due to RFC 3986 - Section 3.4
        let subDelimitersToEncode = "!$&'()*+,;="
        
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: generalDelimitersToEncode + subDelimitersToEncode)
        
        return allowed
    }()
    
    func which(_ str: String) -> [String] {
        // which you-get
        // command -v you-get
        // type -P you-get
        
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launchPath = "/bin/bash"
        task.arguments  = ["-l", "-c", "which \(str)"]
        
        task.launch()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            return output.components(separatedBy: "\n").filter({ $0 != "" })
        }
        return []
    }

    func iinaBuildVersion() -> Int {
        let b = Bundle(path: "/Applications/IINA.app")
        let build = b?.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return Int(build) ?? 0
    }
    
    func iinaArchiveType() -> IINAUrlType {
        let b = Bundle(path: "/Applications/IINA.app")
        let version = b?.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        if version.contains("Danmaku") {
            return .danmaku
        } else if version.contains("plugin") {
            return .plugin
        }
        return .normal
    }
    
    
    func decodeURL(_ url: String) -> Promise<YouGetJSON> {
        return Promise { resolver in
            switch Preferences.shared.liveDecoder {
            case .ykdl, .youget:
                guard let decoder = which(Preferences.shared.liveDecoder.rawValue).first else {
                    resolver.reject(DecodeUrlError.notFoundDecoder)
                    return
                }
                
                decodeTask = Process()
                let pipe = Pipe()
                let errorPipe = Pipe()
                decodeTask?.standardError = errorPipe
                decodeTask?.standardOutput = pipe
                
                decodeTask?.launchPath = decoder
                decodeTask?.arguments  = ["--json", url]
                Log(url)
                
                decodeTask?.terminationHandler = { _ in
                    guard self.decodeTask?.terminationReason != .uncaughtSignal else {
                        resolver.reject(DecodeUrlError.normalExit)
                        return
                    }
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    
                    do {
                        let json = try JSONParser.JSONObjectWithData(data)
                        let re = try YouGetJSON(object: json)
                        resolver.fulfill(re)
                    } catch let er {
                        Log("JSON decode error: \(er)")
                        if let str = String(data: data, encoding: .utf8) {
                            Log("JSON string: \(str)")
                            if str.contains("Real URL") {
                                let url = str.subString(from: "['", to: "']")
                                let re = YouGetJSON(url: url)
                                resolver.fulfill(re)
                            }
                        }
                        resolver.reject(er)
                    }
                    
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    if let str = String(data: errorData, encoding: .utf8), str != "" {
                        Log("Decode url error info: \(str)")
                    }
                }
                decodeTask?.launch()
            case .internal😀:
                videoGetTasks.append(decodeUrlWithVideoGet(url))
                videoGetTasks.last?.0.done {
                    resolver.fulfill($0)
                    }.catch(policy: .allErrors) {
                        switch $0 {
                        case PMKError.cancelled:
                            resolver.reject(PMKError.cancelled)
                        default:
                            resolver.reject($0)
                        }
                }
            }
        }
    }
    
    enum DecodeUrlError: Error {
        case normalExit
        
        case notFoundDecoder
    }
    
    func stopDecodeURL() {
        if let task = decodeTask, task.isRunning {
            decodeTask?.suspend()
            decodeTask?.terminate()
            decodeTask = nil
        }
        
        videoGetTasks.removeAll {
            $0.0.isFulfilled || $0.0.isRejected
        }
        videoGetTasks.last?.cancel()
    }
    
    func decodeUrlWithVideoGet(_ url: String) -> (Promise<YouGetJSON>, cancel: () -> Void) {
        var cancelme = false
        
        let promise = Promise<YouGetJSON> { resolver in
            self.videoGet.decodeUrl(url).done {
                guard !cancelme else { return resolver.reject(PMKError.cancelled) }
                resolver.fulfill($0)
                }.catch {
                    guard !cancelme else { return resolver.reject(PMKError.cancelled) }
                    resolver.reject($0)
            }
        }
        
        let cancel = {
            cancelme = true
        }
        return (promise, cancel)
    }
    
    func openWithPlayer(_ json: YouGetJSON, _ key: String) {
        let task = Process()
        let pipe = Pipe()
        task.standardInput = pipe
        
        let type = iinaArchiveType()
        let buildVersion = iinaBuildVersion()
        

        guard let u = json.videoUrl(key),
              u != "",
              let iinaUrl = json.iinaUrl(key, type: type) else {
            Log("Not Found YouGetJSON Url.")
            return
        }
        
        switch Preferences.shared.livePlayer {
        case .iina where type == .plugin:
            openWithURLScheme(iinaUrl)
        case .iina where type == .danmaku && buildVersion >= 15:
//            IINA-Danmaku 1.1.2 NEW API
            openWithURLScheme(iinaUrl)
        case .iina where type == .danmaku && buildVersion < 15:
            openWithProcess(u, args: json.mpvOptions, uuid: json.uuid)
        case .iina where type == .normal && buildVersion >= 90:
//            1.0.0 beta3 build 86  URL Scheme without mpv options
//            1.0.0 beta4 build 90
            if [.bilibili, .bangumi].contains(json.site) {
                openWithProcess(u, args: json.mpvOptions, uuid: json.uuid)
            } else {
                openWithURLScheme(iinaUrl)
            }
        case .iina where type == .normal && buildVersion >= 56:
//            iinc-cli build 56
            openWithProcess(u, args: json.mpvOptions, uuid: json.uuid)
        case .mpv:
            openWithProcess(u, args: json.mpvOptions, uuid: json.uuid)
        default:
            break
        }
        
    }
    
    func openWithYtdl(_ url: String) {
        // Use IINA's ytdl to open the raw url
        let buildVersion = iinaBuildVersion()
        guard let v = url.addingPercentEncoding(withAllowedCharacters: urlQueryValueAllowed) else { return }
        if buildVersion >= 90 {
            let u = "iina://open?url=\(v)"
            guard let uu = URL(string: u) else { return }
            Log("Open IINA URL:  \(u)")
            NSWorkspace.shared.open(uu)
        } else if buildVersion >= 56 {
            openWithProcess(url, args: [], uuid: "")
        }
    }
    
    func openWithProcess(_ url: String, args: [String], uuid: String) {
        let livePlayer = Preferences.shared.livePlayer
        let isIINA = livePlayer == .iina
        var args = args
        let task = Process()
        let pipe = Pipe()
        task.standardInput = pipe
        task.launchPath = isIINA ? livePlayer.rawValue : self.which(livePlayer.rawValue).first ?? ""
        if isIINA {
            let type = iinaArchiveType()
            args = args.map {
                "--mpv-" + $0
            }
            if type == .danmaku {
                if Preferences.shared.enableDanmaku {
                    args.append("--danmaku")
                    args.append("--uuid=\(uuid)")
                }
                args.append("--directly")
            }
        } else {
            args.append(MPVOption.Terminal.reallyQuiet)
            args = args.map {
                "--" + $0
            }
        }
        args.insert(url, at: 0)
        Log("Player arguments: \(args)")
        task.arguments = args
        task.launch()
    }
    
    func openWithURLScheme(_ url: String) {
        guard let u = URL(string: url) else {
            Log("Invalid url scheme \(url).")
            return
        }
        Log("openWithURLScheme \(url).")
        NSWorkspace.shared.open(u)
    }
}
