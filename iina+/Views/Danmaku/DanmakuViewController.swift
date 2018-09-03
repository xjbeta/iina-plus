//
//  DanmakuViewController.swift
//  iina+
//
//  Created by xjbeta on 2018/8/28.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class DanmakuViewController: NSViewController {

    @IBOutlet weak var webView: WKWebView!
    override func viewDidLoad() {
        super.viewDidLoad()
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webView.configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        webView.setValue(false, forKey: "drawsBackground")
        
        if let resourcePath = Bundle.main.resourcePath {
            let u1 = URL(fileURLWithPath: resourcePath + "/index.htm")
            webView.loadFileURL(u1, allowingReadAccessTo: URL(fileURLWithPath: resourcePath))
        }
    }
    
}

