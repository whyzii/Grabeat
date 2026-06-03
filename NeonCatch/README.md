# GraBeat — Cyberpunk Note Brawl
## Swift / SwiftUI — iPadOS 17+ · macOS 14+ (Sonoma)

A two-player versus game where both players stand in front of the camera
and catch glowing neon notes by pinching their fingers (like a Kinect game).

Runs **natively on iPad and Mac** from a single multiplatform target —
no "Designed for iPad" letterboxing, no black bars on macOS.

---

## Project Structure

```
GraBeat/
├── App/
│   ├── NeonCatchApp.swift          Entry point (@main)
│   └── ContentView.swift           Root view — owns GameManager & tracker, routes screens
│
├── Models/
│   ├── GameModels.swift            Enums: GameState, NoteShape, NoteKind, NoteSize, BeatQuality
│   ├── EntityModels.swift          Structs: NoteItem, HandState, CatchEvent, ParticleItem, ScoreFloat
│   └── PowerUpModels.swift         Structs: FreezeState, TrapGlitchState, FrenzyState, BlackoutState
│
├── Core/
│   ├── GameManager.swift           Game loop, state machine, scoring, catch detection
│   ├── NoteSpawner.swift           Note construction and spawn-position selection
│   └── ParticleSystem.swift        Particle tick, pixel burst, ice burst, glitch burst
│
├── Services/
│   ├── Camera/
│   │   └── CameraHandTracker.swift AVFoundation + Vision hand tracking, calibration
│   └── Audio/
│       └── AudioEngine.swift       Music playback, beat detection, synthesised SFX
│
├── Views/
│   ├── Game/
│   │   ├── GameView.swift          Gameplay layout — assembles all layers (≈170 lines)
│   │   ├── NoteView.swift          Note rendering: glitch frame, catch animation
│   │   ├── HUDBar.swift            Score display, timer, BeatIndicator, ZoneLabels
│   │   ├── HandCursor.swift        Targeting reticle that follows each tracked hand
│   │   └── CameraPreview.swift     UIViewRepresentable / NSViewRepresentable camera feed
│   ├── Screens/
│   │   ├── StartScreen.swift       Title screen + player instruction cards
│   │   ├── CalibrationView.swift   Hand-detection progress rings before each game
│   │   └── EndScreen.swift         Game-over screen with winner + replay buttons
│   ├── Effects/
│   │   ├── CyberpunkFilter.swift   CyberpunkGrid, CyberpunkCameraFilter, Scanlines, Vignette
│   │   ├── AnimatedGrid.swift      Interactive warp grid + catch shockwaves + data streams
│   │   ├── HyperspaceBackground.swift  Full animated start-screen background (8 layers)
│   │   ├── FreezeOverlay.swift     Half-screen ice tint when a player is frozen
│   │   ├── TrapGlitchOverlay.swift Half-screen glitch effect from trap notes
│   │   └── BlackoutOverlay.swift   Full-screen SMPTE test-card blackout effect
│   └── Shared/
│       ├── MenuHandButton.swift    Button activated by hand pinch or tap
│       └── GlitchTitle.swift       Animated chromatic-aberration title text
│
├── Extensions/
│   ├── ColorExtensions.swift       Color.magenta definition
│   ├── UIScaleEnvironment.swift    uiScale environment key for responsive sizing
│   └── GlitchUtilities.swift       GlitchRNG, glitchHue(), buildNoteSegments()
│
└── Resources/
    ├── Audiowide-Regular.ttf       Custom font used throughout the UI
    └── Midnight_Service.mp3        Background music (123.046875 BPM)
```

---

## How to Play

- **Player 1** stands on the **LEFT** side of the camera frame
  - Catches **cyan ♪ notes** in the left half of the screen
- **Player 2** stands on the **RIGHT** side of the camera frame
  - Catches **pink ♪ notes** in the right half of the screen
- **Catch a note:** move your hand over it and **pinch** thumb + index finger
- **60 seconds** — most points wins!

### Special Notes

| Icon | Name     | Effect |
|------|----------|--------|
| ❄   | Freeze   | Catch it → opponent is frozen for 3 s |
| ⚡   | Trap     | Catch it → your own screen glitches for 3 s |
| ★   | Frenzy   | Catch it → 2× points for 5 s |
| ⊘   | Blackout | Catch it → full-screen CRT static, you −1000, opponent −2000 |

### Beat Timing Bonus

Catching a note on the music beat gives a multiplier:

| Timing  | Multiplier |
|---------|-----------|
| PERFECT | 2× |
| GOOD    | 1.5× |
| Off-beat | 1× |

---

## Setup in Xcode

1. Open `NeonCatch.xcodeproj`
2. Select your **Team** in Signing & Capabilities for both destinations
3. Set **Bundle Identifier** to something unique (e.g. `com.yourname.grabeat`)
4. Pick a destination:
   - **iPad** — physical device required (camera); simulator won't work
   - **My Mac** — native macOS app, resizable window, no black bars
5. Run

The scheme builds the same target for both — platform differences are handled
via `#if os(iOS)` / `#if os(macOS)`.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Camera capture | AVFoundation at 720p |
| Hand tracking | Vision `VNDetectHumanHandPoseRequest` (up to 4 hands) |
| Body anchoring | Vision `VNDetectHumanBodyPoseRequest` |
| UI | SwiftUI — `Canvas` for grid/particles, `TimelineView` for animation |
| Game loop | `Timer.publish` at 60 fps on main thread |
| Audio | AVAudioEngine + synthesised PCM tones (no asset files needed) |
| Orientation | Landscape-locked on iPad; freely resizable on macOS |

---

## Platform Notes

### iPad
- Landscape only (enforced in `Info.plist`)
- Status bar and persistent system overlays hidden
- `AVAudioSession` set to `.playback` + `.mixWithOthers`

### macOS
- Native AppKit window — fully resizable
- Opens at 1280×800, minimum 800×500
- Camera entitlement: `com.apple.security.device.camera` (sandboxed)
- `AVAudioSession` not used — macOS routes audio automatically
- No device-orientation observer needed

---

## Requirements

- iPadOS 17.0+ **or** macOS 14.0 (Sonoma)+
- Xcode 15+
- Physical device with a built-in front camera
- Two players standing side by side facing the camera
