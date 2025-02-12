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
    @Published var verticalPosition: Double = 0.8 {  // Default 80% from top (near bottom)
        didSet {
            savePosition()
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
        
        // Load saved position
        if let savedPosition = UserDefaults.standard.object(forKey: "caption_vertical_position") as? Double {
            self.verticalPosition = savedPosition
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
    
    private func savePosition() {
        UserDefaults.standard.set(verticalPosition, forKey: "caption_vertical_position")
    }
} 