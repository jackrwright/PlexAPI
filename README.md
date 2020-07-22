# PlexAPI

This package provides code to sign in to a Plex.tv account.

For secure token storage, it uses the [KeychainWrapper](https://github.com/jrendel/SwiftKeychainWrapper) class, written by Jason Rendel. For simplicity, its source is manually included in this package.

### Example Usage

This follows the authetication procedure for an app as recommended by this Plex [article](https://forums.plex.tv/t/authenticating-with-plex/609370).

Start the sign-in process:

```swift
var isSigningIn = false

@IBAction func signInTapped(_ sender: UIButton) {
	...
	// The following call requests a time-sensistive pin that's used to construct a Plex auth app URL.
	// The pin is saved for use later to verify sign-in.
	PlexAPI.requestToken { (url, error) in
	    
	    if let error = error {
	    
	       // handle the error...
	          
	    } else {
	        
	        if let url = url {
	            
	            // open the url returned in a browser.
	            // The browser is presented on top of your app where the user
	            // has the opportunity to sign into their Plex.tv account.
	            
	            DispatchQueue.main.async {
	                
	                self.safariVC = SFSafariViewController(url: url)
	                
	                self.present(self.safariVC!, animated: true, completion: nil)
	            }
	        }
	    }
	}
}	

```
When the browser is dismissed by the user, your app needs to poll to verify the pin has been claimed. Since the browser was presented modally on top of your app, this can be done in viewDidAppear:

```swift
override func viewDidAppear(_ animated: Bool) {
    
    super.viewDidAppear(animated)
    
    if isSigningIn {
        
        self.pollForAuthToken()
    }
}
    
/// Poll periodically for a valid auth token to show up
private func pollForAuthToken() {
    
    timer =  Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { (timer) in
        
        PlexAPI.checkForAuthToken()
    }
}

```
When PlexAPI.checkForAuthToken() gets a valid auth token, it posts a ntotification that your app should listen for. This can be set up in viewDidLoad:

```swift
override func viewDidLoad() {
	    
	super.viewDidLoad()
	...
	// Register for a notification of when we received an auth token
	Foundation.NotificationCenter.default.addObserver(self,
	                                                  selector: #selector(didSignIn(_:)),
	                                                  name: NSNotification.Name(rawValue: PlexAPI.signedIntoPlex),
	                                                  object: nil)
	...
}   
                                                  
/// This method is called in response to the PlexAPI.signedIntoPlex notification
@objc private func didSignIn(_ notification: Notification) {
    
    DispatchQueue.main.async {
        
        self.isSignedIn = true
        
        self.safariVC?.dismiss(animated: true, completion: nil)
        
        // The token has been saved securely in the user's keychain,
        // and can be retrieved with this call:
        print(PlexAPI.savedToken ?? "no token saved")
    }
}
  

```
An example iPhone project can be found [here](https://github.com/jackrwright/PlexSignInExample) that demonstrates the usage.
