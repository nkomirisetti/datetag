import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    // Folder / files
    @State private var sourceFolder: URL?
    @State private var imageURLs: [URL] = []
    @State private var isDropTargeted = false

    // Options
    @State private var outputMode: OutputMode = .copyToNewFolder
    @State private var formatStyle: DateFormatStyle = .dotted
    @State private var tagStyle: TagStyle = .subtleWhite
    @State private var fontScale: Double = 0.028   // relative to short side
    @State private var opacity: Double = 0.9

    // Run state
    @State private var isProcessing = false
    @State private var processedCount = 0
    @State private var totalCount = 0
    @State private var logLines: [String] = []
    @State private var showInPlaceConfirm = false
    @State private var lastOutputFolder: URL?

    private var currentOptions: TagOptions {
        TagOptions(
            format: formatStyle,
            style: tagStyle,
            relativeFontSize: fontScale,
            opacity: opacity
        )
    }

    private var previewDateString: String {
        guard let first = imageURLs.first else { return formatStyle.string(from: Date()) }
        return formatStyle.string(from: DateTagger.captureDate(for: first))
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: settings
            VStack(alignment: .leading, spacing: 18) {
                header
                folderPicker
                Divider()
                optionsForm
                Spacer()
                actionArea
            }
            .padding(20)
            .frame(width: 360)

            Divider()

            // Right: preview + log
            VStack(alignment: .leading, spacing: 12) {
                Text("Preview")
                    .font(.headline)
                preview
                Text("Log")
                    .font(.headline)
                logView
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.08))
                    .padding(8)
            }
        }
        .alert("Overwrite originals?", isPresented: $showInPlaceConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Overwrite", role: .destructive) { runProcessing() }
        } message: {
            Text("This will replace \(imageURLs.count) original file(s) in place. This can't be undone. Consider \"Copy to new folder\" if you want to keep the originals.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DateTag")
                .font(.largeTitle.bold())
            Text("Adds a subtle date tag to the bottom-right corner of your photos, like the old film stamps.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var folderPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                pickFolder()
            } label: {
                Label("Choose Folder…", systemImage: "folder")
            }
            .controlSize(.large)

            if let folder = sourceFolder {
                Text(folder.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text("\(imageURLs.count) image\(imageURLs.count == 1 ? "" : "s") found")
                    .font(.caption.bold())
            } else {
                Text("or drag a folder onto this window")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var optionsForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Output", selection: $outputMode) {
                ForEach(OutputMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text(outputMode.help)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Date format", selection: $formatStyle) {
                ForEach(DateFormatStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }

            Picker("Style", selection: $tagStyle) {
                ForEach(TagStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Size")
                    Spacer()
                    Text(fontScale < 0.022 ? "Tiny" : fontScale < 0.034 ? "Subtle" : "Large")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                Slider(value: $fontScale, in: 0.015...0.05)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Opacity")
                    Spacer()
                    Text("\(Int(opacity * 100))%")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                Slider(value: $opacity, in: 0.3...1.0)
            }
        }
    }

    private var actionArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isProcessing {
                ProgressView(value: Double(processedCount), total: Double(max(totalCount, 1))) {
                    Text("Processing \(processedCount) / \(totalCount)…")
                        .font(.caption)
                }
            }

            Button {
                if outputMode == .inPlace {
                    showInPlaceConfirm = true
                } else {
                    runProcessing()
                }
            } label: {
                Text("Apply Date Tags")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(imageURLs.isEmpty || isProcessing)

            if let out = lastOutputFolder {
                Button("Reveal Output Folder in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([out])
                }
                .font(.caption)
            }
        }
    }

    private var preview: some View {
        Group {
            if let first = imageURLs.first, let nsImage = NSImage(contentsOf: first) {
                GeometryReader { geo in
                    ZStack(alignment: .bottomTrailing) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .background(Color.black.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        // This overlay mirrors DateTagger's placement math
                        // (padding & size are relative to the short side).
                        Text(previewDateString)
                            .font(.system(size: previewFontSize(container: geo.size, image: nsImage), weight: .medium, design: .monospaced))
                            .foregroundStyle(previewColor)
                            .opacity(opacity)
                            .shadow(color: .black.opacity(tagStyle == .subtleBlack ? 0.0 : 0.45), radius: 2, y: 1)
                            .padding(previewPadding(container: geo.size, image: nsImage))
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.largeTitle)
                                .foregroundStyle(.tertiary)
                            Text("Choose a folder to preview the first photo here")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
    }

    private var previewColor: Color {
        switch tagStyle {
        case .subtleWhite: return .white
        case .classicOrange: return Color(red: 1.0, green: 0.62, blue: 0.15)
        case .subtleBlack: return Color(white: 0.08)
        case .retro: return Color(red: 0.87, green: 0.89, blue: 0.71) // preview approximates the dot-matrix render
        }
    }

    private func previewFontSize(container: CGSize, image: NSImage) -> CGFloat {
        // Approximate displayed short side
        let scale = min(container.width / image.size.width, container.height / image.size.height)
        let displayedShort = min(image.size.width, image.size.height) * scale
        return max(9, displayedShort * fontScale * 2.2) // visual approximation for preview only
    }

    private func previewPadding(container: CGSize, image: NSImage) -> CGFloat {
        let scale = min(container.width / image.size.width, container.height / image.size.height)
        let displayedShort = min(image.size.width, image.size.height) * scale
        return max(6, displayedShort * 0.025)
    }

    private var logView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                if logLines.isEmpty {
                    Text("Nothing yet. Processed files, dates used, and any skips will show up here.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(Array(logLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
    }

    // MARK: - Actions

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder of photos"
        if panel.runModal() == .OK, let url = panel.url {
            setSourceFolder(url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                DispatchQueue.main.async {
                    if isDir.boolValue {
                        setSourceFolder(url)
                    } else if DateTagger.supportedExtensions.contains(url.pathExtension.lowercased()) {
                        // Single file dropped: treat its parent as the folder, but only process that file is a TODO;
                        // for now load the whole parent folder so the UX stays simple and predictable.
                        setSourceFolder(url.deletingLastPathComponent())
                    }
                }
            }
        }
    }

    private func setSourceFolder(_ url: URL) {
        sourceFolder = url
        imageURLs = DateTagger.findImages(in: url)
        logLines = []
        lastOutputFolder = nil
        if imageURLs.isEmpty {
            logLines.append("No supported images found in that folder (JPG, HEIC, PNG, TIFF).")
        } else {
            logLines.append("Found \(imageURLs.count) image(s) in \(url.lastPathComponent)/")
        }
    }

    private func runProcessing() {
        guard let root = sourceFolder, !imageURLs.isEmpty else { return }
        isProcessing = true
        processedCount = 0
        totalCount = imageURLs.count
        let options = currentOptions
        let mode = outputMode
        let files = imageURLs

        Task.detached(priority: .userInitiated) {
            let tagger = DateTagger()
            var success = 0
            var failed = 0

            for file in files {
                let output = DateTagger.outputURL(for: file, sourceRoot: root, mode: mode)
                do {
                    try DateTagger.ensureDirectory(for: output)
                } catch {
                    await MainActor.run {
                        logLines.append("✗ \(file.lastPathComponent) — could not create output folder")
                        processedCount += 1
                    }
                    failed += 1
                    continue
                }

                // For copy mode, if output is different file, remove stale copy first
                // (CGImageDestination won't overwrite reliably in all cases)
                if mode == .copyToNewFolder, FileManager.default.fileExists(atPath: output.path) {
                    try? FileManager.default.removeItem(at: output)
                }

                let result = tagger.process(input: file, output: output, options: options)
                await MainActor.run {
                    switch result {
                    case .success(_, _, let dateString):
                        logLines.append("✓ \(file.lastPathComponent) → \(dateString)")
                        success += 1
                    case .skipped(let reason):
                        logLines.append("– \(file.lastPathComponent) skipped: \(reason)")
                    case .failed(let err):
                        logLines.append("✗ \(file.lastPathComponent) — \(err)")
                        failed += 1
                    }
                    processedCount += 1
                }
            }

            await MainActor.run {
                isProcessing = false
                if mode == .copyToNewFolder {
                    lastOutputFolder = root.deletingLastPathComponent()
                        .appendingPathComponent(root.lastPathComponent + "_dated", isDirectory: true)
                } else {
                    lastOutputFolder = root
                }
                logLines.append("Done. \(success) succeeded, \(failed) failed.")
            }
        }
    }
}
