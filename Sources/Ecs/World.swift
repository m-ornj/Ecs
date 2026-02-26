import Synchronization

private let globalWorldID = Atomic<UInt>(0)

private final class WorldID: Sendable {
    public let id = {
        let (value, _) = globalWorldID.add(1, ordering: .relaxed)
        return value
    }()
}

public struct EntityMetadata: Sendable {
    let archetypeIndex: Int
    let entityIndex: Int

    var isNull: Bool { archetypeIndex == -1 }
    var unwrap: (archetypeIndex: Int, entityIndex: Int) { (archetypeIndex, entityIndex) }

    static let null: EntityMetadata = EntityMetadata(archetypeIndex: -1, entityIndex: 0)
}

public struct World: Sendable {
    private var _id = WorldID()
    public var id: UInt { _id.id }

    public private(set) var entityManager = EntityManager()
    public private(set) var entities: [EntityMetadata] = []
    public private(set) var archetypes: [Archetype] = []
    public private(set) var archetypeIndexByID: [ArchetypeID: Int] = [:]
    public private(set) var groups: [ComponentID: Set<Int>] = [:]
    public private(set) var groupsVersion: UInt = 0

    public init() {}
}

// public
extension World {
    public mutating func create<each T>(
        with components: (repeat each T) = ()
    ) -> Entity {
        ensureUniqueID()
        let entity = entityManager.create()

        let archetypeID = ArchetypeID(Entity.self, repeat (each T).self)
        var archetypeIndex: Int
        if let index = archetypeIndexByID[archetypeID] {
            archetypeIndex = index
        } else {
            archetypeIndex = archetypes.endIndex
            archetypes.append(Archetype(Entity.self, repeat (each T).self))
            archetypeIndexByID[archetypeID] = archetypeIndex
        }

        archetypes[archetypeIndex].append(entity, repeat each components)

        addToGroups(archetypeIndex: archetypeIndex)

        let metadata = EntityMetadata(
            archetypeIndex: archetypeIndex,
            entityIndex: archetypes[archetypeIndex].count - 1
        )
        if entities.indices.contains(entity.id) {
            entities[entity.id] = metadata
        } else {
            entities.append(metadata)
        }

        return entity
    }

    public func isAlive(_ entity: Entity) -> Bool {
        entityManager.isAlive(entity) && !entities[entity.id].isNull
    }

    public mutating func destroy(_ entity: Entity) {
        guard isAlive(entity) else { return }

        ensureUniqueID()

        let (archetypeIndex, entityIndex) = entities[entity.id].unwrap
        removeEntity(archetypeIndex: archetypeIndex, entityIndex: entityIndex)
        entityManager.destroy(entity)
    }

    public mutating func insert<T>(_ component: T, for entity: Entity) {
        precondition(T.self != Entity.self, "Cannot add Entity to an entity")
        guard isAlive(entity) else { return }
        ensureUniqueID()

        let (oldArchetypeIndex, oldEntityIndex) = entities[entity.id].unwrap

        guard !archetypes[oldArchetypeIndex].contains(T.self) else {
            archetypes[oldArchetypeIndex][oldEntityIndex] = component
            return
        }

        let newArchetypeID = archetypes[oldArchetypeIndex].id.adding(T.self)
        var newArchetypeIndex: Int
        if let index = archetypeIndexByID[newArchetypeID] {
            newArchetypeIndex = index
        } else {
            newArchetypeIndex = archetypes.endIndex
            archetypes.append(archetypes[oldArchetypeIndex].adding(T.self, newID: newArchetypeID))
            archetypeIndexByID[newArchetypeID] = newArchetypeIndex
        }

        archetypes[newArchetypeIndex].append(component)
        archetypes[newArchetypeIndex].append(
            from: archetypes[oldArchetypeIndex],
            at: oldEntityIndex
        )

        addToGroups(archetypeIndex: newArchetypeIndex)

        removeEntity(archetypeIndex: oldArchetypeIndex, entityIndex: oldEntityIndex)
        entities[entity.id] = EntityMetadata(
            archetypeIndex: newArchetypeIndex,
            entityIndex: archetypes[newArchetypeIndex].count - 1
        )
    }

