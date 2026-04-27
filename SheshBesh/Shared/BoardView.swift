import SheshBeshGame
import SwiftUI

public struct BoardView: View {
    public let viewModel: MatchViewModel

    @State private var selectedSource: MoveSource?

    public init(viewModel: MatchViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            LinenBackground()
                .ignoresSafeArea()

            VStack(spacing: 12) {
                HeaderCard(viewModel: viewModel)
                PipStrip(viewModel: viewModel)

                BoardSurface(
                    viewModel: viewModel,
                    selectedSource: selectedSource,
                    onPointTap: handlePointTap,
                    onBarTap: handleBarTap,
                    onBearOffTap: handleBearOffTap
                )
                .aspectRatio(0.78, contentMode: .fit)
                .frame(maxHeight: 600)

                ActionBar(viewModel: viewModel) {
                    selectedSource = nil
                }

                if let lastError = viewModel.lastError {
                    Text(lastError)
                        .font(.footnote)
                        .foregroundStyle(LinenBrass.cream)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(LinenBrass.rust, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)
        }
        .onChange(of: viewModel.state.game.phase) { _, _ in
            selectedSource = nil
        }
    }

    private func handlePointTap(_ pointID: PointID) {
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
        let source: MoveSource = .bar
        if selectedSource == source {
            selectedSource = nil
        } else if viewModel.isLegalSource(source) {
            selectedSource = source
        }
    }

    private func handleBearOffTap() {
        guard let selectedSource else { return }
        if viewModel.applyMove(from: selectedSource, to: .off) {
            self.selectedSource = nil
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .lastTextBaseline) {
                Text("YOU vs \(viewModel.opponentName.uppercased())")
                    .font(LinenBrass.displayFont(size: 28, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 10)

                Text("\(viewModel.localScore)-\(viewModel.opponentScore)")
                    .font(LinenBrass.displayFont(size: 28, weight: .bold))
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                Text("game \(viewModel.state.gameNumber)")
                Text("match to \(viewModel.state.config.targetScore)")
                Text(viewModel.phaseTitle)
                    .foregroundStyle(viewModel.isLocalTurn ? LinenBrass.brass : LinenBrass.mutedInk)
                    .fontWeight(.semibold)
            }
            .font(LinenBrass.uiFont(size: 14))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
        }
        .foregroundStyle(LinenBrass.ink)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(LinenBrass.cream)
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(LinenBrass.brass.opacity(0.72), lineWidth: 1)
        )
    }
}

private struct PipStrip: View {
    let viewModel: MatchViewModel

    var body: some View {
        HStack {
            pipCount(for: viewModel.localPlayer)
            Spacer(minLength: 12)
            Text("match \(viewModel.localScore)-\(viewModel.opponentScore)")
                .font(LinenBrass.uiFont(size: 15, weight: .semibold))
                .foregroundStyle(LinenBrass.cream)
                .lineLimit(1)
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
    let selectedSource: MoveSource?
    let onPointTap: (PointID) -> Void
    let onBarTap: () -> Void
    let onBearOffTap: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let trayHeight = max(68, geometry.size.height * 0.18)
            let halfHeight = (geometry.size.height - trayHeight) / 2
            let barWidth = max(38, geometry.size.width * 0.08)
            let legalSources = Set(viewModel.legalMoves.map(\.source))
            let legalDestinations = selectedSource.map { source in
                Set(viewModel.legalMoves.lazy.filter { $0.source == source }.map(\.destination))
            } ?? []

            VStack(spacing: 0) {
                BoardHalf(
                    viewModel: viewModel,
                    selectedSource: selectedSource,
                    leftPoints: pointIDs(13...18),
                    rightPoints: pointIDs(19...24),
                    barWidth: barWidth,
                    pointsDown: true,
                    legalSources: legalSources,
                    legalDestinations: legalDestinations,
                    onPointTap: onPointTap,
                    onBarTap: onBarTap
                )
                .frame(height: halfHeight)

                TrayRow(
                    viewModel: viewModel,
                    selectedSource: selectedSource,
                    barWidth: barWidth,
                    legalDestinations: legalDestinations,
                    onBarTap: onBarTap,
                    onBearOffTap: onBearOffTap
                )
                .frame(height: trayHeight)

                BoardHalf(
                    viewModel: viewModel,
                    selectedSource: selectedSource,
                    leftPoints: pointIDs(stride(from: 12, through: 7, by: -1)),
                    rightPoints: pointIDs(stride(from: 6, through: 1, by: -1)),
                    barWidth: barWidth,
                    pointsDown: false,
                    legalSources: legalSources,
                    legalDestinations: legalDestinations,
                    onPointTap: onPointTap,
                    onBarTap: onBarTap
                )
                .frame(height: halfHeight)
            }
            .background(LinenBrass.linenDeep)
            .overlay(BoardFrame())
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .shadow(color: .black.opacity(0.24), radius: 6, y: 3)
        }
    }

