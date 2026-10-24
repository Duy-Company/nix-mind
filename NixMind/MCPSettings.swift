import SwiftUI
import AppKit

struct MCPSettings: View {
    @ObservedObject private var mcp = MCPState.shared
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 28)).foregroundStyle(Color(nsColor: Palette.purple))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Local MCP").font(.system(size: 23, weight: .semibold))
                    Text("Connect an AI client to your open mind maps.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Toggle("Enable local MCP", isOn: Binding(get: { mcp.enabled }, set: { mcp.setEnabled($0) })).toggleStyle(.switch)
            Label(mcp.running ? "Ready for local clients" : "Not connected", systemImage: mcp.running ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12)).foregroundStyle(mcp.running ? Color.green : .secondary)
            Text("MCP clients can read and edit topics, format nodes, manage sheets, and save or export files. Changes appear in the app and support Undo.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            Text("CLIENT CONFIGURATION").font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary)
            ScrollView([.horizontal, .vertical]) {
                Text(mcp.configuration).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }.frame(height: 180).background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(mcp.configuration, forType: .string); copied = true } label: { Label(copied ? "Configuration copied" : "Copy MCP configuration", systemImage: "doc.on.doc") }.buttonStyle(.borderedProminent).tint(Color(nsColor: Palette.purple))
                Spacer()
            }
            Text("Keep Nix Mind open while your client is connected. The local connection uses a private Unix socket on this Mac.").font(.system(size: 11)).foregroundStyle(.secondary)
            if !mcp.lastActivity.isEmpty { Label(mcp.lastActivity, systemImage: "clock").font(.system(size: 11)).foregroundStyle(.secondary) }
            if let error = mcp.error { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
        }.padding(28).frame(width: 590).background(.white).preferredColorScheme(.light)
    }
}
