public struct ArchetypeLookup: Sendable {
    // Maps each component ID to a set of archetype indices that have it
    public private(set) var map: [ComponentID: Set<Int>] = [:]
    public private(set) var version: UInt64 = 0

    public mutating func add(_ index: Int, for componentIDs: some Collection<ComponentID>) {
        for id in componentIDs {
            map[id, default: []].insert(index)
        }
        version += 1
    }

    public mutating func remove(_ index: Int, for componentIDs: some Collection<ComponentID>) {
        for id in componentIDs {
            map[id, default: []].remove(index)
        }
        version += 1
    }

    public func indices(
        containing included: Set<ComponentID>,
        excluding excluded: Set<ComponentID>
    ) -> Set<Int> {
        guard !included.isEmpty else { return [] }

        var result = map[included.first!, default: []]

        for id in included.dropFirst() {
            result.formIntersection(map[id, default: []])
            if result.isEmpty { break }
        }

        for id in excluded {
            result.subtract(map[id, default: []])
            if result.isEmpty { break }
        }

        return result
    }
}
