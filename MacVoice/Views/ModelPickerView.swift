import SwiftUI

struct ModelPickerView: View {
    @Binding var selection: AsrModel
    var disabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("转写模型")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("全部免费")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.14), in: Capsule())
                    .foregroundStyle(Color.green.opacity(0.9))

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                ForEach(AsrModel.allCases) { model in
                    Button {
                        selection = model
                    } label: {
                        Text(model.label)
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selection == model
                                          ? Color.accentColor.opacity(0.18)
                                          : Color.primary.opacity(0.04))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        selection == model
                                            ? Color.accentColor.opacity(0.55)
                                            : Color.clear,
                                        lineWidth: 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(disabled)
                }
            }

            Text(selection.hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut(duration: 0.15), value: selection)

            Text(AsrModel.freePricingNote)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
