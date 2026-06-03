//
//  PhotoBoothReviewScreen.swift
//  NeonCatch
//
//  Created by Yousefzadeh Abbas on 19/05/26.
//

import SwiftUI

// MARK: - Photo Booth Review Screen
// Shown immediately after the round ends.
// Displays all 4 captured moments in a 2×2 grid that always fits on one screen —
// no scrolling required and photos are never cropped (scaledToFit).

struct PhotoBoothReviewScreen: View {
    @ObservedObject var gameManager: GameManager
    @ObservedObject var photoBooth:  PhotoBoothManager
    @ObservedObject var tracker:     CameraHandTracker

    @State private var appeared   = false
    @State private var saveResult: Bool? = nil
    @State private var showToast  = false
    @Environment(\.uiScale) private var scale

    private let isIOS: Bool = {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── Background ─────────────────────────────────────────────
                Color.black.ignoresSafeArea()
                CyberpunkGrid()

                RadialGradient(
                    colors: [.clear, .black.opacity(0.5)],
                    center: .center,
                    startRadius: min(geo.size.width, geo.size.height) * 0.35,
                    endRadius:   min(geo.size.width, geo.size.height) * 1.05
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                // ── Main layout: title + fixed grid + pinned buttons ────────
                VStack(spacing: 0) {

                    // Title
                    VStack(spacing: 4) {
                        Text("PHOTO BOOTH")
                            .font(.custom("Audiowide-Regular", size: 30 * scale))
                            .foregroundColor(.white)
                            .shadow(color: .cyan, radius: 14)
                            .shadow(color: .cyan.opacity(0.35), radius: 32)

                        Text("\(photoBooth.capturedPhotos.count) OF 4 MOMENTS CAPTURED")
                            .font(.custom("Audiowide-Regular", size: 10 * scale))
                            .foregroundColor(.white.opacity(0.40))
                            .tracking(3)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 14)
                    .scaleEffect(appeared ? 1 : 0.85)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: appeared)

                    // Photo grid — occupies ALL space between title and buttons.
                    // GeometryReader measures exactly what's left so we can
                    // compute per-slot dimensions without guessing.
                    GeometryReader { gridGeo in
                        let hPad:    CGFloat = 20
                        let vPad:    CGFloat = 6
                        let spacing: CGFloat = 10
                        let slotW = (gridGeo.size.width  - 2 * hPad - spacing) / 2
                        let slotH = (gridGeo.size.height - 2 * vPad - spacing) / 2

                        VStack(spacing: spacing) {
                            HStack(spacing: spacing) {
                                photoSlot(index: 0, slotWidth: slotW, slotHeight: slotH)
                                photoSlot(index: 1, slotWidth: slotW, slotHeight: slotH)
                            }
                            HStack(spacing: spacing) {
                                photoSlot(index: 2, slotWidth: slotW, slotHeight: slotH)
                                photoSlot(index: 3, slotWidth: slotW, slotHeight: slotH)
                            }
                        }
                        .padding(.horizontal, hPad)
                        .padding(.vertical, vPad)
                    }
                    .frame(maxHeight: .infinity)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.45).delay(0.12), value: appeared)

