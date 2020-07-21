//
//  UserDefaults+Extensions.swift
//  Movielogue
//
//  Created by Jack Wright on 6/16/20.
//  Copyright © 2020 Jack Wright. All rights reserved.
//

import Foundation

extension UserDefaults {

    var plexAuthPinId: Int? {
        
        set {
            set(newValue, forKey: PlexAPI.plexAuthPinIdKey)
        }
        
        get {
            return self.object(forKey: PlexAPI.plexAuthPinIdKey) as? Int
        }
    }
    
    var plexAuthPinCode: String? {
        
        set {
            set(newValue, forKey: PlexAPI.plexAuthPinCodeKey)
        }
        
        get {
            return self.object(forKey: PlexAPI.plexAuthPinCodeKey) as? String
        }
    }

}
