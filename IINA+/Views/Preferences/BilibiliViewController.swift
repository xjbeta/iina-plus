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
        bilibili.logout().done { _ in
            self.initStatus()
            }.catch { error in
                Log("Logout bilibili error: \(error)")
                self.selectTabViewItem(.error)
        }
    }
    
    @IBAction func tryAgain(_ sender: Any) {
        initStatus()
    }
    
    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    
    enum BiliBiliTabs: Int {
        case info, login, error, progress
    }
    let bilibili = Bilibili()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        initStatus()
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if let vc = segue.destinationController as? BilibiliLoginViewController {
            vc.dismiss = {
                self.dismiss(vc)
                self.initStatus()
            }
        }
    }
    
    func initStatus() {
        selectTabViewItem(.progress)
        bilibili.isLogin().done(on: .main) {
            if $0.0 {
                self.selectTabViewItem(.info)
            } else {
                self.selectTabViewItem(.login)
            }
            self.userNameTextField.stringValue = $0.1
            }.catch { error in
                Log("Init bilibili status error: \(error)")
                self.selectTabViewItem(.error)
        }
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
