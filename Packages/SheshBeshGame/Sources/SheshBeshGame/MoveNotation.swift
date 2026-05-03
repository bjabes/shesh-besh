public enum MoveNotation {
    public static func format(_ moves: [AppliedMove]) -> String {
        let chains = buildChains(from: moves)
        var collapsed: [(chain: [AppliedMove], count: Int)] = []
        for chain in chains {
            if let index = collapsed.firstIndex(where: { $0.chain == chain }) {
                collapsed[index].count += 1
            } else {
                collapsed.append((chain, 1))
            }
        }
        return collapsed.map { entry in
            let text = formatChain(entry.chain)
            return entry.count > 1 ? "\(text)(\(entry.count))" : text
        }.joined(separator: " ")
    }

    private static func buildChains(from moves: [AppliedMove]) -> [[AppliedMove]] {
        var chains: [[AppliedMove]] = []
        var current: [AppliedMove] = []
        for applied in moves {
            if let last = current.last,
               case .point(let lastDest) = last.move.destination,
               case .point(let nextSource) = applied.move.source,
               lastDest == nextSource {
                current.append(applied)
            } else {
                if !current.isEmpty { chains.append(current) }
                current = [applied]
            }
        }
        if !current.isEmpty { chains.append(current) }
        return chains
    }

    private static func formatChain(_ chain: [AppliedMove]) -> String {
        guard let first = chain.first else { return "" }
        var result = sourceText(first.move.source)
            + "/" + destinationText(first.move.destination, didHit: first.didHit)
        for applied in chain.dropFirst() {
            result += "/" + destinationText(applied.move.destination, didHit: applied.didHit)
        }
        return result
    }

    private static func sourceText(_ source: MoveSource) -> String {
        switch source {
        case .bar: return "bar"
        case .point(let point): return String(point.rawValue)
        }
    }

    private static func destinationText(_ destination: MoveDestination, didHit: Bool) -> String {
        switch destination {
        case .point(let point): return String(point.rawValue) + (didHit ? "*" : "")
        case .off: return "off"
        }
    }
}
