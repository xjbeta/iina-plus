//
//  BilibiliViewController.swift
//  iina+
//
//  Created by xjbeta on 2018/8/7.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class BilibiliViewController: NSViewController {

    @IBOutlet weak var tabView: NSTabView!
    @IBOutlet weak var userNameTextField: NSTextField!
    @IBAction func logout(_ sender: Any) {
		Task {
			do {
				let bilibili = await Processes.shared.videoDecoder.bilibili
				try await bilibili.logout()
				initStatus()
			} catch let error {
				Log("Logout bilibili error: \(error)")
				self.selectTabViewItem(.error)
			}
		}
    }
    
    @IBAction func tryAgain(_ sender: Any) {
        initStatus()
    }
    
    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    
    enum BiliCodec: Int {
        case av1, hevc, avc
    }
    
    enum BiliBiliTabs: Int {
        case info, login, error, progress
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        initStatus()
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if let vc = segue.destinationController as? BilibiliLoginViewController {
            vc.dismissLogin = { isLogin in
				vc.view.window?.close()
				guard let isLogin = isLogin else { return }
                self.updateStatus(isLogin)
            }
        }
    }
    
    func initStatus() {
        selectTabViewItem(.progress)
		Task {
			do {
				let bilibili = await Processes.shared.videoDecoder.bilibili
				let s = try await bilibili.isLogin()
				updateStatus(s)
			} catch let error {
				Log("Init bilibili status error: \(error)")
				self.selectTabViewItem(.error)
			}
		}
    }
    
	func updateStatus(_ isLogin: (Bool, String)) {
		if isLogin.0 {
			self.selectTabViewItem(.info)
		} else {
			self.selectTabViewItem(.login)
		}
		self.userNameTextField.stringValue = isLogin.1
	}
	
    func selectTabViewItem(_ tab: BiliBiliTabs) {
        DispatchQueue.main.async {
            if tab == .progress {
                self.progressIndicator.startAnimation(nil)
            }
            self.tabView.selectTabViewItem(at: tab.rawValue)
        }
    }
    
}
