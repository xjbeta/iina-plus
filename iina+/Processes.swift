//
//  YouGet.swift
//  iina+
//
//  Created by xjbeta on 2018/7/5.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Foundation
import Marshal

class Processes: NSObject {
    
    static let shared = Processes()
    
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
        if let task = decodeTask, task.isRunning {
            decodeTask?.suspend()
            decodeTask?.terminate()
            decodeTask?.waitUntilExit()
            decodeTask = nil
        }
        
        decodeTask = Process()
        let pipe = Pipe()

        decodeTask?.standardOutput = pipe
        decodeTask?.launchPath = which(Preferences.shared.liveDecoder.rawValue).first ?? ""
        decodeTask?.arguments  = ["--json", url]
        decodeTask?.launch()
        
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
                error(er)
                print("json error: \(er)")
                if let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            }
        }
    }
    
    func openWithPlayer(_ url: String, title: String) {
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        var mpvArgs = ["\(MPVOption.Miscellaneous.forceMediaTitle)=\(title)"]
        
        switch Preferences.shared.livePlayer {
        case .iina:
            task.launchPath = Preferences.shared.livePlayer.rawValue
            mpvArgs = mpvArgs.map {
                "--mpv-" + $0
            }
        case .mpv:
            task.launchPath = which(Preferences.shared.livePlayer.rawValue).first ?? ""
            mpvArgs.append(MPVOption.Terminal.quiet)
            mpvArgs = mpvArgs.map {
                "--" + $0
            }
        }
        mpvArgs.append(url)
        task.arguments = mpvArgs
        task.launch()
        
    }
    

}
