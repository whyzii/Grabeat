import SwiftUI

// MARK: - Particle System
// Responsible for spawning and ticking all particle effects.

@MainActor
class ParticleSystem {

    // MARK: - Tick

    /// Advances all particles by one frame (dt = 1/60 s) and removes dead ones.
    func tick(particles: inout [ParticleItem]) {
        let dt = 1.0 / 60.0
        for i in particles.indices {
            particles[i].position.x += particles[i].velocity.x
            particles[i].position.y += particles[i].velocity.y
            particles[i].velocity.y += 0.00035  // gravity
            particles[i].life       -= dt * 1.4
        }
        particles.removeAll { $0.life <= 0 }
    }

    // MARK: - Burst Spawners

    /// Standard catch burst — pixel count and colour scale with beat quality.
    func spawnPixelBurst(at pos: CGPoint, color: Color,
                         quality: BeatQuality, into particles: inout [ParticleItem]) {
        let count: Int = quality == .perfect ? 36 : quality == .good ? 28 : 22
        let sizes: [CGFloat] = [3, 4, 4, 5, 6, 6, 8, 10]
        for _ in 0..<count {
            let angle = Double.random(in: 0...(2 * .pi))
            let speed = Double.random(in: 0.003...0.012)
            particles.append(ParticleItem(
                position: pos,
                velocity: CGPoint(x: cos(angle) * speed, y: sin(angle) * speed - 0.004),
                color:    quality == .perfect ? .yellow : color,
                life:     Double.random(in: 0.7...1.2),
                size:     sizes.randomElement()!
            ))
        }
    }

    /// Ice burst for freeze / obstacle catches.
    func spawnIceBurst(at pos: CGPoint, color: Color, into particles: inout [ParticleItem]) {
        let sizes: [CGFloat] = [4, 5, 6, 6, 8, 8, 10, 12]
        let iceWhite = Color(red: 0.85, green: 0.97, blue: 1.0)
        for _ in 0..<48 {
            let angle = Double.random(in: 0...(2 * .pi))
            let speed = Double.random(in: 0.001...0.008)
            particles.append(ParticleItem(
                position: pos,
                velocity: CGPoint(x: cos(angle) * speed, y: sin(angle) * speed - 0.006),
                color:    [color, .white, iceWhite].randomElement()!,
                life:     Double.random(in: 1.0...1.8),
                size:     sizes.randomElement()!
            ))
        }
    }

    /// Generic glitch burst — used for trap, frenzy, and blackout catches.
    func spawnGlitchBurst(at pos: CGPoint, color: Color, into particles: inout [ParticleItem]) {
        let sizes: [CGFloat] = [3, 4, 5, 5, 7, 8, 10]
        for _ in 0..<40 {
            let angle = Double.random(in: 0...(2 * .pi))
            let speed = Double.random(in: 0.002...0.010)
            particles.append(ParticleItem(
                position: pos,
                velocity: CGPoint(x: cos(angle) * speed, y: sin(angle) * speed - 0.004),
                color:    Bool.random() ? color : .white,
                life:     Double.random(in: 0.8...1.5),
                size:     sizes.randomElement()!
            ))
        }
    }
}
