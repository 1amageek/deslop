import Foundation

/// What the platform the tests run on can do.
enum Platform {
    /// SwiftUI and Observation, which only Apple platforms ship.
    static var hasSwiftUI: Bool {
        #if canImport(SwiftUI)
        true
        #else
        false
        #endif
    }

    /// Xcode's `xcodebuild` and `plutil`, which only macOS ships.
    static var hasXcode: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }
}
