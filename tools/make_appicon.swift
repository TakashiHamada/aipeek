#!/usr/bin/env swift

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AppKit

// MARK: - Configuration
let size: CGFloat = 1024

// Theme colors (must stay in sync with Sketch/UI/Theme.swift)
let creamBG = CGColor(srgbRed: 0.93, green: 0.90, blue: 0.83, alpha: 1)
let terracotta = CGColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)
let espresso = CGColor(srgbRed: 0.24, green: 0.18, blue: 0.15, alpha: 1)

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

// Flip coordinate system so y goes down (top-left origin, matches UIKit)
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

// MARK: - Background
ctx.setFillColor(creamBG)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// MARK: - Main stroke: bold cursive "S" in terracotta
ctx.setStrokeColor(terracotta)
ctx.setLineWidth(140)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

let s = CGMutablePath()
s.move(to: CGPoint(x: 720, y: 280))
// top arc of S (bulge upward)
s.addCurve(to: CGPoint(x: 320, y: 350),
           control1: CGPoint(x: 720, y: 100),
           control2: CGPoint(x: 280, y: 100))
// middle diagonal sweep
s.addCurve(to: CGPoint(x: 704, y: 674),
           control1: CGPoint(x: 360, y: 600),
           control2: CGPoint(x: 730, y: 460))
// bottom arc of S (bulge downward)
s.addCurve(to: CGPoint(x: 304, y: 744),
           control1: CGPoint(x: 730, y: 950),
           control2: CGPoint(x: 290, y: 900))

ctx.addPath(s)
ctx.strokePath()

// MARK: - Accent: small espresso dot near the top (like an ink drop / sketch flourish)
ctx.setFillColor(espresso)
ctx.fillEllipse(in: CGRect(x: 800, y: 200, width: 60, height: 60))

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
