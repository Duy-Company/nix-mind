import SwiftUI

struct TopicSearchPopup: View {
    @ObservedObject var store: MapStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var scope = TopicSearchScope.sheet
    @State private var response = TopicSearchResponse()
    @State private var selectedID: String?
    @State private var searching = false
    @State private var cachedIndex: TopicSearchIndex?
    @State private var cachedKey: IndexKey?
    @State private var completedSearch: String?
    private let accent = Color(nsColor: Palette.purple)

    private struct IndexKey: Equatable, Sendable { let revision: UInt64; let sheetID: String? }
    private struct Request: Hashable, Sendable {
        let query: String, scope: TopicSearchScope, revision: UInt64, sheetID: String
    }
    private var request: Request { Request(query: query, scope: scope, revision: store.mapRevision, sheetID: store.activeSheet.id) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.black.opacity(0.12).contentShape(Rectangle()).onTapGesture { store.dismissSearch() }
                    .accessibilityLabel("Close search").accessibilityAddTraits(.isButton)
                VStack(spacing: 0) {
                    searchField
                    Divider().opacity(0.6)
                    HStack {
                        Picker("Search in", selection: $scope) {
                            Text("This sheet").tag(TopicSearchScope.sheet)
                            Text("All sheets").tag(TopicSearchScope.workbook)
                        }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Search in").frame(width: 220)
                            .onChange(of: scope) { _, _ in store.searchFocusRequest = UUID() }
                        Spacer()
                        if searching { ProgressView().controlSize(.small) }
                        else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("\(response.total) \(response.total == 1 ? "result" : "results")").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }.padding(.horizontal, 20).padding(.vertical, 12)
                    results.frame(height: min(370, max(200, geometry.size.height - 280)))
                    Divider().opacity(0.6)
                    HStack(spacing: 12) {
                        Label("↑ ↓  Navigate", systemImage: "keyboard")
                        Text("↵  Go to topic")
                        Spacer()
                        Text(response.total > response.results.count ? "Showing top \(response.results.count)" : "esc  Close")
                    }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 13)
                }
                .frame(width: min(700, geometry.size.width - 64))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.65), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 32, y: 14)
                .padding(.top, min(90, geometry.size.height * 0.12))
                .onExitCommand { store.dismissSearch() }
                .task(id: request) { await search(request) }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 21, weight: .medium)).foregroundStyle(accent)
            TopicSearchInput(query: $query, focusRequest: store.searchFocusRequest,
                             moveSelection: moveSelection, submit: activateSelected, dismiss: store.dismissSearch)
                .frame(height: 28)
            if !query.isEmpty {
                Button { query = ""; store.searchFocusRequest = UUID() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
            Button { store.dismissSearch() } label: { Text("esc").font(.system(size: 10, design: .monospaced)).padding(.horizontal, 7).padding(.vertical, 4).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5)) }
                .buttonStyle(.plain).accessibilityLabel("Close search")
        }.padding(21)
    }

    private var results: some View {
        Group {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(spacing: 13) {
                    Image(systemName: "text.magnifyingglass").font(.system(size: 34, weight: .light)).foregroundStyle(accent.opacity(0.7))
                    Text("Find your next idea").font(.system(size: 17, weight: .semibold))
                    Text("Search titles and notes. Try initials, missing accents, or a small typo in a title.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    HStack(spacing: 7) { hint("Any word order"); hint("Acronyms"); hint("Typos welcome") }.padding(.top, 5)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searching {
                VStack(spacing: 10) { ProgressView(); Text("Finding ideas…").font(.system(size: 12)).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if response.results.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 26)).foregroundStyle(.secondary)
                    Text("No matching topics").font(.system(size: 15, weight: .semibold))
                    Text("Try fewer words or search all sheets.").font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(response.results) { result in
                                Button { store.revealSearchResult(result) } label: { resultRow(result) }
                                    .buttonStyle(.plain).id(result.id)
                                    .accessibilityLabel("\(result.title), \(result.breadcrumb)")
                            }
                        }.padding(10)
                    }.onChange(of: selectedID) { _, id in
                        if let id { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { proxy.scrollTo(id) } }
                    }
                }
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 5)
            .foregroundStyle(accent).background(accent.opacity(0.07), in: Capsule())
    }

    private func resultRow(_ result: TopicSearchResult) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: result.noteHighlights.isEmpty ? "circle.dotted.circle" : "text.alignleft")
                .font(.system(size: 16)).foregroundStyle(accent).frame(width: 22).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(highlight(result.titlePreview, ranges: result.titleHighlights)).font(.system(size: 14)).lineLimit(3)
                if !result.notePreview.isEmpty {
                    Text(highlight(result.notePreview, ranges: result.noteHighlights)).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3)
                }
                Text(result.breadcrumb).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if result.isFuzzy { Text("Similar").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).padding(5).background(.primary.opacity(0.04), in: Capsule()) }
            if selectedID == result.id { Image(systemName: "return").font(.system(size: 12)).foregroundStyle(accent).padding(.top, 3) }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .background(selectedID == result.id ? accent.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 11))
    }

    private func highlight(_ string: String, ranges: [NSRange]) -> AttributedString {
        var value = AttributedString(string)
        for range in ranges {
            if let original = Range(range, in: string),
               let lower = AttributedString.Index(original.lowerBound, within: value),
               let upper = AttributedString.Index(original.upperBound, within: value) {
                value[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
                value[lower..<upper].foregroundColor = accent
                value[lower..<upper].backgroundColor = accent.opacity(0.09)
            }
        }
        return value
    }

    private func moveSelection(_ offset: Int) {
        guard !searching, !response.results.isEmpty else { return }
        let index = response.results.firstIndex(where: { $0.id == selectedID }) ?? 0
        selectedID = response.results[(index + offset + response.results.count) % response.results.count].id
    }

    private func activateSelected() {
        guard !searching, let result = response.results.first(where: { $0.id == selectedID }) else { return }
        store.revealSearchResult(result)
    }

    @MainActor private func search(_ request: Request) async {
        guard !request.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            response = TopicSearchResponse(); selectedID = nil; searching = false; return
        }
        searching = true
        do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
        let key = IndexKey(revision: request.revision, sheetID: request.scope == .sheet ? request.sheetID : nil)
        let previous = cachedKey == key ? cachedIndex : nil
        let book = store.workbook
        let worker = Task.detached(priority: .userInitiated) {
            let index = previous ?? TopicSearchIndex(book: book, sheetID: key.sheetID)
            return (index, index.search(request.query))
        }
        let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
        guard !Task.isCancelled else { return }
        cachedIndex = result.0; cachedKey = key; response = result.1; searching = false
        let searchKey = request.scope.rawValue + "\0" + request.query
        if completedSearch != searchKey || !response.results.contains(where: { $0.id == selectedID }) { selectedID = response.results.first?.id }
        completedSearch = searchKey
    }
}
