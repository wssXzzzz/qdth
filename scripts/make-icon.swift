import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0.21, green: 0.37, blue: 0.29, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.setFillColor(CGColor(red: 0.91, green: 0.94, blue: 0.88, alpha: 1))
for x: CGFloat in [244, 542] {
    context.addPath(CGPath(roundedRect: CGRect(x: x, y: 280, width: 224, height: 268), cornerWidth: 58, cornerHeight: 58, transform: nil))
    context.fillPath()
    context.move(to: CGPoint(x: x, y: 478))
    context.addCurve(to: CGPoint(x: x + 210, y: 751), control1: CGPoint(x: x - 8, y: 660), control2: CGPoint(x: x + 115, y: 751))
    context.addLine(to: CGPoint(x: x + 214, y: 659))
    context.addCurve(to: CGPoint(x: x + 102, y: 493), control1: CGPoint(x: x + 143, y: 650), control2: CGPoint(x: x + 97, y: 582))
    context.closePath()
    context.fillPath()
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write icon") }
