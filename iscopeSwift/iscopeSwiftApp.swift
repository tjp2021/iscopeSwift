//
//  iscopeSwiftApp.swift
//  iscopeSwift
//
//  Created by Timothy Joo on 2/6/25.
//

import SwiftUI
import FirebaseCore

@main
struct iscopeSwiftApp: App {

    init() {
        FirebaseConfig.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
