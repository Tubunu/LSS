import SwiftUI

public struct OversizeDecisionSheet: View {
    public let rawHeight: Int
    public let onSelect: (TileRenderer.OversizeStrategy) -> Void
    @Environment(\.dismiss) private var dismiss

    public init(rawHeight: Int, onSelect: @escaping (TileRenderer.OversizeStrategy) -> Void) {
        self.rawHeight = rawHeight
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text("长截图高度达到 \(rawHeight) px")
                    .font(.title3.bold())
                Text("单张超长图在微信等平台发送时可能被强力压缩导致字迹模糊，或导致相册卡顿。请选择生成方式：")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 12) {
                Button {
                    let targetScale = min(1.0, 20000.0 / Double(rawHeight))
                    dismiss()
                    onSelect(.downsample(scale: CGFloat(targetScale)))
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label("自适应降采样", systemImage: "arrow.down.right.and.arrow.up.left")
                                    .font(.headline)
                                Spacer()
                                Text("推荐单图")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.blue)
                            }
                            Text("缩减至安全高度，保留 100% 字体清晰度，发微信不糊、相册秒开。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button {
                    dismiss()
                    onSelect(.slice(maxSliceHeight: TileRenderer.defaultMaxSliceHeight))
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label("长图智能切片", systemImage: "rectangle.split.2x1")
                                    .font(.headline)
                                Spacer()
                                Text("多图分段")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.orange.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.orange)
                            }
                            Text("在自然接缝处智能分页为多张连续原图，保持 3x 原画质，绝对不破字。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.vertical)
        .presentationDetents([.height(390)])
    }
}
