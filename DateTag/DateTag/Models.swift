import Foundation
import AppKit

// MARK: - Output mode

enum OutputMode: String, CaseIterable, Identifiable {
    case copyToNewFolder = "Copy to new folder"
    case inPlace = "In place (overwrite)"

    var id: String { rawValue }

    var help: String {
        switch self {
        case .copyToNewFolder:
            return "Creates a new folder next to the original — originals untouched."
        case .inPlace:
            return "Overwrites the original files. You'll be asked to confirm first."
        }
    }
}

// MARK: - Date format

enum DateFormatStyle: String, CaseIterable, Identifiable {
    case dotted = "2026.10.18"
    case slash = "10/18/2026"
    case film = "18 10 '26"
    case short = "Oct 18, 2026"
    case iso = "2026-10-18"

    var id: String { rawValue }

    func string(from date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        switch self {
        case .dotted: f.dateFormat = "yyyy.MM.dd"
        case .slash:  f.dateFormat = "MM/dd/yyyy"
        case .film:   f.dateFormat = "d M ''yy" // "13 2 '99" — no leading zeros, like the reference
        case .short:  f.dateFormat = "MMM d, yyyy"
        case .iso:    f.dateFormat = "yyyy-MM-dd"
        }
        return f.string(from: date)
    }
}

// MARK: - Tag style

enum TagStyle: String, CaseIterable, Identifiable {
    case subtleWhite = "Subtle White"
    case classicOrange = "Classic Orange"
    case subtleBlack = "Subtle Black"
    case retro = "Retro '99 (dot-matrix)"

    var id: String { rawValue }

    /// Base color before opacity slider is applied.
    var nsColor: NSColor {
        switch self {
        case .subtleWhite:
            return NSColor(white: 1.0, alpha: 1.0)
        case .classicOrange:
            // Classic '90s point-and-shoot orange
            return NSColor(red: 1.0, green: 0.62, blue: 0.15, alpha: 1.0)
        case .subtleBlack:
            return NSColor(white: 0.08, alpha: 1.0)
        case .retro:
            // Pale dot-matrix yellow sampled from a 1999 reference stamp
            return NSColor(red: 0.87, green: 0.89, blue: 0.71, alpha: 1.0)
        }
    }

    var shadowColor: NSColor {
        switch self {
        case .subtleBlack:
            return NSColor(white: 1.0, alpha: 0.45)
        default:
            return NSColor(white: 0.0, alpha: 0.45)
        }
    }
}

// MARK: - Options passed to the tagger

struct TagOptions {
    var format: DateFormatStyle = .dotted
    var style: TagStyle = .subtleWhite
    /// Font size as a fraction of the image's shorter side. 0.028 ≈ subtle.
    var relativeFontSize: Double = 0.028
    /// 0.3 ... 1.0
    var opacity: Double = 0.9
    /// Padding from right/bottom edges as a fraction of the shorter side.
    var relativePadding: Double = 0.025
    /// JPEG compression, 0...1
    var jpegQuality: Double = 0.92
}

// MARK: - Per-file result

enum ProcessResult {
    case success(output: URL, dateUsed: Date, dateString: String)
    case skipped(reason: String)
    case failed(error: String)
}
