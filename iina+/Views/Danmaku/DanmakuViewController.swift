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
        
        let u1 = URL(fileURLWithPath: "/Users/xjbeta/Developer/CommentCoreLibrary/iina-plus/index.htm")
        
        let u2 = URL(fileURLWithPath: "/Users/xjbeta/Developer/CommentCoreLibrary/")
        webView.loadFileURL(u1, allowingReadAccessTo: u2)
        
        
        
//        wss://tx-sh3-live-comet-01.chat.bilibili.com
        
    }
    @IBAction func start(_ sender: Any) {
        webView.evaluateJavaScript("window.start()") { _, _ in
            
        }
        
    }
    @IBAction func stop(_ sender: Any) {
        webView.evaluateJavaScript("window.stop()") { _, _ in
            
        }
        
    }
    @IBAction func resize(_ sender: Any) {
        webView.evaluateJavaScript("window.resize()") { _, _ in
            
            
        }
        
    }
    @IBAction func loadDM(_ sender: Any) {
        self.webView.evaluateJavaScript("loadDM(\"../download/1.xml\");") { (_, _) in
        }
    }
    
    @IBAction func clear(_ sender: Any) {
        webView.evaluateJavaScript("window.cm.clear()") { _, _ in
            
        }
    }
    
    
    let baseTime: Double = 3240
    
    @IBAction func testSlider(_ sender: Any) {
//        3240630
        let t = slider.doubleValue * baseTime / 100
        sliderTextField.stringValue = "\(t)"

        webView.evaluateJavaScript("window.seek(Math.floor(\(t * 1000)))") { _, _ in
        }
    }
    @IBOutlet weak var slider: NSSlider!
    @IBOutlet weak var sliderTextField: NSTextField!
    @IBAction func sendTest(_ sender: Any) {
        
        webView.evaluateJavaScript("""
        window.cm.send({'text': "wqwjdks;kfa;kfnekwjhfliuhwefakenfklewfkwefw",'stime': 0,'mode': 1,'color': 0xffffff,'border': false})
        """) { _, _ in
        }
    }
    
}

