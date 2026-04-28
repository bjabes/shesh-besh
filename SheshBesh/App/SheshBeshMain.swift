import SwiftUI

#if canImport(SheshBeshApp)
import SheshBeshApp
#endif

@main
struct SheshBeshMain: App {
    var body: some Scene {
        WindowGroup {
            RootContainer()
        }
    }
}

private struct RootContainer: View {
    @State private var showSplash: Bool
    private let root: RootView

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.root = AppLaunchConfiguration.rootView(arguments: arguments)
        let isUITesting = arguments.contains("-uiTesting") || arguments.contains("-uiTestingRootLedger")
        _showSplash = State(initialValue: !isUITesting)
    }

    var body: some View {
        ZStack {
            root
            if showSplash {
                SplashView(onFinished: {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        showSplash = false
                    }
                })
                .transition(.opacity)
            }
        }
    }
}
