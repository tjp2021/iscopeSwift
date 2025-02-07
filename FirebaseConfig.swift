import SwiftUI
import FirebaseCore
import UIKit

class FirebaseConfig: NSObject, UIApplicationDelegate {
    static let shared = FirebaseConfig()
    
    static func configure() {
        FirebaseApp.configure()
    }
    
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
} 