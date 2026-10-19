import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Core engine: reads EXIF dates, draws the tag, writes the image back
/// preserving metadata. No UI in here — ContentView calls this from a
/// background Task, one file at a time.
final class DateTagger {

    static let supportedExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "png", "tiff", "tif"]

    // MARK: - Folder scanning

    static func findImages(in folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            if supportedExtensions.contains(url.pathExtension.lowercased()) {
                urls.append(url)
            }
        }
        return urls.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    // MARK: - Date extraction

    /// EXIF DateTimeOriginal -> TIFF DateTime -> file creation/modification date.
    static func captureDate(for url: URL) -> Date {
        if let date = exifDate(for: url) {
            return date
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let created = attrs?[.creationDate] as? Date, created.timeIntervalSince1970 > 0 {
            return created
        }
        if let modified = attrs?[.modificationDate] as? Date {
            return modified
        }
        return Date()
    }

    private static func exifDate(for url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }

        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"

        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let s = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
           let d = parser.date(from: s) {
            return d
        }
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let s = exif[kCGImagePropertyExifDateTimeDigitized] as? String,
           let d = parser.date(from: s) {
            return d
        }
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let s = tiff[kCGImagePropertyTIFFDateTime] as? String,
           let d = parser.date(from: s) {
            return d
        }
        return nil
    }

    // MARK: - Processing a single image

    func process(input: URL, output: URL, options: TagOptions) -> ProcessResult {
        let date = Self.captureDate(for: input)
        let dateString = options.format.string(from: date)

        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil) else {
            return .failed(error: "Could not read file")
        }

        // Load full-res image with EXIF orientation baked into the pixels.
        // This is the key trick for Fujifilm portrait shots — without it
        // they'd come out sideways after re-encoding.
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 20000 // effectively "no downscale"
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return .failed(error: "Could not decode image")
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else {
            return .failed(error: "Invalid image size")
        }

        // Bitmap context to draw into
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return .failed(error: "Could not create canvas")
        }

        NSGraphicsContext.saveGraphicsState()

        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return .failed(error: "Could not create graphics context")
        }
        NSGraphicsContext.current = ctx

        // Draw the photo (origin is bottom-left in this context — perfect for a bottom-right tag)
        let fullRect = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.cgContext.draw(cgImage, in: fullRect)

        // Draw the date string
        let shortSide = Double(min(width, height))

        if options.style == .retro {
            // Analogue data-back imprint, mirroring datetag.py: FIXED spec —
            // glyph height 3.8% of frame height, right inset 9.5% of width,
            // bottom inset 4.5% of height, fixed warm light colour, screen
            // blend mode (adding light, like exposing film). The size and
            // opacity options intentionally do not apply.
            // Context origin is bottom-left: glyph bottom sits at 4.5% up.
            let glyphHeight = CGFloat(height) * 0.038
            let pitch = glyphHeight / 7
            let units = dateString.uppercased().reduce(0) { $0 + Self.retroCharUnits($1) } - 2
            let startX = CGFloat(width) - CGFloat(width) * 0.095 - CGFloat(units) * pitch
            let baseY = CGFloat(height) * 0.045
            ctx.cgContext.setBlendMode(.screen)
            // Two passes: bloom (big, dim) then core (small, bright).
            for (scale, col) in [(CGFloat(1.9), NSColor(red: 0.238, green: 0.235, blue: 0.122, alpha: 1)),
                                 (CGFloat(1.0), NSColor(red: 0.553, green: 0.545, blue: 0.284, alpha: 1))] {
                let dotR = pitch * 0.34 * scale
                col.setFill()
                var cursorX = startX
                for ch in dateString.uppercased() {
                    if let glyph = Self.dotMatrix[ch] {
                        for (rowI, row) in glyph.enumerated() {
                            for (colI, bit) in row.enumerated() where bit == "1" {
                                let cx = cursorX + CGFloat(colI) * pitch + pitch / 2
                                let cy = baseY + CGFloat(6 - rowI) * pitch + pitch / 2
                                NSBezierPath(ovalIn: CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)).fill()
                            }
                        }
                    }
                    cursorX += CGFloat(Self.retroCharUnits(ch)) * pitch
                }
            }
            ctx.cgContext.setBlendMode(.normal)
            NSGraphicsContext.restoreGraphicsState()
            guard let renderedCG = rep.cgImage else {
                return .failed(error: "Could not render stamped image")
            }
            return finishWriting(renderedCG: renderedCG, source: source, input: input, output: output, width: width, height: height, date: date, dateString: dateString, options: options)
        }

        let fontSize = max(11, shortSide * options.relativeFontSize)
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)

        let shadow = NSShadow()
        shadow.shadowColor = options.style.shadowColor
        shadow.shadowBlurRadius = fontSize * 0.08
        shadow.shadowOffset = NSSize(width: 0, height: -fontSize * 0.03)

        let color = options.style.nsColor.withAlphaComponent(CGFloat(options.opacity))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .shadow: shadow
        ]
        let attributed = NSAttributedString(string: dateString, attributes: attrs)
        let textSize = attributed.size()
        let padding = CGFloat(shortSide * options.relativePadding)

        let drawPoint = NSPoint(
            x: CGFloat(width) - textSize.width - padding,
            y: padding
        )
        attributed.draw(at: drawPoint)

        NSGraphicsContext.restoreGraphicsState()

        guard let renderedCG = rep.cgImage else {
            return .failed(error: "Could not render stamped image")
        }
        return finishWriting(renderedCG: renderedCG, source: source, input: input, output: output, width: width, height: height, date: date, dateString: dateString, options: options)
    }

    /// Shared tail for both renderers: write with original EXIF preserved.
    /// Orientation is reset to 1 because it's now baked into pixels.
    private func finishWriting(renderedCG: CGImage, source: CGImageSource, input: URL, output: URL, width: Int, height: Int, date: Date, dateString: String, options: TagOptions) -> ProcessResult {
        var preservedProps: [CFString: Any] = [:]
        if let originalProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            preservedProps = originalProps
        }
        preservedProps[kCGImagePropertyOrientation] = 1
        preservedProps[kCGImagePropertyPixelWidth] = width
        preservedProps[kCGImagePropertyPixelHeight] = height

        let outputType = Self.outputUTType(for: input)

        // In-place: write to a temp file first, then swap.
        let isInPlace = input.standardizedFileURL == output.standardizedFileURL
        let effectiveOutput: URL = isInPlace
            ? output.deletingLastPathComponent()
                .appendingPathComponent(".datetag-tmp-\(UUID().uuidString).\(output.pathExtension)")
            : output

        guard let dest = CGImageDestinationCreateWithURL(effectiveOutput as CFURL, outputType.identifier as CFString, 1, nil) else {
            return .failed(error: "Could not create output file")
        }

        var destProps: [CFString: Any] = preservedProps
        if outputType == .jpeg {
            destProps[kCGImageDestinationLossyCompressionQuality] = options.jpegQuality
        }
        CGImageDestinationAddImage(dest, renderedCG, destProps as CFDictionary)

        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: effectiveOutput)
            return .failed(error: "Could not write output file")
        }

        if isInPlace {
            do {
                _ = try FileManager.default.replaceItemAt(output, withItemAt: effectiveOutput)
            } catch {
                try? FileManager.default.removeItem(at: effectiveOutput)
                return .failed(error: "Could not replace original: \(error.localizedDescription)")
            }
        }

        return .success(output: output, dateUsed: date, dateString: dateString)
    }

    // MARK: - Retro dot-matrix glyphs (subset mirroring datetag.py)

    static let dotMatrix: [Character: [String]] = [
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["01110", "10001", "00001", "00110", "00001", "10001", "01110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        "'": ["00100", "00100", "01000", "00000", "00000", "00000", "00000"],
        ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
        " ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
    ]

    static func retroCharUnits(_ ch: Character) -> Int {
        if ch == " " { return 5 }
        if ch == "'" { return 4 }
        return 7
    }

    private static func outputUTType(for url: URL) -> UTType {
        switch url.pathExtension.lowercased() {
        case "png": return .png
        case "heic", "heif": return .heic
        case "tiff", "tif": return .tiff
        default: return .jpeg
        }
    }

    // MARK: - Batch helpers

    /// For copy mode: <folder>_dated preserving relative subfolder structure.
    static func outputURL(for input: URL, sourceRoot: URL, mode: OutputMode) -> URL {
        switch mode {
        case .inPlace:
            return input
        case .copyToNewFolder:
            let datedRoot = sourceRoot.deletingLastPathComponent()
                .appendingPathComponent(sourceRoot.lastPathComponent + "_dated", isDirectory: true)
            let relative = input.path.replacingOccurrences(of: sourceRoot.path + "/", with: "")
            return datedRoot.appendingPathComponent(relative)
        }
    }

    static func ensureDirectory(for fileURL: URL) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
