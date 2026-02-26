import Synchronization

private let globalWorldID = Atomic<UInt>(0)

private final class WorldID: Sendable {
    public let id = {
        let (value, _) = globalWorldID.add(1, ordering: .relaxed)
        return value
    }()
}

public struct EntityRecord: Sendable {
    @usableFromInline let archetypeIndex: UInt32
    @usableFromInline let storage: Entity

    // When ALIVE: This is the index of the entity in the archetype
    // When DEAD:  This is the index of the next dead entity in the recycle list
    @inlinable public var innerIndex: Int { storage.index }
    @inlinable public var generation: UInt8 { storage.generation }

    init(archetypeIndex: UInt32, innerIndex: UInt32, generation: UInt8) {
        self.archetypeIndex = archetypeIndex
        self.storage = Entity(index: innerIndex, generation: generation)
    }

    var unwrap: (archetypeIndex: Int, entityIndex: Int) { (Int(archetypeIndex), innerIndex) }
}

public struct World: Sendable {
    private var _id = WorldID()
    public var id: UInt { _id.id }

    public private(set) var entities: [EntityRecord] = []
    public private(set) var archetypes: [Archetype] = []
    public private(set) var archetypeIndexByID: [ArchetypeID: Int] = [:]
    public private(set) var groups: [ComponentID: Set<Int>] = [:]
    public private(set) var groupsVersion: UInt = 0

    private var recycleListHead: UInt32 = Entity.endIndex

    public init() {}
}

// public
extension World {
    public mutating func create<each T>(
        with components: (repeat each T) = ()
    ) -> Entity {
        let entity = createEntity()

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

        entities[entity.index] = EntityRecord(
            archetypeIndex: UInt32(archetypeIndex),
            innerIndex: UInt32(archetypes[archetypeIndex].count - 1),
            generation: entity.generation
        )

        return entity
    }

    public func isAlive(_ entity: Entity) -> Bool {
        let index = entity.index
        return entities.indices.contains(index) && entities[index].generation == entity.generation
    }

    public mutating func destroy(_ entity: Entity) {
        guard isAlive(entity) else { return }

        ensureUniqueID()

        let (archetypeIndex, entityIndex) = entities[entity.index].unwrap
        removeEntity(archetypeIndex: archetypeIndex, entityIndex: entityIndex)
        destroyEntity(entity)
    }

    public mutating func insert<T>(_ component: T, for entity: Entity) {
        precondition(T.self != Entity.self, "Cannot add Entity to an entity")
        guard isAlive(entity) else { return }
        ensureUniqueID()

        let (oldArchetypeIndex, oldEntityIndex) = entities[entity.index].unwrap

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
        entities[entity.index] = EntityRecord(
            archetypeIndex: UInt32(newArchetypeIndex),
            innerIndex: UInt32(archetypes[newArchetypeIndex].count - 1),
            generation: entity.generation
        )
    }

    public mutating func remove<T>(_ type: T.Type, for entity: Entity) {
        precondition(T.self != Entity.self, "Cannot remove Entity from an entity")
        guard isAlive(entity) else { return }
        ensureUniqueID()

        let (oldArchetypeIndex, oldEntityIndex) = entities[entity.index].unwrap

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
        entities[entity.index] = EntityRecord(
            archetypeIndex: UInt32(newArchetypeIndex),
            innerIndex: UInt32(archetypes[newArchetypeIndex].count - 1),
            generation: entity.generation
        )
    }

    public func get<T>(_ type: T.Type, for entity: Entity) -> T? {
        guard isAlive(entity) else { return nil }
        let (archetypeIndex, entityIndex) = entities[entity.index].unwrap
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
        let (archetypeIndex, entityIndex) = entities[entity.index].unwrap
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
        let entityComponentID = ComponentID(Entity.self)

        var groups: [Set<Int>] = []
        for id in included {
            if id == entityComponentID && included.count > 1 {
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

    private mutating func createEntity() -> Entity {
        ensureUniqueID()

        if recycleListHead != Entity.endIndex {
            let recycledIndex = recycleListHead
            let metadata = entities[Int(recycledIndex)]

            recycleListHead = UInt32(metadata.innerIndex)

            return Entity(index: recycleListHead, generation: metadata.generation)
        } else {
            let newIndex = UInt32(entities.endIndex)
            precondition(newIndex < Entity.endIndex, "Reached the limit for Entity index")
            entities.append(
                EntityRecord(
                    archetypeIndex: .max,
                    innerIndex: Entity.endIndex,
                    generation: 0
                )
            )
            return Entity(index: newIndex, generation: 0)
        }
    }

    private mutating func destroyEntity(_ entity: Entity) {
        guard isAlive(entity) else { return }
        ensureUniqueID()

        let index = entity.index
        let record = entities[index]

        entities[index] = EntityRecord(
            archetypeIndex: .max,
            innerIndex: recycleListHead,
            generation: record.generation &+ 1
        )

        recycleListHead = UInt32(index)
    }

    private mutating func removeEntity(archetypeIndex: Int, entityIndex: Int) {
        let lastEntityIndex = archetypes[archetypeIndex].count - 1
        let entity: Entity = archetypes[archetypeIndex][entityIndex]
        let lastEntity: Entity = archetypes[archetypeIndex][lastEntityIndex]
        archetypes[archetypeIndex].swapRemove(at: entityIndex)

        entities[lastEntity.index] = EntityRecord(
            archetypeIndex: UInt32(archetypeIndex),
            innerIndex: UInt32(entityIndex),
            generation: lastEntity.generation
        )
        entities[entity.index] = EntityRecord(
            archetypeIndex: .max,
            innerIndex: Entity.endIndex,
            generation: entity.generation
        )

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
