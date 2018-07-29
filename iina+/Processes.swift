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
    
    enum Decoder: String {
        case youget = "you-get"
        case ykdl
//        case youtubedl = "youtube-dl"
    }
    
    func findDecoder(_ decoder: Decoder,
                     _ block: @escaping (_ path: String) -> Void) {
        // which you-get
        // command -v you-get
        // type -P you-get
        
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launchPath = "/usr/bin/which"
        task.arguments  = [decoder.rawValue]

        task.launch()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            print(output)
        }
    }

    var decodeTask: Process?
    func decodeURL(_ url: String,
                   with decoder: Decoder,
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
        decodeTask?.launchPath = "/usr/local/bin/" + decoder.rawValue
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
    
    
    func openWithIINA(_ url: String, title: String) {
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launchPath = "/Applications/IINA.app/Contents/MacOS/iina-cli"
        task.arguments  = ["--mpv-force-media-title=\(title)", url, "-w"]
        task.launch()
    }
}
