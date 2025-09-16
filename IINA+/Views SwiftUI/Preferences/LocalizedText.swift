//
//  LocalizedText.swift
//  IINA+
//
//  Created by xjbeta on 2025/5/9.
//  Copyright © 2025 xjbeta. All rights reserved.
//


import SwiftUI

enum LocalizationTable: String {
    case preferences = "Preferences"
    case main = "Main"
}

struct LocalizedText: View {
    let key: String
    let tableName: LocalizationTable
    let bundle: Bundle
    let comment: String
    
    init(_ key: String, tableName: LocalizationTable, bundle: Bundle = .main, comment: String = "") {
        self.key = key
        self.tableName = tableName
        self.bundle = bundle
        self.comment = comment
    }
    
    var body: some View {
        Text(NSLocalizedString(key, tableName: tableName.rawValue, bundle: bundle, comment: comment))
    }
}

// Preview
struct LocalizedText_Previews: PreviewProvider {
    static var previews: some View {
        LocalizedText("nYK-y9-7tF.title", tableName: .preferences)
    }
}
