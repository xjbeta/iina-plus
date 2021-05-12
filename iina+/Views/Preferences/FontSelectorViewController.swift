//
//  FontSelectorViewController.swift
//  iina+
//
//  Created by xjbeta on 5/5/21.
//  Copyright © 2021 xjbeta. All rights reserved.
//

import Cocoa

protocol FontSelectorDelegate {
    func fontDidUpdated()
}

class FontSelectorViewController: NSViewController {
    
    @IBOutlet var familyPopUpButton: NSPopUpButton!
    @IBOutlet var stylePopUpButton: NSPopUpButton!
    @IBOutlet var sizeTextField: NSTextField!
    @IBOutlet var sizeStepper: NSStepper!
    
    @IBAction func popUpButtonAction(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title else { return }
        let pref = Preferences.shared
        
        switch sender {
        case familyPopUpButton:
            pref.danmukuFontFamilyName = title
            guard let vc = self.presentingViewController as? GereralViewController else {
                return
            }
            styles = vc.fontWeights(ofFontFamily: title)
            let weight = pref.danmukuFontWeight
            if !styles.contains(weight),
               let w = styles.first {
                style = w
                pref.danmukuFontWeight = w
            }
        case stylePopUpButton:
            pref.danmukuFontWeight = title
        default:
            break
        }
        delegate?.fontDidUpdated()
    }
    
    
    @objc dynamic var families = [String]()
    @objc dynamic var family = ""
    @objc dynamic var styles = [String]()
    @objc dynamic var style = ""
    @objc dynamic var size = 1 {
        didSet {
            let pref = Preferences.shared
            pref.danmukuFontSize = size
            delegate?.fontDidUpdated()
        }
    }
    let minFontSize = 1
    let maxFontSize = 100
    
    var delegate: FontSelectorDelegate?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        sizeTextField.integerValue = size
        sizeStepper.integerValue = size
        sizeStepper.minValue = Double(minFontSize)
        sizeStepper.maxValue = Double(maxFontSize)
        
        sizeTextField.delegate = self
    }
    
}

extension FontSelectorViewController: NSTextFieldDelegate, NSControlTextEditingDelegate {
    
    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        
        
        print(#function, sizeTextField.stringValue)
        return true
    }
    
    func controlTextDidChange(_ obj: Notification) {
        guard let sizeTF = obj.object as? NSTextField,
              sizeTF == sizeTextField else { return }
        let newSize = sizeTF.integerValue
        size = newSize
    }
    
}