                    // Pinned buttons — always visible at the bottom
                    VStack(spacing: 10) {
                        if gameManager.isCoopMode {
                            // Co-op: same three buttons as Versus
                            HStack(spacing: 16) {
                                MenuHandButton(
                                    label: "SAVE ALL",
                                    color: .cyan,
                                    tracker: tracker,
                                    screenSize: geo.size
                                ) {
                                    photoBooth.saveAllToLibrary { success in
                                        saveResult = success
                                        showToast  = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                            showToast = false
                                        }
                                    }
                                }
                                MenuHandButton(
                                    label: "PLAY AGAIN",
                                    color: .magenta,
                                    tracker: tracker,
                                    screenSize: geo.size
                                ) {
                                    photoBooth.reset()
                                    gameManager.beginCoopCalibration()
                                }
                                MenuHandButton(
                                    label: "HOME",
                                    color: Color(white: 0.55),
                                    tracker: tracker,
                                    screenSize: geo.size
                                ) {
                                    photoBooth.reset()
                                    gameManager.resetToStart()
                                }
                            }
                        } else {
                            // Versus: all three in one row
                            HStack(spacing: 16) {
                                MenuHandButton(
                                    label: "SAVE ALL",
                                    color: .cyan,
                                    tracker: tracker,
                                    screenSize: geo.size
                                ) {
                                    photoBooth.saveAllToLibrary { success in
                                        saveResult = success
                                        showToast  = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                            showToast = false
                                        }
                                    }
                                }
                                MenuHandButton(
                                    label: "PLAY AGAIN",
                                    color: .magenta,
                                    tracker: tracker,
                                    screenSize: geo.size
                                ) {
                                    photoBooth.reset()
                                    gameManager.beginCalibration()
                                }
                                MenuHandButton(
                                    label: "HOME",
                                    color: Color(white: 0.55),
                                    tracker: tracker,
                                    screenSize: geo.size
                                ) {
                                    photoBooth.reset()
                                    gameManager.resetToStart()
                                }
                            }
                        }

                        Text("")
                            .font(.custom("Audiowide-Regular", size: 9 * scale))
                            .foregroundColor(.white.opacity(0.25))
                            .tracking(3)
                    }
                    .padding(.vertical, 16)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.25), value: appeared)
                }

                // ── Hand cursors ───────────────────────────────────────────
                if tracker.handsP1.count > 0 { HandCursor(hand: tracker.handsP1[0], color: .cyan,    size: geo.size) }
                if tracker.handsP1.count > 1 { HandCursor(hand: tracker.handsP1[1], color: .cyan,    size: geo.size) }
                if tracker.handsP2.count > 0 { HandCursor(hand: tracker.handsP2[0], color: .magenta, size: geo.size) }
                if tracker.handsP2.count > 1 { HandCursor(hand: tracker.handsP2[1], color: .magenta, size: geo.size) }

                // ── Save toast — floats above the button row ───────────────
                if showToast {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: saveResult == true
                                  ? "checkmark.circle.fill"
                                  : "exclamationmark.triangle.fill")
                            Text(saveResult == true
                                 ? (isIOS ? "SAVED TO LIBRARY" : "SAVED TO FOLDER")
                                 : "SAVE FAILED")
                                .font(.custom("Audiowide-Regular", size: 12 * scale))
                                .tracking(2)
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(saveResult == true ? Color.cyan : Color.red)
                        .cornerRadius(8)
                        .shadow(color: (saveResult == true ? Color.cyan : Color.red).opacity(0.7),
                                radius: 14)
                        .padding(.bottom, 110)   // sit just above the button row
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: showToast)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { appeared = true }
    }

    // MARK: - Photo Slot

    @ViewBuilder
    private func photoSlot(index: Int, slotWidth: CGFloat, slotHeight: CGFloat) -> some View {
        let hasPhoto    = index < photoBooth.capturedPhotos.count
        let isEven      = index % 2 == 0
        let borderColor: Color = isEven ? .cyan : .magenta

        ZStack(alignment: .topTrailing) {
            // Border + tinted background
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(hasPhoto ? 0.03 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            borderColor.opacity(hasPhoto ? 0.85 : 0.20),
                            lineWidth: hasPhoto ? 1.5 : 1.0
                        )
                )

            if hasPhoto {
                // scaledToFit ensures the whole photo is always visible (no cropping).
                photoBooth.capturedPhotos[index].swiftUIImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: slotWidth, height: slotHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                // Number badge
                Text("\(index + 1)")
                    .font(.custom("Audiowide-Regular", size: 8 * scale))
                    .foregroundColor(borderColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.65))
                    .cornerRadius(4)
                    .padding(6)

            } else {
                // Empty placeholder
                VStack(spacing: 6) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.12))
                    Text("—")
                        .font(.custom("Audiowide-Regular", size: 11))
                        .foregroundColor(.white.opacity(0.08))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: slotWidth, height: slotHeight)
        .scaleEffect(appeared ? 1 : 0.88)
        .animation(
            .spring(response: 0.45, dampingFraction: 0.72)
                .delay(0.06 * Double(index)),
            value: appeared
        )
    }
}
