import AppKit
import Foundation

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesURL = rootURL.appendingPathComponent("AppResources", isDirectory: true)
let iconSetURL = resourcesURL.appendingPathComponent("SleepLatch.iconset", isDirectory: true)
let iconURL = resourcesURL.appendingPathComponent("SleepLatch.icns")

let iconSpecs: [(name: String, points: CGFloat, icnsType: String?)] = [
    ("icon_16x16.png", 16, "icp4"),
    ("icon_16x16@2x.png", 32, "icp5"),
    ("icon_32x32.png", 32, nil),
    ("icon_32x32@2x.png", 64, "icp6"),
    ("icon_128x128.png", 128, "ic07"),
    ("icon_128x128@2x.png", 256, "ic08"),
    ("icon_256x256.png", 256, nil),
    ("icon_256x256@2x.png", 512, "ic09"),
    ("icon_512x512.png", 512, nil),
    ("icon_512x512@2x.png", 1024, "ic10"),
]

try? FileManager.default.removeItem(at: iconSetURL)
try? FileManager.default.removeItem(at: iconURL)
try FileManager.default.createDirectory(at: iconSetURL, withIntermediateDirectories: true)

var icnsChunks: [(type: String, data: Data)] = []

for spec in iconSpecs {
    let image = try renderIcon(size: spec.points)
    let destinationURL = iconSetURL.appendingPathComponent(spec.name)
    let pngData = try pngData(for: image)
    try pngData.write(to: destinationURL)

    if let icnsType = spec.icnsType {
        icnsChunks.append((type: icnsType, data: pngData))
    }
}

try writeICNS(chunks: icnsChunks, to: iconURL)

func renderIcon(size: CGFloat) throws -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high

    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.225

    let basePath = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.07, green: 0.34, blue: 0.38, alpha: 1.0),
        NSColor(calibratedRed: 0.12, green: 0.53, blue: 0.55, alpha: 1.0),
    ])!
    gradient.draw(in: basePath, angle: -18)

    let glowRect = bounds.insetBy(dx: size * 0.07, dy: size * 0.07)
    let glowPath = NSBezierPath(roundedRect: glowRect, xRadius: size * 0.18, yRadius: size * 0.18)
    NSColor(calibratedWhite: 1.0, alpha: 0.12).setFill()
    glowPath.fill()

    let symbolConfig = NSImage.SymbolConfiguration(pointSize: size * 0.52, weight: .regular)
    guard
        let symbol = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig)
    else {
        throw NSError(domain: "SleepLatchIcon", code: 2)
    }

    let symbolBounds = NSRect(
        x: size * 0.205,
        y: size * 0.205,
        width: size * 0.59,
        height: size * 0.59
    )

    NSColor(calibratedRed: 1.0, green: 0.98, blue: 0.93, alpha: 1.0).setFill()
    symbol.draw(
        in: symbolBounds,
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
    )

    let steamColor = NSColor(calibratedRed: 1.0, green: 0.93, blue: 0.82, alpha: 0.92)
    steamColor.setStroke()

    let steamWidth = max(size * 0.026, 1.0)
    for xOffset in [0.41, 0.5, 0.59] {
        let steam = NSBezierPath()
        steam.lineWidth = steamWidth
        steam.lineCapStyle = .round
        steam.move(to: NSPoint(x: size * xOffset, y: size * 0.74))
        steam.curve(
            to: NSPoint(x: size * (xOffset + 0.008), y: size * 0.9),
            controlPoint1: NSPoint(x: size * (xOffset - 0.028), y: size * 0.8),
            controlPoint2: NSPoint(x: size * (xOffset + 0.04), y: size * 0.86)
        )
        steam.stroke()
    }

    return image
}

func pngData(for image: NSImage) throws -> Data {
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "SleepLatchIcon", code: 3)
    }

    return pngData
}

func writeICNS(chunks: [(type: String, data: Data)], to url: URL) throws {
    let chunkData = try chunks.reduce(into: Data()) { partialResult, chunk in
        guard chunk.type.utf8.count == 4 else {
            throw NSError(domain: "SleepLatchIcon", code: 4)
        }

        partialResult.append(Data(chunk.type.utf8))

        var chunkLength = UInt32(chunk.data.count + 8).bigEndian
        withUnsafeBytes(of: &chunkLength) { partialResult.append(contentsOf: $0) }
        partialResult.append(chunk.data)
    }

    var fileData = Data("icns".utf8)
    var totalLength = UInt32(chunkData.count + 8).bigEndian
    withUnsafeBytes(of: &totalLength) { fileData.append(contentsOf: $0) }
    fileData.append(chunkData)

    try fileData.write(to: url)
}
