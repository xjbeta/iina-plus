//
//  LiveStateTransformers.swift
//  IINA+
//
//  Created by xjbeta on 11/11/21.
//  Copyright © 2021 xjbeta. All rights reserved.
//

import Cocoa

@objc(LiveStateTransformer)
class LiveStateTransformer: ValueTransformer {
    override func transformedValue(_ value: Any?) -> Any? {
        guard let i = value as? Int,
                let state = LiveState(rawValue: i) else {
            return nil
        }
        
        return state.color
    }
}

@objc(LiveStateHideTransformer)
class LiveStateHideTransformer: ValueTransformer {
    override func transformedValue(_ value: Any?) -> Any? {
        guard let s = value as? String else {
            return nil
        }
        let site = SupportSites(url: s)
        return site == .bangumi || site == .bilibili
    }
}
