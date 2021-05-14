//
//  Bookmark+CoreDataProperties.swift
//  iina+
//
//  Created by xjbeta on 2018/7/19.
//  Copyright © 2018 xjbeta. All rights reserved.
//
//

import Foundation
import CoreData


extension Bookmark {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Bookmark> {
        return NSFetchRequest<Bookmark>(entityName: "Bookmark")
    }
    
    @NSManaged public var order: Double
    @NSManaged public var remark: String?
    @NSManaged public var url: String
    
}
