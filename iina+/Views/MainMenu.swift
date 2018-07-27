//
//  MainMenu.swift
//  iina+
//
//  Created by xjbeta on 2018/7/27.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class MainMenu: NSObject {
    @IBAction func reloadLiveStatus(_ sender: Any) {
        NotificationCenter.default.post(name: .reloadLiveStatus, object: nil)
    }
    
}
