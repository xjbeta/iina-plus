//
//  PersistenceController.swift
//  IINA+
//
//  Created by xjbeta on 1/19/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Foundation
import CoreData

struct PersistenceController {
    // A singleton for our entire app to use
    static let shared = PersistenceController()

    // Storage for Core Data
    let container: NSPersistentContainer
    
    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        Bookmarks().prepareData(for: viewContext)
        return result
    }()
    
    struct Bookmarks {
        func prepareData(for viewContext: NSManagedObjectContext) {
            // ** Prepare all sample data for previews here ** //

            (0...10).forEach {
                let bookmark = Bookmark(context: viewContext)
                bookmark.liveName = "liveName"
                bookmark.liveTitle = "title \($0)"
//                bookmark
            }
            
            do {
                try viewContext.save()
            } catch {
                // handle error for production
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "DataModel")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Unresolved error \(error)")
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        
        // Update Model Version
        guard let storeUrl = container.persistentStoreDescriptions.first?.url else {
            return
        }
        
        print(storeUrl.path)
        
        do {
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: storeUrl)
            
            guard container.managedObjectModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata),
                  let versionHashModifier = container.managedObjectModel.entitiesByName["Bookmark"]?.versionHashModifier else {
                      return
                  }
            
            let bookmarks = try container.viewContext.fetch(NSFetchRequest<NSFetchRequestResult>(entityName: "Bookmark"))
            
            switch versionHashModifier {
            case "added order":
                bookmarks.enumerated().forEach {
                    if let bookmark = $0.element as? Bookmark {
                        bookmark.setValue($0.offset, forKey: "order")
                    }
                }
                try container.viewContext.save()
            case "swiftui":
                bookmarks.forEach {
                    if let bookmark = $0 as? Bookmark {
                        bookmark.setValue(UUID().uuidString, forKey: "uuid")
                        bookmark.setValue(nil, forKey: "cover")
                    }
                }
                try container.viewContext.save()
                
            default:
                break
            }
        } catch let error {
            print(error)
        }
    }
    
    func saveContext() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nserror = error as NSError
                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
            }
        }
    }
    
}
