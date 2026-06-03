//
//  PhotoBoothManager.swift
//  NeonCatch
//
//  Created by Yousefzadeh Abbas on 19/05/26.
//

import SwiftUI
import CoreImage
import CoreText
import ImageIO
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
import Photos
#else
import AppKit
#endif

// MARK: - Platform Image Type Alias

#if os(iOS)
typealias BoothImage = UIImage
#else
typealias BoothImage = NSImage
#endif

extension BoothImage {
    /// Wraps the platform image as a SwiftUI Image for display in views.
    var swiftUIImage: Image {
        #if os(iOS)
        return Image(uiImage: self)
        #else
        return Image(nsImage: self)
        #endif
    }
}

// MARK: - Photo Booth Manager
// Captures 4 screenshots during a round, all taken at random moments
// spread between second 5 and second 55 of the game.
// Each capture applies the cyberpunk camera filter and stamps a #GRABEAT watermark.

@MainActor
final class PhotoBoothManager: ObservableObject {

    // MARK: - Published
    let maxPhotos = 4

    @Published var capturedPhotos: [BoothImage] = []
    /// Briefly true after each capture — GameView uses this to flash the screen.
    @Published var flashTriggered = false

    // MARK: - Private state

    private var obstaclePhotosTaken = 0
    private var randomPhotosTaken   = 0
    private weak var tracker: CameraHandTracker?

    /// Each game session gets a unique token. Pending asyncAfter blocks check this
    /// before firing — if the token no longer matches, the capture is silently dropped.
    private var captureToken: UUID? = nil

    // MARK: - Setup

    func setup(tracker: CameraHandTracker) {
        self.tracker = tracker
    }

    // MARK: - Game lifecycle

    /// Call when the round starts. Resets counters and schedules random captures.
    func startCaptures(gameDuration: Int) {
        capturedPhotos      = []
        obstaclePhotosTaken = 0
        randomPhotosTaken   = 0
        let token = UUID()
        captureToken = token
        scheduleRandomCaptures(duration: Double(gameDuration), token: token)
    }

    /// Call when the game ends (transitions away from .playing / .coopPlaying).
    /// Cancels any pending captures without clearing the already-taken photos.
    func stopCaptures() {
        captureToken = nil
    }

    /// Clears everything (call when returning to the start screen).
    func reset() {
        captureToken        = nil
        capturedPhotos      = []
        obstaclePhotosTaken = 0
        randomPhotosTaken   = 0
    }

    // MARK: - Obstacle-triggered capture

    /// All photos are now scheduled randomly; this is intentionally a no-op.
    func onObstacleActivated() { }

    // MARK: - Random capture scheduling

