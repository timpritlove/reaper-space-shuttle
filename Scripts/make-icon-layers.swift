#!/usr/bin/env swift
// Draws the layers of Packaging/AppIcon.icon (ADR-0016): a SpaceMouse as it stands on a desk, seen from the front and
// above, whose cap has the finger dimple of a jog shuttle. Icon Composer adds the Liquid Glass; this only draws flat-ish shapes on a 1024 canvas.
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

// Seen from the front and above, as it stands on a desk: circles become ellipses squashed by `tilt`, and heights
// show as vertical bands.
let tilt = 0.58

/// An ellipse for a circle of `radius` lying flat at screen height `y`.
func flat(_ radius: Double, y: Double, x: Double = center.x) -> CGRect {
    CGRect(x: x - radius, y: y - radius * tilt, width: 2 * radius, height: 2 * radius * tilt)
}

/// The outline of an upright cylinder (or a cone section) from its top and bottom ellipses.
func upright(top: Double, topRadius: Double, bottom: Double, bottomRadius: Double) -> CGPath {
    let path = CGMutablePath()
    path.addEllipse(in: flat(topRadius, y: top))
    path.addEllipse(in: flat(bottomRadius, y: bottom))
    path.addLines(between: [CGPoint(x: center.x - topRadius, y: top), CGPoint(x: center.x + topRadius, y: top),
                            CGPoint(x: center.x + bottomRadius, y: bottom), CGPoint(x: center.x - bottomRadius, y: bottom)])
    path.closeSubpath()
    return path
}

// The base like the original: one rounded body of revolution, brushed aluminium below and black plastic above,
// meeting flush; the cap stands on its flat black top.
let baseBottom = 660.0, baseHeight = 184.0, baseFoot = 426.0, baseShoulder = 312.0
/// Fraction of the height (from the desk) where the metal ends and the black plastic begins.
let metalEnds = 0.72
let baseTop = baseBottom - baseHeight
let capTop = 330.0, capBottom = baseTop - 4, capRadius = 268.0
let ledRadius = 284.0

/// The base's radius at `t` (0 = desk, 1 = top): convex, steep at the desk, rounding in towards the top.
func baseRadius(at t: Double) -> Double {
    baseShoulder + (baseFoot - baseShoulder) * pow(cos(t * .pi / 2), 0.7)
}

/// Fills `path` with a gradient across the width, darker at the edges like a lit cylinder.
func cylinderSide(_ c: CGContext, _ path: CGPath, radius: Double, colors: [CGColor]) {
    c.saveGState()
    c.addPath(path)
    c.clip()
    c.drawLinearGradient(gradient(colors), start: CGPoint(x: center.x - radius, y: 0),
                         end: CGPoint(x: center.x + radius, y: 0), options: [])
    c.restoreGState()
}

// A soft contact shadow on the desk.
layer("shadow.png") { c in
    c.setShadow(offset: .zero, blur: 40, color: color(0, 0, 0, 0.55))
    c.setFillColor(color(0, 0, 0, 0.55))
    c.fillEllipse(in: flat(baseFoot + 10, y: baseBottom + 10))
}

// The base, painted in thin slices from the desk up: each slice hides the inside of the ones below, so what stays
// visible is the front of the body, as seen from above.
layer("base.png") { c in
    let metal = gradient([
        color(0.38, 0.40, 0.43), color(0.80, 0.82, 0.85), color(0.97, 0.98, 0.99), color(0.62, 0.64, 0.68),
        color(0.88, 0.89, 0.91), color(0.99, 0.99, 1.00), color(0.70, 0.72, 0.75), color(0.42, 0.44, 0.47),
    ])
    let plastic = gradient([color(0.02, 0.02, 0.03), color(0.17, 0.18, 0.20), color(0.08, 0.08, 0.09),
                            color(0.01, 0.01, 0.02)])
    let slices = Int(baseHeight)
    for i in 0...slices {
        let t = Double(i) / Double(slices)
        let radius = baseRadius(at: t)
        let rect = flat(radius, y: baseBottom - t * baseHeight)
        c.saveGState()
        c.addEllipse(in: rect)
        c.clip()
        if i == slices {
            // The flat top around the cap.
            c.drawLinearGradient(gradient([color(0.05, 0.05, 0.06), color(0.20, 0.21, 0.24)]),
                                 start: CGPoint(x: center.x, y: rect.minY), end: CGPoint(x: center.x, y: rect.maxY),
                                 options: [])
        } else {
            c.drawLinearGradient(t < metalEnds ? metal : plastic, start: CGPoint(x: center.x - radius, y: 0),
                                 end: CGPoint(x: center.x + radius, y: 0), options: [])
            // The metal darkens towards the desk, where it turns away from the light.
            if t < metalEnds {
                c.setFillColor(color(0, 0, 0, 0.35 * (1 - t / metalEnds)))
                c.fill(rect)
            }
        }
        c.restoreGState()
    }
}

// The LED ring where the cap meets the base; its back half disappears behind the cap.
layer("led.png") { c in
    c.setShadow(offset: .zero, blur: 26, color: color(0.25, 0.60, 1.0, 1))
    c.setStrokeColor(color(0.45, 0.75, 1.0))
    c.setLineWidth(10)
    c.strokeEllipse(in: flat(ledRadius, y: capBottom + 2))
}

// The cap: a knurled cylinder with a smooth top.
layer("cap.png") { c in
    let side = upright(top: capTop, topRadius: capRadius, bottom: capBottom, bottomRadius: capRadius)
    cylinderSide(c, side, radius: capRadius, colors: [color(0.07, 0.07, 0.09), color(0.30, 0.32, 0.37),
                                                     color(0.18, 0.19, 0.22), color(0.05, 0.05, 0.06)])
    // Knurling on the front of the side: vertical ridges, closer together towards the edges.
    c.saveGState()
    c.addPath(side)
    c.clip()
    let ridges = 64
    for i in 0..<ridges where i % 2 == 0 {
        let a = Double(i) / Double(ridges) * .pi
        let x = center.x + capRadius * cos(a)
        let y = sin(a) * capRadius * tilt
        c.move(to: CGPoint(x: x, y: capTop + y + 6))
        c.addLine(to: CGPoint(x: x, y: capBottom + y))
    }
    c.setStrokeColor(color(0, 0, 0, 0.35))
    c.setLineWidth(5)
    c.strokePath()
    c.restoreGState()
    // The top, lit from above and behind.
    c.saveGState()
    c.addEllipse(in: flat(capRadius, y: capTop))
    c.clip()
    c.drawLinearGradient(gradient([color(0.46, 0.48, 0.54), color(0.20, 0.21, 0.25)]),
                         start: CGPoint(x: center.x - capRadius, y: capTop - capRadius * tilt),
                         end: CGPoint(x: center.x + capRadius, y: capTop + capRadius * tilt), options: [])
    c.restoreGState()
}

// The jog shuttle's finger dimple on the cap: its far inner wall in shadow, the near one catching light.
layer("dimple.png") { c in
    let radius = 72.0
    let at = CGPoint(x: center.x + 100, y: capTop - 90 * tilt)
    let rect = CGRect(x: at.x - radius, y: at.y - radius * tilt, width: 2 * radius, height: 2 * radius * tilt)
    c.saveGState()
    c.addEllipse(in: rect)
    c.clip()
    c.drawLinearGradient(gradient([color(0.03, 0.03, 0.04), color(0.10, 0.11, 0.13), color(0.30, 0.32, 0.37)]),
                         start: CGPoint(x: at.x, y: rect.minY), end: CGPoint(x: at.x, y: rect.maxY), options: [])
    c.restoreGState()
}
