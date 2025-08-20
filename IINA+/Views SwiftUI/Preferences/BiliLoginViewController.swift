//
//  StoryboardViewController.swift
//  IINA+
//
//  Created by xjbeta on 2025/8/9.
//  Copyright © 2025 xjbeta. All rights reserved.
//

import SwiftUI

struct BiliLoginViewController: NSViewControllerRepresentable {
    
    var dismiss: (((Bool, String)?) -> Void)
    
    let vc = NSStoryboard(name: "Preferences", bundle: nil).instantiateController(withIdentifier: "BilibiliLoginViewController") as! BilibiliLoginViewController
    
    func makeNSViewController(context: Context) -> NSViewController {
        vc.dismissLogin = dismiss
        return vc
    }
    
    func updateNSViewController(_ nsViewController: NSViewControllerType, context: Context) {
        
    }
    
}
