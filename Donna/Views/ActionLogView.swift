import SwiftUI

struct ActionLogView: View {
    let entries: [ActionLogEntry]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(entries) { entry in
                        Text(entry.text)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .id(entry.id)
                    }
                }
                .padding(10)
            }
            .onChange(of: entries.count) { _ in
                if let lastId = entries.last?.id {
                    withAnimation(.linear(duration: 0.15)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }
}

struct ActionLogView_Previews: PreviewProvider {
    static var previews: some View {
        ActionLogView(entries: [
            ActionLogEntry(text: "Thinking…"),
            ActionLogEntry(text: "Preparing response…"),
            ActionLogEntry(text: "Generating reply (local)…"),
            ActionLogEntry(text: "Done.")
        ])
        .frame(height: 140)
        .padding()
    }
}
