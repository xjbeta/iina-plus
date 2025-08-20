//
//  WindowManger.swift
//  IINA+
//
//  Created by xjbeta on 2025/8/20.
//  Copyright © 2025 xjbeta. All rights reserved.
//

import Cocoa
import Settings

@MainActor
final class WindowManger: NSObject, Sendable {
    static let shared = WindowManger()
    
    enum SettingsItem: String {
        case general = "General"
        case sites = "Sites"
        case advanced = "Advanced"
        case about = "About"
        
        var identifier: Settings.PaneIdentifier {
            .init(rawValue)
        }
        
        var title: String {
            rawValue
        }
        
        var icon: NSImage {
            switch self {
            case .general:
                NSImage(named: NSImage.preferencesGeneralName)!
            case .sites:
                NSImage(named: NSImage.userAccountsName)!
            case .advanced:
                NSImage(named: NSImage.advancedName)!
            case .about:
                NSImage(named: NSImage.infoName)!
            }
        }
    }
    
    @MainActor
    private lazy var settingsWindowController = {
        let settings = SettingsWindowController(panes: [
            Settings.Pane(identifier: SettingsItem.general.identifier,
                          title: SettingsItem.general.title,
                          toolbarIcon: SettingsItem.general.icon) {
                GeneralPrefsView()
            },
            Settings.Pane(identifier: SettingsItem.sites.identifier,
                          title: SettingsItem.sites.title,
                          toolbarIcon: SettingsItem.sites.icon) {
                SitePrefsView()
            },
            Settings.Pane(identifier: SettingsItem.advanced.identifier,
                          title: SettingsItem.advanced.title,
                          toolbarIcon: SettingsItem.advanced.icon) {
                AdvancedPrefsView()
            },
            Settings.Pane(identifier: SettingsItem.about.identifier,
                          title: SettingsItem.about.title,
                          toolbarIcon: SettingsItem.about.icon) {
                AboutPrefsView()
            }
        ])
        
        settings.window?.titleVisibility = .hidden
        settings.window?.toolbarStyle = .unifiedCompact
        
        return settings
    }()
    
    @MainActor
    func showSettings(_ item: SettingsItem? = nil) {
        settingsWindowController.show(pane: item?.identifier)
    }
}
