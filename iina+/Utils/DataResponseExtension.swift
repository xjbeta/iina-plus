//
//  DataResponseExtension.swift
//  iina+
//
//  Created by xjbeta on 2019/6/24.
//  Copyright © 2019 xjbeta. All rights reserved.
//

import Cocoa
import Alamofire

extension DataResponse {
    var text: String? {
        get {
            guard let d = data else { return nil }
            return String(data: d, encoding: .utf8)
        }
    }
}
