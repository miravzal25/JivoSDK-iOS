//
//  UIApplicationExtensions.swift
//  JivoMobile
//
//  Created by Stan Potemkin on 27/09/2017.
//  Copyright © 2017 JivoSite. All rights reserved.
//

import Foundation
import UIKit

extension UIApplication {
    var jv_isActive: Bool {
        switch applicationState {
        case .active: return true
        case .inactive: return false
        case .background: return false
        @unknown default: return false
        }
    }
    
    func jv_discardCachedLaunchScreen() {
        let path = NSHomeDirectory() + "/Library/SplashBoard"
        try? FileManager.default.removeItem(atPath: path)
    }
}

extension UIApplication.State {
    var jv_description: String {
        switch self {
        case .active: return "active"
        case .background: return "background"
        case .inactive: return "inactive"
        @unknown default: return String(describing: self)
        }
    }
}