    public mutating func remove<T>(_ type: T.Type, for entity: Entity) {
        precondition(T.self != Entity.self, "Cannot remove Entity from an entity")
        guard isAlive(entity) else { return }
        ensureUniqueID()

        let (oldArchetypeIndex, oldEntityIndex) = entities[entity.id].unwrap

        guard archetypes[oldArchetypeIndex].contains(T.self) else { return }

        let newArchetypeID = archetypes[oldArchetypeIndex].id.removing(T.self)
        var newArchetypeIndex: Int
        if let index = archetypeIndexByID[newArchetypeID] {
            newArchetypeIndex = index
        } else {
            newArchetypeIndex = archetypes.endIndex
            archetypes.append(archetypes[oldArchetypeIndex].removing(T.self, newID: newArchetypeID))
            archetypeIndexByID[newArchetypeID] = newArchetypeIndex
        }

        archetypes[newArchetypeIndex].append(
            from: archetypes[oldArchetypeIndex],
            at: oldEntityIndex
        )
        addToGroups(archetypeIndex: newArchetypeIndex)

        removeEntity(archetypeIndex: oldArchetypeIndex, entityIndex: oldEntityIndex)
        entities[entity.id] = EntityMetadata(
            archetypeIndex: newArchetypeIndex,
            entityIndex: archetypes[newArchetypeIndex].count - 1
        )
    }

    public func get<T>(_ type: T.Type, for entity: Entity) -> T? {
        guard isAlive(entity) else { return nil }
        let (archetypeIndex, entityIndex) = entities[entity.id].unwrap
        guard archetypes[archetypeIndex].contains(T.self) else { return nil }
        return .some(archetypes[archetypeIndex][entityIndex])
    }

    public mutating func update<T>(
        _ type: T.Type,
        for entity: Entity,
        _ body: (inout T) throws -> Void
    ) rethrows {
        precondition(T.self != Entity.self, "Cannot update Entity of an entity")
        guard isAlive(entity) else { return }
        let (archetypeIndex, entityIndex) = entities[entity.id].unwrap
        guard archetypes[archetypeIndex].contains(T.self) else { return }

        ensureUniqueID()
        try body(&archetypes[archetypeIndex][entityIndex])
    }

    public mutating func withArchetype<T>(
        at index: Int,
        _ body: (inout Archetype) throws -> T
    ) rethrows -> T {
        try body(&archetypes[index])
    }

    public func archetypeIndices(
        containing included: Set<ComponentID>,
        excluding excluded: Set<ComponentID>
    ) -> Set<Int> {
        var groups: [Set<Int>] = []
        for id in included {
            if id == Entity.componentID && included.count > 1 {
                // can skip Entity because every Archetype has it anyways
                // unless Entity is the only component we're looking for
                continue
            }
            guard let group = self.groups[id], !group.isEmpty else { return [] }
            groups.append(group)
        }

        let minimum = groups.enumerated().min { $0.element.count < $1.element.count }
        guard let minimum else { return [] }
        groups.swapAt(0, minimum.offset)

        var result = groups[0]
        for i in 1..<groups.count {
            result.formIntersection(groups[i])
            if result.isEmpty { return [] }
        }

        for id in excluded {
            if let group = self.groups[id] {
                result.subtract(group)
                if result.isEmpty { return [] }
            }
        }
        return result
    }
}

// private
extension World {
    private mutating func ensureUniqueID() {
        if !isKnownUniquelyReferenced(&_id) {
            self._id = WorldID()
        }
    }

    private mutating func removeEntity(archetypeIndex: Int, entityIndex: Int) {
        let lastEntityIndex = archetypes[archetypeIndex].count - 1
        let entity: Entity = archetypes[archetypeIndex][entityIndex]
        let lastEntity: Entity = archetypes[archetypeIndex][lastEntityIndex]
        archetypes[archetypeIndex].swapRemove(at: entityIndex)
        entities[lastEntity.id] = EntityMetadata(
            archetypeIndex: archetypeIndex,
            entityIndex: entityIndex
        )
        entities[entity.id] = .null

        if archetypes[archetypeIndex].count == 0 {
            removeFromGroups(archetypeIndex: archetypeIndex)
        }
    }

    private mutating func addToGroups(archetypeIndex: Int) {
        for id in archetypes[archetypeIndex].id.componentIDs {
            groups[id, default: []].insert(archetypeIndex)
        }
        groupsVersion += 1
    }

    private mutating func removeFromGroups(archetypeIndex: Int) {
        for id in archetypes[archetypeIndex].id.componentIDs {
            groups[id]?.remove(archetypeIndex)
        }
        groupsVersion += 1
    }
}
