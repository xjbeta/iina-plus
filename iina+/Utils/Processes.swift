//
//  YouGet.swift
//  iina+
//
//  Created by xjbeta on 2018/7/5.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Foundation
import Marshal
import SwiftHTTP
import Socket

class Processes: NSObject {
    
    static let shared = Processes()
    
    private var internalYKDL: String? {
        get {
            var path = Bundle.main.executablePath
            path?.deleteLastPathComponent()
            if let path = path {
                return path + "/ykdl"
            }
            return nil
        }
    }
    
    fileprivate override init() {
    }
    
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

    var decodeTask: Process?
    func decodeURL(_ url: String,
                   _ block: @escaping (_ youget: YouGetJSON) -> Void,
                   _ error: @escaping (_ error: Error) -> Void) {
        stopDecodeURL()
        
        decodeTask = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()
        decodeTask?.standardError = errorPipe
        decodeTask?.standardOutput = pipe
        
        switch Preferences.shared.liveDecoder {
        case .internalYKDL:
            decodeTask?.launchPath = internalYKDL
        case .ykdl, .youget:
            decodeTask?.launchPath = which(Preferences.shared.liveDecoder.rawValue).first ?? ""
        case .internal😀:
            return
        }
        decodeTask?.arguments  = ["--json", url]
        decodeTask?.launch()
        
        Logger.log(url)
        
        decodeTask?.terminationHandler = { _ in
            guard self.decodeTask?.terminationReason != .uncaughtSignal else {
                return
            }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            
            do {
                let json = try JSONParser.JSONObjectWithData(data)
                let re = try YouGetJSON(object: json)
                block(re)
            } catch let er {
                Logger.log("JSON decode error: \(er)")
                if let str = String(data: data, encoding: .utf8) {
                    Logger.log("JSON string: \(str)")
                    if str.contains("Real URL") {
                        let url = str.subString(from: "['", to: "']")
                        let re = YouGetJSON.init(url: url)
                        block(re)
                        return
                    }
                }
                error(er)
            }
            
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            if let str = String(data: errorData, encoding: .utf8) {
                Logger.log("Decode url error info: \(str)")
            }
        }
    }
    
    func stopDecodeURL() {
        if let task = decodeTask, task.isRunning {
            decodeTask?.suspend()
            decodeTask?.terminate()
            decodeTask = nil
        }
    }
    
    enum PlayerOptions {
        case douyu, bilibili, withoutYtdl, none
    }
    
    func openWithPlayer(_ urls: [String], title: String, options: PlayerOptions) {
        let task = Process()
        let pipe = Pipe()
        task.standardInput = pipe
        var mpvArgs = ["\(MPVOption.Miscellaneous.forceMediaTitle)=\(title)"]
        
        switch options {
        case .douyu:
            mpvArgs.append(contentsOf: [MPVOption.Network.cookies,
                                        "\(MPVOption.Network.cookiesFile)=\(getCookies(for: .douyu))",
                                        "\(MPVOption.ProgramBehavior.ytdl)=no"])
        case .bilibili:
            mpvArgs.append(contentsOf: ["\(MPVOption.ProgramBehavior.ytdl)=no",
                                        "\(MPVOption.Network.referrer)=https://www.bilibili.com/"])
        case .withoutYtdl:
            mpvArgs.append("\(MPVOption.ProgramBehavior.ytdl)=no")
        case .none: break
        }
        
        let mergeWithEdl = true
        if !mergeWithEdl {
            if urls.count > 1 {
                mpvArgs.append(MPVOption.ProgramBehavior.mergeFiles)
            }
        }

        switch Preferences.shared.livePlayer {
        case .iina:
            task.launchPath = Preferences.shared.livePlayer.rawValue
            mpvArgs.append("\(MPVOption.Input.inputIpcServer)=/tmp/IINA-Plus-Danmaku-socket")
            mpvArgs = mpvArgs.map {
                "--mpv-" + $0
            }
        case .mpv:
            task.launchPath = which(Preferences.shared.livePlayer.rawValue).first ?? ""
            mpvArgs.append(MPVOption.Terminal.reallyQuiet)
            mpvArgs = mpvArgs.map {
                "--" + $0
            }
        }
        if urls.count == 1 {
            mpvArgs.append(urls.first ?? "")
        } else if urls.count > 1 {
            if mergeWithEdl {
                var edlString = urls.reduce(String()) { result, url in
                    var re = result
                    re += "%\(url.count)%\(url);"
                    return re
                }
                edlString = "edl://" + edlString
                
                mpvArgs.append(edlString)
            } else {
                mpvArgs.append(contentsOf: urls)
            }

        }
        Logger.log("Player arguments: \(mpvArgs)")
        task.arguments = mpvArgs
        task.launch()
    }
    
