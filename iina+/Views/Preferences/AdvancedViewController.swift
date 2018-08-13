//
//  AdvancedViewController.swift
//  iina+
//
//  Created by xjbeta on 2018/8/13.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class AdvancedViewController: NSViewController {

    @IBOutlet weak var openLogDirectory: NSButton!
    @IBAction func openLogDirectory(_ sender: Any) {
        NSWorkspace.shared.open(Logger.logDirURL)
    }
    
    @objc dynamic var enableLogging = false {
        didSet {
            Preferences.shared.enableLogging = enableLogging
        }
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        enableLogging = Preferences.shared.enableLogging
    }
    
}
