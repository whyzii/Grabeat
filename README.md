# NeonCatch — Cyberpunk Note Brawl
## Swift / SwiftUI — iPadOS 17+ · macOS 14+ (Sonoma)

A two-player versus game where both players stand in front of the camera
and catch glowing neon notes by pinching their fingers (like a Kinect game).

This build runs **natively on iPad and on Mac** from a single multiplatform
target — no "Designed for iPad" letterboxing, no black bars on macOS.

---

## Files

| File | Role |
|------|------|
| `NeonCatchApp.swift` | App entry point |
| `ContentView.swift` | Root view — routes between screens, sizes the macOS window |
| `GameManager.swift` | All game logic: state, timer, scoring, notes, particles, audio |
| `CameraHandTracker.swift` | AVFoundation camera + Vision hand pose detection |
| `GameView.swift` | Main gameplay view: camera feed, notes, HUD, hand cursors |
| `StartEndScreens.swift` | Start screen and end/winner screen |
| `Info.plist` | iOS bundle metadata (scenes + landscape orientation) |
| `Info-macOS.plist` | macOS bundle metadata (no scene/orientation keys) |
| `NeonCatch.entitlements` | macOS sandbox + camera entitlement |

---

## Setup in Xcode

1. Open `NeonCatch.xcodeproj`
2. Select your **Team** in Signing & Capabilities for both destinations
3. Set **Bundle Identifier** to something unique (e.g. `com.yourname.neoncatch`)
4. Pick a destination:
   - **iPad** — a real iPad (camera required, simulator won't work)
   - **My Mac (Designed for iPad)** — *don't use this*; use the native Mac
     destination below
   - **My Mac** — runs as a real macOS app, resizable window, no black bars
5. Run

The Xcode scheme builds the same target for whichever destination you
pick — there's only one target, with platform-conditional code via
`#if os(iOS)` / `#if os(macOS)`.

---

## How to Play

- **Player 1** stands on the **LEFT** side of the camera frame
  - Catches **cyan ♪ notes** that appear in the left half of the screen
- **Player 2** stands on the **RIGHT** side of the camera frame
  - Catches **pink ♪ notes** that appear in the right half of the screen
- **Catch a note:** move your hand over a note and **pinch** thumb + index finger together
- **60 seconds** — most catches wins!

---

## Tech

- **AVFoundation** — front camera capture at 720p (built-in on both platforms)
- **Vision** — `VNDetectHumanHandPoseRequest` tracking up to 4 hands
- **SwiftUI** — all UI, game loop via `Timer.publish`, `Canvas` for grid
- **AVAudioEngine** — PCM synth tones on each catch (no `AVAudioSession` on macOS)
- **Orientation** — landscape-locked on iPad; macOS uses freely resizable window

---

## Platform notes

### iPad
- Landscape only (enforced in `Info.plist`)
- Status bar hidden, persistent system overlays hidden
- `AVAudioSession` configured for `.playback` + `.mixWithOthers`

### macOS
- Native AppKit window — fully resizable, no aspect-ratio lock
  (this is what fixes the black bars on the sides)
- Default window opens at 1280×800, min 800×500
- Camera entitlement: `com.apple.security.device.camera`
- Sandboxed (App Store-ready)
- `AVAudioSession` is skipped — macOS routes audio automatically
- Device-orientation notifications are skipped — the camera doesn't
  rotate on a Mac

---

## Requirements

- iPadOS 17.0+ **or** macOS 14.0 (Sonoma)+
- Xcode 15+
- Physical device with a built-in or USB front camera
- Two players standing side by side facing the camera
