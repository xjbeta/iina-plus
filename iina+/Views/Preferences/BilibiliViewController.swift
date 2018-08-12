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
        bilibili.logout({
            self.initStatus()
        }) { re in
            do {
                let _ = try re()
            } catch let error {
                print(error)
                self.selectTabViewItem(.error)
            }
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
        bilibili.isLogin({
            if $0 {
                self.selectTabViewItem(.info)
            } else {
                self.selectTabViewItem(.login)
            }
        }, { name in
            DispatchQueue.main.async {
                self.userNameTextField.stringValue = name
            }
        }) { re in
            do {
                let _ = try re()
            } catch let error {
                print(error)
                self.selectTabViewItem(.error)
            }
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
