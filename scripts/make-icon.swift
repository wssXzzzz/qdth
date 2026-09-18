import Foundation
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

// Preserve the original settings mark: quote.opening, bold, 55% of the
// container size, on #3D6B57 with #F5F5F0 ink. Do not approximate the glyph
// with hand-drawn paths. Both consumers receive the exact same opaque PNG.
@MainActor
func generate() throws {
    let size: CGFloat = 1024
    let mark = Image(systemName: "quote.opening")
        .font(.system(size: size * 0.55, weight: .bold))
        .foregroundStyle(Color(red: 245 / 255, green: 245 / 255, blue: 240 / 255))
        .frame(width: size, height: size)
        .background(Color(red: 61 / 255, green: 107 / 255, blue: 87 / 255))
        .environment(\.colorScheme, .light)
    let renderer = ImageRenderer(content: mark)
    renderer.scale = 1
    renderer.isOpaque = true
    guard let image = renderer.cgImage else { fatalError("Could not render brand mark") }
    let outputs = CommandLine.arguments.dropFirst()
    guard !outputs.isEmpty else { fatalError("Usage: swift scripts/make-icon.swift <AppIcon.png> <BrandMark.png>") }
    for path in outputs {
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            fatalError("Could not create PNG destination")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Could not write icon") }
    }
}

try MainActor.assumeIsolated { try generate() }
