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
        .frame(minWidth: 1200, minHeight: 650)
    }
}

// MARK: - Workbench

struct WorkbenchTab: View {
    // Inputs
    @State private var shortcutA: Shortcut?
    @State private var shortcutB: Shortcut?
    @State private var sequenceA: ShortcutSequence?
    @State private var sequenceB: ShortcutSequence?

    // Controls A
    @State private var selectedStyleA: ShortcutRecorderStyle = .rounded
    @State private var selectedSizeA: ControlSize = .regular
    @State private var selectedTextColorA: NamedColor = .default
    @State private var selectedBgColorA: NamedBgColor = .default
    @State private var placeholderTextA: String = "Record Shortcut"
    @State private var selectedSensitivityModeA: SensitivityMode = .discrete
    @State private var selectedSensitivityPositionA: SensitivityPosition = .below

    // Controls B
    @State private var selectedStyleB: ShortcutRecorderStyle = .rounded
    @State private var selectedSizeB: ControlSize = .regular
    @State private var selectedTextColorB: NamedColor = .default
    @State private var selectedBgColorB: NamedBgColor = .default
    @State private var placeholderTextB: String = "Record Shortcut"
    @State private var selectedSensitivityModeB: SensitivityMode = .discrete
    @State private var selectedSensitivityPositionB: SensitivityPosition = .below

    // Counters: single shortcut
    @State private var matchCountA = 0
    @State private var lastMatchedA = false
    @State private var matchCountB = 0
    @State private var lastMatchedB = false

