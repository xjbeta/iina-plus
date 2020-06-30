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
        
        getVideo().get {
            yougetJSON = $0
            }.then { _ in
                self.getDanmaku()
        }.done {
            guard let stream = yougetJSON?.streams.sorted(by: { $0.key < $1.key }).first?.value,
                let urlStr = stream.url else {
                return
            }
            let id = UUID().uuidString
            
            if self.isBilibiliVideo() {
                Processes.shared.openWithPlayer([urlStr], audioUrl: yougetJSON?.audio ?? "", title: yougetJSON?.title ?? "", options: .bilibili, uuid: id)
            } else {
                Processes.shared.openWithPlayer([urlStr], title: yougetJSON?.title ?? "", options: .withoutYtdl, uuid: id)
            }
            
            NotificationCenter.default.post(name: .loadDanmaku, object: nil, userInfo: ["id": id])
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
            return videoStr.starts(with: "av") || videoStr.starts(with: "https://www.bilibili.com/video/av")
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
            
            if videoStr.starts(with: "av") || videoStr.starts(with: "https://www.bilibili.com/video/av") {
                guard let aid = Int(videoStr.subString(from: "av")) else {
                        resolver.reject(OpenFilesError.invalidVideoString)
                        return
                }
                Processes.shared.videoGet.decodeUrl("https://www.bilibili.com/video/av\(aid)").done {
                    resolver.fulfill($0)
                    }.catch {
                        resolver.reject($0)
                }
            } else {
                resolver.fulfill(YouGetJSON(url: videoStr))
            }
        }
    }
    
    func getDanmaku() -> Promise<()> {
        return Promise { resolver in
            guard danmakuURL == nil else {
                if let url = danmakuURL {
                    guard let resourcePath = Bundle.main.resourcePath else {
                        resolver.reject(VideoGetError.prepareDMFailed)
                        return
                    }
                    let danmakuFilePath = resourcePath + "/danmaku/iina-plus-danmaku.xml"
                    try FileManager.default.removeItem(atPath: danmakuFilePath)
                    try FileManager.default.copyItem(atPath: url.path, toPath: danmakuFilePath)
                    resolver.fulfill(())
                } else {
                    resolver.reject(OpenFilesError.invalidDanmakuUrl)
                }
                return
            }
            
            let danmakuStr = danmakuTextField.stringValue
            
            if danmakuStr.starts(with: "av") || danmakuStr.starts(with: "https://www.bilibili.com/video/av") {
                guard let aid = Int(danmakuStr.subString(from: "av")), let url = URL(string: "https://www.bilibili.com/video/av\(aid)") else {
                    resolver.reject(OpenFilesError.invalidVideoString)
                    return
                }
                Processes.shared.videoGet.prepareDanmakuFile(url).done {
                    resolver.fulfill(())
                    }.catch {
                        resolver.reject($0)
                }
            } else {
                resolver.reject(OpenFilesError.unsupported)
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
