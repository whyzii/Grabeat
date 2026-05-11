# NeonCatch — Cyberpunk Note Brawl
## Swift / SwiftUI — iOS 17+ / iPadOS 17+

A two-player versus game where both players stand in front of the camera
and catch glowing neon notes by pinching their fingers (like a Kinect game).

---

## Files

| File | Role |
|------|------|
| `NeonCatchApp.swift` | App entry point |
| `ContentView.swift` | Root view — routes between screens |
| `GameManager.swift` | All game logic: state, timer, scoring, notes, particles, audio |
| `CameraHandTracker.swift` | AVFoundation camera + Vision hand pose detection |
| `GameView.swift` | Main gameplay view: camera feed, notes, HUD, hand cursors |
| `StartEndScreens.swift` | Start screen and end/winner screen |
| `Info.plist` | Camera permission + landscape-only orientation |

---

## Setup in Xcode

1. Open `NeonCatch.xcodeproj`
2. Select your **Team** in Signing & Capabilities
3. Set **Bundle Identifier** to something unique (e.g. `com.yourname.neoncatch`)
4. Run on a **real iPhone or iPad** (camera required — simulator won't work)

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

- **AVFoundation** — front camera capture at 720p
- **Vision** — `VNDetectHumanHandPoseRequest` tracking up to 4 hands
- **SwiftUI** — all UI, game loop via `Timer.publish`, `Canvas` for grid
- **AVAudioEngine** — PCM synth tones on each catch
- **Orientation** — landscape only (set in Info.plist)

---

## Requirements

- iOS 17.0+ / iPadOS 17.0+
- Xcode 15+
- Physical device with front camera
- Two players standing side by side facing the camera
