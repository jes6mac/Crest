import SwiftUI
import UIKit

/// Tiles exist only for one visible block and are released when its transition ends.
struct MobileElementHidingSnapshot: View, Animatable {
    // MARK: - Types

    private struct Tile {
        let image: Image
        let frame: CGRect
        let drift: CGSize
        let delay: Double
    }

    // MARK: - Variables

    let id = UUID()
    private let tiles: [Tile]
    nonisolated private var progress: CGFloat = 0
    private var reduceMotion = false
    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    // MARK: - Initializers

    /// Crops a captured block into at most 100 in-memory tiles. Returns nil for missing pixels
    /// or an empty frame, allowing the caller to hide the element without an animation.
    init?(image: UIImage, frame: CGRect) {
        guard let pixels = image.cgImage, frame.width > 0, frame.height > 0 else { return nil }
        let columns = 10
        let rows = min(10, max(2, Int(frame.height / 36)))
        var result: [Tile] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let crop = CGRect(
                    x: CGFloat(column) * CGFloat(pixels.width) / CGFloat(columns),
                    y: CGFloat(row) * CGFloat(pixels.height) / CGFloat(rows),
                    width: CGFloat(pixels.width) / CGFloat(columns), height: CGFloat(pixels.height) / CGFloat(rows)
                ).integral
                guard let part = pixels.cropping(to: crop) else { continue }
                result.append(
                    Tile(
                        image: Image(decorative: part, scale: 1),
                        frame: CGRect(
                            x: frame.minX + frame.width * CGFloat(column) / CGFloat(columns),
                            y: frame.minY + frame.height * CGFloat(row) / CGFloat(rows),
                            width: frame.width / CGFloat(columns) + 0.5, height: frame.height / CGFloat(rows) + 0.5),
                        drift: CGSize(
                            width: 12 + Double((row * 7 + column * 11) % 32),
                            height: -8 - Double((row * 13 + column * 3) % 24)),
                        delay: Double(column) * 0.018))
            }
        }
        tiles = result
    }

    // MARK: - Actions - Rendering

    /// Reuses the captured tiles at the supplied animation progress. Reduced Motion keeps tiles
    /// in place and fades them instead of applying drift and shrinkage.
    func render(progress: CGFloat, reduceMotion: Bool) -> Self {
        var copy = self
        copy.progress = progress
        copy.reduceMotion = reduceMotion
        return copy
    }

    var body: some View {
        Canvas { context, _ in
            for tile in tiles {
                let phase = reduceMotion ? progress : min(1, max(0, (progress - tile.delay) / (1 - tile.delay)))
                var layer = context
                layer.opacity = Double(1 - phase)
                let rect =
                    reduceMotion
                    ? tile.frame
                    : tile.frame.offsetBy(dx: tile.drift.width * phase, dy: tile.drift.height * phase)
                        .insetBy(dx: tile.frame.width * phase * 0.18, dy: tile.frame.height * phase * 0.18)
                layer.draw(tile.image, in: rect)
            }
        }
    }
}