    private func scheduleRandomCaptures(duration: Double, token: UUID) {
        // All 4 photos are taken at random moments between second 5 and second 55.
        let earliest: Double = 5.0
        let latest:   Double = min(55.0, max(earliest + 5.0, duration - 5.0))

        let times = (0..<maxPhotos)
            .map { _ in Double.random(in: earliest...latest) }
            .sorted()

        for t in times {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
                guard let self,
                      self.captureToken == token,          // game still active
                      self.capturedPhotos.count < self.maxPhotos else { return }
                self.capturePhoto()
                self.randomPhotosTaken += 1
            }
        }
    }

    // MARK: - Capture
    // Uses CGImage / CGContext — no UIKit dependency, works on iOS and macOS.

    private func capturePhoto() {
        guard capturedPhotos.count < maxPhotos else { return }
        guard let cgImage = tracker?.captureCurrentFrame() else { return }
        let filtered = applyCyberpunkFilter(to: cgImage)
        capturedPhotos.append(filtered)
        triggerFlash()
    }

    private func triggerFlash() {
        flashTriggered = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.flashTriggered = false
        }
    }

    // MARK: - Cyberpunk Filter (CoreGraphics — iOS + macOS)
    // Replicates CyberpunkCameraFilter using only CGContext APIs:
    //   1. Base camera image
    //   2. Pink→purple→cyan diagonal gradient overlay
    //   3. Horizontal scanlines every 4 px
    //   4. Dark radial vignette
    //   5. Cyan left-edge glow  /  Magenta right-edge glow
    //   6. #GRABEAT watermark (bottom-right, cyan neon)

    private func applyCyberpunkFilter(to source: CGImage) -> BoothImage {
        let w  = CGFloat(source.width)
        let h  = CGFloat(source.height)
        let cs = CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(
            data: nil, width: source.width, height: source.height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).rawValue
        ) else { return boothImage(source, w, h) }

        // 1. Draw base image.
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))

        // 2. Gradient: pink (top-right = w,h) → purple → cyan (bottom-left = 0,0).
        let mainC: [CGColor] = [
            CGColor(red: 1.00, green: 0.05, blue: 0.75, alpha: 0.14),
            CGColor(red: 0.55, green: 0.00, blue: 1.00, alpha: 0.10),
            CGColor(red: 0.00, green: 0.85, blue: 1.00, alpha: 0.14),
        ]
        if let g = CGGradient(colorsSpace: cs, colors: mainC as CFArray,
                               locations: [0, 0.5, 1] as [CGFloat]) {
            ctx.drawLinearGradient(g,
                start: CGPoint(x: w, y: h), end: .zero, options: [])
        }

        // 3. Scanlines.
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.10))
        var sy: CGFloat = 0
        while sy < h { ctx.fill(CGRect(x: 0, y: sy, width: w, height: 1)); sy += 4 }

        // 4. Vignette.
        let cx = w / 2, cy = h / 2, r = min(w, h)
        let vigC: [CGColor] = [
            CGColor(red: 0, green: 0, blue: 0, alpha: 0),
            CGColor(red: 0, green: 0, blue: 0, alpha: 0.48),
        ]
        if let vg = CGGradient(colorsSpace: cs, colors: vigC as CFArray,
                                locations: [0.45, 1.10] as [CGFloat]) {
            ctx.drawRadialGradient(vg,
                startCenter: CGPoint(x: cx, y: cy), startRadius: r * 0.45,
                endCenter:   CGPoint(x: cx, y: cy), endRadius:   r * 1.10,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }

        // 5. Cyan left-edge glow.
        let cyanC: [CGColor] = [
            CGColor(red: 0.0, green: 0.85, blue: 1.0, alpha: 0.22),
            CGColor(red: 0, green: 0, blue: 0, alpha: 0),
        ]
        if let cg = CGGradient(colorsSpace: cs, colors: cyanC as CFArray,
                                locations: [0, 1] as [CGFloat]) {
            ctx.drawLinearGradient(cg,
                start: CGPoint(x: 0, y: cy), end: CGPoint(x: w * 0.35, y: cy), options: [])
        }

        // 6. Magenta right-edge glow.
        let magC: [CGColor] = [
            CGColor(red: 0, green: 0, blue: 0, alpha: 0),
            CGColor(red: 1.0, green: 0.0, blue: 0.65, alpha: 0.22),
        ]
        if let mg = CGGradient(colorsSpace: cs, colors: magC as CFArray,
                                locations: [0, 1] as [CGFloat]) {
            ctx.drawLinearGradient(mg,
                start: CGPoint(x: w * 0.65, y: cy), end: CGPoint(x: w, y: cy), options: [])
        }

        // 7. #GRABEAT watermark — bottom-right, cyan neon, so shared photos are branded.
        let tag      = "#GRABEAT" as CFString
        let fontSize = max(20.0, w * 0.028)
        let ctFont   = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let tagAttrs: CFDictionary = [
            kCTFontAttributeName:            ctFont,
            kCTForegroundColorAttributeName: CGColor(red: 0.0, green: 0.85, blue: 1.0, alpha: 0.90)
        ] as CFDictionary
        let attrStr = CFAttributedStringCreate(nil, tag, tagAttrs)!
        let ctLine  = CTLineCreateWithAttributedString(attrStr)
        let bounds  = CTLineGetBoundsWithOptions(ctLine, [])
        let tagPad  = w * 0.025
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 10,
                      color: CGColor(red: 0.0, green: 0.85, blue: 1.0, alpha: 0.95))
        ctx.textPosition = CGPoint(x: w - bounds.width - tagPad, y: tagPad)
        CTLineDraw(ctLine, ctx)
        ctx.restoreGState()

        guard let result = ctx.makeImage() else { return boothImage(source, w, h) }
        return boothImage(result, w, h)
    }

    /// Wraps a CGImage into the platform's native image type.
    private func boothImage(_ cg: CGImage, _ w: CGFloat, _ h: CGFloat) -> BoothImage {
        #if os(iOS)
        return UIImage(cgImage: cg)
        #else
        return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
        #endif
    }

    // MARK: - Save to Photo Library / Disk

    /// iOS  – saves all captured photos to the device's photo library.
    ///        Requires NSPhotoLibraryAddUsageDescription in Info.plist.
    /// macOS – writes numbered PNGs into the user's chosen folder (remembered after first pick).
    func saveAllToLibrary(completion: @escaping (Bool) -> Void) {
        #if os(iOS)

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let self,
                  status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }

            let photos = self.capturedPhotos

            PHPhotoLibrary.shared().performChanges({
                for photo in photos {
                    PHAssetChangeRequest.creationRequestForAsset(from: photo)
                }
            }, completionHandler: { success, error in
                if let error {
                    print("iOS save error:", error.localizedDescription)
                }
                DispatchQueue.main.async {
                    completion(success)
                }
            })
        }

        #else
        saveToDesktopMacOS(completion: completion)
        #endif
    }

    // MARK: - macOS Save
    // The app is sandboxed (App Store requirement).
    // Strategy: on the very first save, show NSOpenPanel so the user picks a folder once.
    // That folder is persisted as a security-scoped bookmark in UserDefaults.
    // Every subsequent save goes straight to that folder — no panel, no interruption.

    private static let bookmarkKey = "PhotoBooth.savedFolderBookmark"

    #if os(macOS)
    private func saveToDesktopMacOS(completion: @escaping (Bool) -> Void) {
        guard !capturedPhotos.isEmpty else {
            print("[PhotoBooth] No photos to save")
            completion(false)
            return
        }

        // Try to restore a previously-chosen folder from the bookmark
        if let bookmarkData = UserDefaults.standard.data(forKey: Self.bookmarkKey),
           let folderURL = resolveBookmark(bookmarkData) {
            writePhotos(to: folderURL, completion: completion)
        } else {
            // First time: ask the user to pick a folder, then save the bookmark
            pickFolderAndSave(completion: completion)
        }
    }

    /// Resolves a stored security-scoped bookmark back to a URL.
    private func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        if isStale {
            // Bookmark is stale — drop it and let the panel re-pick next time
            UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
            return nil
        }
        return url
    }

    /// Shows NSOpenPanel once, saves a security-scoped bookmark, then writes photos.
    private func pickFolderAndSave(completion: @escaping (Bool) -> Void) {
        let panel = NSOpenPanel()
        panel.title                   = "Choose Photo Save Folder"
        panel.message                 = "Photos will always be saved here — you won't be asked again."
        panel.prompt                  = "Choose"
        panel.canChooseFiles          = false
        panel.canChooseDirectories    = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories    = true

        let photos = capturedPhotos

        panel.begin { [weak self] response in
            guard response == .OK, let folderURL = panel.url else {
                print("[PhotoBooth] Folder picker cancelled")
                DispatchQueue.main.async { completion(false) }
                return
            }

            // Persist as a security-scoped bookmark so future saves skip the panel
            if let bookmark = try? folderURL.bookmarkData(options: .withSecurityScope) {
                UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
                print("[PhotoBooth] Bookmark saved for: \(folderURL.lastPathComponent)")
            }

            self?.writePhotos(to: folderURL, photos: photos, completion: completion)
        }
    }

    /// Writes photos into folderURL and calls completion. Never opens Finder.
    private func writePhotos(
        to folderURL: URL,
        photos: [BoothImage]? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        let images = photos ?? capturedPhotos

        // Security-scoped resource access is required for bookmarked URLs
        let accessing = folderURL.startAccessingSecurityScopedResource()
        defer { if accessing { folderURL.stopAccessingSecurityScopedResource() } }

        // Each save session gets a date prefix + short UUID so files never collide,
        // even if you save multiple rounds within the same second.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let datePart  = formatter.string(from: Date())
        let uuidPart  = UUID().uuidString.prefix(6)   // e.g. "A3F2C1"
        let sessionID = "\(datePart)_\(uuidPart)"     // e.g. "2026-05-20_15-30-45_A3F2C1"

        var saved = 0
        for (i, nsImage) in images.enumerated() {
            let fileURL = folderURL.appendingPathComponent("GraBeat_\(sessionID)_\(i + 1).png")

            var rect = NSRect(origin: .zero, size: nsImage.size)
            guard let cgImg = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
                print("[PhotoBooth] Photo \(i + 1): cgImage() returned nil")
                continue
            }
            let rep = NSBitmapImageRep(cgImage: cgImg)
            guard let png = rep.representation(using: .png, properties: [:]) else {
                print("[PhotoBooth] Photo \(i + 1): PNG conversion failed")
                continue
            }
            do {
                try png.write(to: fileURL, options: .atomic)
                print("[PhotoBooth] Photo \(i + 1): saved → \(fileURL.lastPathComponent)")
                saved += 1
            } catch {
                print("[PhotoBooth] Photo \(i + 1): write error: \(error)")
            }
        }

        print("[PhotoBooth] \(saved)/\(images.count) saved to '\(folderURL.lastPathComponent)'")
        DispatchQueue.main.async { completion(saved > 0) }
    }
    #endif // os(macOS)
}