    private func pointIDs(_ range: ClosedRange<Int>) -> [PointID] {
        range.compactMap(PointID.init(rawValue:))
    }

    private func pointIDs<S: Sequence>(_ values: S) -> [PointID] where S.Element == Int {
        values.compactMap(PointID.init(rawValue:))
    }
}

private struct BoardHalf: View {
    let viewModel: MatchViewModel
    let selectedSource: MoveSource?
    let leftPoints: [PointID]
    let rightPoints: [PointID]
    let barWidth: CGFloat
    let pointsDown: Bool
    let legalSources: Set<MoveSource>
    let legalDestinations: Set<MoveDestination>
    let onPointTap: (PointID) -> Void
    let onBarTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            PointRun(
                viewModel: viewModel,
                selectedSource: selectedSource,
                pointIDs: leftPoints,
                pointsDown: pointsDown,
                startsWithDarkPoint: pointsDown,
                legalSources: legalSources,
                legalDestinations: legalDestinations,
                onPointTap: onPointTap
            )

            BarWell(
                viewModel: viewModel,
                selectedSource: selectedSource,
                segment: pointsDown ? .top : .bottom,
                isLegalSource: legalSources.contains(.bar),
                isLegalDestination: false,
                onBarTap: onBarTap
            )
            .frame(width: barWidth)

            PointRun(
                viewModel: viewModel,
                selectedSource: selectedSource,
                pointIDs: rightPoints,
                pointsDown: pointsDown,
                startsWithDarkPoint: !pointsDown,
                legalSources: legalSources,
                legalDestinations: legalDestinations,
                onPointTap: onPointTap
            )
        }
    }
}

