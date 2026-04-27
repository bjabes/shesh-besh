import SwiftUI

public struct RootView: View {
    @State private var viewModel: MatchViewModel

    public init(viewModel: MatchViewModel = MatchViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        if viewModel.doubleOfferForLocalPlayer != nil {
            DoubleOfferSheet(viewModel: viewModel)
        } else if viewModel.isOpponentTurn {
            OpponentTurnView(viewModel: viewModel)
        } else {
            BoardView(viewModel: viewModel)
        }
    }
}
