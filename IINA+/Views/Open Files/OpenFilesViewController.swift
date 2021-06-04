//
//  OpenFilesViewController.swift
//  iina+
//
//  Created by xjbeta on 2019/6/11.
//  Copyright © 2019 xjbeta. All rights reserved.
//

import Cocoa
import PromiseKit

class OpenFilesViewController: NSViewController {
    @IBOutlet weak var videoTextField: NSTextField!
    @IBOutlet weak var danmakuTextField: NSTextField!
    
    @IBOutlet weak var videoButton: NSButton!
    @IBOutlet weak var danmakuButton: NSButton!
    
    @IBAction func select(_ sender: NSButton) {
        guard let window = view.window else { return }
        
        panel.beginSheetModal(for: window) { [weak self] in
            guard $0 == .OK, let url = self?.panel.url else {
                return
            }
            switch sender {
            case self?.videoButton:
                self?.videoURL = url
                self?.videoTextField.stringValue = url.lastPathComponent
            case self?.danmakuButton:
                self?.danmakuURL = url
                self?.danmakuTextField.stringValue = url.lastPathComponent
            default:
                break
            }
        }
    }
    
    @IBAction func cancel(_ sender: NSButton) {
        view.window?.close()
    }
    
    @IBAction func open(_ sender: NSButton) {
        var yougetJSON: YouGetJSON?
        let id = UUID().uuidString
        getVideo().get {
            yougetJSON = $0
        }.then { _ in
            self.getDanmaku(id)
        }.done {
            guard let stream = yougetJSON?.videos.first?.value,
                let urlStr = stream.url else {
                return
            }
            NotificationCenter.default.post(name: .loadDanmaku, object: nil, userInfo: ["id": id])
            
            if self.isBilibiliVideo() {
                Processes.shared.openWithPlayer([urlStr], audioUrl: yougetJSON?.audio ?? "", title: yougetJSON?.title ?? "", options: .bilibili, uuid: id)
            } else {
                Processes.shared.openWithPlayer([urlStr], title: yougetJSON?.title ?? "", options: .withoutYtdl, uuid: id)
            }
            
            self.view.window?.close()
        }.catch {
            Log($0)
        }
    }
    
    var videoURL: URL?
    var danmakuURL: URL?
    
    lazy var panel: NSOpenPanel = {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = false
        p.canChooseDirectories = false
        p.canChooseFiles = true
        return p
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
    }
    
    func isBilibiliVideo() -> Bool {
        if videoURL == nil {
            let videoStr = videoTextField.stringValue
            return videoStr.starts(with: "av") || videoStr.starts(with: "https://www.bilibili.com/video/av") ||
                videoStr.starts(with: "BV") || videoStr.starts(with: "https://www.bilibili.com/video/BV")
        } else {
            return false
        }
    }
    
    func getVideo() -> Promise<(YouGetJSON)> {
        return Promise { resolver in
            guard videoURL == nil else {
                if let path = videoURL?.path {
                    resolver.fulfill(YouGetJSON(url: path))
                } else {
                    resolver.reject(OpenFilesError.invalidVideoUrl)
                }
                return
            }
            
            let videoStr = videoTextField.stringValue
            
            var url = ""
            
            if videoStr.starts(with: "av") ||
                videoStr.starts(with: "BV") {
                url = "https://www.bilibili.com/video/" + videoStr

            } else if videoStr.starts(with: "https://www.bilibili.com/video/av") ||
                        videoStr.starts(with: "https://www.bilibili.com/video/BV") {
                url = videoStr
            } else {
                resolver.fulfill(YouGetJSON(url: videoStr))
                return
            }
            
            Processes.shared.videoGet.decodeUrl(url).done {
                resolver.fulfill($0)
                }.catch {
                    resolver.reject($0)
            }
        }
    }
    
    func getDanmaku(_ id: String, yougetJSON: YouGetJSON? = nil) -> Promise<()> {
        let videoGet = Processes.shared.videoGet
        return Promise { resolver in
            guard danmakuURL == nil else {
                let url = danmakuURL!
                let data = FileManager.default.contents(atPath: url.path)
                videoGet.saveDMFile(data, with: id)
                resolver.fulfill(())
                return
            }
            
            
            var url = ""
            
            let s = danmakuTextField.stringValue
            

            if s.starts(with: "https://www.bilibili.com") {
                url = s
            } else {
                guard s.count > 2 else {
                    resolver.reject(OpenFilesError.invalidDanmakuString)
                    return
                }
                
                let i2 = s.index(s.startIndex, offsetBy: 2)
                let head = s[i2...]
                let v = s[s.startIndex..<i2]

                if let type = BilibiliIdType(rawValue: String(head)),
                   type != .ss,
                   let _ = Int(v) {
                    url = type.url() + s
                } else {
                    resolver.reject(OpenFilesError.unsupported)
                }
            }
            
            guard let u = URL(string: url) else {
                resolver.reject(OpenFilesError.unsupported)
                return
            }
            
            videoGet.decodeUrl(url).then {
                videoGet.prepareDanmakuFile(yougetJSON: $0, id: id)
            }.done {
                resolver.fulfill(())
            }.catch {
                resolver.reject($0)
            }
        }
    }
    
    enum BilibiliIdType: String {
        case ep
        case ss
        case bv = "BV"
        case av
        
        func url() -> String {
            switch self {
            case .av, .bv:
                return "https://www.bilibili.com/video/"
            case .ss, .ep:
                return "https://www.bilibili.com/bangumi/play/"
            }
        }
    }
    
    enum OpenFilesError: Error {
        case invalidVideoString
        case invalidVideoUrl
        case invalidDanmakuString
        case invalidDanmakuUrl
        case unsupported
    }
}

extension OpenFilesViewController: NSTextFieldDelegate {
    func control(_ control: NSControl, textShouldBeginEditing fieldEditor: NSText) -> Bool {
        switch control {
        case videoTextField:
            videoURL = nil
        case danmakuTextField:
            danmakuURL = nil
        default:
            return false
        }
        
        return true
    }
}
