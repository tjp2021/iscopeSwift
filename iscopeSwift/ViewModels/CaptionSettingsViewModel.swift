import Foundation
import SwiftUI

class CaptionSettingsViewModel: ObservableObject {
    @Published var fontSize: Double = 20 {  // Default size
        didSet {
            saveFontSize()
        }
    }
    @Published var captionColor: Color = .white {  // Default color
        didSet {
            saveColor()
        }
    }
    
    init() {
        // Load saved font size
        if let savedSize = UserDefaults.standard.object(forKey: "caption_font_size") as? Double {
            self.fontSize = savedSize
        }
        
        // Load saved color
        if let components = UserDefaults.standard.array(forKey: "caption_color") as? [CGFloat],
           components.count >= 3 {
            self.captionColor = Color(red: components[0], green: components[1], blue: components[2])
        }
    }
    
    private func saveFontSize() {
        UserDefaults.standard.set(fontSize, forKey: "caption_font_size")
    }
    
    private func saveColor() {
        if let components = UIColor(captionColor).cgColor.components {
            UserDefaults.standard.set(components, forKey: "caption_color")
        }
    }
} 