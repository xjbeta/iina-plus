//
//  Log.swift
//  Aria2D
//
//  Created by xjbeta on 2016/12/25.
//  Copyright © 2016年 xjbeta. All rights reserved.
//

import Cocoa

public func Log<T>(_ message: T, file: String = #file, method: String = #function, line: Int = #line) {
    var logStr = "\(URL(fileURLWithPath: file).lastPathComponent)[\(line)], \(method): \(message)"
	#if DEBUG
		print(logStr)
	#endif
    
    logStr += "\n"
    guard let log = (NSApp.delegate as? AppDelegate)?.logUrl else { return }
    do {
        if !FileManager.default.fileExists(atPath: log.path) {
            FileManager.default.createFile(atPath: log.path, contents: nil, attributes: nil)
        }
        
        let handle = try FileHandle(forWritingTo: log)
        handle.seekToEndOfFile()
        handle.write(logStr.data(using: .utf8)!)
        handle.closeFile()
    } catch {
        print(error.localizedDescription)
        do {
            try logStr.data(using: .utf8)?.write(to: log)
        } catch {
            print(error.localizedDescription)
        }
    }
}