private struct PointRun: View {
    let viewModel: MatchViewModel
    let selectedSource: MoveSource?
    let pointIDs: [PointID]
    let pointsDown: Bool
    let startsWithDarkPoint: Bool
    let legalSources: Set<MoveSource>
    let legalDestinations: Set<MoveDestination>
    let onPointTap: (PointID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(pointIDs.enumerated()), id: \.element.rawValue) { index, pointID in
                PointCell(
                    pointID: pointID,
                    point: viewModel.state.game.board.point(pointID),
                    pointsDown: pointsDown,
                    isDarkPoint: (index.isMultiple(of: 2)) == startsWithDarkPoint,
                    isSelected: selectedSource == .point(pointID),
                    isLegalSource: legalSources.contains(.point(pointID)),
                    isLegalDestination: legalDestinations.contains(.point(pointID)),
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
    let pointsDown: Bool
    let isDarkPoint: Bool
    let isSelected: Bool
    let isLegalSource: Bool
    let isLegalDestination: Bool
    let localPlayer: Player
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: pointsDown ? .top : .bottom) {
                PointTriangle(pointsDown: pointsDown)
                    .fill(isDarkPoint ? LinenBrass.rust.opacity(0.68) : LinenBrass.cream.opacity(0.72))
                    .padding(.horizontal, 1)

                CheckerStack(point: point, pointsDown: pointsDown, localPlayer: localPlayer)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 1)

                VStack {
                    if pointsDown { Spacer(minLength: 0) }
                    Text("\(pointID.rawValue)")
                        .font(LinenBrass.uiFont(size: 9, weight: .medium))
                        .foregroundStyle(LinenBrass.coffee.opacity(0.64))
                        .lineLimit(1)
                    if !pointsDown { Spacer(minLength: 0) }
                }
                .padding(.vertical, 3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay(highlight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    @ViewBuilder
    private var highlight: some View {
        if isSelected {
            PointTriangle(pointsDown: pointsDown)
                .stroke(LinenBrass.brass, lineWidth: 3)
                .padding(2)
        } else if isLegalDestination {
            PointTriangle(pointsDown: pointsDown)
                .stroke(LinenBrass.brass.opacity(0.88), lineWidth: 2)
                .padding(4)
        } else if isLegalSource {
            PointTriangle(pointsDown: pointsDown)
                .stroke(LinenBrass.cream.opacity(0.48), lineWidth: 1)
                .padding(5)
        }
    }

    private var accessibilityLabel: String {
        guard let owner = point.owner else {
            return "Point \(pointID.rawValue), empty\(stateSuffix)"
        }
        let player = owner == localPlayer ? "your" : "opponent"
        let checkerWord = point.count == 1 ? "checker" : "checkers"
        return "Point \(pointID.rawValue), \(point.count) \(player) \(checkerWord)\(stateSuffix)"
    }

    private var stateSuffix: String {
        if isSelected { return ", selected" }
        if isLegalDestination { return ", legal destination" }
        if isLegalSource { return ", legal source" }
        return ""
    }

    private var accessibilityHint: String {
        if isSelected { return "Tap to deselect this point." }
        if isLegalDestination { return "Tap to move the selected checker here." }
        if isLegalSource { return "Tap to select this point as a move source." }
        return "Tap to inspect this point."
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
    let point: PointState
    let pointsDown: Bool
    let localPlayer: Player

    var body: some View {
        GeometryReader { geometry in
            let visibleCount = min(point.count, 5)
            let diameter = max(6, min(geometry.size.width * 0.88, geometry.size.height / 5.4))
            let spacing = max(-diameter * 0.12, -3)

            VStack(spacing: spacing) {
                ForEach(0..<visibleCount, id: \.self) { _ in
                    Checker(owner: point.owner, localPlayer: localPlayer)
                        .frame(width: diameter, height: diameter)
                }

                if point.count > visibleCount {
                    Text("\(point.count)")
                        .font(LinenBrass.uiFont(size: 10, weight: .bold))
                        .foregroundStyle(LinenBrass.ink)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(LinenBrass.brass, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: pointsDown ? .top : .bottom)
        }
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
        .accessibilityLabel(accessibilityLabel)
    }

    private func barCheckers(for player: Player) -> some View {
        let count = viewModel.state.game.board.barCount(for: player)
        return Group {
            if count > 0 {
                Checker(owner: player, localPlayer: viewModel.localPlayer)
                    .overlay {
                        Text("\(count)")
                            .font(LinenBrass.uiFont(size: 10, weight: .bold))
                            .foregroundStyle(player == viewModel.localPlayer ? LinenBrass.cream : LinenBrass.ink)
                    }
            }
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
}

private struct TrayRow: View {
    let viewModel: MatchViewModel
    let selectedSource: MoveSource?
    let barWidth: CGFloat
    let legalDestinations: Set<MoveDestination>
    let onBarTap: () -> Void
    let onBearOffTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            BearOffZone(
                title: "\(viewModel.displayName(for: viewModel.localPlayer.opponent)) off",
                count: viewModel.state.game.board.borneOffCount(for: viewModel.localPlayer.opponent),
                owner: viewModel.localPlayer.opponent,
                localPlayer: viewModel.localPlayer,
                isLegalDestination: false,
                onTap: {}
            )

            BarWell(
                viewModel: viewModel,
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
                    ForEach(Array(dice.enumerated()), id: \.offset) { _, value in
                        DieFace(value: value)
                            .frame(width: 34, height: 34)
                    }
                }

                Text(viewModel.phaseTitle.uppercased())
                    .font(LinenBrass.uiFont(size: 12, weight: .bold))
                    .foregroundStyle(viewModel.isLocalTurn ? LinenBrass.brass : LinenBrass.cream.opacity(0.72))
                    .lineLimit(2)
                    .minimumScaleFactor(0.68)

                Spacer(minLength: 0)

                BearOffZone(
                    title: "You off",
                    count: viewModel.state.game.board.borneOffCount(for: viewModel.localPlayer),
                    owner: viewModel.localPlayer,
                    localPlayer: viewModel.localPlayer,
                    isLegalDestination: viewModel.isLegalDestination(.off, from: selectedSource),
                    onTap: onBearOffTap
                )
                .frame(width: 72)
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

private struct BearOffZone: View {
    let title: String
    let count: Int
    let owner: Player
    let localPlayer: Player
    let isLegalDestination: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                Checker(owner: owner, localPlayer: localPlayer)
                    .frame(width: 24, height: 24)
                    .opacity(count == 0 ? 0.38 : 1)
                    .overlay {
                        if count > 0 {
                            Text("\(count)")
                                .font(LinenBrass.uiFont(size: 9, weight: .bold))
                                .foregroundStyle(owner == localPlayer ? LinenBrass.cream : LinenBrass.ink)
                        }
                    }

                Text(title)
                    .font(LinenBrass.uiFont(size: 9, weight: .semibold))
                    .foregroundStyle(LinenBrass.cream.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isLegalDestination ? LinenBrass.brass.opacity(0.2) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    }

    private var label: String {
        let displayValue = cube.owner == nil && cube.value == 1 ? cube.value * 2 : cube.value
        return "\(displayValue)"
    }
}

private struct DieFace: View {
    let value: Int

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(red: 0.963, green: 0.918, blue: 0.812))
                    .shadow(color: .black.opacity(0.24), radius: 2, y: 1)

                RoundedRectangle(cornerRadius: 6)
                    .stroke(LinenBrass.coffee.opacity(0.24), lineWidth: 1)

                ForEach(Array(pipPositions.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(LinenBrass.ink)
                        .frame(width: geometry.size.width * 0.13, height: geometry.size.width * 0.13)
                        .position(x: geometry.size.width * point.x, y: geometry.size.height * point.y)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Die \(value)")
    }

    private var pipPositions: [CGPoint] {
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
            switch viewModel.state.game.phase {
            case .awaitingOpeningRoll(let tiedRoll):
                PrimaryActionButton(title: tiedRoll == nil ? "Opening roll" : "Reroll") {
                    viewModel.rollOpeningDice()
                    onAction()
                }

            case .awaitingRoll(let player) where player == viewModel.localPlayer:
                if viewModel.containsAction(.offerDouble(viewModel.localPlayer)) {
                    SecondaryActionButton(title: "Offer double") {
                        viewModel.offerDoubleIfAllowed()
                        onAction()
                    }
                }
                resignationMenu
                PrimaryActionButton(title: "Roll dice") {
                    viewModel.rollDiceIfAllowed()
                    onAction()
                }

            case .awaitingMove(let turn) where turn.player == viewModel.localPlayer:
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
                resignationMenu

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

    @ViewBuilder
    private var resignationMenu: some View {
        if viewModel.containsAction(.offerResignation(viewModel.localPlayer, .single)) {
            Menu("Resign…") {
                Button("Offer single") {
                    viewModel.offerResignationIfAllowed(.single)
                    onAction()
                }
                Button("Offer gammon") {
                    viewModel.offerResignationIfAllowed(.gammon)
                    onAction()
                }
                Button("Offer backgammon") {
                    viewModel.offerResignationIfAllowed(.backgammon)
                    onAction()
                }
            }
            .buttonStyle(LinenButtonStyle(kind: .secondary))
        }
    }
}

private struct PrimaryActionButton: View {
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
        .buttonStyle(LinenButtonStyle(kind: .primary))
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
    }
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
