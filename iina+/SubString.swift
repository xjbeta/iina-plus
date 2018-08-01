//
//  SubString.swift
//  Aria2D
//
//  Created by xjbeta on 2016/12/17.
//  Copyright © 2016年 xjbeta. All rights reserved.
//

import Foundation

extension String {
	func subString(from startString: String, to endString: String) -> String {
        var str = self
        if let startIndex = self.range(of: startString)?.upperBound {
            str.removeSubrange(str.startIndex ..< startIndex)
            if let endIndex = str.range(of: endString)?.lowerBound {
                str.removeSubrange(endIndex ..< str.endIndex)
				return str
			}
		}
		return ""
	}
	
	func subString(from startString: String) -> String {
        var str = self
        if let startIndex = self.range(of: startString)?.upperBound {
            str.removeSubrange(self.startIndex ..< startIndex)
            return str
		}
		return ""
	}
	
	
	func delete(between startString: String, and endString: String) -> String {
        var str = self
        if let start = self.range(of: startString), let end = self.range(of: endString) {
            str.removeSubrange(start.upperBound ..< end.lowerBound)
            return str
		}
		return ""
	}
    
//MARK: - String Path
    var pathComponents: [String] {
        get {
            return (self.standardizingPath as NSString).pathComponents
        }
    }
    
    var lastPathComponent: String {
        get {
            return (self as NSString).lastPathComponent
        }
    }
    
    var standardizingPath: String {
        get {
            return (self as NSString).standardizingPath
        }
    }
    
    mutating func deleteLastPathComponent() {
        self = (self.standardizingPath as NSString).deletingLastPathComponent
    }
    
    mutating func deletePathExtension() {
        self = (self.standardizingPath as NSString).deletingPathExtension
    }
    
    mutating func appendingPathComponent(_ str: String) {
        self = (self.standardizingPath as NSString).appendingPathComponent(str)
    }
    
    func isChildPath(of url: String) -> Bool {
        guard self.pathComponents.count > url.pathComponents.count else {
            return false
        }
        var t = self.pathComponents
        t.removeSubrange(url.pathComponents.count ..< self.pathComponents.count)
        return t == url.pathComponents
    }
    
    func isChildItem(of url: String) -> Bool {
        var pathComponents = self.pathComponents
        pathComponents.removeLast()
        return pathComponents == url.pathComponents
    }
}

