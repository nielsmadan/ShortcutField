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
        .frame(minWidth: 1000, minHeight: 600)
    }
}

// MARK: - Workbench

struct WorkbenchTab: View {
    // Inputs
    @State private var shortcutA: DiscreteShortcut?
    @State private var shortcutB: DiscreteShortcut?
    @State private var continuousA: ContinuousShortcut?
    @State private var continuousB: ContinuousShortcut?

    // Controls A
    @State private var selectedTextColorA: NamedColor = .default
    @State private var selectedWidthA: NamedWidth = .medium
    @State private var placeholderTextA: String = "Record Shortcut"
    @State private var selectedSensitivityModeA: SensitivityMode = .discrete
    @State private var selectedSensitivityPositionA: SensitivityPosition = .below

    // Controls B
    @State private var selectedTextColorB: NamedColor = .default
    @State private var selectedWidthB: NamedWidth = .medium
    @State private var placeholderTextB: String = "Record Shortcut"
    @State private var selectedSensitivityModeB: SensitivityMode = .discrete
    @State private var selectedSensitivityPositionB: SensitivityPosition = .below

    // Counters: Shortcut
    @State private var matchCountA = 0
    @State private var lastMatchedA = false
    @State private var matchCountB = 0
    @State private var lastMatchedB = false

