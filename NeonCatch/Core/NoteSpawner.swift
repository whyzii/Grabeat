import Foundation

// MARK: - Note Spawner
// Responsible for all note creation logic: position selection and note construction.

@MainActor
class NoteSpawner {

    private let symbols = ["♩", "♪", "♫", "♬"]

    // MARK: - Normal Notes

    func spawnNote(player: Int, existingNotes: [NoteItem]) -> NoteItem {
        let pos   = bestSpawnPosition(player: player, existingNotes: existingNotes)
        let sizes: [NoteSize] = [.tiny, .small, .medium, .medium, .large, .large]
        return NoteItem(
            player:    player,
            position:  pos,
            symbol:    symbols.randomElement() ?? "♩",
            noteSize:  sizes.randomElement()!,
            noteShape: Bool.random() ? .hexagon : .square,
            noteKind:  .normal
        )
    }

    // MARK: - Power-Up Notes

    func spawnObstacleNote(player: Int, existingNotes: [NoteItem]) -> NoteItem {
        let pos = bestSpawnPosition(player: player, existingNotes: existingNotes)
        return NoteItem(
            player:    player,
            position:  pos,
            symbol:    "❄",
            noteSize:  .medium,
            noteShape: .circle,
            noteKind:  .obstacle
        )
    }

    func spawnTrapNote(player: Int, existingNotes: [NoteItem]) -> NoteItem {
        let pos = bestSpawnPosition(player: player, existingNotes: existingNotes)
        return NoteItem(
            player:    player,
            position:  pos,
            symbol:    "⚡",
            noteSize:  .medium,
            noteShape: .triangle,
            noteKind:  .trap,
            decayRate: 1.0 / (10.0 * 60.0)
        )
    }

    func spawnFrenzyNote(player: Int, existingNotes: [NoteItem]) -> NoteItem {
        let pos = bestSpawnPosition(player: player, existingNotes: existingNotes)
        return NoteItem(
            player:    player,
            position:  pos,
            symbol:    "★",
            noteSize:  .medium,
            noteShape: .diamond,
            noteKind:  .frenzy,
            decayRate: 1.0 / (10.0 * 60.0)
        )
    }

    func spawnBlackoutNote(player: Int, existingNotes: [NoteItem]) -> NoteItem {
        let pos = bestSpawnPosition(player: player, existingNotes: existingNotes)
        return NoteItem(
            player:    player,
            position:  pos,
            symbol:    "⊘",
            noteSize:  .medium,
            noteShape: .octagon,
            noteKind:  .blackout,
            decayRate: 1.0 / (10.0 * 60.0)
        )
    }

    // MARK: - Position Selection
    // Tries 12 candidate positions and picks the one furthest from all live notes,
    // ensuring at least minSep separation before giving up early.

    private func bestSpawnPosition(player: Int, existingNotes: [NoteItem]) -> CGPoint {
        let xRange: ClosedRange<CGFloat> = player == 1 ? 0.06...0.44 : 0.56...0.94
        let yRange: ClosedRange<CGFloat> = 0.18...0.82
        let minSep: CGFloat = 0.22
        let live = existingNotes.filter { $0.player == player && !$0.caught }

        var bestPos  = CGPoint(x: CGFloat.random(in: xRange), y: CGFloat.random(in: yRange))
        var bestDist: CGFloat = 0

        for _ in 0..<12 {
            let candidate = CGPoint(x: CGFloat.random(in: xRange), y: CGFloat.random(in: yRange))
            let d = live.map {
                let dx = candidate.x - $0.position.x
                let dy = candidate.y - $0.position.y
                return sqrt(dx * dx + dy * dy)
            }.min() ?? .infinity

            if d > bestDist { bestDist = d; bestPos = candidate }
            if bestDist >= minSep { break }
        }
        return bestPos
    }
}
