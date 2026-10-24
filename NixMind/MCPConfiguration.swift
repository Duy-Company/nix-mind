import Foundation

enum MCPClientFormat: String, CaseIterable, Identifiable {
    case vscode = "VS Code"
    case standard = "Other clients (mcpServers)"
    var id: String { rawValue }
    var instructions: String {
        switch self {
        case .vscode: return "In VS Code's mcp.json, merge nix-mind directly into the top-level servers object. Do not put mcpServers inside servers."
        case .standard: return "Use this format for clients that expect a top-level mcpServers object. For VS Code's mcp.json, select VS Code above."
        }
    }
}

enum MCPConfiguration {
    static func json(executable: String, format: MCPClientFormat) -> String {
        var server: [String: Any] = ["command": executable, "args": ["--mcp"]]
        if format == .vscode { server["type"] = "stdio" }
        let key = format == .vscode ? "servers" : "mcpServers"
        let object = [key: ["nix-mind": server]]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
