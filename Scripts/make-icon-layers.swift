#!/usr/bin/env swift
// Draws the layers of Packaging/AppIcon.icon (ADR-0016): a SpaceMouse seen from above whose cap has the finger dimple
// of a jog shuttle. Icon Composer adds the Liquid Glass; this only draws flat-ish shapes on a 1024 canvas.
// Usage: swift Scripts/make-icon-layers.swift <Assets folder>
import AppKit
import CoreGraphics

let size = 1024
let center = CGPoint(x: 512, y: 512)
let assets = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Packaging/AppIcon.icon/Assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
// Start from an empty folder, so layers that are no longer drawn do not linger.
for file in try FileManager.default.contentsOfDirectory(at: assets, includingPropertiesForKeys: nil)
where file.pathExtension == "png" {
    try FileManager.default.removeItem(at: file)
}

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

/// Draws into a transparent canvas with y pointing down (like SVG) and writes `name`.
func layer(_ name: String, draw: (CGContext) -> Void) {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: 1, y: -1)
    draw(context)
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: assets.appendingPathComponent(name))
}

func circle(_ radius: Double, at point: CGPoint = center) -> CGRect {
    CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius)
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: nil)!
}

let baseRadius = 410.0
let ledRadius = 318.0
let capRadius = 296.0

// The base: a dark graphite disc, lit from the upper left.
layer("base.png") { c in
    c.saveGState()
    c.addEllipse(in: circle(baseRadius))
    c.clip()
    c.drawLinearGradient(gradient([color(0.36, 0.38, 0.43), color(0.12, 0.13, 0.16)]),
                         start: CGPoint(x: 220, y: 140), end: CGPoint(x: 800, y: 900), options: [])
    c.restoreGState()
}

// The LED ring around the cap.
layer("led.png") { c in
    c.setShadow(offset: .zero, blur: 30, color: color(0.25, 0.60, 1.0, 1))
    c.setStrokeColor(color(0.45, 0.75, 1.0))
    c.setLineWidth(12)
    c.strokeEllipse(in: circle(ledRadius))
}

// The cap: a knurled rim and a smooth top.
layer("cap.png") { c in
    c.saveGState()
    c.addEllipse(in: circle(capRadius))
    c.clip()
    c.drawLinearGradient(gradient([color(0.30, 0.32, 0.37), color(0.08, 0.09, 0.11)]),
                         start: CGPoint(x: 280, y: 230), end: CGPoint(x: 740, y: 790), options: [])
    let ridges = 72
    for i in 0..<ridges {
        let a = Double(i) / Double(ridges) * 2 * .pi
        c.move(to: CGPoint(x: center.x + (capRadius - 34) * cos(a), y: center.y + (capRadius - 34) * sin(a)))
        c.addLine(to: CGPoint(x: center.x + capRadius * cos(a), y: center.y + capRadius * sin(a)))
    }
    c.setStrokeColor(color(0, 0, 0, 0.35))
    c.setLineWidth(7)
    c.strokePath()
    c.addEllipse(in: circle(capRadius - 40))
    c.clip()
    c.drawLinearGradient(gradient([color(0.38, 0.40, 0.46), color(0.14, 0.15, 0.18)]),
                         start: CGPoint(x: 300, y: 260), end: CGPoint(x: 720, y: 760), options: [])
    c.restoreGState()
}

// The jog shuttle's finger dimple: a hollow, lit from the lower right (the opposite of a dome).
layer("dimple.png") { c in
    let at = CGPoint(x: center.x + 118, y: center.y - 118)
    let radius = 78.0
    c.saveGState()
    c.addEllipse(in: circle(radius, at: at))
    c.clip()
    c.drawLinearGradient(gradient([color(0.03, 0.03, 0.04), color(0.22, 0.24, 0.28)]),
                         start: CGPoint(x: at.x - radius, y: at.y - radius),
                         end: CGPoint(x: at.x + radius, y: at.y + radius), options: [])
    c.restoreGState()
}
