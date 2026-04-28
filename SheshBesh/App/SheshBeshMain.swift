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
    private static let splashFadeDuration: Double = 0.35
    private static let splashRemovalBuffer: Double = 0.05

    @State private var splashOpacity: Double
    @State private var splashRemoved: Bool
    private let root: RootView

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.root = AppLaunchConfiguration.rootView(arguments: arguments)
        let isUITesting = arguments.contains("-uiTesting") || arguments.contains("-uiTestingRootLedger")
        _splashOpacity = State(initialValue: isUITesting ? 0 : 1)
        _splashRemoved = State(initialValue: isUITesting)
    }

    var body: some View {
        ZStack {
            root
            if !splashRemoved {
                SplashView(onFinished: {
                    withAnimation(.easeInOut(duration: Self.splashFadeDuration)) {
                        splashOpacity = 0
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(Self.splashFadeDuration + Self.splashRemovalBuffer))
                        splashRemoved = true
                    }
                })
                .opacity(splashOpacity)
                .allowsHitTesting(splashOpacity > 0)
            }
        }
    }
}
