#!/usr/bin/env swift
import AppKit
import Foundation

// Generates the Lumina app icon from the same geometry as `LuminaMark`.
// Run from the project root: `swift scripts/GenerateAppIcon.swift`.
// The result is a transparent 1024 pt canvas holding a dark rounded square,
// three ivory bars, and one warm beam of light.

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
let assetDirectory = root.appendingPathComponent("AppResources/Assets.xcassets", isDirectory: true)
let iconDirectory = assetDirectory.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
let accentDirectory = assetDirectory.appendingPathComponent("AccentColor.colorset", isDirectory: true)

try fileManager.createDirectory(at: iconDirectory, withIntermediateDirectories: true)
try fileManager.createDirectory(at: accentDirectory, withIntermediateDirectories: true)

struct IconVariant {
    let fileName: String
    let pixels: Int
}

let variants: [IconVariant] = [
    .init(fileName: "icon_16x16.png", pixels: 16),
    .init(fileName: "icon_16x16@2x.png", pixels: 32),
    .init(fileName: "icon_32x32.png", pixels: 32),
    .init(fileName: "icon_32x32@2x.png", pixels: 64),
    .init(fileName: "icon_128x128.png", pixels: 128),
    .init(fileName: "icon_128x128@2x.png", pixels: 256),
    .init(fileName: "icon_256x256.png", pixels: 256),
    .init(fileName: "icon_256x256@2x.png", pixels: 512),
    .init(fileName: "icon_512x512.png", pixels: 512),
    .init(fileName: "icon_512x512@2x.png", pixels: 1024)
]

func renderIcon(pixels: Int) -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Could not create a bitmap for \(pixels) px")
    }

    bitmap.size = NSSize(width: pixels, height: pixels)
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not create a graphics context")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    let size = CGFloat(pixels)
    let scale = size / 1024.0

    // The icon uses a 6.25% transparent margin, matching macOS's visual grid
    // without relying on the system to mask the artwork.
    let squareInset = 56.0 * scale
    let squareRect = NSRect(
        x: squareInset,
        y: squareInset,
        width: size - squareInset * 2,
        height: size - squareInset * 2
    )
    let cornerRadius = 202.0 * scale

    let ink = NSColor(srgbRed: 0x11 / 255.0, green: 0x19 / 255.0, blue: 0x20 / 255.0, alpha: 1)
    let ivory = NSColor(srgbRed: 0xED / 255.0, green: 0xE7 / 255.0, blue: 0xDB / 255.0, alpha: 1)
    let beam = NSColor(srgbRed: 0xD3 / 255.0, green: 0xA4 / 255.0, blue: 0x5E / 255.0, alpha: 1)

    let background = NSBezierPath(
        roundedRect: squareRect,
        xRadius: cornerRadius,
        yRadius: cornerRadius
    )
    ink.setFill()
    background.fill()

    // A hairline edge keeps the icon legible on near-black desktops.
    NSColor.white.withAlphaComponent(0.10).setStroke()
    background.lineWidth = max(1, 1.5 * scale)
    background.stroke()

    // Beam first so the bars stay crisp where the light passes behind them.
    let beamPath = NSBezierPath()
    beamPath.move(to: NSPoint(x: 318 * scale, y: 322 * scale))
    beamPath.line(to: NSPoint(x: 706 * scale, y: 700 * scale))
    beamPath.lineWidth = 34 * scale
    beamPath.lineCapStyle = .round
    beam.setStroke()
    beamPath.stroke()

    // A narrow ivory highlight on one edge of the beam gives it direction
    // without turning the icon into a glow effect.
    let beamHighlight = NSBezierPath()
    beamHighlight.move(to: NSPoint(x: 328 * scale, y: 334 * scale))
    beamHighlight.line(to: NSPoint(x: 700 * scale, y: 694 * scale))
    beamHighlight.lineWidth = 5 * scale
    beamHighlight.lineCapStyle = .round
    ivory.withAlphaComponent(0.42).setStroke()
    beamHighlight.stroke()

    let barWidth = 84 * scale
    let gap = 64 * scale
    let totalWidth = barWidth * 3 + gap * 2
    let startX = (size - totalWidth) / 2
    let heights: [CGFloat] = [0.40, 0.56, 0.40]

    for index in 0..<3 {
        let height = (size - squareInset * 2) * heights[index]
        let rect = NSRect(
            x: startX + CGFloat(index) * (barWidth + gap),
            y: (size - height) / 2,
            width: barWidth,
            height: height
        )
        let bar = NSBezierPath(
            roundedRect: rect,
            xRadius: barWidth / 2,
            yRadius: barWidth / 2
        )
        ivory.withAlphaComponent(index == 1 ? 1 : 0.80).setFill()
        bar.fill()
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode \(pixels) px icon")
    }
    return png
}

for variant in variants {
    let data = renderIcon(pixels: variant.pixels)
    try data.write(to: iconDirectory.appendingPathComponent(variant.fileName))
    print("wrote \(variant.fileName) (\(variant.pixels) px)")
}

let iconContents = """
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try iconContents.write(to: iconDirectory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

let accentContents = """
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.612",
          "green" : "0.435",
          "red" : "0.247"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try accentContents.write(to: accentDirectory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

let rootContents = """
{
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try rootContents.write(to: assetDirectory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

print("wrote AppIcon.appiconset, AccentColor.colorset, and catalog Contents.json")
