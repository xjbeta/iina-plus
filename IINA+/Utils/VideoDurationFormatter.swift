//
//  VideoDurationFormatter.swift
//  iina+
//
//  Created by xjbeta on 2018/8/8.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class VideoDurationFormatter: Formatter {
    override func string(for obj: Any?) -> String? {
        let defaultStr = "00:00"
        if let duration = obj as? Int {
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .positional
            if duration >= 3600 {
                formatter.allowedUnits = [.hour, .minute, .second]
            } else {
                formatter.allowedUnits = [.minute, .second]
            }
            formatter.zeroFormattingBehavior = [.pad]
            return formatter.string(from: TimeInterval(duration)) ?? defaultStr
        }
        return defaultStr
    }
    
    
}
