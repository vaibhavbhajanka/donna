import SwiftUI

struct AssistantInputView: View {
    @Binding var text: String
    var onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextEditor(text: $text)
                .font(.system(size: 14))
                .frame(minHeight: 44, maxHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(spacing: 6) {
                Button(action: onSend) {
                    Image(systemName: "paperplane.fill")
                        .imageScale(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Text("Cmd+Return")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct AssistantInputView_Previews: PreviewProvider {
    static var previews: some View {
        AssistantInputView(text: .constant(""), onSend: {})
            .padding()
            .frame(width: 720)
    }
}
