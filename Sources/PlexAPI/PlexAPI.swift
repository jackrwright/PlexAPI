//
//  PlexAPI.swift
//  Movielogue
//
//  Created by Jack Wright on 6/12/20.
//  Copyright © 2020 Jack Wright. All rights reserved.
//

import Foundation

public enum PlexError: Error {
    
    case notSignedIn
    case pinError(String)
    case tokenError(String)
    case sessionError(String)
    case badResponse(Int, String)
    case noData(String)
    
    /// Return an NSError for Objective-C
    func nsError() -> NSError {
        
        var errorCode: Int = -1
        let description: String
        var recovery: String = ""
        
        switch self {
        case .notSignedIn:
            description = "Not signed into a Plex server."
            recovery = "Please sign in via Settings->Plex"
        case .pinError(let msg):
            description = "Pin Error: \(msg)"
        case .tokenError(let msg):
            description = "Token Error: \(msg)"
        case .sessionError(let msg):
            description = "Session Error: \(msg)"
        case .badResponse(let code, let url):
            errorCode = code
            description = "Bad Response: \(HTTPURLResponse.localizedString(forStatusCode: code)) for '\(url)'"
        case .noData(let url):
            description = "No data returned from request: '\(url)'"
        }
        
        let userInfo = [
            NSLocalizedDescriptionKey: description,
            NSLocalizedRecoverySuggestionErrorKey: recovery
        ]
        
        return NSError(domain: Bundle.main.bundleIdentifier ?? "", code: errorCode, userInfo: userInfo)
    }
}

public enum PlexAPI {
    
    case validateToken(_ token: String)
    case getPin
    case checkForAuthToken(_ pin: PlexAuthPin)
    
    var request: URLRequest {
        
        let infoDictionary = Bundle.main.infoDictionary!
        let bundleID = Bundle.main.bundleIdentifier!
        let appName = infoDictionary["CFBundleName"] as! String
        
        var components = URLComponents()
        components.scheme = "https"
        components.host = "plex.tv"
        
        switch self {
            
        case .validateToken(let token):
            
            components.path = "/api/v2/user"
            
            var request = URLRequest(url: components.url!)
            
            request.httpMethod = "GET"
            request.setValue(bundleID, forHTTPHeaderField: "X-Plex-Client-Identifier")
            request.setValue(appName, forHTTPHeaderField: "X-Plex-Product")
            request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            return request
            
        case .getPin:
            
            components.path = "/api/v2/pins"
            
            var request = URLRequest(url: components.url!)
            
            request.httpMethod = "POST"
            request.setValue(bundleID, forHTTPHeaderField: "X-Plex-Client-Identifier")
            request.setValue(appName, forHTTPHeaderField: "X-Plex-Product")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            var components = URLComponents()
            components.queryItems = [
                URLQueryItem(name: "strong", value: "true"),
            ]
            if let bodyStr = components.percentEncodedQuery {
                request.httpBody = bodyStr.data(using: .utf8)
            }
            
            return request
            
        case .checkForAuthToken(let pin):
            
            components.path = "/api/v2/pins/\(pin.id)"
            
            var request = URLRequest(url: components.url!)
            
            request.httpMethod = "GET"
            request.setValue(bundleID, forHTTPHeaderField: "X-Plex-Client-Identifier")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(pin.code, forHTTPHeaderField: "code")
            
            return request
        }
        
    }
    
    // MARK: UserDefault keys
    static let plexAuthPinIdKey = "PlexAuthPinIdKey"
    static let plexAuthPinCodeKey = "PlexAuthPinCodeKey"
    
    // MARK: Keychain keys
    static let tokenKey = "PlexToken"
    
    // MARK: Notifications
    static public let signedIntoPlex = "signedIntoPlex"
    
    public struct PlexAuthPin {
        var id: Int
        var code: String
    }
    
