import SwiftUI

struct AssistantResponseView: View {
    let messages: [ChatMessage]
    @State private var isAtBottom: Bool = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            switch message.role {
                            case .user:
                                HStack {
                                    Spacer(minLength: 32)
                                    Text(message.content)
                                        .font(.system(size: 14))
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.accentColor.opacity(0.18))
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .frame(maxWidth: 620, alignment: .trailing)
                                }
                                .id(message.id)
                            case .assistant:
                                Text(message.content)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.secondary.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .frame(maxWidth: 620, alignment: .leading)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 2) // avoid clipping under scrollbar
                    }
                }
                .simultaneousGesture(DragGesture(minimumDistance: 1).onChanged { _ in
                    // User is scrolling manually
                    isAtBottom = false
                })
                .onChange(of: messages.count) { _ in
                    if isAtBottom, let lastId = messages.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    // Start at bottom on appear
                    if let lastId = messages.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }

            if !isAtBottom {
                Button {
                    isAtBottom = true
                    // Programmatic scroll will trigger onChange on next append
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Jump to latest")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(radius: 6)
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
    }
}

struct AssistantResponseView_Previews: PreviewProvider {
    static var previews: some View {
        AssistantResponseView(messages: [
            ChatMessage(role: .user, content: "Send emails to Sarah and Mike"),
            ChatMessage(role: .assistant, content: "Now I’ll send emails to Sarah and Mike, then mark rows green if sent.\n\n1. Draft emails\n2. Send\n3. Update sheet")
        ])
        .padding()
        .frame(width: 720, height: 300)
    }
}
