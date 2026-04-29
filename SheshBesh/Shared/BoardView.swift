import SheshBeshGame
import SwiftUI

public struct BoardView: View {
    public let viewModel: MatchViewModel
    private let onBackToRivals: (() -> Void)?
    private let onSendReminder: (@MainActor () async -> Void)?

    @State private var didSendReminder = false
    @State private var selectedSource: MoveSource?
    @Namespace private var checkerNamespace

    public init(
        viewModel: MatchViewModel,
        onBackToRivals: (() -> Void)? = nil,
        onSendReminder: (@MainActor () async -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onBackToRivals = onBackToRivals
        self.onSendReminder = onSendReminder
    }

    public var body: some View {
        ZStack {
            LinenBackground()
                .ignoresSafeArea()

            VStack(spacing: 12) {
                HeaderCard(viewModel: viewModel, onBackToRivals: onBackToRivals)
                PipStrip(viewModel: viewModel)

                BoardSurface(
                    viewModel: viewModel,
                    checkerNamespace: checkerNamespace,
                    isReadOnly: isReadOnly,
                    selectedSource: selectedSource,
                    onPointTap: handlePointTap,
                    onBarTap: handleBarTap
                )
                .aspectRatio(0.78, contentMode: .fit)
                .frame(maxHeight: 600)

                BearOffStrip(
                    viewModel: viewModel,
                    checkerNamespace: checkerNamespace,
                    selectedSource: selectedSource,
                    isReadOnly: isReadOnly,
                    onBearOffTap: handleBearOffTap
                )

                bottomSlot

                if showsActionBar, let lastError = viewModel.lastError {
                    Text(lastError)
                        .font(.footnote)
                        .foregroundStyle(LinenBrass.cream)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(LinenBrass.rust, in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityIdentifier("last-error")
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)
        }
        .onChange(of: viewModel.state.game.phase) { _, _ in
            selectedSource = nil
        }
        .onChange(of: viewModel.isOpponentTurn) { _, isOpponentTurn in
            if isOpponentTurn {
                didSendReminder = false
            }
        }
    }

    @ViewBuilder
    private var bottomSlot: some View {
        if viewModel.isOpponentTurn {
            opponentStatus
                .frame(maxWidth: .infinity, minHeight: 64)
        } else if showsActionBar {
            ActionBar(viewModel: viewModel) {
                selectedSource = nil
            }
        } else {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 64)
        }
    }

    private var opponentStatus: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(LinenBrass.brass)
                .frame(width: 9, height: 9)

            Text(statusText)
                .font(LinenBrass.uiFont(size: 15, weight: .semibold))
                .foregroundStyle(LinenBrass.cream.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Spacer(minLength: 0)

            if let onSendReminder {
                reminderButton(action: onSendReminder)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(LinenBrass.coffee.opacity(0.94), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(LinenBrass.brass.opacity(0.34), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("opponent-turn-status")
    }

    private func reminderButton(action: @escaping @MainActor () async -> Void) -> some View {
        Button {
            didSendReminder = true
            Task {
                await action()
            }
        } label: {
            Label(
                didSendReminder ? "Reminded" : "Remind",
                systemImage: didSendReminder ? "bell.fill" : "bell.badge"
            )
                .font(LinenBrass.uiFont(size: 13, weight: .semibold))
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .tint(LinenBrass.brass)
        .foregroundStyle(LinenBrass.cream)
        .disabled(didSendReminder)
        .accessibilityIdentifier("opponent-turn-remind")
    }

    private var statusText: String {
        if let offer = viewModel.currentCubeOffer, offer.offeredBy == viewModel.localPlayer {
            return "Waiting for \(viewModel.opponentName) to answer the double"
        }

        switch viewModel.state.game.phase {
        case .awaitingRoll:
            return "Waiting for \(viewModel.opponentName) to roll"
        case .awaitingMove:
            return "Waiting for \(viewModel.opponentName) to move"
        case .awaitingResignationResponse:
            return "Waiting for \(viewModel.opponentName) to answer"
        default:
            return "Waiting for \(viewModel.opponentName)"
        }
    }

    private var isReadOnly: Bool {
        viewModel.isOpponentTurn || viewModel.doubleOfferForLocalPlayer != nil
    }

    private var showsActionBar: Bool {
        !viewModel.isOpponentTurn && viewModel.doubleOfferForLocalPlayer == nil
    }

    private func handlePointTap(_ pointID: PointID) {
        guard !isReadOnly else { return }

        let source: MoveSource = .point(pointID)
        let destination: MoveDestination = .point(pointID)

        if selectedSource == source {
            selectedSource = nil
            return
        }

        if viewModel.applyMove(from: selectedSource ?? source, to: destination) {
            selectedSource = nil
            return
        }

        if viewModel.isLegalSource(source) {
            selectedSource = source
        }
    }

    private func handleBarTap() {
        guard !isReadOnly else { return }

        let source: MoveSource = .bar
        if selectedSource == source {
            selectedSource = nil
        } else if viewModel.isLegalSource(source) {
            selectedSource = source
        }
    }

    private func handleBearOffTap() {
        guard !isReadOnly else { return }
        guard let selectedSource else { return }
        if viewModel.applyMove(from: selectedSource, to: .off) {
            self.selectedSource = nil
        }
    }
}

public struct DoubleOfferSheet: View {
    public let viewModel: MatchViewModel
    private let onBackToRivals: (() -> Void)?

    public init(
        viewModel: MatchViewModel,
        onBackToRivals: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onBackToRivals = onBackToRivals
    }

    public var body: some View {
        ZStack {
            BoardView(
                viewModel: viewModel,
                onBackToRivals: onBackToRivals
            )

            LinenBrass.ink.opacity(0.42)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if let offer = viewModel.doubleOfferForLocalPlayer {
                offerCard(offer)
                    .padding(.horizontal, 24)
            }
        }
    }

    private func offerCard(_ offer: CubeOffer) -> some View {
        VStack(spacing: 18) {
            CubeView(cube: CubeState(value: offer.proposedValue, owner: viewModel.localPlayer.opponent), localPlayer: viewModel.localPlayer)
                .frame(width: 54, height: 54)

            VStack(spacing: 6) {
                Text("\(viewModel.opponentName) is offering a double to \(offer.proposedValue)")
                    .font(LinenBrass.displayFont(size: 24, weight: .bold))
                    .foregroundStyle(LinenBrass.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.78)
                    .accessibilityIdentifier("double-offer-title")

                Text("The board is frozen until you take or drop.")
                    .font(LinenBrass.uiFont(size: 14, weight: .medium))
                    .foregroundStyle(LinenBrass.mutedInk)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            VStack(spacing: 8) {
                consequenceRow(
                    title: "Take",
                    detail: "Play on with the cube at \(offer.proposedValue)."
                )
                consequenceRow(
                    title: "Drop",
                    detail: "\(viewModel.opponentName) scores \(pointsText(offer.previousCubeValue))."
                )
            }

            HStack(spacing: 12) {
                Button {
                    viewModel.dropDoubleIfAllowed()
                } label: {
                    Text("Drop")
                        .font(LinenBrass.uiFont(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(LinenButtonStyle(kind: .secondary))
                .accessibilityIdentifier("action-drop-double")

                Button {
                    viewModel.takeDoubleIfAllowed()
                } label: {
                    Text("Take")
                        .font(LinenBrass.uiFont(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(LinenButtonStyle(kind: .primary))
                .accessibilityIdentifier("action-take-double")
            }
        }
        .padding(22)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(LinenBrass.cream)
                .shadow(color: .black.opacity(0.28), radius: 14, y: 7)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(LinenBrass.brass.opacity(0.72), lineWidth: 1)
        )
    }

    private func consequenceRow(title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(LinenBrass.uiFont(size: 14, weight: .bold))
                .foregroundStyle(LinenBrass.ink)
                .frame(width: 44, alignment: .leading)

            Text(detail)
                .font(LinenBrass.uiFont(size: 14, weight: .medium))
                .foregroundStyle(LinenBrass.mutedInk)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(LinenBrass.linen, in: RoundedRectangle(cornerRadius: 6))
    }

    private func pointsText(_ value: Int) -> String {
        value == 1 ? "1 point" : "\(value) points"
    }
}

private enum LinenBrass {
    static let linen = Color(red: 0.937, green: 0.902, blue: 0.831)
    static let linenDeep = Color(red: 0.871, green: 0.785, blue: 0.647)
    static let cream = Color(red: 0.929, green: 0.886, blue: 0.800)
    static let coffee = Color(red: 0.420, green: 0.290, blue: 0.180)
    static let saddle = Color(red: 0.243, green: 0.157, blue: 0.090)
    static let rust = Color(red: 0.659, green: 0.314, blue: 0.165)
    static let brass = Color(red: 0.722, green: 0.537, blue: 0.227)
    static let ink = Color(red: 0.126, green: 0.075, blue: 0.035)
    static let mutedInk = Color(red: 0.363, green: 0.265, blue: 0.174)

    static func displayFont(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func uiFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

private struct LinenBackground: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(LinenBrass.linen))

            for x in stride(from: 0.0, through: size.width, by: 9.0) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.white.opacity(0.11)), lineWidth: 0.6)
            }

            for y in stride(from: 0.0, through: size.height, by: 7.0) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(LinenBrass.coffee.opacity(0.06)), lineWidth: 0.55)
            }
        }
    }
}

private struct HeaderCard: View {
    let viewModel: MatchViewModel
    let onBackToRivals: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            if let onBackToRivals {
                Button(action: onBackToRivals) {
                    Image(systemName: "chevron.left")
                        .font(LinenBrass.uiFont(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(LinenBrass.coffee)
                .accessibilityLabel("Back to rivals")
                .accessibilityIdentifier("match-back-button")
            }

            Spacer(minLength: 10)

            MatchProgressColumn(viewModel: viewModel)
        }
        .foregroundStyle(LinenBrass.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MatchProgressColumn: View {
    let viewModel: MatchViewModel

    private static let dotDisplayMaxTarget = 7

    private var target: Int { viewModel.state.config.targetScore }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("\(viewModel.localScore)-\(viewModel.opponentScore)")
                .font(LinenBrass.displayFont(size: 18, weight: .bold))
                .foregroundStyle(LinenBrass.ink)
                .monospacedDigit()
                .accessibilityIdentifier("header-score")

            if target <= Self.dotDisplayMaxTarget {
                dotRow(
                    label: "You",
                    score: viewModel.localScore,
                    filled: LinenBrass.brass
                )
                dotRow(
                    label: viewModel.opponentName,
                    score: viewModel.opponentScore,
                    filled: LinenBrass.coffee
                )
            } else {
                Text("to \(target)")
                    .font(LinenBrass.uiFont(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(LinenBrass.mutedInk)
                    .textCase(.uppercase)
            }
        }
    }

    private func dotRow(label: String, score: Int, filled: Color) -> some View {
        HStack(spacing: 7) {
            Text(label.uppercased())
                .font(LinenBrass.uiFont(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(LinenBrass.mutedInk)
                .lineLimit(1)
            HStack(spacing: 4) {
                ForEach(0..<max(target, 1), id: \.self) { index in
                    Circle()
                        .fill(index < score ? filled : LinenBrass.linenDeep)
                        .frame(width: 7, height: 7)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(score) of \(target)")
    }
}

private struct PipStrip: View {
    let viewModel: MatchViewModel

    var body: some View {
        HStack {
            pipCount(for: viewModel.localPlayer)
            Spacer(minLength: 12)
            pipCount(for: viewModel.localPlayer.opponent)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(LinenBrass.coffee)
        )
    }

    private func pipCount(for player: Player) -> some View {
        Text("\(viewModel.displayName(for: player)) · \(viewModel.pipCount(for: player)) pips")
            .font(LinenBrass.uiFont(size: 15, weight: .medium))
            .foregroundStyle(LinenBrass.cream)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

private struct BoardSurface: View {
    let viewModel: MatchViewModel
    let checkerNamespace: Namespace.ID
    let isReadOnly: Bool
    let selectedSource: MoveSource?
    let onPointTap: (PointID) -> Void
    let onBarTap: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let trayHeight = max(68, geometry.size.height * 0.18)
            let halfHeight = (geometry.size.height - trayHeight) / 2
            let barWidth = max(38, geometry.size.width * 0.08)
            let interactiveMoves = isReadOnly ? [] : viewModel.interactiveLegalMoves
            let legalSources = Set(interactiveMoves.map(\.source))
            let legalDestinationDice = Self.legalDestinationDice(for: interactiveMoves, selectedSource: selectedSource)
            let pointLayout = BoardPointLayout(localPlayer: viewModel.localPlayer)

            VStack(spacing: 0) {
                BoardHalf(
                    viewModel: viewModel,
                    checkerNamespace: checkerNamespace,
                    selectedSource: selectedSource,
                    leftPoints: pointLayout.topLeft,
                    rightPoints: pointLayout.topRight,
                    barWidth: barWidth,
                    pointsDown: true,
                    legalSources: legalSources,
                    legalDestinationDice: legalDestinationDice,
                    onPointTap: onPointTap,
                    onBarTap: onBarTap
                )
                .frame(height: halfHeight)

                TrayRow(
                    viewModel: viewModel,
                    checkerNamespace: checkerNamespace,
                    selectedSource: selectedSource,
                    barWidth: barWidth,
                    onBarTap: onBarTap
                )
                .frame(height: trayHeight)

                BoardHalf(
                    viewModel: viewModel,
                    checkerNamespace: checkerNamespace,
                    selectedSource: selectedSource,
                    leftPoints: pointLayout.bottomLeft,
                    rightPoints: pointLayout.bottomRight,
                    barWidth: barWidth,
                    pointsDown: false,
                    legalSources: legalSources,
                    legalDestinationDice: legalDestinationDice,
                    onPointTap: onPointTap,
                    onBarTap: onBarTap
                )
                .frame(height: halfHeight)
            }
            .background(LinenBrass.linenDeep)
            .overlay(BoardFrame())
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .shadow(color: .black.opacity(0.24), radius: 6, y: 3)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("board")
            .allowsHitTesting(!isReadOnly)
        }
    }

    private static func legalDestinationDice(
        for moves: [Move],
        selectedSource: MoveSource?
    ) -> [MoveDestination: Int] {
        guard let selectedSource else { return [:] }

        var diceByDestination: [MoveDestination: Int] = [:]
        for move in moves where move.source == selectedSource {
            diceByDestination[move.destination] = move.die
        }
        return diceByDestination
    }
}

private struct BoardPointLayout {
    let topLeft: [PointID]
    let topRight: [PointID]
    let bottomLeft: [PointID]
    let bottomRight: [PointID]

    init(localPlayer: Player) {
        switch localPlayer {
        case .white:
            topLeft = Self.pointIDs(13...18)
            topRight = Self.pointIDs(19...24)
            bottomLeft = Self.pointIDs(stride(from: 12, through: 7, by: -1))
            bottomRight = Self.pointIDs(stride(from: 6, through: 1, by: -1))
        case .black:
            topLeft = Self.pointIDs(stride(from: 12, through: 7, by: -1))
            topRight = Self.pointIDs(stride(from: 6, through: 1, by: -1))
            bottomLeft = Self.pointIDs(13...18)
            bottomRight = Self.pointIDs(19...24)
        }
    }

    private static func pointIDs(_ range: ClosedRange<Int>) -> [PointID] {
        range.compactMap(PointID.init(rawValue:))
    }

    private static func pointIDs<S: Sequence>(_ values: S) -> [PointID] where S.Element == Int {
        values.compactMap(PointID.init(rawValue:))
    }
}

private struct BoardHalf: View {
    let viewModel: MatchViewModel
    let checkerNamespace: Namespace.ID
    let selectedSource: MoveSource?
    let leftPoints: [PointID]
    let rightPoints: [PointID]
    let barWidth: CGFloat
    let pointsDown: Bool
    let legalSources: Set<MoveSource>
    let legalDestinationDice: [MoveDestination: Int]
    let onPointTap: (PointID) -> Void
    let onBarTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            PointRun(
                viewModel: viewModel,
                checkerNamespace: checkerNamespace,
                selectedSource: selectedSource,
                pointIDs: leftPoints,
                pointsDown: pointsDown,
                startsWithDarkPoint: pointsDown,
                legalSources: legalSources,
                legalDestinationDice: legalDestinationDice,
                onPointTap: onPointTap
            )

            BarWell(
                viewModel: viewModel,
                checkerNamespace: checkerNamespace,
                selectedSource: selectedSource,
                segment: pointsDown ? .top : .bottom,
                isLegalSource: legalSources.contains(.bar),
                isLegalDestination: false,
                onBarTap: onBarTap
            )
            .frame(width: barWidth)

            PointRun(
                viewModel: viewModel,
                checkerNamespace: checkerNamespace,
                selectedSource: selectedSource,
                pointIDs: rightPoints,
                pointsDown: pointsDown,
                startsWithDarkPoint: !pointsDown,
                legalSources: legalSources,
                legalDestinationDice: legalDestinationDice,
                onPointTap: onPointTap
            )
        }
    }
}

private struct PointRun: View {
    let viewModel: MatchViewModel
    let checkerNamespace: Namespace.ID
    let selectedSource: MoveSource?
    let pointIDs: [PointID]
    let pointsDown: Bool
    let startsWithDarkPoint: Bool
    let legalSources: Set<MoveSource>
    let legalDestinationDice: [MoveDestination: Int]
    let onPointTap: (PointID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(pointIDs.enumerated()), id: \.element.rawValue) { index, pointID in
                PointCell(
                    pointID: pointID,
                    point: viewModel.state.game.board.point(pointID),
                    checkerIDs: viewModel.checkerLayout.slots[.point(pointID)] ?? [],
                    checkerNamespace: checkerNamespace,
                    pointsDown: pointsDown,
                    isDarkPoint: (index.isMultiple(of: 2)) == startsWithDarkPoint,
                    isSelected: selectedSource == .point(pointID),
                    isLegalSource: legalSources.contains(.point(pointID)),
                    legalDestinationDie: legalDestinationDice[.point(pointID)],
                    localPlayer: viewModel.localPlayer
                ) {
                    onPointTap(pointID)
                }
            }
        }
    }
}

private struct PointCell: View {
    let pointID: PointID
    let point: PointState
    let checkerIDs: [CheckerID]
    let checkerNamespace: Namespace.ID
    let pointsDown: Bool
    let isDarkPoint: Bool
    let isSelected: Bool
    let isLegalSource: Bool
    let legalDestinationDie: Int?
    let localPlayer: Player
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: pointsDown ? .top : .bottom) {
                PointTriangle(pointsDown: pointsDown)
                    .fill(isDarkPoint ? LinenBrass.rust.opacity(0.68) : LinenBrass.cream.opacity(0.72))
                    .padding(.horizontal, 1)

                CheckerStack(
                    checkerIDs: checkerIDs,
                    pointsDown: pointsDown,
                    isSelected: isSelected,
                    localPlayer: localPlayer,
                    checkerNamespace: checkerNamespace
                )
                    .padding(.vertical, 5)
                    .padding(.horizontal, 1)

                VStack {
                    if pointsDown { Spacer(minLength: 0) }
                    Text("\(displayPointNumber)")
                        .font(LinenBrass.uiFont(size: 9, weight: .medium))
                        .foregroundStyle(LinenBrass.coffee.opacity(0.64))
                        .lineLimit(1)
                    if !pointsDown { Spacer(minLength: 0) }
                }
                .padding(.vertical, 3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay(pointTipMarker)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier("point-\(pointID.rawValue)")
    }

    @ViewBuilder
    private var pointTipMarker: some View {
        if let legalDestinationDie {
            PointTipOverlay(pointsDown: pointsDown) {
                DiePipChip(value: legalDestinationDie)
            }
        } else if isLegalSource, !isSelected {
            PointTipOverlay(pointsDown: pointsDown) {
                SourceDot()
            }
        }
    }

    private var accessibilityLabel: String {
        guard let owner = point.owner else {
            return "Point \(displayPointNumber), empty\(stateSuffix)"
        }
        let player = owner == localPlayer ? "your" : "opponent"
        let checkerWord = point.count == 1 ? "checker" : "checkers"
        return "Point \(displayPointNumber), \(point.count) \(player) \(checkerWord)\(stateSuffix)"
    }

    private var displayPointNumber: Int {
        pointID.perspectiveValue(for: localPlayer)
    }

    private var stateSuffix: String {
        if isSelected { return ", selected" }
        if let legalDestinationDie { return ", legal destination using die \(legalDestinationDie)" }
        if isLegalSource { return ", legal source" }
        return ""
    }

    private var accessibilityHint: String {
        if isSelected { return "Tap to deselect this point." }
        if let legalDestinationDie { return "Tap to move the selected checker here using die \(legalDestinationDie)." }
        if isLegalSource { return "Tap to select this point as a move source." }
        return "Tap to inspect this point."
    }
}

private struct PointTipOverlay<Content: View>: View {
    let pointsDown: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            content()
                .position(
                    x: geometry.size.width / 2,
                    y: pointsDown ? geometry.size.height * 0.9 : geometry.size.height * 0.1
                )
        }
        .allowsHitTesting(false)
    }
}

private struct DiePipChip: View {
    let value: Int

    var body: some View {
        GeometryReader { geometry in
            let pipSize = max(2.2, geometry.size.width * 0.13)
            let positions = DicePipLayout.positions(for: value)

            ZStack {
                Circle()
                    .fill(LinenBrass.rust)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)

                Circle()
                    .stroke(LinenBrass.cream.opacity(0.88), lineWidth: 1.2)

                ForEach(Array(positions.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(LinenBrass.cream)
                        .frame(width: pipSize, height: pipSize)
                        .position(x: geometry.size.width * point.x, y: geometry.size.height * point.y)
                }
            }
        }
        .frame(width: 21, height: 21)
    }
}

private struct SourceDot: View {
    var body: some View {
        Circle()
            .fill(LinenBrass.rust)
            .frame(width: 7, height: 7)
            .overlay {
                Circle()
                    .stroke(LinenBrass.cream.opacity(0.82), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.16), radius: 1, y: 0.5)
    }
}

private struct PointTriangle: Shape {
    let pointsDown: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointsDown {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY * 0.92))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.08))
        }
        path.closeSubpath()
        return path
    }
}

private struct CheckerStack: View {
    let checkerIDs: [CheckerID]
    let pointsDown: Bool
    let isSelected: Bool
    let localPlayer: Player
    let checkerNamespace: Namespace.ID

    var body: some View {
        GeometryReader { geometry in
            let visibleIDs = Array(checkerIDs.suffix(5))
            let renderedIDs = pointsDown ? visibleIDs : Array(visibleIDs.reversed())
            let diameter = max(6, min(geometry.size.width * 0.88, geometry.size.height / 5.4))
            let spacing = max(-diameter * 0.12, -3)

            VStack(spacing: spacing) {
                if !pointsDown, checkerIDs.count > visibleIDs.count {
                    checkerCountBadge
                }

                ForEach(renderedIDs, id: \.self) { checkerID in
                    Checker(owner: checkerID.player, localPlayer: localPlayer)
                        .frame(width: diameter, height: diameter)
                        .overlay {
                            if isSelected, checkerID == checkerIDs.last {
                                SelectedCheckerRing()
                            }
                        }
                        .matchedGeometryEffect(id: checkerID, in: checkerNamespace)
                }

                if pointsDown, checkerIDs.count > visibleIDs.count {
                    checkerCountBadge
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: pointsDown ? .top : .bottom)
        }
    }

    private var checkerCountBadge: some View {
        Text("\(checkerIDs.count)")
            .font(LinenBrass.uiFont(size: 10, weight: .bold))
            .foregroundStyle(LinenBrass.ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(LinenBrass.brass, in: Capsule())
    }
}

private struct SelectedCheckerRing: View {
    var body: some View {
        Circle()
            .stroke(LinenBrass.cream.opacity(0.95), lineWidth: 5)
            .overlay {
                Circle()
                    .stroke(LinenBrass.rust, lineWidth: 3)
            }
            .padding(-3)
            .allowsHitTesting(false)
    }
}

private struct Checker: View {
    let owner: Player?
    let localPlayer: Player

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)
                .shadow(color: .black.opacity(0.24), radius: 2, y: 1)

            Circle()
                .stroke(stroke, lineWidth: 2)

            if owner == localPlayer {
                Crosshatch()
                    .stroke(LinenBrass.cream.opacity(0.18), lineWidth: 1)
                    .clipShape(Circle())
                    .padding(4)
            }

            Circle()
                .stroke(.white.opacity(0.16), lineWidth: 1)
                .padding(4)
        }
    }

    private var fill: Color {
        guard let owner else { return .clear }
        return owner == localPlayer ? LinenBrass.rust : LinenBrass.cream
    }

    private var stroke: Color {
        guard let owner else { return .clear }
        return owner == localPlayer ? LinenBrass.coffee.opacity(0.8) : LinenBrass.rust.opacity(0.72)
    }
}

private struct Crosshatch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 7

        for offset in stride(from: -rect.height, through: rect.width, by: step) {
            path.move(to: CGPoint(x: offset, y: rect.maxY))
            path.addLine(to: CGPoint(x: offset + rect.height, y: rect.minY))
        }

        for offset in stride(from: 0, through: rect.width + rect.height, by: step) {
            path.move(to: CGPoint(x: offset, y: rect.minY))
            path.addLine(to: CGPoint(x: offset - rect.height, y: rect.maxY))
        }

        return path
    }
}