    // Counters: sequence
    @State private var seqAMatchCount = 0
    @State private var seqALastMatched = false
    @State private var seqBMatchCount = 0
    @State private var seqBLastMatched = false

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                controlsPanel(
                    style: $selectedStyleA,
                    size: $selectedSizeA,
                    textColor: $selectedTextColorA,
                    bgColor: $selectedBgColorA,
                    placeholder: $placeholderTextA,
                    sensitivityMode: $selectedSensitivityModeA,
                    sensitivityPosition: $selectedSensitivityPositionA
                )
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
            }
            .frame(width: 260)
            .background(Color.gray.opacity(0.04))

            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    shortcutSection()
                    Divider()
                    sequenceSection()
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.08))

            Divider()

            ScrollView {
                controlsPanel(
                    style: $selectedStyleB,
                    size: $selectedSizeB,
                    textColor: $selectedTextColorB,
                    bgColor: $selectedBgColorB,
                    placeholder: $placeholderTextB,
                    sensitivityMode: $selectedSensitivityModeB,
                    sensitivityPosition: $selectedSensitivityPositionB
                )
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
            }
            .frame(width: 260)
            .background(Color.gray.opacity(0.04))
        }
    }

    // MARK: Section Helpers

    @ViewBuilder
    private func shortcutSection() -> some View {
        let content = VStack(spacing: 12) {
            sectionHeading(
                "Shortcut",
                counterA: counterChip(count: matchCountA, lit: lastMatchedA) { matchCountA = 0 },
                counterB: counterChip(count: matchCountB, lit: lastMatchedB) { matchCountB = 0 }
            )

            HStack(alignment: .top, spacing: 16) {
                fieldColumn {
                    makeRecorder($shortcutA, style: selectedStyleA, size: selectedSizeA,
                                 textColor: selectedTextColorA.nsColor, bgColor: selectedBgColorA.nsColor,
                                 placeholder: placeholderTextA,
                                 sensitivityMode: selectedSensitivityModeA,
                                 sensitivityPosition: selectedSensitivityPositionA)
                        .frame(width: shortcutFrameWidth(
                            shortcut: shortcutA, position: selectedSensitivityPositionA
                        ))

                    if let shortcutA {
                        Text(shortcutA.displayString)
                            .font(.title.monospaced())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No shortcut")
                            .foregroundStyle(.tertiary)
                    }
                }

                fieldColumn {
                    makeRecorder($shortcutB, style: selectedStyleB, size: selectedSizeB,
                                 textColor: selectedTextColorB.nsColor, bgColor: selectedBgColorB.nsColor,
                                 placeholder: placeholderTextB,
                                 sensitivityMode: selectedSensitivityModeB,
                                 sensitivityPosition: selectedSensitivityPositionB)
                        .frame(width: shortcutFrameWidth(
                            shortcut: shortcutB, position: selectedSensitivityPositionB
                        ))

                    if let shortcutB {
                        Text(shortcutB.displayString)
                            .font(.title.monospaced())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No shortcut")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }

        if #available(macOS 14.0, *) {
            content
                .onShortcut(shortcutA) { fire($matchCountA, $lastMatchedA) }
                .onShortcut(shortcutB) { fire($matchCountB, $lastMatchedB) }
        } else {
            content
        }
    }

    @ViewBuilder
    private func sequenceSection() -> some View {
        let content = VStack(spacing: 12) {
            sectionHeading(
                "Sequence",
                counterA: counterChip(count: seqAMatchCount, lit: seqALastMatched) { seqAMatchCount = 0 },
                counterB: counterChip(count: seqBMatchCount, lit: seqBLastMatched) { seqBMatchCount = 0 }
            )

            HStack(alignment: .top, spacing: 16) {
                fieldColumn {
                    makeSequenceRecorder($sequenceA, style: selectedStyleA, size: selectedSizeA,
                                         textColor: selectedTextColorA.nsColor,
                                         bgColor: selectedBgColorA.nsColor)
                        .frame(width: 220)

                    if let sequenceA {
                        Text(sequenceA.displayString)
                            .font(.title.monospaced())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No sequence")
                            .foregroundStyle(.tertiary)
                    }
                }

                fieldColumn {
                    makeSequenceRecorder($sequenceB, style: selectedStyleB, size: selectedSizeB,
                                         textColor: selectedTextColorB.nsColor,
                                         bgColor: selectedBgColorB.nsColor)
                        .frame(width: 220)

                    if let sequenceB {
                        Text(sequenceB.displayString)
                            .font(.title.monospaced())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No sequence")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }

        if #available(macOS 14.0, *) {
            content
                .onShortcutSequence(sequenceA) { fire($seqAMatchCount, $seqALastMatched) }
                .onShortcutSequence(sequenceB) { fire($seqBMatchCount, $seqBLastMatched) }
        } else {
            content
        }
    }

    private func shortcutFrameWidth(shortcut: Shortcut?, position: SensitivityPosition) -> CGFloat {
        guard let shortcut, Shortcut.isContinuous(shortcut.kind), position != .below else {
            return 220
        }
        return 320
    }

    private func fieldColumn(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 8) {
            content()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Heading + Counter Chip

    private func sectionHeading(
        _ title: String,
        counterA: some View,
        counterB: some View
    ) -> some View {
        HStack(spacing: 12) {
            counterA
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(title)
                .font(.title3)
                .foregroundColor(.white)
            counterB
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func counterChip(count value: Int, lit: Bool, onReset: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(lit ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)
            Text("\(value)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            if value > 0 {
                Button(action: onReset) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func fire(_ count: Binding<Int>, _ lit: Binding<Bool>) {
        count.wrappedValue += 1
        lit.wrappedValue = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            lit.wrappedValue = false
        }
    }

    private func makeRecorder(_ shortcut: Binding<Shortcut?>, style: ShortcutRecorderStyle,
                              size: ControlSize, textColor: NSColor?, bgColor: NSColor?,
                              placeholder: String, sensitivityMode: SensitivityMode,
                              sensitivityPosition: SensitivityPosition) -> some View
    {
        var view = ShortcutRecorderView(shortcut)
            .placeholder(placeholder)
            .style(style)
            .sensitivityMode(sensitivityMode)
            .sensitivityPosition(sensitivityPosition)
        if let textColor { view = view.textColor(textColor) }
        if let bgColor { view = view.fieldBackgroundColor(bgColor) }
        return view.controlSize(size)
    }

    private func makeSequenceRecorder(_ sequence: Binding<ShortcutSequence?>, style: ShortcutRecorderStyle,
                                      size: ControlSize, textColor: NSColor?, bgColor: NSColor?) -> some View
    {
        var view = ShortcutSequenceRecorderView(sequence)
            .placeholder("Record Sequence")
            .style(style)
        if let textColor { view = view.textColor(textColor) }
        if let bgColor { view = view.fieldBackgroundColor(bgColor) }
        return view.controlSize(size)
    }

    // MARK: Controls Panel

    private func controlsPanel(
        style: Binding<ShortcutRecorderStyle>,
        size: Binding<ControlSize>,
        textColor: Binding<NamedColor>,
        bgColor: Binding<NamedBgColor>,
        placeholder: Binding<String>,
        sensitivityMode: Binding<SensitivityMode>,
        sensitivityPosition: Binding<SensitivityPosition>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                Text("Style")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: style) {
                    Text(".rounded").tag(ShortcutRecorderStyle.rounded)
                    Text(".plain").tag(ShortcutRecorderStyle.plain)
                    Text(".borderless").tag(ShortcutRecorderStyle.borderless)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            Group {
                Text("Size")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: size) {
                    Text(".mini").tag(ControlSize.mini)
                    Text(".small").tag(ControlSize.small)
                    Text(".regular").tag(ControlSize.regular)
                    Text(".large").tag(ControlSize.large)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            colorRow(textColor: textColor, bgColor: bgColor)

            Group {
                Text("Placeholder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Placeholder text", text: placeholder)
            }

            Group {
                Text("Sensitivity mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: sensitivityMode) {
                    Text(".discrete").tag(SensitivityMode.discrete)
                    Text(".continuous").tag(SensitivityMode.continuous)
                    Text(".hidden").tag(SensitivityMode.hidden)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            Group {
                Text("Sensitivity position")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: sensitivityPosition) {
                    Text(".below").tag(SensitivityPosition.below)
                    Text(".left").tag(SensitivityPosition.left)
                    Text(".right").tag(SensitivityPosition.right)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func colorRow(
        textColor: Binding<NamedColor>,
        bgColor: Binding<NamedBgColor>
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Text color")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: textColor) {
                    ForEach(NamedColor.allCases) { color in
                        Text(color.label).tag(color)
                    }
                }
                .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Background")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: bgColor) {
                    ForEach(NamedBgColor.allCases) { color in
                        Text(color.label).tag(color)
                    }
                }
                .labelsHidden()
            }
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
        GridItem(.adaptive(minimum: 170, maximum: 200), spacing: 16),
    ]

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 0) {
                column("Shortcuts") {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(GalleryItem.allItems) { item in
                            GalleryCard(item: item)
                        }
                    }
                }

                Divider()

                column("Shortcut Sequences") {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(SequenceGalleryItem.allItems) { item in
                            SequenceGalleryCard(item: item)
                        }
                    }
                }
            }
            .padding(.vertical, 24)
        }
    }

    @ViewBuilder
    private func column(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
        GalleryItem("Blue tint bg", bgColor: NSColor.systemBlue.withAlphaComponent(0.1)),
        GalleryItem("Dark bg + white text", textColor: .white, bgColor: .darkGray),
    ]
}

// MARK: - Sequence Gallery

struct SequenceGalleryCard: View {
    let item: SequenceGalleryItem
    @State private var sequence: ShortcutSequence?

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
        var view = ShortcutSequenceRecorderView($sequence).style(item.style)
        if let textColor = item.textColor { view = view.textColor(textColor) }
        if let bgColor = item.bgColor { view = view.fieldBackgroundColor(bgColor) }
        return view.controlSize(item.size)
    }
}

struct SequenceGalleryItem: Identifiable {
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

    static let allItems: [SequenceGalleryItem] = [
        SequenceGalleryItem("Default"),
        SequenceGalleryItem(".plain", style: .plain),
        SequenceGalleryItem(".borderless", style: .borderless),
        SequenceGalleryItem(".mini", size: .mini),
        SequenceGalleryItem(".large", size: .large),
        SequenceGalleryItem("Teal text", textColor: .systemTeal),
        SequenceGalleryItem("Blue tint bg", bgColor: NSColor.systemBlue.withAlphaComponent(0.1)),
        SequenceGalleryItem("Dark bg + white text", textColor: .white, bgColor: .darkGray),
    ]
}
