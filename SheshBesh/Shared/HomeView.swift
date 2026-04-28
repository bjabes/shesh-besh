import SheshBeshGame
import SwiftUI

#if canImport(SheshBeshLedger)
import SheshBeshLedger
#endif

public struct HomeView: View {
    public let coordinator: LedgerCoordinator
    public let onOpenMatch: (ActiveMatch) -> Void

    @State private var isAddingRival = false
    @State private var newRivalName = ""
    @State private var isWorking = false
    @State private var isShowingRemoveAllConfirmation = false
    @State private var deletionRequest: RivalryDeletionRequest?
    @State private var localError: String?

    public init(
        coordinator: LedgerCoordinator,
        onOpenMatch: @escaping (ActiveMatch) -> Void
    ) {
        self.coordinator = coordinator
        self.onOpenMatch = onOpenMatch
    }

    public var body: some View {
        ZStack {
            LedgerBackground()
                .ignoresSafeArea()

            List {
                header
                    .ledgerListRow(top: 18, bottom: 18)
                RivalryLaunchActions(
                    primaryTitle: "Practice vs AI",
                    primarySystemImage: "cpu",
                    secondaryTitle: "Add Rival",
                    secondarySystemImage: "person.badge.plus",
                    onPrimary: startAIRivalry,
                    onSecondary: {
                        newRivalName = ""
                        isAddingRival = true
                    }
                )
                .ledgerListRow(bottom: activeMatches.count > 0 ? 18 : 14)

                if activeMatches.count > 0 {
                    RemoveAllMatchesButton(
                        activeMatchCount: activeMatches.count,
                        isDisabled: isWorking,
                        action: { isShowingRemoveAllConfirmation = true }
                    )
                    .ledgerListRow(bottom: 18)
                }

                if coordinator.ledgers.isEmpty {
                    EmptyLedgerView()
                        .ledgerListRow(bottom: 28)
                } else {
                    RivalryStack(
                        ledgers: coordinator.ledgers,
                        onStart: startMatch,
                        onResume: onOpenMatch,
                        onDelete: requestDelete
                    )
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .task {
            await coordinator.refresh()
        }
        .alert("New Rival", isPresented: $isAddingRival) {
            TextField("Name", text: $newRivalName)
            Button("Add") {
                addRival()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Create a head-to-head ledger.")
        }
        .alert("Remove All Matches?", isPresented: $isShowingRemoveAllConfirmation) {
            Button("Remove All Matches", role: .destructive) {
                removeAllActiveMatches()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removeAllConfirmationMessage)
        }
        .alert("Delete Rivalry?", isPresented: deletionConfirmationBinding) {
            if let request = deletionRequest {
                Button("Delete Rivalry", role: .destructive) {
                    deleteRival(request.ledger, deletingRecords: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let request = deletionRequest {
                Text(deleteConfirmationMessage(for: request.ledger))
            }
        }
        .alert(
            "Ledger Error",
            isPresented: Binding(
                get: { localError != nil || coordinator.lastErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        localError = nil
                        coordinator.clearError()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(localError ?? coordinator.lastErrorMessage ?? "")
        }
    }

    private var activeMatches: [ActiveMatch] {
        coordinator.ledgers.compactMap(\.activeMatch)
    }

    private var removeAllConfirmationMessage: String {
        "This will clear \(activeMatches.count) active \(activeMatches.count == 1 ? "match" : "matches"). Completed rivalry history stays."
    }

    private var deletionConfirmationBinding: Binding<Bool> {
        Binding {
            deletionRequest != nil
        } set: { isPresented in
            if !isPresented {
                deletionRequest = nil
            }
        }
    }

    private func deleteConfirmationMessage(for ledger: RivalLedger) -> String {
        "This rivalry has \(ledger.totalMatches) completed \(ledger.totalMatches == 1 ? "match" : "matches"). Delete anyway?"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Rivalries")
                .font(LedgerTheme.displayFont(size: 34, weight: .bold))
                .foregroundStyle(LedgerTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text("YOU against one rival at a time")
                .font(LedgerTheme.uiFont(size: 14, weight: .semibold))
                .foregroundStyle(LedgerTheme.mutedInk)
                .textCase(.uppercase)
                .tracking(0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addRival() {
        guard !isWorking else { return }
        isWorking = true
        Task {
            do {
                _ = try await coordinator.addRival(displayName: newRivalName)
                newRivalName = ""
            } catch {
                localError = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func startAIRivalry(difficulty: AIDifficulty) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            do {
                onOpenMatch(try await coordinator.startAIRivalry(difficulty: difficulty))
            } catch {
                localError = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func removeAllActiveMatches() {
        guard !isWorking else { return }
        let matchesToClear = activeMatches
        guard !matchesToClear.isEmpty else { return }

        isWorking = true
        Task {
            do {
                try await coordinator.clearActiveMatches(matchesToClear)
            } catch {
                localError = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func requestDelete(_ ledger: RivalLedger) {
        guard !isWorking else { return }
        if ledger.totalMatches > 0 {
            deletionRequest = RivalryDeletionRequest(ledger: ledger)
        } else {
            deleteRival(ledger, deletingRecords: false)
        }
    }

    private func deleteRival(_ ledger: RivalLedger, deletingRecords: Bool) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await coordinator.deleteRival(ledger.rival, deletingRecords: deletingRecords)
            } catch {
                localError = error.localizedDescription
            }
        }
    }

    private func startMatch(for ledger: RivalLedger) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            do {
                let match = try await coordinator.startMatch(
                    against: ledger.rival,
                    userPlays: ledger.totalMatches.isMultiple(of: 2) ? .white : .black,
                    config: .tournament(targetScore: 7)
                )
                onOpenMatch(match)
            } catch {
                localError = error.localizedDescription
            }
            isWorking = false
        }
    }
}

struct RivalryDeletionRequest: Identifiable {
    let ledger: RivalLedger
    var id: Rival.ID { ledger.rival.id }
}

struct RemoveAllMatchesButton: View {
    let activeMatchCount: Int
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            ThemedButtonLabel(
                title: "Remove All Matches",
                systemImage: "trash",
                foregroundStyle: LedgerTheme.rust
            )
                .font(LedgerTheme.uiFont(size: 15, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .tint(LedgerTheme.rust)
        .disabled(isDisabled || activeMatchCount == 0)
        .accessibilityIdentifier("home-remove-all-matches")
    }
}

struct RivalryLaunchActions: View {
    let primaryTitle: String
    let primarySystemImage: String
    let secondaryTitle: String
    let secondarySystemImage: String
    let onPrimary: (AIDifficulty) -> Void
    let onSecondary: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(AIDifficulty.allCases, id: \.self) { difficulty in
                    Button(difficulty.menuLabel) {
                        onPrimary(difficulty)
                    }
                    .accessibilityIdentifier("home-new-ai-rival-\(difficulty.rawValue)")
                }
            } label: {
                ThemedButtonLabel(
                    title: primaryTitle,
                    systemImage: primarySystemImage,
                    foregroundStyle: .white
                )
                    .font(LedgerTheme.uiFont(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(LedgerTheme.rust)
            .accessibilityIdentifier("home-new-ai-rival")

            Button(action: onSecondary) {
                ThemedButtonLabel(
                    title: secondaryTitle,
                    systemImage: secondarySystemImage,
                    foregroundStyle: LedgerTheme.coffee
                )
                    .font(LedgerTheme.uiFont(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .tint(LedgerTheme.coffee)
            .accessibilityIdentifier("home-new-game-center-rival")
        }
    }
}

struct RivalryStack: View {
    let ledgers: [RivalLedger]
    let onStart: (RivalLedger) -> Void
    let onResume: (ActiveMatch) -> Void
    var onDelete: (RivalLedger) -> Void = { _ in }
    var startTitle: (RivalLedger) -> String = { _ in "Start match" }
    var startSystemImage: (RivalLedger) -> String = { _ in "play.fill" }
    var resumeTitle: (RivalLedger) -> String = { ledger in
        ledger.activeMatch?.gameCenterMatchID == nil ? "Resume match" : "Open turn"
    }
    var resumeSystemImage: (RivalLedger) -> String = { ledger in
        ledger.activeMatch?.gameCenterMatchID == nil ? "arrow.uturn.forward" : "arrow.turn.up.right"
    }

    var body: some View {
        ForEach(Array(ledgers.enumerated()), id: \.element.rival.id) { index, ledger in
            RivalryCard(
                ledger: ledger,
                isHero: index == 0,
                startTitle: startTitle(ledger),
                startSystemImage: startSystemImage(ledger),
                resumeTitle: resumeTitle(ledger),
                resumeSystemImage: resumeSystemImage(ledger),
                onStart: { onStart(ledger) },
                onResume: {
                    if let match = ledger.activeMatch {
                        onResume(match)
                    }
                }
            )
            .ledgerListRow(bottom: index == ledgers.count - 1 ? 28 : 14)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    onDelete(ledger)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

private struct RivalryCard: View {
    let ledger: RivalLedger
    let isHero: Bool
    let startTitle: String
    let startSystemImage: String
    let resumeTitle: String
    let resumeSystemImage: String
    let onStart: () -> Void
    let onResume: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: isHero ? 16 : 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: ledger.rival.gameCenterPlayerID == nil ? "cpu" : "person.crop.circle.fill")
                            .font(LedgerTheme.displayFont(size: isHero ? 28 : 22, weight: .bold))
                            .foregroundStyle(LedgerTheme.mutedInk)
                            .accessibilityHidden(true)

                        Text(ledger.rival.displayName.uppercased())
                            .font(LedgerTheme.displayFont(size: isHero ? 28 : 22, weight: .bold))
                            .foregroundStyle(LedgerTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                    }

                    Text(statusLine)
                        .font(LedgerTheme.uiFont(size: 14, weight: .semibold))
                        .foregroundStyle(LedgerTheme.mutedInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }

                Spacer(minLength: 10)

                Text("\(ledger.userWins)-\(ledger.rivalWins)")
                    .font(LedgerTheme.displayFont(size: isHero ? 34 : 28, weight: .bold))
                    .foregroundStyle(LedgerTheme.rust)
                    .monospacedDigit()
                    .accessibilityIdentifier("ledger-score-\(ledger.rival.id.uuidString)")
            }

            HStack(spacing: 10) {
                MetricPill(title: "Matches", value: "\(ledger.totalMatches)")
                MetricPill(title: "Streak", value: streakText)
                Spacer(minLength: 0)
            }

            if ledger.activeMatch == nil {
                Button(action: onStart) {
                    ThemedButtonLabel(
                        title: startTitle,
                        systemImage: startSystemImage,
                        foregroundStyle: .white
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(LedgerTheme.coffee)
                .accessibilityIdentifier("start-match-\(ledger.rival.id.uuidString)")
            } else {
                Button(action: onResume) {
                    ThemedButtonLabel(
                        title: resumeTitle,
                        systemImage: resumeSystemImage,
                        foregroundStyle: .white
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(LedgerTheme.brass)
                .accessibilityIdentifier("resume-match-\(ledger.rival.id.uuidString)")
            }
        }
        .padding(isHero ? 18 : 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LedgerTheme.cream, in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(LedgerTheme.brass.opacity(isHero ? 0.86 : 0.52), lineWidth: 1)
        )
        .shadow(color: .black.opacity(isHero ? 0.16 : 0.09), radius: isHero ? 6 : 3, y: 2)
    }

    private var statusLine: String {
        if let activeMatch = ledger.activeMatch {
            return activeStatus(for: activeMatch)
        }

        guard let lastPlayedAt = ledger.lastPlayedAt else {
            return "No matches yet"
        }

        return "Last played \(lastPlayedAt.formatted(date: .abbreviated, time: .omitted))"
    }

    private var streakText: String {
        guard ledger.currentStreak.count > 0 else { return "0" }
        let holder = ledger.currentStreak.holder == .you ? "YOU" : ledger.rival.displayName
        return "\(holder) \(ledger.currentStreak.count)"
    }

    private func activeStatus(for match: ActiveMatch) -> String {
        switch match.state.game.phase {
        case .awaitingOpeningRoll:
            "Opening roll"
        case .awaitingRoll(let player):
            player == match.userPlayed ? "Your roll" : "\(ledger.rival.displayName)'s roll"
        case .awaitingMove(let turn):
            turn.player == match.userPlayed ? "Your turn" : "\(ledger.rival.displayName)'s turn"
        case .awaitingCubeResponse(let offer):
            offer.offeredBy == match.userPlayed ? "Double offered" : "\(ledger.rival.displayName) offered double"
        case .awaitingResignationResponse(let offer):
            offer.offeredBy == match.userPlayed ? "Resignation offered" : "\(ledger.rival.displayName) offered resignation"
        case .gameOver:
            "Game over"
        }
    }
}

private struct MetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(LedgerTheme.uiFont(size: 11, weight: .semibold))
                .foregroundStyle(LedgerTheme.mutedInk)
                .textCase(.uppercase)
            Text(value)
                .font(LedgerTheme.uiFont(size: 15, weight: .bold))
                .foregroundStyle(LedgerTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(LedgerTheme.linen, in: RoundedRectangle(cornerRadius: 6))
    }
}

struct ThemedButtonLabel: View {
    let title: String
    let systemImage: String
    let foregroundStyle: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(foregroundStyle)
            Text(title)
                .foregroundStyle(foregroundStyle)
        }
    }
}

private struct EmptyLedgerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Start a head-to-head ledger")
                .font(LedgerTheme.displayFont(size: 26, weight: .bold))
                .foregroundStyle(LedgerTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            Text("Pick the first rival and every completed match will build the running score.")
                .font(LedgerTheme.uiFont(size: 15))
                .foregroundStyle(LedgerTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LedgerTheme.cream, in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(LedgerTheme.brass.opacity(0.72), lineWidth: 1)
        )
    }
}

struct LedgerBackground: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(LedgerTheme.linen))

            for y in stride(from: 0.0, through: size.height, by: 8.0) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(LedgerTheme.coffee.opacity(0.05)), lineWidth: 0.6)
            }

            for x in stride(from: 0.0, through: size.width, by: 11.0) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.white.opacity(0.10)), lineWidth: 0.55)
            }
        }
    }
}

enum LedgerTheme {
    static let linen = Color(red: 0.937, green: 0.902, blue: 0.831)
    static let cream = Color(red: 0.929, green: 0.886, blue: 0.800)
    static let coffee = Color(red: 0.420, green: 0.290, blue: 0.180)
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

extension View {
    func ledgerListRow(top: CGFloat = 0, bottom: CGFloat) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 18, bottom: bottom, trailing: 18))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
