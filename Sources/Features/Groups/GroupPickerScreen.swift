import SwiftUI

/// The EPITA group tree, searchable and multi-selectable. Shared by onboarding and settings.
struct GroupPickerScreen: View {
    var isOnboarding: Bool = false
    var onDone: (() -> Void)? = nil

    @Environment(ReferenceStore.self) private var reference
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""
    @State private var expanded: Set<String> = []

    private var nodes: [GroupNode] {
        GroupTree.filter(reference.groupTree, query: search)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !preferences.selectedGroupIDs.isEmpty {
                selectionStrip
            }

            if reference.isLoadingGroups, reference.groupTree.isEmpty {
                VStack(spacing: 10) {
                    ForEach(0 ..< 6, id: \.self) { _ in SkeletonBlock(height: 44, radius: 14) }
                }
                .padding(Metrics.gutter)
            } else if reference.groupTree.isEmpty {
                EmptyStateView(
                    symbol: "person.2.slash",
                    title: "Groupes indisponibles",
                    message: reference.error ?? "Impossible de récupérer la liste des groupes.",
                    actionTitle: "Réessayer",
                    action: { Task { await reference.loadGroups(force: true) } }
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(nodes) { node in
                            GroupRow(node: node, depth: 0, expanded: $expanded, autoExpand: !search.isEmpty)
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.vertical, 10)
                    .padding(.bottom, 24)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .searchable(text: $search, prompt: "Chercher un groupe")
        .auroraBackdrop(animated: false)
        .navigationTitle("Mes groupes")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) {
            if isOnboarding {
                Button {
                    Haptics.success()
                    onDone?()
                } label: {
                    Text("Continuer")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .disabled(preferences.selectedGroupIDs.isEmpty)
                .padding(Metrics.gutter)
            }
        }
        .task { await reference.loadGroups() }
    }

    private var selectionStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(preferences.selectedGroupIDs, id: \.self) { id in
                    Button {
                        Haptics.tap()
                        withAnimation(Motion.snappy) {
                            preferences.selectedGroupIDs.removeAll { $0 == id }
                            preferences.selectedGroupNames[id] = nil
                        }
                    } label: {
                        GlassPill(tint: Theme.accent) {
                            HStack(spacing: 5) {
                                Text(preferences.selectedGroupNames[id] ?? id)
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
    }
}

private struct GroupRow: View {
    let node: GroupNode
    let depth: Int
    @Binding var expanded: Set<String>
    let autoExpand: Bool

    @Environment(Preferences.self) private var preferences

    private var isOpen: Bool { autoExpand || expanded.contains(node.id) }
    private var isSelected: Bool { preferences.selectedGroupIDs.contains(node.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if !node.isLeaf {
                    Button {
                        withAnimation(Motion.snappy) {
                            if expanded.contains(node.id) { expanded.remove(node.id) } else { expanded.insert(node.id) }
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                            .frame(width: 20, height: 20)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isOpen ? "Replier" : "Déplier")
                } else {
                    Spacer().frame(width: 20)
                }

                Button {
                    Haptics.select()
                    withAnimation(Motion.snappy) { preferences.select(node) }
                } label: {
                    HStack(spacing: 10) {
                        Text(node.name)
                            .font(.system(size: 14, weight: isSelected ? .semibold : .regular, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(isSelected ? Theme.accent : Theme.hairline)
                            .symbolEffect(.bounce, value: isSelected)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Theme.accent.opacity(0.12) : Theme.surface.opacity(0.35))
            }
            .padding(.leading, CGFloat(depth) * 14)

            if isOpen {
                ForEach(node.children) { child in
                    GroupRow(node: child, depth: depth + 1, expanded: $expanded, autoExpand: autoExpand)
                }
            }
        }
    }
}
