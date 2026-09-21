import SwiftUI

public struct SeamAdjustmentItem: Identifiable, Sendable {
    public let id: Int // segment index
    public var offsetDelta: Int
    public var isExcluded: Bool

    public init(id: Int, offsetDelta: Int = 0, isExcluded: Bool = false) {
        self.id = id
        self.offsetDelta = offsetDelta
        self.isExcluded = isExcluded
    }
}

public struct SeamAdjusterView: View {
    public let segmentCount: Int
    @Binding public var adjustments: [SeamAdjustmentItem]
    @Environment(\.dismiss) private var dismiss
    public let onApply: () -> Void

    public init(
        segmentCount: Int,
        adjustments: Binding<[SeamAdjustmentItem]>,
        onApply: @escaping () -> Void
    ) {
        self.segmentCount = segmentCount
        self._adjustments = adjustments
        self.onApply = onApply
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("若自动拼接在特定位置产生了微小的错位或重复，你可以上下微调接缝对齐，或将误滚的广告/重复段直接排除。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(0..<segmentCount, id: \.self) { idx in
                    let item = getAdjustment(for: idx)
                    Section("第 \(idx + 1) 个接缝段") {
                        Toggle("保留此段内容", isOn: Binding(
                            get: { !item.isExcluded },
                            set: { newValue in
                                updateExcluded(for: idx, excluded: !newValue)
                            }
                        ))

                        if !item.isExcluded {
                            Stepper("接缝垂直偏移微调: \(item.offsetDelta > 0 ? "+\(item.offsetDelta)" : "\(item.offsetDelta)") px",
                                    value: Binding(
                                        get: { item.offsetDelta },
                                        set: { updateDelta(for: idx, delta: $0) }
                                    ),
                                    in: -80...80,
                                    step: 4)
                        }
                    }
                }
            }
            .navigationTitle("接缝与段落修正")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用并重拼") {
                        dismiss()
                        onApply()
                    }
                    .bold()
                }
            }
        }
    }

    private func getAdjustment(for idx: Int) -> SeamAdjustmentItem {
        if let existing = adjustments.first(where: { $0.id == idx }) {
            return existing
        }
        return SeamAdjustmentItem(id: idx)
    }

    private func updateDelta(for idx: Int, delta: Int) {
        if let index = adjustments.firstIndex(where: { $0.id == idx }) {
            adjustments[index].offsetDelta = delta
        } else {
            adjustments.append(SeamAdjustmentItem(id: idx, offsetDelta: delta, isExcluded: false))
        }
    }

    private func updateExcluded(for idx: Int, excluded: Bool) {
        if let index = adjustments.firstIndex(where: { $0.id == idx }) {
            adjustments[index].isExcluded = excluded
        } else {
            adjustments.append(SeamAdjustmentItem(id: idx, offsetDelta: 0, isExcluded: excluded))
        }
    }
}
