//
//  Logger.swift
//  iina
//
//  Created by Collider LI on 24/5/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation
import Cocoa

struct Logger {
    
    static let logDirURL: URL = {
        // get path
        let libraryPath = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
        Logger.ensure(libraryPath.count >= 1, "Cannot get path to Logs directory")
        let logsUrl = libraryPath.first!.appendingPathComponent("Logs", isDirectory: true)
        let bundleID = Bundle.main.bundleIdentifier!
        let appLogsUrl = logsUrl.appendingPathComponent(bundleID, isDirectory: true)
        createDirIfNotExist(url: appLogsUrl)
        return appLogsUrl
    }()
    
    static func createDirIfNotExist(url: URL) {
        let path = url.path
        // check exist
        if !FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            } catch {
                Logger.fatal("Cannot create directory: \(url)")
            }
        }
    }
    
    struct Subsystem: RawRepresentable {
        var rawValue: String
        
        static let general = Subsystem(rawValue: "iina+")
        
        init(rawValue: String) {
            self.rawValue = rawValue
        }
    }
    
    enum Level: Int, Comparable, CustomStringConvertible {
        static func < (lhs: Level, rhs: Level) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
        
        case verbose
        case debug
        case warning
        case error
        
        static var preferred: Level = Level(rawValue: Preferences.shared.logLevel)!
        
        var description: String {
            switch self {
            case .verbose: return "v"
            case .debug: return "d"
            case .warning: return "w"
            case .error: return "e"
            }
        }
    }
    
    static var enabled: Bool {
        return Preferences.shared.enableLogging
    }
    
    static let logDirectory: URL = {
        let formatter = DateFormatter()
        formatter.dateFormat = "YYYY-MM-dd-HH-mm-ss"
        let timeString  = formatter.string(from: Date())
        let token = ShortCodeGenerator.getCode(length: 6)
        let sessionDirName = "\(timeString)_\(token)"
        let sessionDir = logDirURL.appendingPathComponent(sessionDirName, isDirectory: true)
        createDirIfNotExist(url: sessionDir)
        return sessionDir
    }()
    
    private static var logFileHandle: FileHandle = {
        let logFileURL = logDirectory.appendingPathComponent("iina+.log")
        FileManager.default.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
        return try! FileHandle(forWritingTo: logFileURL)
    }()
    
    private static var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
    
    static func closeLogFile() {
        guard enabled else { return }
        logFileHandle.closeFile()
    }
    
    @inline(__always)
    static func log(_ message: String, level: Level = .debug, subsystem: Subsystem = .general, appendNewlineAtTheEnd: Bool = true) {
        #if !DEBUG
        guard enabled else { return }
        #endif
        
        guard level >= .preferred else { return }
        let time = dateFormatter.string(from: Date())
        let string = "\(time) [\(subsystem.rawValue)][\(level.description)] \(message)\(appendNewlineAtTheEnd ? "\n" : "")"
        print(string, terminator: "")
        
        #if DEBUG
        guard enabled else { return }
        #endif
        
        if let data = string.data(using: .utf8) {
            logFileHandle.write(data)
        } else {
            NSLog("Cannot encode log string!")
        }
    }
    
    static func ensure(_ condition: @autoclosure () -> Bool, _ errorMessage: String = "Assertion failed in \(#line):\(#file)", _ cleanup: () -> Void = {}) {
        guard condition() else {
            log(errorMessage, level: .error)
            showAlert("fatal_error", arguments: [errorMessage])
            cleanup()
            exit(1)
        }
    }
    
    static func fatal(_ message: String, _ cleanup: () -> Void = {}) -> Never {
        log(message, level: .error)
        log(Thread.callStackSymbols.joined(separator: "\n"))
        showAlert("fatal_error", arguments: [message])
        cleanup()
        exit(1)
    }
    
    static func showAlert(_ key: String, comment: String? = nil, arguments: [CVarArg]? = nil, style: NSAlert.Style = .critical) {
        let alert = NSAlert()
        switch style {
        case .critical:
            alert.messageText = NSLocalizedString("alert.title_error", comment: "Error")
        case .informational:
            alert.messageText = NSLocalizedString("alert.title_info", comment: "Information")
        case .warning:
            alert.messageText = NSLocalizedString("alert.title_warning", comment: "Warning")
        }
        
        var format: String
        if let stringComment = comment {
            format = NSLocalizedString("alert." + key, comment: stringComment)
        } else {
            format = NSLocalizedString("alert." + key, comment: key)
        }
        
        if let stringArguments = arguments {
            alert.informativeText = String(format: format, arguments: stringArguments)
        } else {
            alert.informativeText = String(format: format)
        }
        
        alert.alertStyle = style
        alert.runModal()
    }
    
    struct ShortCodeGenerator {
        
        private static let base62chars = [Character]("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        private static let maxBase : UInt32 = 62
        
        static func getCode(withBase base: UInt32 = maxBase, length: Int) -> String {
            var code = ""
            for _ in 0..<length {
                let random = Int(arc4random_uniform(min(base, maxBase)))
                code.append(base62chars[random])
            }
            return code
        }
    }
}