    // Counters: ContinuousShortcut
    @State private var contAMatchCount = 0
    @State private var contALastMatched = false
    @State private var contBMatchCount = 0
    @State private var contBLastMatched = false

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                controlsPanel(
                    textColor: $selectedTextColorA,
                    width: $selectedWidthA,
                    placeholder: $placeholderTextA,
                    sensitivityMode: $selectedSensitivityModeA,
                    sensitivityPosition: $selectedSensitivityPositionA
                )
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
            }
            .frame(width: 240)
            .background(Color.gray.opacity(0.04))
            .padding(12)

            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    shortcutSection()
                    Divider()
                    continuousSection()
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.08))

            Divider()

            ScrollView {
                controlsPanel(
                    textColor: $selectedTextColorB,
                    width: $selectedWidthB,
                    placeholder: $placeholderTextB,
                    sensitivityMode: $selectedSensitivityModeB,
                    sensitivityPosition: $selectedSensitivityPositionB
                )
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
            }
            .frame(width: 240)
            .background(Color.gray.opacity(0.04))
            .padding(12)
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
                    makeRecorder($shortcutA, textColor: selectedTextColorA.color,
                                 placeholder: placeholderTextA)
                        .frame(width: selectedWidthA.value)

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
                    makeRecorder($shortcutB, textColor: selectedTextColorB.color,
                                 placeholder: placeholderTextB)
                        .frame(width: selectedWidthB.value)

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

        content
            .onShortcut(shortcutA.map(Shortcut.discrete)) { fire($matchCountA, $lastMatchedA) }
            .onShortcut(shortcutB.map(Shortcut.discrete)) { fire($matchCountB, $lastMatchedB) }
    }

    @ViewBuilder
    private func continuousSection() -> some View {
        let content = VStack(spacing: 12) {
            sectionHeading(
                "Continuous",
                counterA: counterChip(count: contAMatchCount, lit: contALastMatched) { contAMatchCount = 0 },
                counterB: counterChip(count: contBMatchCount, lit: contBLastMatched) { contBMatchCount = 0 }
            )

            HStack(alignment: .top, spacing: 16) {
                fieldColumn {
                    makeContinuousRecorder($continuousA,
                                           textColor: selectedTextColorA.color,
                                           placeholder: "Record Continuous",
                                           sensitivityMode: selectedSensitivityModeA,
                                           sensitivityPosition: selectedSensitivityPositionA)
                        .frame(width: continuousFrameWidth(
                            base: selectedWidthA.value,
                            position: selectedSensitivityPositionA
                        ))

                    if let continuousA {
                        Text(continuousA.displayString)
                            .font(.title.monospaced())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No continuous")
                            .foregroundStyle(.tertiary)
                    }
                }

                fieldColumn {
                    makeContinuousRecorder($continuousB,
                                           textColor: selectedTextColorB.color,
                                           placeholder: "Record Continuous",
                                           sensitivityMode: selectedSensitivityModeB,
                                           sensitivityPosition: selectedSensitivityPositionB)
                        .frame(width: continuousFrameWidth(
                            base: selectedWidthB.value,
                            position: selectedSensitivityPositionB
                        ))

                    if let continuousB {
                        Text(continuousB.displayString)
                            .font(.title.monospaced())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No continuous")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }

        content
            .onShortcut(continuousA.map(Shortcut.continuous)) { fire($contAMatchCount, $contALastMatched) }
            .onShortcut(continuousB.map(Shortcut.continuous)) { fire($contBMatchCount, $contBLastMatched) }
    }

    private func continuousFrameWidth(base: CGFloat, position: SensitivityPosition) -> CGFloat {
        // Reserve extra horizontal room for the slider when it sits next to the field.
        position == .below ? base : base + 100
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

    private func makeRecorder(_ shortcut: Binding<DiscreteShortcut?>,
                              textColor: Color?,
                              placeholder: String) -> some View
    {
        var view = ShortcutRecorderView(shortcut)
            .placeholder(placeholder)
        if let textColor { view = view.textColor(textColor) }
        return view
    }

    private func makeContinuousRecorder(
        _ shortcut: Binding<ContinuousShortcut?>,
        textColor: Color?,
        placeholder: String,
        sensitivityMode: SensitivityMode,
        sensitivityPosition: SensitivityPosition
    ) -> some View {
        var view = ContinuousShortcutRecorderView(shortcut)
            .placeholder(placeholder)
            .sensitivityMode(sensitivityMode)
            .sensitivityPosition(sensitivityPosition)
        if let textColor { view = view.textColor(textColor) }
        return view
    }

    // MARK: Controls Panel

    private func controlsPanel(
        textColor: Binding<NamedColor>,
        width: Binding<NamedWidth>,
        placeholder: Binding<String>,
        sensitivityMode: Binding<SensitivityMode>,
        sensitivityPosition: Binding<SensitivityPosition>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
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

            Group {
                Text("Width")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: width) {
                    ForEach(NamedWidth.allCases) { w in
                        Text(w.label).tag(w)
                    }
                }
                .labelsHidden()
            }

            Group {
                Text("Placeholder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Placeholder text", text: placeholder)
            }

            Group {
                Text("Sensitivity mode (Continuous only)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: sensitivityMode) {
                    Text(".discrete").tag(SensitivityMode.discrete)
                    Text(".continuous").tag(SensitivityMode.continuous)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            Group {
                Text("Sensitivity position (Continuous only)")
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
}

// MARK: - Named Width Enum

enum NamedWidth: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: "Small (120)"
        case .medium: "Medium (160)"
        case .large: "Large (200)"
        }
    }

    var value: CGFloat {
        switch self {
        case .small: 120
        case .medium: 160
        case .large: 200
        }
    }
}

// MARK: - Named Color Enum

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

    var color: Color? {
        switch self {
        case .default: nil
        case .teal: .teal
        case .orange: .orange
        case .indigo: .indigo
        case .white: .white
        }
    }
}

// MARK: - Gallery

struct GalleryTab: View {
    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16),
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

                column("Continuous Shortcuts") {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(ContinuousGalleryItem.allItems) { item in
                            ContinuousGalleryCard(item: item)
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
                .frame(maxWidth: .infinity, alignment: .center)
            content()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct GalleryCard: View {
    let item: GalleryItem
    @State private var shortcut: DiscreteShortcut?

    var body: some View {
        VStack(spacing: 8) {
            cardRecorder

            Text(item.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var cardRecorder: some View {
        var view = ShortcutRecorderView($shortcut)
        if let textColor = item.textColor { view = view.textColor(textColor) }
        return view
            .disabled(item.disabled)
            .frame(width: item.width ?? 160)
    }
}

struct GalleryItem: Identifiable {
    let id = UUID()
    let label: String
    let textColor: Color?
    let width: CGFloat?
    let disabled: Bool

    init(
        _ label: String,
        textColor: Color? = nil,
        width: CGFloat? = nil,
        disabled: Bool = false
    ) {
        self.label = label
        self.textColor = textColor
        self.width = width
        self.disabled = disabled
    }

    static let allItems: [GalleryItem] = [
        GalleryItem("Default"),
        GalleryItem("Teal text", textColor: .teal),
        GalleryItem("Orange text", textColor: .orange),
        GalleryItem("Wider (240)", width: 240),
        GalleryItem("Disabled", disabled: true),
    ]
}

// MARK: - Continuous Gallery

struct ContinuousGalleryCard: View {
    let item: ContinuousGalleryItem
    @State private var shortcut: ContinuousShortcut?

    var body: some View {
        VStack(spacing: 8) {
            cardRecorder

            Text(item.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var cardRecorder: some View {
        var view = ContinuousShortcutRecorderView($shortcut)
            .sensitivityMode(item.sensitivityMode)
            .sensitivityPosition(item.sensitivityPosition)
        if let textColor = item.textColor { view = view.textColor(textColor) }
        return view
            .disabled(item.disabled)
            .frame(width: item.width ?? (item.sensitivityPosition == .below ? 160 : 260))
    }
}

struct ContinuousGalleryItem: Identifiable {
    let id = UUID()
    let label: String
    let textColor: Color?
    let width: CGFloat?
    let sensitivityMode: SensitivityMode
    let sensitivityPosition: SensitivityPosition
    let disabled: Bool

    init(
        _ label: String,
        textColor: Color? = nil,
        width: CGFloat? = nil,
        sensitivityMode: SensitivityMode = .discrete,
        sensitivityPosition: SensitivityPosition = .below,
        disabled: Bool = false
    ) {
        self.label = label
        self.textColor = textColor
        self.width = width
        self.sensitivityMode = sensitivityMode
        self.sensitivityPosition = sensitivityPosition
        self.disabled = disabled
    }

    static let allItems: [ContinuousGalleryItem] = [
        ContinuousGalleryItem("Default (slider below, discrete)"),
        ContinuousGalleryItem("Continuous mode", sensitivityMode: .continuous),
        ContinuousGalleryItem("Teal text", textColor: .teal),
        ContinuousGalleryItem("Disabled", disabled: true),
    ]
}
