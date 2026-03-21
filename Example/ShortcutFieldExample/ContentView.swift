import AppKit
import ShortcutField
import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Workbench", systemImage: "slider.horizontal.3") {
                WorkbenchTab()
            }
            Tab("Gallery", systemImage: "paintpalette") {
                GalleryTab()
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

// MARK: - Workbench

struct WorkbenchTab: View {
    @State private var shortcut: Shortcut?
    @State private var selectedStyle: ShortcutRecorderStyle = .rounded
    @State private var selectedSize: ControlSize = .regular
    @State private var selectedTextColor: NamedColor = .default
    @State private var selectedBgColor: NamedBgColor = .default
    @State private var placeholderText: String = "Record Shortcut"
    @State private var matchCount = 0
    @State private var lastMatched = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 16) {
                    configuredRecorder

                    if let shortcut {
                        Text(shortcut.displayString)
                            .font(.title.monospaced())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No shortcut")
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minWidth: 150)
                .background(Color.gray.opacity(0.08))

                Divider()

                ScrollView {
                    controlsSection
                        .padding(20)
                }
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.04))
            }

            Divider()
            fireCounterSection
                .padding(16)
        }
    }

    private var configuredRecorder: some View {
        makeRecorder($shortcut, style: selectedStyle, size: selectedSize,
                     textColor: selectedTextColor.nsColor, bgColor: selectedBgColor.nsColor,
                     placeholder: placeholderText)
            .frame(width: 180)
    }

    private func makeRecorder(_ shortcut: Binding<Shortcut?>, style: ShortcutRecorderStyle,
                              size: ControlSize, textColor: NSColor?, bgColor: NSColor?,
                              placeholder: String) -> some View {
        var view = ShortcutRecorderView(shortcut)
            .placeholder(placeholder)
            .style(style)
        if let textColor { view = view.textColor(textColor) }
        if let bgColor { view = view.fieldBackgroundColor(bgColor) }
        return view.controlSize(size)
    }

    // MARK: Controls

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("Style:")
                        .frame(width: 100, alignment: .trailing)
                    Picker("", selection: $selectedStyle) {
                        Text(".rounded").tag(ShortcutRecorderStyle.rounded)
                        Text(".plain").tag(ShortcutRecorderStyle.plain)
                        Text(".borderless").tag(ShortcutRecorderStyle.borderless)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                }

                GridRow {
                    Text("Size:")
                        .frame(width: 100, alignment: .trailing)
                    Picker("", selection: $selectedSize) {
                        Text(".mini").tag(ControlSize.mini)
                        Text(".small").tag(ControlSize.small)
                        Text(".regular").tag(ControlSize.regular)
                        Text(".large").tag(ControlSize.large)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                }

                GridRow {
                    Text("Text color:")
                        .frame(width: 100, alignment: .trailing)
                    Picker("", selection: $selectedTextColor) {
                        ForEach(NamedColor.allCases) { color in
                            Text(color.label).tag(color)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                GridRow {
                    Text("Background:")
                        .frame(width: 100, alignment: .trailing)
                    Picker("", selection: $selectedBgColor) {
                        ForEach(NamedBgColor.allCases) { color in
                            Text(color.label).tag(color)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                GridRow {
                    Text("Placeholder:")
                        .frame(width: 100, alignment: .trailing)
                    TextField("Placeholder text", text: $placeholderText)
                        .frame(width: 200)
                }
            }
        }
    }

    // MARK: Fire Counter

    @ViewBuilder
    private var fireCounterSection: some View {
        if #available(macOS 14.0, *) {
            HStack(spacing: 12) {
                Circle()
                    .fill(lastMatched ? .green : .gray.opacity(0.3))
                    .frame(width: 12, height: 12)

                Text("Fired \(matchCount) time\(matchCount == 1 ? "" : "s")")
                    .font(.body.monospaced())

                Spacer()

                if shortcut != nil {
                    Button("Reset") { matchCount = 0 }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .onShortcut(shortcut) {
                matchCount += 1
                lastMatched = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    lastMatched = false
                }
            }
        } else {
            Text("Live matching requires macOS 14+")
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Named Color Enums

enum NamedColor: String, CaseIterable, Identifiable {
    case `default`, teal, orange, indigo, white

    var id: String { rawValue }

    var label: String {
        switch self {
        case .default: "Default"
        case .teal: "Teal"
        case .orange: "Orange"
        case .indigo: "Indigo"
        case .white: "White"
        }
    }

    var nsColor: NSColor? {
        switch self {
        case .default: nil
        case .teal: .systemTeal
        case .orange: .systemOrange
        case .indigo: .systemIndigo
        case .white: .white
        }
    }
}

enum NamedBgColor: String, CaseIterable, Identifiable {
    case `default`, blueTint, darkGray, indigoTint

    var id: String { rawValue }

    var label: String {
        switch self {
        case .default: "Default"
        case .blueTint: "Blue Tint"
        case .darkGray: "Dark Gray"
        case .indigoTint: "Indigo Tint"
        }
    }

    var nsColor: NSColor? {
        switch self {
        case .default: nil
        case .blueTint: NSColor.systemBlue.withAlphaComponent(0.1)
        case .darkGray: .darkGray
        case .indigoTint: NSColor.systemIndigo.withAlphaComponent(0.1)
        }
    }
}

// MARK: - Gallery

struct GalleryTab: View {
    private let columns = [
        GridItem(.adaptive(minimum: 170, maximum: 200), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(GalleryItem.allItems) { item in
                    GalleryCard(item: item)
                }
            }
            .padding(24)
        }
    }
}

struct GalleryCard: View {
    let item: GalleryItem
    @State private var shortcut: Shortcut?

    var body: some View {
        VStack(spacing: 8) {
            cardRecorder
                .frame(maxWidth: .infinity)

            Text(item.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var cardRecorder: some View {
        var view = ShortcutRecorderView($shortcut).style(item.style)
        if let textColor = item.textColor { view = view.textColor(textColor) }
        if let bgColor = item.bgColor { view = view.fieldBackgroundColor(bgColor) }
        return view.controlSize(item.size)
    }
}

struct GalleryItem: Identifiable {
    let id = UUID()
    let label: String
    let style: ShortcutRecorderStyle
    let size: ControlSize
    let textColor: NSColor?
    let bgColor: NSColor?

    init(
        _ label: String,
        style: ShortcutRecorderStyle = .rounded,
        size: ControlSize = .regular,
        textColor: NSColor? = nil,
        bgColor: NSColor? = nil
    ) {
        self.label = label
        self.style = style
        self.size = size
        self.textColor = textColor
        self.bgColor = bgColor
    }

    static let allItems: [GalleryItem] = [
        GalleryItem("Default"),
        GalleryItem(".plain", style: .plain),
        GalleryItem(".borderless", style: .borderless),
        GalleryItem(".mini", size: .mini),
        GalleryItem(".large", size: .large),
        GalleryItem("Teal text", textColor: .systemTeal),
        GalleryItem("Orange text", textColor: .systemOrange),
        GalleryItem("Blue tint bg", bgColor: NSColor.systemBlue.withAlphaComponent(0.1)),
        GalleryItem("Dark bg + white text", textColor: .white, bgColor: .darkGray),
        GalleryItem(
            "Indigo tint + text",
            textColor: .systemIndigo,
            bgColor: NSColor.systemIndigo.withAlphaComponent(0.1)
        ),
        GalleryItem("Borderless + teal", style: .borderless, textColor: .systemTeal),
        GalleryItem("Plain + large", style: .plain, size: .large),
        GalleryItem("Mini + orange", size: .mini, textColor: .systemOrange)
    ]
}
