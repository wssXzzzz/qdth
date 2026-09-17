import Foundation

extension VaultIndex {
    /// Merge duplicates by content, preserving either copy's pin and favorite.
    /// A reused identifier with different content receives a new identifier.
    public mutating func merge(_ incoming: VaultIndex) {
        for clip in incoming.clips {
            if let i = clips.firstIndex(where: { $0.text == clip.text }) {
                clips[i].isPinned = clips[i].isPinned || clip.isPinned
                clips[i].isFavorite = clips[i].isFavorite || clip.isFavorite
            } else {
                var new = clip
                if clips.contains(where: { $0.id == new.id }) || sync?.entries[SyncEnvelope.key(new.id, kind: .clip)]?.deleted == true { new.id = UUID() }
                clips.append(new)
            }
        }
        for workflow in incoming.workflows {
            if !workflows.contains(where: { $0.name == workflow.name && $0.steps.map(\.kind) == workflow.steps.map(\.kind) && $0.steps.map(\.search) == workflow.steps.map(\.search) && $0.steps.map(\.replacement) == workflow.steps.map(\.replacement) }) {
                var new = workflow
                if workflows.contains(where: { $0.id == new.id }) || sync?.entries[SyncEnvelope.key(new.id, kind: .workflow)]?.deleted == true { new.id = UUID() }
                workflows.append(new)
            }
        }
    }
}
