import AppKit
import CoreGraphics
import Foundation
import ImageIO

private struct PixelSize {
    let width: Int
    let height: Int

    var pixelCount: Int { width * height }
}

private enum Target: String {
    case t3 = "t3"
    case old800x480 = "old-800x480"
    case new528x792 = "new-528x792"

    var size: PixelSize {
        switch self {
        case .old800x480: return PixelSize(width: 800, height: 480)
        case .t3, .new528x792: return PixelSize(width: 528, height: 792)
        }
    }

    var isT3: Bool {
        self == .t3 || self == .new528x792
    }
}

private enum Orientation: String {
    case rotate180ThenFlipHorizontal = "rotate-180-then-flip-horizontal"
    case normal
}

private struct NativeColor {
    let name: String
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let code: UInt8
}

private let nativePalette: [NativeColor] = [
    NativeColor(name: "black", red: 0, green: 0, blue: 0, code: 0),
    NativeColor(name: "white", red: 255, green: 255, blue: 255, code: 1),
    NativeColor(name: "yellow", red: 255, green: 255, blue: 0, code: 2),
    NativeColor(name: "red", red: 255, green: 0, blue: 0, code: 3),
    NativeColor(name: "blue", red: 0, green: 0, blue: 255, code: 5),
    NativeColor(name: "green", red: 0, green: 255, blue: 0, code: 6)
]

private func log(_ message: String) {
    print(message)
    fflush(stdout)
}

private func usage() -> Never {
    log("""
    Usage:
      image_to_payload --input image.png --target t3 --output-prefix /tmp/final
      image_to_payload --input image.jpg --target old-800x480 --output-prefix /tmp/final

    Orientation:
      Images use normal orientation by default.
      Add --orientation rotate-180-then-flip-horizontal for an inverted screen.

    Outputs:
      <prefix>.bin
      <prefix>.protocol.qlz for t3
    """)
    Foundation.exit(64)
}

private func loadCGImage(path: String) throws -> CGImage {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(domain: "ImageToPayload", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot decode image: \(path)"])
    }
    return cgImage
}

private func renderCoverRGBA(_ source: CGImage, to size: PixelSize) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 255, count: size.pixelCount * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: &bytes,
        width: size.width,
        height: size.height,
        bitsPerComponent: 8,
        bytesPerRow: size.width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "ImageToPayload", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot create bitmap context"])
    }

    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))

    let scale = max(CGFloat(size.width) / CGFloat(source.width), CGFloat(size.height) / CGFloat(source.height))
    let drawWidth = CGFloat(source.width) * scale
    let drawHeight = CGFloat(source.height) * scale
    let drawRect = CGRect(
        x: (CGFloat(size.width) - drawWidth) / 2,
        y: (CGFloat(size.height) - drawHeight) / 2,
        width: drawWidth,
        height: drawHeight
    )
    context.interpolationQuality = .high
    context.draw(source, in: drawRect)
    return bytes
}

private func nearestNativeColor(red: Float, green: Float, blue: Float) -> NativeColor {
    var best = nativePalette[0]
    var bestDistance = Float.greatestFiniteMagnitude
    for color in nativePalette {
        let dr = red - Float(color.red)
        let dg = green - Float(color.green)
        let db = blue - Float(color.blue)
        let distance = dr * dr + dg * dg + db * db
        if distance < bestDistance {
            bestDistance = distance
            best = color
        }
    }
    return best
}

