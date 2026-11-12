import Foundation

/// A `StudyGroup` with its descendants resolved, ready for an outline list.
struct GroupNode: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var children: [GroupNode]

    var isLeaf: Bool { children.isEmpty }

    /// Every id in this subtree, including this node's own.
    var subtreeIDs: [String] {
        [id] + children.flatMap(\.subtreeIDs)
    }
}

enum GroupTree {
    static func build(from groups: [StudyGroup]) -> [GroupNode] {
        var childrenByParent: [String: [StudyGroup]] = [:]
        var roots: [StudyGroup] = []
        let known = Set(groups.map(\.id))

        for group in groups {
            if let parent = group.parentID, parent != group.id, known.contains(parent) {
                childrenByParent[parent, default: []].append(group)
            } else {
                roots.append(group)
            }
        }

        func node(for group: StudyGroup) -> GroupNode {
            let children = (childrenByParent[group.id] ?? []).map(node(for:)).sorted(by: compare)
            return GroupNode(id: group.id, name: group.name, children: children)
        }

        return roots.map(node(for:)).sorted(by: compare)
    }

    private static func compare(_ lhs: GroupNode, _ rhs: GroupNode) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    /// Keeps a node when it matches, or when any descendant does.
    static func filter(_ nodes: [GroupNode], query: String) -> [GroupNode] {
        let term = query.trimmed
        guard !term.isEmpty else { return nodes }
        return nodes.compactMap { node in
            let children = filter(node.children, query: term)
            let matches = node.name.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            guard matches || !children.isEmpty else { return nil }
            return GroupNode(id: node.id, name: node.name, children: children)
        }
    }

    static func find(_ nodes: [GroupNode], id: String) -> GroupNode? {
        for node in nodes {
            if node.id == id { return node }
            if let match = find(node.children, id: id) { return match }
        }
        return nil
    }

    /// Breadcrumb from the root down to `id`, used to label a selection.
    static func path(_ nodes: [GroupNode], to id: String) -> [GroupNode] {
        for node in nodes {
            if node.id == id { return [node] }
            let sub = path(node.children, to: id)
            if !sub.isEmpty { return [node] + sub }
        }
        return []
    }
}
