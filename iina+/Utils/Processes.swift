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
        let b = Bundle.init(path: "/Applications/IINA.app")
        let build = b?.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return Int(build) ?? 0
    }
    
    func isDanmakuVersion() -> Bool {
        let b = Bundle.init(path: "/Applications/IINA.app")
        let version = b?.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return version.contains("Danmaku")
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
    
    enum PlayerOptions {
        case douyu, bilibili, bililive, withoutYtdl, none
    }
    
    func openWithPlayer(_ urls: [String], audioUrl: String = "", title: String, options: PlayerOptions, uuid: String, rawBiliURL: String = "") {
        let task = Process()
        let pipe = Pipe()
        task.standardInput = pipe
        
        let isDV = isDanmakuVersion()
        let buildVersion = iinaBuildVersion()
        
        // Fix title
        let t = title.replacingOccurrences(of: "\"", with: "''")
        var mpvArgs = ["\(MPVOption.Miscellaneous.forceMediaTitle)=\(t)"]
        
        switch options {
        case .douyu:
            mpvArgs.append(contentsOf: ["\(MPVOption.ProgramBehavior.ytdl)=no"])
        case .bilibili:
            if !isDV, !rawBiliURL.contains("?p=") {
                guard let v = rawBiliURL.addingPercentEncoding(withAllowedCharacters: urlQueryValueAllowed) else { return }
                let u = "iina://open?url=\(v)"
                guard let uu = URL(string: u) else { return }
                Log("Open IINA URL:  \(u)")
                NSWorkspace.shared.open(uu)
                return
            }
            
            mpvArgs.append(contentsOf: ["\(MPVOption.ProgramBehavior.ytdl)=no",
                "\(MPVOption.Network.referrer)=https://www.bilibili.com/"])
            if audioUrl != "" {
                mpvArgs.append("\(MPVOption.Audio.audioFile)=\(audioUrl)")
            }
        case .bililive:
            mpvArgs.append(contentsOf: ["\(MPVOption.ProgramBehavior.ytdl)=no",
                "\(MPVOption.Network.referrer)=https://www.bilibili.com/"])
        case .withoutYtdl:
            mpvArgs.append("\(MPVOption.ProgramBehavior.ytdl)=no")
        case .none: break
        }

        var u = ""
        if urls.count == 1 || !isDV {
            u = urls.first ?? ""
        } else if urls.count > 1 {
            let edlString = urls.reduce(String()) { result, url in
                var re = result
                re += "%\(url.count)%\(url);"
                return re
            }
            u = "edl://" + edlString
        }
        
        switch Preferences.shared.livePlayer {
        case .iina where buildVersion < 15:
                task.launchPath = Preferences.shared.livePlayer.rawValue
                mpvArgs = mpvArgs.map {
                    "--mpv-" + $0
                }
        case .mpv:
            task.launchPath = self.which(Preferences.shared.livePlayer.rawValue).first ?? ""
            mpvArgs.append(MPVOption.Terminal.reallyQuiet)
            mpvArgs = mpvArgs.map {
                "--" + $0
            }
            
        default:
            break
        }
        
        

        if Preferences.shared.livePlayer == .iina, isDV {
            if Preferences.shared.enableDanmaku {
                mpvArgs.append("--danmaku")
                mpvArgs.append("--uuid=\(uuid)")
            }
            mpvArgs.append("--directly")
        }
        
        if buildVersion >= 15 {
            openWithIINAUrlScheme(u, args: mpvArgs, uuid: uuid)
            return
        }
        
        mpvArgs.insert(u, at: 0)
        Log("Player arguments: \(mpvArgs)")
        task.arguments = mpvArgs
        task.launch()
    }
    
    
    func openWithIINAUrlScheme(_ url: String, args: [String], uuid: String) {
        let isDV = isDanmakuVersion()
        
        var u = ""
        
        u += isDV ? "iina://iina-plus.base64?" : "iina://open?"
        
        var args = args.map {
            "mpv_" + $0
        }
        
        if isDV {
            args.insert("url=\(url)", at: 0)
        } else {
            args.insert("url=\(url)", at: 0)
            
            args = args.compactMap { kvs -> String? in
                let kv = kvs.split(separator: "=", maxSplits: 1).map(String.init)
                guard kv.count == 2 else {
                    return kvs
                }
                
                guard let v = kv[1].addingPercentEncoding(withAllowedCharacters: urlQueryValueAllowed) else { return nil }
                let k = kv[0]
                return "\(k)=\(v)"
            }
            
        }
        
        var argsStr = ""
        
        if isDV {
            let str = args.joined(separator: "👻")
            Log("Open IINA args:  \(str)")
            guard let base64Str = str.data(using: .utf8)?.base64EncodedString() else {
                return
            }
            argsStr = base64Str
        } else {
            argsStr = args.joined(separator: "&")
        }
        
        u += argsStr
        
        guard let uu = URL(string: u) else { return }
        
        Log("Open IINA URL:  \(u)")
        NSWorkspace.shared.open(uu)
        
    }
    
}
