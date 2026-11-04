#if DEBUG
import Metal
import QuartzCore
import SpriteKit
import UIKit

/// Gameplay footage for the website, from Xcode builds only; `scripts/store-capture.sh --footage` drives it. Launched
/// with a race's moment and `-ApexStoreFootage <before>,<after>` (`-ApexStoreCapture ghosts -ApexStoreFootage 3,7`),
/// the app stages the moment as for a screenshot, then plays its race a frame at a time, exactly 1/60 s apart, each
/// drawn off screen by an `SKRenderer`, which runs the scene's updates and actions (the skid marks' fade) on that same
/// clock, giving the main thread back between frames for what the race waits on. It saves the frames from `before` seconds ahead of the moment to `after` past it, with no HUD, as
/// Documents/StoreFootage/NNNNN.jpg at the screen's pixel size, then `done.txt`. Drawn rather than recorded live, the
/// footage never stutters however slowly the simulator draws, and a run repeats exactly: the race is seeded.
enum StoreFootage {
    /// Frames a second.
    static let rate = 60.0
    /// Seconds of racing to wait for the moment before giving up.
    static let limit = 150.0

    /// How much of the race around its moment is kept: `-ApexStoreFootage 3,7`.
    struct Window: Equatable {
        var before: Double
        var after: Double

        init(before: Double, after: Double) {
            self.before = before
            self.after = after
        }

        /// "3,7": seconds before the moment, then after it; nil for anything else.
        init?(_ text: String?) {
            let parts = (text ?? "").split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2, parts[0] >= 0, parts[1] > 0 else { return nil }
            self.init(before: parts[0], after: parts[1])
        }
    }

    @MainActor private static var came = false

    /// The moment has come (`StoreCapture.mark`): the frames from here on are its.
    @MainActor static func momentCame() { came = true }

    /// Records the race once SwiftUI has laid it out at the screen's size.
    @MainActor static func record(_ scene: RaceScene, window: Window) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            await play(scene, window: window)
        }
    }

    /// Plays the race a frame at a time, giving the main thread back between frames: what the race waits for comes back
    /// there (the bot rival, driven on its own queue, and the ideal line).
    @MainActor private static func play(_ scene: RaceScene, window: Window) async {
        let folder = URL.documentsDirectory.appending(path: "StoreFootage")
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let drawing = Drawing(scene) else { return StoreCapture.fail("couldn't set up Metal to draw the footage") }
        let lead = Int((window.before * rate).rounded()), tail = Int((window.after * rate).rounded())
        var clock = CACurrentMediaTime()
        // The last `lead` frames, until the moment comes; then how many are still to save.
        var waiting: [Data] = []
        var left: Int?
        var frame = 0, saved = 0, momentFrame = 0
        let started = Date()
        came = false
        func save(_ jpeg: Data) -> Bool {
            defer { saved += 1 }
            return (try? jpeg.write(to: folder.appending(path: String(format: "%05d.jpg", saved)))) != nil
        }
        while left != 0 {
            guard Double(frame) < limit * rate else {
                return StoreCapture.fail("the moment didn't come in \(Int(limit)) seconds of racing: \(scene.captureStatus)")
            }
            clock += 1 / rate
            guard let jpeg = drawing.frame(at: clock) else { return StoreCapture.fail("couldn't draw frame \(frame)") }
            frame += 1
            await Task.yield()
            if left == nil, came {
                momentFrame = frame
                for earlier in waiting where !save(earlier) { return StoreCapture.fail("couldn't save frame \(saved)") }
                waiting = []
                left = tail
            }
            if let remaining = left {
                guard save(jpeg) else { return StoreCapture.fail("couldn't save frame \(saved)") }
                left = remaining - 1
            } else {
                waiting.append(jpeg)
                if waiting.count > lead { waiting.removeFirst() }
            }
        }
        let summary = String(format: "%d frames of %dx%d at %.0f fps, the moment %.2f s into the race, drawn in %d s",
                             saved, drawing.width, drawing.height, rate, Double(momentFrame) / rate,
                             Int(Date().timeIntervalSince(started)))
        try? summary.write(to: folder.appending(path: "done.txt"), atomically: true, encoding: .utf8)
    }

    /// The scene, run and drawn off screen: the view stops drawing it, and an `SKRenderer` runs it instead, on the
    /// footage's clock. Filling rather than resizing, the scene keeps its size in points, drawn at the screen's pixels.
    @MainActor private struct Drawing {
        let width: Int
        let height: Int
        private let renderer: SKRenderer
        private let queue: MTLCommandQueue
        private let target: MTLTexture
        private let pixels: MTLBuffer
        private let pass = MTLRenderPassDescriptor()

        init?(_ scene: SKScene) {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
            let scale = scene.view?.contentScaleFactor ?? 3
            // Pausing the view pauses its scene too; the renderer runs only a scene that isn't.
            scene.view?.isPaused = true
            scene.isPaused = false
            scene.scaleMode = .aspectFill
            width = Int((scene.size.width * scale).rounded())
            height = Int((scene.size.height * scale).rounded())
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width,
                                                                      height: height, mipmapped: false)
            descriptor.usage = .renderTarget
            descriptor.storageMode = .private
            guard let target = device.makeTexture(descriptor: descriptor),
                  let pixels = device.makeBuffer(length: width * height * 4, options: .storageModeShared) else { return nil }
            self.queue = queue
            self.target = target
            self.pixels = pixels
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            renderer = SKRenderer(device: device)
            renderer.scene = scene
            renderer.ignoresSiblingOrder = scene.view?.ignoresSiblingOrder ?? true
        }

        /// Runs the scene to `clock` and draws it: a JPEG of the frame.
        func frame(at clock: TimeInterval) -> Data? {
            renderer.update(atTime: clock)
            guard let commands = queue.makeCommandBuffer() else { return nil }
            renderer.render(withViewport: CGRect(x: 0, y: 0, width: width, height: height), commandBuffer: commands,
                            renderPassDescriptor: pass)
            guard let blit = commands.makeBlitCommandEncoder() else { return nil }
            blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: width, height: height, depth: 1), to: pixels, destinationOffset: 0,
                      destinationBytesPerRow: width * 4, destinationBytesPerImage: width * height * 4)
            blit.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()
            return StoreFootage.jpeg(pixels, width: width, height: height)
        }
    }

    /// A frame's pixels (BGRA, as the renderer drew them) as a JPEG.
    fileprivate static func jpeg(_ pixels: MTLBuffer, width: Int, height: Int) -> Data? {
        let bytes = Data(bytes: pixels.contents(), count: width * height * 4)
        guard let provider = CGDataProvider(data: bytes as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                                                           | CGImageAlphaInfo.noneSkipFirst.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.92)
    }
}
#endif