    func mpvSocket(_ notice: @escaping (_ str: MpvSocketEvent) -> Void,
                   _ closed: @escaping () -> Void) {
        
        let queue = DispatchQueue(label: "socket.test.iina+")
        queue.async {
            let server = "/tmp/IINA-Plus-Danmaku-socket"
            
            do {
                let socket = try Socket.create(family: .unix, proto: .unix)
                try socket.connect(to: server)
                Logger.log("mpv socket connect: \(socket.isConnected)")
                
                if let obs = "{ \"command\": [\"observe_property_string\", 1, \"time-pos\"] }\n".data(using: .utf8) {
                    try socket.write(from: obs)
                }
                if let obs = "{ \"command\": [\"observe_property_string\", 2, \"window-scale\"] }\n".data(using: .utf8) {
                    try socket.write(from: obs)
                }
                
                var shouldKeepRunning = true
                repeat {
                    var d = Data()
                    let _ = try socket.read(into: &d)
                    if d.count > 0 {
                        let json = try JSONParser.JSONObjectWithData(d)
                        let socketEvent = try MpvSocketEvent(object: json)
                        notice(socketEvent)
                    } else {
                        shouldKeepRunning = false
                    }
                } while shouldKeepRunning
                socket.close()
                closed()
            } catch let error {
                Logger.log("mpvSocket error \(error)")
            }
        }
    }
    
    
}

private extension Processes {
    
    func getCookies(for website: LiveSupportList) -> String {
        switch website {
        case .douyu:
            let douyuCookie = "https://passport.douyu.com/lapi/did/api/get"
            let time = UInt32(NSDate().timeIntervalSinceReferenceDate)
            srand48(Int(time))
            let random = "\(drand48())"
            let parameters = ["client_id": "1",
                              "callback": ("jsonp_" + random).replacingOccurrences(of: ".", with: "")]
            let headers = ["Referer": "http://www.douyu.com"]
            
            let httpSemaphore = DispatchSemaphore(value: 0)
            var cookiesString = ""
            
            HTTP.GET(douyuCookie, parameters: parameters, headers: headers) { response in
                do {
                    var str = response.text
                    str = str?.subString(from: "(", to: ")")
                    let json = try JSONParser.JSONObjectWithData(str?.data(using: .utf8) ?? Data())
                    let didStr: String = try json.value(for: "data.did")
                    let date = Int(Date().timeIntervalSince1970)
                    cookiesString = """
                    ..douyu.com    TRUE    /    FALSE    \(date)    dy_did    \(didStr)
                    .www.douyu.com    TRUE    /    FALSE    \(date)    acf_did    \(didStr)
                    """
                } catch let error {
                    Logger.log("DouYu cookies error: \(error)")
                }
                httpSemaphore.signal()
            }
            httpSemaphore.wait()
            return cookiesString
        default:
            return ""
        }
    }
}


struct MpvSocketEvent: Unmarshaling {
    enum MpvEvent: String {
        case propertyChange = "property-change"
        case unpause
        case pause
        case idle
    }

    var event: MpvEvent?
    var id: Int?
    var name: String?
    var data: String?
    var success: Bool?
    
    init(object: MarshaledObject) throws {
        let eventStr: String? = try object.value(for: "event")
        event = MpvEvent(rawValue: eventStr ?? "")
        id = try object.value(for: "id")
        name = try object.value(for: "name")
        data = try object.value(for: "data")
        let errorStr: String? = try object.value(for: "error")
        if errorStr != nil {
            success = errorStr == "success"
        }
    }
}

