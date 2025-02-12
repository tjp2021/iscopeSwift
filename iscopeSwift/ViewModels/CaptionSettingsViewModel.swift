import Foundation

class CaptionSettingsViewModel: ObservableObject {
    @Published var fontSize: Double {
        didSet {
            UserDefaults.standard.set(fontSize, forKey: "caption_font_size")
        }
    }
    
    init() {
        // Load saved font size or use default
        self.fontSize = UserDefaults.standard.double(forKey: "caption_font_size")
        if self.fontSize == 0 {
            self.fontSize = 20 // Default size
        }
    }
} 