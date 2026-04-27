import SwiftUI

#if canImport(SheshBeshApp)
import SheshBeshApp
#endif

@main
struct SheshBeshMain: App {
    var body: some Scene {
        WindowGroup {
            AppLaunchConfiguration.rootView()
        }
    }
}
