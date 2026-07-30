import AppKit
import SwiftUI

struct HourglassMenuBarIcon: View {
    let isActive: Bool
    let elapsedFraction: Double

    @Environment(\.accessibilityReduceMotion)
    private var accessibilityReduceMotion

    var body: some View {
        Image(
            nsImage: HourglassMenuBarImage.make(
                isActive: isActive,
                elapsedFraction: elapsedFraction
            )
        )
        .renderingMode(.template)
        .resizable()
        .interpolation(.high)
        .frame(width: 16, height: 16)
        .rotationEffect(.degrees(isActive ? 180 : 0))
        .animation(
            accessibilityReduceMotion
                ? nil
                : .easeInOut(duration: 0.25),
            value: isActive
        )
        .accessibilityHidden(true)
    }
}

private enum HourglassMenuBarImage {
    private static let imageSize = NSSize(width: 16, height: 16)

    static func make(
        isActive: Bool,
        elapsedFraction: Double
    ) -> NSImage {
        let elapsed = min(1, max(0, elapsedFraction))
        let topFill = isActive ? elapsed : 0
        let bottomFill = isActive ? 1 - elapsed : 0.84

        let image = NSImage(
            size: imageSize,
            flipped: false
        ) { bounds in
            draw(
                in: bounds,
                topFill: topFill,
                bottomFill: bottomFill,
                showStream:
                    isActive && elapsed > 0 && elapsed < 1
            )
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func draw(
        in bounds: NSRect,
        topFill: Double,
        bottomFill: Double,
        showStream: Bool
    ) {
        let width = bounds.width
        let height = bounds.height
        let centerX = bounds.midX
        let neckY = bounds.midY
        let topBaseY = bounds.minY + height * 0.80
        let bottomBaseY = bounds.minY + height * 0.20
        let baseHalfWidth = width * 0.24
        let neckHalfWidth = width * 0.025

        NSColor.black.setFill()
        fillTopSand(
            fraction: topFill,
            centerX: centerX,
            neckY: neckY,
            baseY: topBaseY,
            baseHalfWidth: baseHalfWidth,
            neckHalfWidth: neckHalfWidth
        )
        fillBottomSand(
            fraction: bottomFill,
            centerX: centerX,
            neckY: neckY,
            baseY: bottomBaseY,
            baseHalfWidth: baseHalfWidth,
            neckHalfWidth: neckHalfWidth
        )

        if showStream {
            let stream = NSBezierPath()
            stream.move(
                to: NSPoint(
                    x: centerX,
                    y: neckY + height * 0.06
                )
            )
            stream.line(to: NSPoint(x: centerX, y: neckY))
            stream.lineWidth = max(0.75, width * 0.055)
            stream.lineCapStyle = .round
            stream.stroke()
        }

        let frame = NSBezierPath()
        frame.move(
            to: NSPoint(
                x: bounds.minX + width * 0.14,
                y: bounds.minY + height * 0.91
            )
        )
        frame.line(
            to: NSPoint(
                x: bounds.minX + width * 0.86,
                y: bounds.minY + height * 0.91
            )
        )
        frame.move(
            to: NSPoint(
                x: bounds.minX + width * 0.14,
                y: bounds.minY + height * 0.09
            )
        )
        frame.line(
            to: NSPoint(
                x: bounds.minX + width * 0.86,
                y: bounds.minY + height * 0.09
            )
        )
        frame.move(
            to: NSPoint(
                x: bounds.minX + width * 0.23,
                y: bounds.minY + height * 0.84
            )
        )
        frame.curve(
            to: NSPoint(x: centerX, y: neckY),
            controlPoint1: NSPoint(
                x: bounds.minX + width * 0.23,
                y: bounds.minY + height * 0.67
            ),
            controlPoint2: NSPoint(
                x: bounds.minX + width * 0.42,
                y: bounds.minY + height * 0.57
            )
        )
        frame.curve(
            to: NSPoint(
                x: bounds.minX + width * 0.23,
                y: bounds.minY + height * 0.16
            ),
            controlPoint1: NSPoint(
                x: bounds.minX + width * 0.42,
                y: bounds.minY + height * 0.43
            ),
            controlPoint2: NSPoint(
                x: bounds.minX + width * 0.23,
                y: bounds.minY + height * 0.33
            )
        )
        frame.move(
            to: NSPoint(
                x: bounds.minX + width * 0.77,
                y: bounds.minY + height * 0.84
            )
        )
        frame.curve(
            to: NSPoint(x: centerX, y: neckY),
            controlPoint1: NSPoint(
                x: bounds.minX + width * 0.77,
                y: bounds.minY + height * 0.67
            ),
            controlPoint2: NSPoint(
                x: bounds.minX + width * 0.58,
                y: bounds.minY + height * 0.57
            )
        )
        frame.curve(
            to: NSPoint(
                x: bounds.minX + width * 0.77,
                y: bounds.minY + height * 0.16
            ),
            controlPoint1: NSPoint(
                x: bounds.minX + width * 0.58,
                y: bounds.minY + height * 0.43
            ),
            controlPoint2: NSPoint(
                x: bounds.minX + width * 0.77,
                y: bounds.minY + height * 0.33
            )
        )
        NSColor.black.setStroke()
        frame.lineWidth = max(1, width * 0.075)
        frame.lineCapStyle = .round
        frame.lineJoinStyle = .round
        frame.stroke()
    }

    private static func fillTopSand(
        fraction: Double,
        centerX: Double,
        neckY: Double,
        baseY: Double,
        baseHalfWidth: Double,
        neckHalfWidth: Double
    ) {
        guard fraction > 0 else {
            return
        }

        let chamberHeight = baseY - neckY
        let sandHeight = chamberHeight * fraction.squareRoot()
        let surfaceY = neckY + sandHeight
        let widthProgress = sandHeight / chamberHeight
        let surfaceHalfWidth = neckHalfWidth
            + (baseHalfWidth - neckHalfWidth) * widthProgress

        let sand = NSBezierPath()
        sand.move(
            to: NSPoint(
                x: centerX - surfaceHalfWidth,
                y: surfaceY
            )
        )
        sand.line(
            to: NSPoint(
                x: centerX + surfaceHalfWidth,
                y: surfaceY
            )
        )
        sand.line(
            to: NSPoint(x: centerX + neckHalfWidth, y: neckY)
        )
        sand.line(
            to: NSPoint(x: centerX - neckHalfWidth, y: neckY)
        )
        sand.close()
        sand.fill()
    }

    private static func fillBottomSand(
        fraction: Double,
        centerX: Double,
        neckY: Double,
        baseY: Double,
        baseHalfWidth: Double,
        neckHalfWidth: Double
    ) {
        guard fraction > 0 else {
            return
        }

        let chamberHeight = neckY - baseY
        let unfilledHeight =
            chamberHeight * max(0, 1 - fraction).squareRoot()
        let surfaceY = neckY - unfilledHeight
        let widthProgress = unfilledHeight / chamberHeight
        let surfaceHalfWidth = neckHalfWidth
            + (baseHalfWidth - neckHalfWidth) * widthProgress

        let sand = NSBezierPath()
        sand.move(
            to: NSPoint(
                x: centerX - surfaceHalfWidth,
                y: surfaceY
            )
        )
        sand.line(
            to: NSPoint(
                x: centerX + surfaceHalfWidth,
                y: surfaceY
            )
        )
        sand.line(
            to: NSPoint(x: centerX + baseHalfWidth, y: baseY)
        )
        sand.line(
            to: NSPoint(x: centerX - baseHalfWidth, y: baseY)
        )
        sand.close()
        sand.fill()
    }
}
