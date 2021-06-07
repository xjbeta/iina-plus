//
//  VideoViewsFormatter.swift
//  iina+
//
//  Created by xjbeta on 2018/8/8.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class VideoViewsFormatter: Formatter {
    override func string(for obj: Any?) -> String? {
        
        if let viewsCount = obj as? Int {
            var views = Float(viewsCount)
            var unit: Unit = .def
            var str = ""
            switch viewsCount {
            case _ where views >= Unit.b.rawValue:
                unit = .b
                views = views / Unit.b.rawValue
            case _ where views >= Unit.m.rawValue:
                unit = .m
                views = views / Unit.m.rawValue
            case _ where views >= Unit.k.rawValue:
                unit = .k
                views = views / Unit.k.rawValue
            default:
                str = "\(viewsCount)"
            }
            if views >= 10 {
                str = String(format: "%.0f", views)
            } else {
                str = String(format: "%.1f", views)
            }
            str += unit.string
            str += " views"
            return str

        }
        
        return ""
    }
    
    
    private enum Unit: Float {
        case def
        case k = 1000
        case m = 1000000
        case b = 1000000000
        
        var string: String {
            get {
                switch self {
                case .k: return "K"
                case .m: return "M"
                case .b: return "B"
                case .def: return ""
                }
            }
        }
    }
    
}