private func makeSixColorBitmap(rgba: [UInt8], size: PixelSize) -> Data {
    var working = rgba.map(Float.init)
    var codes = [UInt8](repeating: 1, count: size.pixelCount)

    func addError(at x: Int, _ y: Int, red: Float, green: Float, blue: Float, weight: Float) {
        guard x >= 0, x < size.width, y >= 0, y < size.height else { return }
        let offset = (y * size.width + x) * 4
        working[offset] += red * weight
        working[offset + 1] += green * weight
        working[offset + 2] += blue * weight
    }

    for y in 0 ..< size.height {
        for x in 0 ..< size.width {
            let pixelIndex = y * size.width + x
            let offset = pixelIndex * 4
            let red = min(255, max(0, working[offset]))
            let green = min(255, max(0, working[offset + 1]))
            let blue = min(255, max(0, working[offset + 2]))
            let selected = nearestNativeColor(red: red, green: green, blue: blue)
            codes[pixelIndex] = selected.code

            let errorRed = red - Float(selected.red)
            let errorGreen = green - Float(selected.green)
            let errorBlue = blue - Float(selected.blue)
            addError(at: x + 1, y, red: errorRed, green: errorGreen, blue: errorBlue, weight: 7 / 16)
            addError(at: x - 1, y + 1, red: errorRed, green: errorGreen, blue: errorBlue, weight: 3 / 16)
            addError(at: x, y + 1, red: errorRed, green: errorGreen, blue: errorBlue, weight: 5 / 16)
            addError(at: x + 1, y + 1, red: errorRed, green: errorGreen, blue: errorBlue, weight: 1 / 16)
        }
    }

    var output = [UInt8]()
    output.reserveCapacity((size.pixelCount + 1) / 2)
    var byte: UInt8 = 0
    for pixelIndex in 0 ..< size.pixelCount {
        let code = codes[pixelIndex]
        if pixelIndex.isMultiple(of: 2) {
            byte = code << 4
        } else {
            output.append(byte | code)
            byte = 0
        }
    }
    if !size.pixelCount.isMultiple(of: 2) {
        output.append(byte)
    }
    return Data(output)
}

private func rotated180(_ data: Data, size: PixelSize) -> Data {
    let source = Array(data)
    var output = [UInt8](repeating: 0, count: source.count)

    func code(at pixelIndex: Int) -> UInt8 {
        let byte = source[pixelIndex / 2]
        return pixelIndex.isMultiple(of: 2) ? byte >> 4 : byte & 0x0f
    }

    func setCode(_ code: UInt8, at pixelIndex: Int) {
        let byteIndex = pixelIndex / 2
        if pixelIndex.isMultiple(of: 2) {
            output[byteIndex] = (output[byteIndex] & 0x0f) | (code << 4)
        } else {
            output[byteIndex] = (output[byteIndex] & 0xf0) | (code & 0x0f)
        }
    }

    for sourceIndex in 0 ..< size.pixelCount {
        setCode(code(at: sourceIndex), at: size.pixelCount - 1 - sourceIndex)
    }
    return Data(output)
}

private func flippedHorizontally(_ data: Data, size: PixelSize) -> Data {
    let source = Array(data)
    var output = [UInt8](repeating: 0, count: source.count)

    func code(at pixelIndex: Int) -> UInt8 {
        let byte = source[pixelIndex / 2]
        return pixelIndex.isMultiple(of: 2) ? byte >> 4 : byte & 0x0f
    }

    func setCode(_ code: UInt8, at pixelIndex: Int) {
        let byteIndex = pixelIndex / 2
        if pixelIndex.isMultiple(of: 2) {
            output[byteIndex] = (output[byteIndex] & 0x0f) | (code << 4)
        } else {
            output[byteIndex] = (output[byteIndex] & 0xf0) | (code & 0x0f)
        }
    }

    for y in 0 ..< size.height {
        for x in 0 ..< size.width {
            let sourceIndex = y * size.width + x
            let destinationIndex = y * size.width + (size.width - 1 - x)
            setCode(code(at: sourceIndex), at: destinationIndex)
        }
    }
    return Data(output)
}