    static func authAppUrl(pin: PlexAuthPin) -> URL? {
        
        var components = URLComponents()
        components.scheme = "https"
        components.host = "app.plex.tv"
        components.path = "/auth"
        
        let infoDictionary = Bundle.main.infoDictionary
        guard let bundleID = Bundle.main.bundleIdentifier,
            let appName = infoDictionary?["CFBundleName"] as? String
            else {
                return nil
        }
        
        let fragment = "?clientID=\(bundleID)&code=\(pin.code)&context[device][product]=\(appName)"
        
        components.fragment = fragment
        
        return components.url
    }
    
    
    /// This simply retrieves the token saved in the keychain and does not check for validity
    static public var savedToken: String? {
        
        return KeychainWrapper.standard.string(forKey: PlexAPI.tokenKey)
    }
    
    
    /// This determines if the user is signed in by checking for a saved token and does not check the token for validity.
    static public var isSignedIn: Bool {
        
        if let _ = KeychainWrapper.standard.string(forKey: PlexAPI.tokenKey)
        {
            return true
            
        } else {
            
            return false
        }
    }
    
    static public func signOut() {
        
        KeychainWrapper.standard.removeObject(forKey: PlexAPI.tokenKey)
    }
    
    
    /// Return a valid token
    /// - Parameter token: If not nil, a valid token
    /// - Parameter error: If not nil, the error that occurred
    static public func getToken(completion: @escaping (_ token: String?, _ error: PlexError?) -> Void) {
        
        if let token = KeychainWrapper.standard.string(forKey: Self.tokenKey) {
            
            // We already have a token
            NSLog("Already have a token: '\(token)'")
            
            // check that the token is valid...
            
            Self.validateToken(token) { (isValid, error) in
                
                if let error = error {
                    
                    completion(nil, error)
                }
                
                if isValid {
                    
                    // save the token in the keychain
                    KeychainWrapper.standard.set(token, forKey: Self.tokenKey)
                    
                    // deliver the valid token
                    completion(token, nil)
                    
                } else {
                    
                    // The token is not valid.
                    // Remove it from the keychain, and indicate we need a new one...
                    
                    KeychainWrapper.standard.removeObject(forKey: Self.tokenKey)
                    
                    completion(nil, nil)
                }
            }
            
        } else {
            
            // No stored token
            completion(nil, nil)
        }
        
    }
    
    static func validateToken(_ token: String, completion: @escaping (_ isValid: Bool, _ error: PlexError?) -> Void) {
        
        let request = PlexAPI.validateToken(token).request
        
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            
            if let error = error {
                
                // A server error, possibly a timeout.
                // We don't know if the token is valid, but we'll try to be positive.
                completion(true, PlexError.sessionError(error.localizedDescription))
                
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                (200...299).contains(httpResponse.statusCode) else {
                    
                    let statusCode = (response as! HTTPURLResponse).statusCode
                    
                    if statusCode == 401 {
                        
                        // invalid token
                        completion(false, nil)
                        
                    } else {
                        
                        // Some other bad response.
                        // We don't know if the token is valid, but we'll try to be positive.
                        completion(true, PlexError.badResponse(statusCode, request.url!.absoluteString))
                    }
                    
                    return
            }
            
            // the token is valid
            completion(true, nil)
            
        }.resume()
    }
    
