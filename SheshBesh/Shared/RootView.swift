import SwiftUI

public struct RootView: View {
    @State private var viewModel: MatchViewModel

    public init(viewModel: MatchViewModel = MatchViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        BoardView(viewModel: viewModel)
    }
}
