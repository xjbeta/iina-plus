import SwiftUI
import AppKit

extension Color {
    /// Convert SwiftUI Color to NSColor if possible
    var nsColor: NSColor {
        NSColor(cgColor: cgColor ?? .black) ?? .black
    }
}

extension NSColor {
    /// Convert NSColor to SwiftUI Color
    var color: Color {
        Color(self)
    }
}
