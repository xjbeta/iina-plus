//
//  BilibiliLoginViewController.swift
//  iina+
//
//  Created by xjbeta on 2018/8/6.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import WebKit
import PromiseKit

class BilibiliLoginViewController: NSViewController {

    @IBOutlet weak var tabView: NSTabView!
    @IBOutlet weak var viewForWeb: NSView!
    @IBOutlet weak var waitProgressIndicator: NSProgressIndicator!
    var webView: WKWebView!
    var dismiss: (() -> Void)?
    let bilibili = Bilibili()
    @IBAction func tryAgain(_ sender: Any) {
        loadWebView()
    }
    
    var webviewObserver: NSKeyValueObservation?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        loadWebView()
    }
    
    override func keyDown(with event: NSEvent) {
        super.keyUp(with: event)
        switch event.keyCode {
        case 53:
            dismiss?()
        default:
            break
        }
    }
    
    func clearCookies() {
        HTTPCookieStorage.shared.removeCookies(since: Date.distantPast)
        WKWebsiteDataStore.default().fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            records.forEach { record in
                WKWebsiteDataStore.default().removeData(ofTypes: record.dataTypes, for: [record], completionHandler: {})
            }
        }
    }
    
    func loadWebView() {
        tabView.selectTabViewItem(at: 0)
        
        let url = URL(string: "https://passport.bilibili.com/login")
        let script = """
document.getElementsByClassName("sns")[0].remove();
document.getElementsByClassName("btn btn-reg")[0].remove()
"""
        // WebView Config
        let contentController = WKUserContentController()
        let scriptInjection = WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        contentController.addUserScript(scriptInjection)
        let webViewConfiguration = WKWebViewConfiguration()
        webViewConfiguration.userContentController = contentController
        
        // Display Views
        waitProgressIndicator.isHidden = true
        webView = WKWebView(frame: viewForWeb.bounds, configuration: webViewConfiguration)
        webView.navigationDelegate = self
        viewForWeb.subviews.removeAll()
        viewForWeb.addSubview(webView)
        webView.isHidden = false
        
        let request = URLRequest(url: url!)
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 10_2_1 like Mac OS X) AppleWebKit/602.4.6 (KHTML, like Gecko) Version/10.0 Mobile/14D27 Safari/602.1"
        webView.load(request)
    }
    
    func displayWait() {
        webView.isHidden = true
        waitProgressIndicator.isHidden = false
        waitProgressIndicator.startAnimation(self)
    }
    
}


extension BilibiliLoginViewController: WKNavigationDelegate {
    
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        guard let str = webView.url?.absoluteString,
              str.contains("bili_jct") else { return }
        displayWait()
        webviewObserver = webView.observe(\.isLoading) { (webView, _) in
            if !webView.isLoading {
                Log("Finish loading")
                firstly {
                    after(seconds: 3)
                }.then {
                    Bilibili().isLogin()
                }.done(on: .main) {
                    Log("islogin \($0.0), \($0.1)")
                    
                    if $0.0 {
                        self.dismiss?()
                    } else {
                        self.tabView.selectTabViewItem(at: 1)
                    }
                }.catch(on: .main) { _ in
                    self.tabView.selectTabViewItem(at: 1)
                }
            }
        }
    }
    
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nserr = error as NSError
        if nserr.code == -1022 {
            Log("NSURLErrorAppTransportSecurityRequiresSecureConnection")
        } else if let err = error as? URLError {
            switch(err.code) {
            case .cancelled:
                break
            case .cannotFindHost, .notConnectedToInternet, .resourceUnavailable, .timedOut:
                tabView.selectTabViewItem(at: 1)
            default:
                tabView.selectTabViewItem(at: 1)
                Log("Error code: " + String(describing: err.code) + "  does not fall under known failures")
            }
        }
    }
    
}
