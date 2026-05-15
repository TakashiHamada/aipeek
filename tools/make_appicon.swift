#!/usr/bin/env swift

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AppKit

// MARK: - Configuration
let size: CGFloat = 1024

// Theme colors (must stay in sync with Sketch/UI/Theme.swift)
// Background: terracotta orange (app's main accent / active-tool color)
// Foreground: espresso brown (the dark color used for inactive tools)
let bg = CGColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)
let fg = CGColor(srgbRed: 0.24, green: 0.18, blue: 0.15, alpha: 1)

// MARK: - Build context
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("error: could not create CGContext\n", stderr)
    exit(1)
}

// Use the default (y-up math) coordinate system for clarity; AppIcon doesn't need a flip.
// Coordinate space: origin at bottom-left, y grows up.
// We'll author with center at (size/2, size/2).

let cx = size / 2
let cy = size / 2

// MARK: - Background fill (whole canvas — the OS rounds corners for us)
ctx.setFillColor(bg)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// MARK: - Eyes geometry
// Two vertically-oriented ovals sitting side-by-side, slightly overlapping in the
// middle (mirroring the FontAwesome reference). The pupils are circles inside,
// nudged toward the center to feel like the eyes are looking at each other / forward.

// Circles, not ovals — reads more like eyes, less like a snout.
let eyeDiameter: CGFloat = 460
let eyeWidth: CGFloat = eyeDiameter
let eyeHeight: CGFloat = eyeDiameter
let eyeSpacing: CGFloat = 360 // center-to-center horizontal distance (slight overlap)

let leftEyeCenter = CGPoint(x: cx - eyeSpacing / 2, y: cy)
let rightEyeCenter = CGPoint(x: cx + eyeSpacing / 2, y: cy)

// MARK: - Draw eye whites (espresso ovals filled, looking like the FA silhouette)
// We use a single combined path so any overlap fills cleanly.
ctx.setFillColor(fg)
let eyeWhitesPath = CGMutablePath()
eyeWhitesPath.addEllipse(in: CGRect(
    x: leftEyeCenter.x - eyeWidth / 2,
    y: leftEyeCenter.y - eyeHeight / 2,
    width: eyeWidth,
    height: eyeHeight
))
eyeWhitesPath.addEllipse(in: CGRect(
    x: rightEyeCenter.x - eyeWidth / 2,
    y: rightEyeCenter.y - eyeHeight / 2,
    width: eyeWidth,
    height: eyeHeight
))
ctx.addPath(eyeWhitesPath)
ctx.fillPath()

// MARK: - Pupils as "knock-out" holes (background-colored circles punched through)
// In the FA reference each eye has a bg-colored ring/scoop that reveals the bg
// behind it, leaving only the rim of the eye visible on the inside edge.
let pupilRadius: CGFloat = 140
// Pupils tuck toward each other (looking inward) but a bit downward — peek vibe.
let leftPupilCenter = CGPoint(x: leftEyeCenter.x + 40, y: leftEyeCenter.y - 10)
let rightPupilCenter = CGPoint(x: rightEyeCenter.x - 40, y: rightEyeCenter.y - 10)

ctx.setFillColor(bg)
ctx.fillEllipse(in: CGRect(
    x: leftPupilCenter.x - pupilRadius,
    y: leftPupilCenter.y - pupilRadius,
    width: pupilRadius * 2,
    height: pupilRadius * 2
))
ctx.fillEllipse(in: CGRect(
    x: rightPupilCenter.x - pupilRadius,
    y: rightPupilCenter.y - pupilRadius,
    width: pupilRadius * 2,
    height: pupilRadius * 2
))

// MARK: - Inner solid pupil dot in espresso
// Smaller filled circle in the center-ish of the bg knockout, completing the FA look.
let innerPupilRadius: CGFloat = 85
ctx.setFillColor(fg)
ctx.fillEllipse(in: CGRect(
    x: leftPupilCenter.x - innerPupilRadius,
    y: leftPupilCenter.y - innerPupilRadius,
    width: innerPupilRadius * 2,
    height: innerPupilRadius * 2
))
ctx.fillEllipse(in: CGRect(
    x: rightPupilCenter.x - innerPupilRadius,
    y: rightPupilCenter.y - innerPupilRadius,
    width: innerPupilRadius * 2,
    height: innerPupilRadius * 2
))

// MARK: - Eyelashes
// Two espresso lashes per eye, fanning OUTWARD from the upper edge.
// In this y-up context the top of an eye is at +y (= cy + radius);
// outer side of each eye is away from the icon center on the x axis.
ctx.setStrokeColor(fg)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setLineWidth(28)

func drawLashes(eyeCenter: CGPoint, mirror: Bool) {
    let radius = eyeWidth / 2
    // Two lashes per eye: one upper-outer, one further-outer. Angles are measured
    // from +x; top of the circle is at +π/2. For the LEFT eye (mirror=false)
    // outer = left side, i.e. angles greater than π/2.
    // For the right eye (mirror=true) we reflect across the vertical axis.
    let raw: [(angle: CGFloat, length: CGFloat, bend: CGFloat)] = [
        (angle: .pi / 2 + 0.15, length: 120, bend: -0.05),   // near the top, almost straight up
        (angle: .pi / 2 + 0.55, length: 135, bend: -0.30),   // middle of the fan, longest
        (angle: .pi / 2 + 0.95, length: 105, bend: -0.55),   // outermost, curls out
    ]

    for entry in raw {
        let baseAngle: CGFloat = mirror ? (.pi - entry.angle) : entry.angle
        let signedBend = mirror ? -entry.bend : entry.bend
        let length = entry.length

        let anchor = CGPoint(
            x: eyeCenter.x + radius * cos(baseAngle),
            y: eyeCenter.y + radius * sin(baseAngle)
        )
        let outDx = cos(baseAngle)
        let outDy = sin(baseAngle)
        // Tangent (CCW). In y-up rotating (outDx,outDy) by +90° gives (-outDy,outDx).
        let tanDx = -outDy
        let tanDy = outDx

        let tip = CGPoint(
            x: anchor.x + outDx * length + tanDx * signedBend * length * 0.6,
            y: anchor.y + outDy * length + tanDy * signedBend * length * 0.6
        )
        let ctrl = CGPoint(
            x: anchor.x + outDx * length * 0.55,
            y: anchor.y + outDy * length * 0.55
        )

        let p = CGMutablePath()
        p.move(to: anchor)
        p.addQuadCurve(to: tip, control: ctrl)
        ctx.addPath(p)
        ctx.strokePath()
    }
}

drawLashes(eyeCenter: leftEyeCenter, mirror: false)
drawLashes(eyeCenter: rightEyeCenter, mirror: true)

// MARK: - Output
guard let cgImage = ctx.makeImage() else {
    fputs("error: could not make image\n", stderr)
    exit(1)
}

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon-1024.png"
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(
    url as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fputs("error: could not create CGImageDestination\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(dest, cgImage, nil)
if !CGImageDestinationFinalize(dest) {
    fputs("error: could not finalize PNG\n", stderr)
    exit(1)
}
print("wrote \(url.path)")
