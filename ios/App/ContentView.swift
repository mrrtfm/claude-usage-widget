import SwiftUI
import ClaudeUsageKit

// account list + pull-to-refresh. the iPhone counterpart of the macOS dropdown panel.
struct ContentView: View {
    @Environment(UsageStore.self) private var store
    @State private var showSettings = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Group {
                if store.states.isEmpty {
                    emptyState
                } else {
                    cardList
                }
            }
            .navigationTitle("Claude Usage")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.addAccount() } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $store.showingLogin) {
                NavigationStack {
                    LoginWebView { store.finishLogin($0) }
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle("Sign in to Claude")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { store.showingLogin = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView().environment(store)
            }
        }
    }

    private var cardList: some View {
        List {
            ForEach(store.states) { state in
                AccountCardView(state: state)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { store.remove(state.account.id) } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
            }
            if let last = store.lastRefresh {
                Text("updated \(last, format: .relative(presentation: .numeric))")
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .refreshable { await store.refreshAll() }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No accounts yet", systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text("Add a Claude account to track its session and weekly limits.")
        } actions: {
            Button("Add account") { store.addAccount() }
                .buttonStyle(.borderedProminent)
        }
    }
}