private func rotatedClockwiseMirroredForSE0368(_ data: Data, size: PixelSize) -> Data {
    let source = Array(data)
    let destinationWidth = size.height
    var output = [UInt8](repeating: 0, count: source.count)

    func code(at pixelIndex: Int) -> UInt8 {
        let byte = source[pixelIndex / 2]
        return pixelIndex.isMultiple(of: 2) ? byte >> 4 : byte & 0x0f
    }

    func setCode(_ code: UInt8, at pixelIndex: Int) {
        let byteIndex = pixelIndex / 2
        if pixelIndex.isMultiple(of: 2) {
            output[byteIndex] = (output[byteIndex] & 0x0f) | (code << 4)
        } else {
            output[byteIndex] = (output[byteIndex] & 0xf0) | (code & 0x0f)
        }
    }

    for destinationIndex in 0 ..< size.pixelCount {
        let destinationX = destinationIndex % destinationWidth
        let destinationY = destinationIndex / destinationWidth
        let sourceX = size.width - 1 - destinationY
        let sourceY = size.height - 1 - destinationX
        setCode(code(at: sourceY * size.width + sourceX), at: destinationIndex)
    }
    return Data(output)
}

private func quickLZStoredPayload(from rawData: Data) throws -> Data {
    let decodedBlockSize = 64
    guard rawData.count.isMultiple(of: decodedBlockSize) else {
        throw NSError(domain: "ImageToPayload", code: 4, userInfo: [NSLocalizedDescriptionKey: "Raw data length is not divisible by 64: \(rawData.count)"])
    }
    var output = Data(repeating: 0, count: 4)
    output.reserveCapacity(4 + rawData.count / decodedBlockSize * 67)
    for offset in stride(from: 0, to: rawData.count, by: decodedBlockSize) {
        output.append(contentsOf: [0x74, 0x43, 0x40])
        output.append(rawData.subdata(in: offset ..< offset + decodedBlockSize))
    }
    return output
}

private var inputPath: String?
private var target = Target.t3
private var outputPrefix: String?
private var orientation = Orientation.normal
private var args = Array(CommandLine.arguments.dropFirst())

while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "--input":
        guard !args.isEmpty else { usage() }
        inputPath = args.removeFirst()
    case "--target":
        guard !args.isEmpty, let parsed = Target(rawValue: args.removeFirst()) else { usage() }
        target = parsed
    case "--output-prefix":
        guard !args.isEmpty else { usage() }
        outputPrefix = args.removeFirst()
    case "--orientation":
        guard !args.isEmpty, let parsed = Orientation(rawValue: args.removeFirst()) else { usage() }
        orientation = parsed
    default:
        usage()
    }
}

guard let inputPath, let outputPrefix else { usage() }

do {
    let size = target.size
    let image = try loadCGImage(path: inputPath)
    let rgba = try renderCoverRGBA(image, to: size)
    let unrotatedBitmap = makeSixColorBitmap(rgba: rgba, size: size)
    log("Color mode: six-color Floyd-Steinberg dithering")
    let bitmap: Data
    switch orientation {
    case .rotate180ThenFlipHorizontal:
        bitmap = flippedHorizontally(rotated180(unrotatedBitmap, size: size), size: size)
    case .normal:
        bitmap = unrotatedBitmap
    }
    log("Image orientation: \(orientation.rawValue)")
    let binURL = URL(fileURLWithPath: outputPrefix + ".bin")
    try bitmap.write(to: binURL)
    log("Wrote \(binURL.path) (\(bitmap.count) bytes)")

    if target.isT3 {
        let controllerRaw = rotatedClockwiseMirroredForSE0368(bitmap, size: size)
        let protocolPayload = try quickLZStoredPayload(from: controllerRaw)
        let qlzURL = URL(fileURLWithPath: outputPrefix + ".protocol.qlz")
        try protocolPayload.write(to: qlzURL)
        log("Wrote \(qlzURL.path) (\(protocolPayload.count) bytes)")
    }
} catch {
    log("Failed: \(error.localizedDescription)")
    Foundation.exit(1)
}
