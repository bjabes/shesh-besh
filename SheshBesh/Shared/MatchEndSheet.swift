import SwiftUI

#if canImport(SheshBeshLedger)
import SheshBeshLedger
#endif

public struct MatchEndSheet: View {
    public let record: MatchRecord
    public let ledger: RivalLedger?
    public let onDismiss: () -> Void

    public init(
        record: MatchRecord,
        ledger: RivalLedger?,
        onDismiss: @escaping () -> Void
    ) {
        self.record = record
        self.ledger = ledger
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(SheetTheme.brass.opacity(0.56))
                .frame(width: 42, height: 5)
                .padding(.top, 8)

            VStack(spacing: 8) {
                Text(record.winner == .you ? "You won" : "\(rivalName) won")
                    .font(SheetTheme.displayFont(size: 32, weight: .bold))
                    .foregroundStyle(SheetTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("Match final \(record.userScore)-\(record.rivalScore)")
                    .font(SheetTheme.uiFont(size: 16, weight: .semibold))
                    .foregroundStyle(SheetTheme.mutedInk)
                    .monospacedDigit()

                Text(marginLine)
                    .font(SheetTheme.uiFont(size: 14, weight: .medium))
                    .foregroundStyle(SheetTheme.rust)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }

            HStack(spacing: 12) {
                LedgerNumber(label: "YOU", value: ledger?.userWins ?? 0)
                LedgerNumber(label: rivalName.uppercased(), value: ledger?.rivalWins ?? 0)
            }

            Text(streakLine)
                .font(SheetTheme.uiFont(size: 15, weight: .semibold))
                .foregroundStyle(SheetTheme.mutedInk)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)

            Button(action: onDismiss) {
                Label("Back home", systemImage: "house.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(SheetTheme.coffee)
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        .presentationDetents([.medium])
        .presentationBackground(SheetTheme.cream)
    }

    private var rivalName: String {
        ledger?.rival.displayName ?? "Rival"
    }

    private var marginLine: String {
        let margin = record.userScore - record.rivalScore
        if margin > 0 {
            return "You by \(margin)"
        } else if margin < 0 {
            return "\(rivalName) by \(abs(margin))"
        } else {
            return "Level score"
        }
    }

    private var streakLine: String {
        guard let streak = ledger?.currentStreak, streak.count > 0 else {
            return "Ledger streak starts now"
        }

        let holder = streak.holder == .you ? "YOU" : rivalName
        return "\(holder) streak: \(streak.count)"
    }
}

private struct LedgerNumber: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(SheetTheme.uiFont(size: 12, weight: .bold))
                .foregroundStyle(SheetTheme.mutedInk)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text("\(value)")
                .font(SheetTheme.displayFont(size: 38, weight: .bold))
                .foregroundStyle(SheetTheme.rust)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(SheetTheme.linen, in: RoundedRectangle(cornerRadius: 7))
    }
}

private enum SheetTheme {
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
