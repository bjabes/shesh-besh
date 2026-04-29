public enum MoveNotation {
    public static func format(_ moves: [AppliedMove], from perspective: Player) -> String {
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
            let text = formatChain(entry.chain, from: perspective)
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

    private static func formatChain(_ chain: [AppliedMove], from perspective: Player) -> String {
        guard let first = chain.first else { return "" }
        var result = sourceText(first.move.source, from: perspective)
            + "/" + destinationText(first.move.destination, didHit: first.didHit, from: perspective)
        for applied in chain.dropFirst() {
            result += "/" + destinationText(applied.move.destination, didHit: applied.didHit, from: perspective)
        }
        return result
    }

    private static func sourceText(_ source: MoveSource, from perspective: Player) -> String {
        switch source {
        case .bar: return "bar"
        case .point(let point): return String(pointNumber(point, from: perspective))
        }
    }

    private static func destinationText(_ destination: MoveDestination, didHit: Bool, from perspective: Player) -> String {
        switch destination {
        case .point(let point): return String(pointNumber(point, from: perspective)) + (didHit ? "*" : "")
        case .off: return "off"
        }
    }

    private static func pointNumber(_ point: PointID, from perspective: Player) -> Int {
        point.perspectiveValue(for: perspective)
    }
}
