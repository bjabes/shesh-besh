import Foundation

/// Single source of truth for the public app name.
///
/// The actual value comes from `CFBundleDisplayName`, which is in turn
/// driven by the `BRAND_NAME` user-defined build setting in
/// `SheshBesh.xcodeproj/project.pbxproj`. Change `BRAND_NAME` in the project
/// file and every reference (home-screen label, splash, Game Center
/// notifications, etc.) updates on the next build.
enum AppBrand {
    static let name: String = {
        let display = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        if let display, !display.isEmpty {
            return display
        }
        let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        return bundleName ?? "Gammonade"
    }()
}