private enum BarSegment {
    case top
    case tray
    case bottom
}

private struct BarWell: View {
    let viewModel: MatchViewModel
    let checkerNamespace: Namespace.ID
    let selectedSource: MoveSource?
    let segment: BarSegment
    let isLegalSource: Bool
    let isLegalDestination: Bool
    let onBarTap: () -> Void

    var body: some View {
        Button(action: onBarTap) {
            ZStack {
                LinenBrass.saddle

                Rectangle()
                    .stroke(borderColor, lineWidth: borderWidth)
                    .padding(5)

                VStack(spacing: 3) {
                    if segment == .top {
                        barCheckers(for: viewModel.localPlayer.opponent)
                    }

                    Spacer(minLength: 3)

                    if segment == .bottom {
                        barCheckers(for: viewModel.localPlayer)
                    }
                }
                .padding(.vertical, 5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private func barCheckers(for player: Player) -> some View {
        let checkerIDs = viewModel.checkerLayout.slots[.bar(player)] ?? []
        if !checkerIDs.isEmpty {
            BarCheckerStack(
                checkerIDs: checkerIDs,
                localPlayer: viewModel.localPlayer,
                checkerNamespace: checkerNamespace
            )
            .frame(height: 74)
        }
    }

    private var borderColor: Color {
        if selectedSource == .bar { return LinenBrass.brass.opacity(0.9) }
        if isLegalDestination { return LinenBrass.brass.opacity(0.88) }
        if isLegalSource { return LinenBrass.brass.opacity(0.4) }
        return LinenBrass.brass.opacity(0.28)
    }

    private var borderWidth: CGFloat {
        selectedSource == .bar || isLegalDestination ? 2 : 1
    }

    private var accessibilityLabel: String {
        let yourCount = viewModel.state.game.board.barCount(for: viewModel.localPlayer)
        let opponentCount = viewModel.state.game.board.barCount(for: viewModel.localPlayer.opponent)
        var label = "Bar, your \(yourCount), opponent \(opponentCount)"
        if selectedSource == .bar {
            label += ", selected"
        } else if isLegalDestination {
            label += ", legal destination"
        } else if isLegalSource {
            label += ", legal source"
        }
        return label
    }

    private var accessibilityIdentifier: String {
        switch segment {
        case .top:
            return "bar-top"
        case .tray:
            return "bar-tray"
        case .bottom:
            return "bar-bottom"
        }
    }
}

private struct BarCheckerStack: View {
    let checkerIDs: [CheckerID]
    let localPlayer: Player
    let checkerNamespace: Namespace.ID

    var body: some View {
        GeometryReader { geometry in
            let visibleIDs = Array(checkerIDs.suffix(3))
            let diameter = max(14, min(geometry.size.width * 0.72, geometry.size.height / 3.2, 28))
            let spacing = -diameter * 0.24

            VStack(spacing: spacing) {
                ForEach(visibleIDs, id: \.self) { checkerID in
                    Checker(owner: checkerID.player, localPlayer: localPlayer)
                        .frame(width: diameter, height: diameter)
                        .matchedGeometryEffect(id: checkerID, in: checkerNamespace)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .overlay(alignment: .topTrailing) {
                if checkerIDs.count > visibleIDs.count {
                    Text("\(checkerIDs.count)")
                        .font(LinenBrass.uiFont(size: 9, weight: .bold))
                        .foregroundStyle(LinenBrass.ink)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(LinenBrass.brass, in: Capsule())
                }
            }
        }
    }
}

private struct TrayRow: View {
    let viewModel: MatchViewModel
    let checkerNamespace: Namespace.ID
    let selectedSource: MoveSource?
    let barWidth: CGFloat
    let onBarTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            PreviousRollSlot(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LinenBrass.linenDeep)

            BarWell(
                viewModel: viewModel,
                checkerNamespace: checkerNamespace,
                selectedSource: selectedSource,
                segment: .tray,
                isLegalSource: viewModel.isLegalSource(.bar),
                isLegalDestination: false,
                onBarTap: onBarTap
            )
                .frame(width: barWidth)
                .overlay(alignment: cubeAlignment) {
                    CubeView(cube: viewModel.state.game.cube, localPlayer: viewModel.localPlayer)
                        .frame(width: 32, height: 32)
                        .padding(.vertical, 5)
                }

            HStack(spacing: 9) {
                if let dice = diceValues {
                    ForEach(Array(dice.enumerated()), id: \.offset) { index, value in
                        DieFace(value: value, accessibilityIdentifier: "die-\(index + 1)")
                            .frame(width: 34, height: 34)
                    }
                }

                Text(viewModel.phaseTitle.uppercased())
                    .font(LinenBrass.uiFont(size: 12, weight: .bold))
                    .foregroundStyle(viewModel.isLocalTurn ? LinenBrass.brass : LinenBrass.cream.opacity(0.72))
                    .lineLimit(2)
                    .minimumScaleFactor(0.68)
                    .accessibilityIdentifier("tray-phase-title")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinenBrass.coffee)
        }
    }

    private var cubeAlignment: Alignment {
        if viewModel.state.game.cube.owner == viewModel.localPlayer {
            .bottom
        } else if viewModel.state.game.cube.owner == viewModel.localPlayer.opponent {
            .top
        } else {
            .center
        }
    }

    private var diceValues: [Int]? {
        switch viewModel.state.game.phase {
        case .awaitingOpeningRoll(let tiedRoll):
            tiedRoll.map { [$0.die1, $0.die2] }
        case .awaitingMove(let turn):
            [turn.roll.die1, turn.roll.die2]
        default:
            nil
        }
    }
}

private struct BearOffStrip: View {
    let viewModel: MatchViewModel
    let checkerNamespace: Namespace.ID
    let selectedSource: MoveSource?
    let isReadOnly: Bool
    let onBearOffTap: () -> Void

    var body: some View {
        let opponent = viewModel.localPlayer.opponent
        let opponentCheckerIDs = viewModel.checkerLayout.slots[.off(opponent)] ?? []
        let localCheckerIDs = viewModel.checkerLayout.slots[.off(viewModel.localPlayer)] ?? []

        HStack(spacing: 10) {
            BearOffZone(
                title: viewModel.displayName(for: opponent),
                checkerIDs: opponentCheckerIDs,
                owner: opponent,
                localPlayer: viewModel.localPlayer,
                checkerNamespace: checkerNamespace,
                isLegalDestination: false,
                accessibilityIdentifier: "bear-off-opponent",
                onTap: {}
            )
            .disabled(true)

            BearOffZone(
                title: viewModel.displayName(for: viewModel.localPlayer),
                checkerIDs: localCheckerIDs,
                owner: viewModel.localPlayer,
                localPlayer: viewModel.localPlayer,
                checkerNamespace: checkerNamespace,
                isLegalDestination: !isReadOnly && viewModel.isLegalDestination(.off, from: selectedSource),
                accessibilityIdentifier: "bear-off-local",
                onTap: onBearOffTap
            )
            .disabled(isReadOnly)
        }
        .padding(8)
        .background(LinenBrass.coffee, in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(LinenBrass.brass.opacity(0.34), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bear-off-strip")
    }
}

private struct BearOffZone: View {
    let title: String
    let checkerIDs: [CheckerID]
    let owner: Player
    let localPlayer: Player
    let checkerNamespace: Namespace.ID
    let isLegalDestination: Bool
    let accessibilityIdentifier: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                BearOffCheckerStack(
                    checkerIDs: checkerIDs,
                    owner: owner,
                    localPlayer: localPlayer,
                    checkerNamespace: checkerNamespace
                )
                .frame(width: 62, height: 32)

                Text("\(title) \(count)")
                    .font(LinenBrass.uiFont(size: 14, weight: .semibold))
                    .foregroundStyle(LinenBrass.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .accessibilityHidden(true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(isLegalDestination ? LinenBrass.brass.opacity(0.24) : LinenBrass.saddle.opacity(0.36))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(title), \(count) borne off")
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var count: Int {
        checkerIDs.count
    }
}

private struct BearOffCheckerStack: View {
    let checkerIDs: [CheckerID]
    let owner: Player
    let localPlayer: Player
    let checkerNamespace: Namespace.ID

    var body: some View {
        GeometryReader { geometry in
            let visibleIDs = Array(checkerIDs.suffix(3))
            let diameter = max(20, min(geometry.size.height * 0.86, 28))
            let spacing = -diameter * 0.38

            ZStack(alignment: .topTrailing) {
                if visibleIDs.isEmpty {
                    Checker(owner: owner, localPlayer: localPlayer)
                        .frame(width: diameter, height: diameter)
                        .opacity(0.32)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: spacing) {
                        ForEach(visibleIDs, id: \.self) { checkerID in
                            Checker(owner: checkerID.player, localPlayer: localPlayer)
                                .frame(width: diameter, height: diameter)
                                .matchedGeometryEffect(id: checkerID, in: checkerNamespace)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }

                if checkerIDs.count > visibleIDs.count {
                    Text("\(checkerIDs.count)")
                        .font(LinenBrass.uiFont(size: 9, weight: .bold))
                        .foregroundStyle(LinenBrass.ink)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(LinenBrass.brass, in: Capsule())
                }
            }
        }
    }
}

private struct CubeView: View {
    let cube: CubeState
    let localPlayer: Player

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinenBrass.brass)
                .shadow(color: .black.opacity(0.28), radius: 2, y: 1)

            RoundedRectangle(cornerRadius: 5)
                .stroke(LinenBrass.cream.opacity(0.46), lineWidth: 1)
                .padding(3)

            Text(label)
                .font(LinenBrass.displayFont(size: label.count > 1 ? 15 : 20, weight: .bold))
                .foregroundStyle(LinenBrass.ink)
                .monospacedDigit()
                .minimumScaleFactor(0.62)
        }
        .accessibilityLabel("Doubling cube \(label)")
        .accessibilityIdentifier("doubling-cube")
    }

    private var label: String {
        let displayValue = cube.owner == nil && cube.value == 1 ? cube.value * 2 : cube.value
        return "\(displayValue)"
    }
}

private struct PreviousRollSlot: View {
    let viewModel: MatchViewModel

    var body: some View {
        if let dice = viewModel.previousRollDice {
            HStack(spacing: 9) {
                ForEach(Array(dice.enumerated()), id: \.offset) { index, value in
                    DieFace(value: value, accessibilityIdentifier: "previous-die-\(index + 1)")
                        .frame(width: 28, height: 28)
                        .opacity(0.86)
                }

                if let notation = viewModel.previousMoveNotation {
                    Text(notation)
                        .font(LinenBrass.uiFont(size: 12, weight: .semibold))
                        .foregroundStyle(LinenBrass.coffee.opacity(0.86))
                        .lineLimit(2)
                        .minimumScaleFactor(0.62)
                } else if let skipNote = viewModel.previousRollSkipNote {
                    Text(skipNote.uppercased())
                        .font(LinenBrass.uiFont(size: 12, weight: .semibold))
                        .foregroundStyle(LinenBrass.coffee.opacity(0.7))
                        .lineLimit(2)
                        .minimumScaleFactor(0.62)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("previous-roll-slot")
        } else {
            Spacer(minLength: 0)
        }
    }
}

private struct DieFace: View {
    let value: Int
    let accessibilityIdentifier: String

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(red: 0.963, green: 0.918, blue: 0.812))
                    .shadow(color: .black.opacity(0.24), radius: 2, y: 1)

                RoundedRectangle(cornerRadius: 6)
                    .stroke(LinenBrass.coffee.opacity(0.24), lineWidth: 1)

                ForEach(Array(DicePipLayout.positions(for: value).enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(LinenBrass.ink)
                        .frame(width: geometry.size.width * 0.13, height: geometry.size.width * 0.13)
                        .position(x: geometry.size.width * point.x, y: geometry.size.height * point.y)
                    }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Die \(value)")
            .accessibilityIdentifier(accessibilityIdentifier)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private enum DicePipLayout {
    static func positions(for value: Int) -> [CGPoint] {
        guard (1...6).contains(value) else {
            return [CGPoint(x: 0.5, y: 0.5)]
        }

        switch value {
        case 1:
            return [CGPoint(x: 0.5, y: 0.5)]
        case 2:
            return [CGPoint(x: 0.3, y: 0.3), CGPoint(x: 0.7, y: 0.7)]
        case 3:
            return [CGPoint(x: 0.3, y: 0.3), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.7, y: 0.7)]
        case 4:
            return [CGPoint(x: 0.3, y: 0.3), CGPoint(x: 0.7, y: 0.3), CGPoint(x: 0.3, y: 0.7), CGPoint(x: 0.7, y: 0.7)]
        case 5:
            return [CGPoint(x: 0.3, y: 0.3), CGPoint(x: 0.7, y: 0.3), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.3, y: 0.7), CGPoint(x: 0.7, y: 0.7)]
        case 6:
            return [CGPoint(x: 0.3, y: 0.25), CGPoint(x: 0.7, y: 0.25), CGPoint(x: 0.3, y: 0.5), CGPoint(x: 0.7, y: 0.5), CGPoint(x: 0.3, y: 0.75), CGPoint(x: 0.7, y: 0.75)]
        default:
            return [CGPoint(x: 0.5, y: 0.5)]
        }
    }
}

private struct BoardFrame: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .stroke(LinenBrass.saddle, lineWidth: 10)
            RoundedRectangle(cornerRadius: 5)
                .stroke(LinenBrass.brass.opacity(0.34), lineWidth: 1)
                .padding(6)
        }
    }
}

private struct ActionBar: View {
    let viewModel: MatchViewModel
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if viewModel.isRaceAutoplayActive {
                HStack {
                    Text(viewModel.autoplayStatusText)
                        .font(LinenBrass.uiFont(size: 15, weight: .semibold))
                        .foregroundStyle(LinenBrass.cream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                    Spacer()
                }
                .frame(minHeight: 48)

                SecondaryActionButton(title: "Stop") {
                    viewModel.stopRaceAutoplay()
                    onAction()
                }
            } else if viewModel.canStartRaceAutoplay && !viewModel.canStartLocalAutoplay {
                PrimaryActionButton(title: "Autoplay race") {
                    viewModel.startRaceAutoplay()
                    onAction()
                }
            } else if viewModel.isTurnDraftPending {
                SecondaryActionButton(title: "Undo move") {
                    viewModel.undoLastMove()
                    onAction()
                }

                Text(draftStatusText)
                    .font(LinenBrass.uiFont(size: 15, weight: .semibold))
                    .foregroundStyle(LinenBrass.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .opacity(viewModel.canSubmitTurn ? 0 : 1)
                    .accessibilityHidden(viewModel.canSubmitTurn)

                PrimaryActionButton(title: "Submit turn", isEnabled: viewModel.canSubmitTurn) {
                    if viewModel.submitTurnIfAllowed() {
                        onAction()
                    }
                }
            } else {
                switch viewModel.state.game.phase {
            case .awaitingOpeningRoll(let tiedRoll):
                PrimaryActionButton(
                    title: tiedRoll == nil ? "Roll opening dice" : "Reroll",
                    accessibilityIdentifier: tiedRoll == nil ? "action-opening-roll" : nil
                ) {
                    viewModel.rollOpeningDice()
                    onAction()
                }

            case _ where viewModel.isOpponentAutomationActive:
                HStack {
                    Text(viewModel.isOpponentThinking ? "\(viewModel.opponentName) is thinking..." : "\(viewModel.opponentName)'s turn")
                        .font(LinenBrass.uiFont(size: 15, weight: .semibold))
                        .foregroundStyle(LinenBrass.cream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                    Spacer()
                }
                .frame(minHeight: 48)

            case .awaitingRoll(let player) where player == viewModel.localPlayer:
                resignationMenu
                if viewModel.containsAction(.offerDouble(viewModel.localPlayer)) {
                    SecondaryActionButton(title: "Double") {
                        viewModel.offerDoubleIfAllowed()
                        onAction()
                    }
                }
                PrimaryActionButton(title: "Roll") {
                    viewModel.rollDiceIfAllowed()
                    onAction()
                }
                localAutoplayButton

            case .awaitingMove(let turn) where turn.player == viewModel.localPlayer:
                resignationMenu
                if viewModel.containsAction(.passTurn(viewModel.localPlayer)) {
                    PrimaryActionButton(title: "Pass") {
                        viewModel.passIfAllowed()
                        onAction()
                    }
                } else {
                    Text("\(turn.remainingDice.count) move\(turn.remainingDice.count == 1 ? "" : "s") left")
                        .font(LinenBrass.uiFont(size: 15, weight: .semibold))
                        .foregroundStyle(LinenBrass.cream)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                localAutoplayButton

            case .awaitingCubeResponse(let offer) where offer.offeredBy.opponent == viewModel.localPlayer:
                PrimaryActionButton(title: "Take \(offer.proposedValue)") {
                    viewModel.send(.takeDouble(viewModel.localPlayer))
                    onAction()
                }
                SecondaryActionButton(title: "Drop") {
                    viewModel.send(.dropDouble(viewModel.localPlayer))
                    onAction()
                }

            case .awaitingResignationResponse(let offer) where offer.offeredBy.opponent == viewModel.localPlayer:
                PrimaryActionButton(title: "Accept \(offer.winKind.rawValue)") {
                    viewModel.send(.acceptResignation(viewModel.localPlayer))
                    onAction()
                }
                SecondaryActionButton(title: "Reject \(offer.winKind.rawValue)") {
                    viewModel.send(.rejectResignation(viewModel.localPlayer))
                    onAction()
                }

            case .gameOver:
                if viewModel.state.completion == nil {
                    PrimaryActionButton(title: "Next game") {
                        viewModel.send(.startNextGame)
                        onAction()
                    }
                } else {
                    PrimaryActionButton(title: "New match") {
                        viewModel.restartMatch()
                        onAction()
                    }
                }

            default:
                if case .awaitingRoll(let player) = viewModel.state.game.phase,
                   viewModel.containsAction(.rollDice(player))
                {
                    PrimaryActionButton(title: "Roll for \(viewModel.displayName(for: player))") {
                        viewModel.send(.rollDice(player))
                        onAction()
                    }
                } else {
                    HStack {
                        Text("Pass device to continue.")
                            .font(LinenBrass.uiFont(size: 15, weight: .semibold))
                            .foregroundStyle(LinenBrass.cream)
                        Spacer()
                    }
                    .frame(minHeight: 48)
                }
            }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(LinenBrass.coffee, in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(LinenBrass.brass.opacity(0.32), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var localAutoplayButton: some View {
        if viewModel.canStartLocalAutoplay {
            SecondaryActionButton(title: "Autoplay") {
                viewModel.startLocalAutoplay()
                onAction()
            }
        }
    }

    @ViewBuilder
    private var resignationMenu: some View {
        if viewModel.containsAction(.offerResignation(viewModel.localPlayer, .single)) {
            Menu {
                Button("Offer single") {
                    viewModel.offerResignationIfAllowed(.single)
                    onAction()
                }
                .accessibilityIdentifier("action-offer-single")
                if viewModel.containsAction(.offerResignation(viewModel.localPlayer, .gammon)) {
                    Button("Offer gammon") {
                        viewModel.offerResignationIfAllowed(.gammon)
                        onAction()
                    }
                    .accessibilityIdentifier("action-offer-gammon")
                }
                if viewModel.containsAction(.offerResignation(viewModel.localPlayer, .backgammon)) {
                    Button("Offer backgammon") {
                        viewModel.offerResignationIfAllowed(.backgammon)
                        onAction()
                    }
                    .accessibilityIdentifier("action-offer-backgammon")
                }
            } label: {
                Text("Resign...")
                    .font(LinenBrass.uiFont(size: 18, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(minWidth: 128, minHeight: 48)
            }
            .buttonStyle(LinenButtonStyle(kind: .secondary))
            .accessibilityIdentifier("action-resign")
        }
    }

    private var draftStatusText: String {
        if case .awaitingMove(let turn) = viewModel.state.game.phase, turn.player == viewModel.localPlayer {
            return "\(turn.remainingDice.count) move\(turn.remainingDice.count == 1 ? "" : "s") left"
        }
        return "Finish moves"
    }
}

private struct PrimaryActionButton: View {
    let title: String
    var isEnabled: Bool = true
    var accessibilityIdentifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(LinenBrass.uiFont(size: 18, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(LinenButtonStyle(kind: .primary))
        .disabled(!isEnabled)
        .accessibilityIdentifier(accessibilityIdentifier ?? actionAccessibilityIdentifier(for: title))
    }
}

private struct SecondaryActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(LinenBrass.uiFont(size: 18, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(LinenButtonStyle(kind: .secondary))
        .accessibilityIdentifier(actionAccessibilityIdentifier(for: title))
    }
}

private func actionAccessibilityIdentifier(for title: String) -> String {
    let words = title.lowercased().split { character in
        !character.isLetter && !character.isNumber
    }
    return "action-\(words.joined(separator: "-"))"
}

private struct LinenButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(kind == .primary ? LinenBrass.cream : LinenBrass.cream)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(kind == .primary ? LinenBrass.brass : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(LinenBrass.brass, lineWidth: 1.3)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
