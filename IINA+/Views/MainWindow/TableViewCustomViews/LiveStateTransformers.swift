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
        guard let i = value as? Int else {
            return nil
        }
        var name = ""
        switch i {
        case 0:
            name = "NSStatusUnavailable"
        case 1:
            name = "NSStatusAvailable"
        default:
            name = "NSStatusNone"
        }
        return NSImage(named: .init(name))
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
