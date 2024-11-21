//
//  BilibiliLoginViewController.swift
//  iina+
//
//  Created by xjbeta on 2018/8/6.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import WebKit

class BilibiliLoginViewController: NSViewController {

    @IBOutlet weak var tabView: NSTabView!
    @IBOutlet weak var viewForWeb: NSView!
    @IBOutlet weak var waitProgressIndicator: NSProgressIndicator!
    var webView: WKWebView!
	var dismissLogin: (((Bool, String)?) -> Void)?
    
    @IBAction func tryAgain(_ sender: Any) {
        loadWebView()
    }
	@IBAction func cancel(_ sender: NSButton) {
		dismissLogin?(nil)
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
            dismissLogin?(nil)
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
		
		webviewObserver?.invalidate()
		webviewObserver = nil
        
		//	https://passport.bilibili.com/ajax/miniLogin/minilogin
        let url = URL(string: "https://passport.bilibili.com/login")
        let script = """
document.getElementsByClassName("v-navbar__back")[0].remove();
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
		webView.autoresizingMask = [.height, .width, .minXMargin, .minYMargin, .maxXMargin, .maxYMargin]

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
    
	func checkLogin() async {
		do {
			let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
			cookies.forEach {
				HTTPCookieStorage.shared.setCookie($0)
			}
			
			let bilibili = await Processes.shared.videoDecoder.bilibili
			let isLogin = try await bilibili.isLogin()
			
			Log("islogin \(isLogin.0), \(isLogin.1)")
			
			if isLogin.0 {
				self.dismissLogin?(isLogin)
			} else {
				self.tabView.selectTabViewItem(at: 1)
			}
		} catch let error {
			Log(error)
			self.tabView.selectTabViewItem(at: 1)
		}
	}
	
}


extension BilibiliLoginViewController: WKNavigationDelegate {
    
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        guard let str = webView.url?.absoluteString,
              str.contains("bili_jct") else { return }
        displayWait()
		
		webviewObserver = webView.observe(\.isLoading) { (webView, _) in
			Task { @MainActor in
				guard !webView.isLoading else { return }
				Log("Finish loading")
				await self.checkLogin()
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