    static func getPin(completion: @escaping (_ pin: PlexAuthPin?, _ error: PlexError?) -> Void) {
        
        // get a time-limited pin...
        
        let request = PlexAPI.getPin.request
        
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            
            if let error = error {
                
                completion(nil, PlexError.tokenError(error.localizedDescription))
                
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                (200...299).contains(httpResponse.statusCode) else {
                    let httpResponse = response as! HTTPURLResponse
                    let statusCode = httpResponse.statusCode
                    NSLog("---- bad http response: '\(statusCode)' for url '\(request.url!.absoluteString)'")
                    print(httpResponse.allHeaderFields)
                    
                    completion(nil, PlexError.badResponse(statusCode, "\(request.url!.absoluteString)"))
                    
                    return
            }
            
            if let data = data {
                
                do {
                    
                    if let jsonResult = try JSONSerialization.jsonObject(with: data, options: []) as? Dictionary<String, Any> {
                        
                        if let id = jsonResult["id"] as? Int,
                            let code = jsonResult["code"] as? String {
                            
                            #if DEBUG
                            print("Plex Pin received:\n\(jsonResult)")
                            #endif
                            
                            completion(PlexAuthPin(id: id, code: code), nil)
                            
                        } else {
                            
                            completion(nil, PlexError.pinError("Failed to get (id, code) in response"))
                        }
                    }
                    
                } catch {
                    
                    completion(nil, PlexError.tokenError("Failed to decode pin: '\(error.localizedDescription)'"))
                }
                
            } // if data
            
        }.resume()
        
    }
    
    
    /// Start the sign-in process by requesting a time-limited pin and returning a url for letting the user authenticate with plex.tv
    /// - Parameter url:a url for letting the user authenticate with plex.tv
    /// - Parameter error: If not nil the error that occurred .
    static public func requestToken(completion: @escaping (_ url: URL?, _ error: PlexError?) -> Void) {
        
        /*
         High-level Steps
         
         Generate a PIN, and store its id.
         Construct an Auth App url and send the user’s browser there to authenticate.
         After authentication, check the PIN’s id to obtain and store the user’s Access Token.
         */
        
        Self.getPin { (pin: PlexAuthPin?, error) in
            
            // Construct the Auth App URL
            
            guard let pin = pin else {
                completion(nil, PlexError.pinError("No pin returned from the pin request"))
                return
            }
            
            guard let url = Self.authAppUrl(pin: pin) else {
                completion(nil, PlexError.pinError("Failed to contruct an auth app URL for signing in"))
                return
            }
            
            // save the pin ID for use by PlexController.checkForAuthToken()
            UserDefaults.standard.plexAuthPinId = pin.id
            UserDefaults.standard.plexAuthPinCode = pin.code
            
            #if DEBUG
            print("Auth App URL: '\(url.absoluteString)'")
            #endif
            
            completion(url, nil)
        }
    }
    
    static public func checkForAuthToken() {
        
        // Get the pin ID and pin code from user defaults.
        // If there's no pin info saved, do nothing
        guard let pinId = UserDefaults.standard.plexAuthPinId,
            let pinCode = UserDefaults.standard.plexAuthPinCode else
        {
            return
        }
        
        let request = PlexAPI.checkForAuthToken(PlexAuthPin(id: pinId, code: pinCode)).request
        
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            
            if let error = error {
                NSLog("Error returned from auth code request: \(error.localizedDescription)")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                (200...299).contains(httpResponse.statusCode) else {
                    let httpResponse = response as! HTTPURLResponse
                    let statusCode = httpResponse.statusCode
                    NSLog("---- bad http response: '\(statusCode)' for url '\(request.url!.absoluteString)'")
                    print(httpResponse.allHeaderFields)
                    
                    return
            }
            
            if let data = data {
                
                do {
                    
                    if let jsonResult = try JSONSerialization.jsonObject(with: data, options: []) as? Dictionary<String, Any> {
                        
                        print(jsonResult)
                        
                        if let token = jsonResult["authToken"] as? String {
                            
                            // Save the token in the keychain
                            KeychainWrapper.standard.set(token, forKey: PlexAPI.tokenKey)
                            
                            // Send a notification to whoever is listening
                            Foundation.NotificationCenter.default.post(
                                name: Notification.Name(rawValue: PlexAPI.signedIntoPlex),
                                object: self,
                                userInfo: nil
                            )
                        }
                    }
                    
                } catch {
                    
                    NSLog("Failed to decode token from: '\(error.localizedDescription)'")
                }
            }
            
        }.resume()
    }
    
}
