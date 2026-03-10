import Synchronization

private let globalWorldID = Atomic<UInt>(0)

private final class WorldID: Sendable {
    let id = {
        let (value, _) = globalWorldID.add(1, ordering: .relaxed)
        return value
    }()
}

public struct World: Sendable {
    private var _id = WorldID()
    public var id: UInt { _id.id }

    public private(set) var entityManager = EntityManager()
    public private(set) var archetypes: [Archetype] = []
    public private(set) var archetypeIndexByID: [ArchetypeID: Int] = [:]
    public private(set) var archetypeLookup = ArchetypeLookup()

    public init() {}
}

extension World {
    @discardableResult public mutating func create<each T>(
        with components: (repeat each T) = ()
    ) -> Entity {
        let archetypeID = ArchetypeID(Entity.self, repeat (each T).self)
        let archetypeIndex: Int
        if let index = archetypeIndexByID[archetypeID] {
            archetypeIndex = index
        } else {
            archetypeIndex = archetypes.endIndex
            archetypes.append(Archetype(for: Entity.self, repeat (each T).self))
            archetypeIndexByID[archetypeID] = archetypeIndex
        }

        if archetypes[archetypeIndex].count == 0 {
            archetypeLookup.add(archetypeIndex, for: archetypeID.componentIDs)
        }

        let entity = entityManager.create(
            archetypeIndex: archetypeIndex,
            innerIndex: archetypes[archetypeIndex].endIndex
        )

        archetypes[archetypeIndex].append(entity, repeat each components)

        return entity
    }

    public func isAlive(_ entity: Entity) -> Bool { entityManager.isAlive(entity) }

    public mutating func destroy(_ entity: Entity) {
        guard isAlive(entity) else { return }
        ensureUniqueID()

        let (archetypeIndex, entityIndex) = entityManager.unwrap(entity)
        removeEntity(archetypeIndex: archetypeIndex, entityIndex: entityIndex)
        entityManager.destroy(entity)
    }

    public mutating func insert<T>(_ component: T, for entity: Entity) {
        precondition(T.self != Entity.self, "Cannot add Entity to an entity")
        guard isAlive(entity) else { return }
        ensureUniqueID()

        let (oldArchetypeIndex, oldEntityIndex) = entityManager.unwrap(entity)

        guard !archetypes[oldArchetypeIndex].contains(T.self) else {
            archetypes[oldArchetypeIndex][oldEntityIndex] = component
            return
        }

        let newArchetypeID = archetypes[oldArchetypeIndex].id.adding(T.self)
        let newArchetypeIndex: Int
        if let index = archetypeIndexByID[newArchetypeID] {
            newArchetypeIndex = index
        } else {
            newArchetypeIndex = archetypes.endIndex
            archetypes.append(archetypes[oldArchetypeIndex].adding(T.self))
            archetypeIndexByID[newArchetypeID] = newArchetypeIndex
        }

        if archetypes[newArchetypeIndex].count == 0 {
            archetypeLookup.add(newArchetypeIndex, for: newArchetypeID.componentIDs)
        }

        archetypes[newArchetypeIndex].append(component)
        archetypes[newArchetypeIndex].append(
            from: archetypes[oldArchetypeIndex],
            at: oldEntityIndex
        )

        removeEntity(archetypeIndex: oldArchetypeIndex, entityIndex: oldEntityIndex)
        entityManager.update(
            entity,
            archetypeIndex: newArchetypeIndex,
            innerIndex: archetypes[newArchetypeIndex].endIndex - 1
        )
    }

    public mutating func remove<T>(_ type: T.Type, for entity: Entity) {
        precondition(T.self != Entity.self, "Cannot remove Entity from an entity")
        guard isAlive(entity) else { return }
        ensureUniqueID()

        let (oldArchetypeIndex, oldEntityIndex) = entityManager.unwrap(entity)

        guard archetypes[oldArchetypeIndex].contains(T.self) else { return }

        let newArchetypeID = archetypes[oldArchetypeIndex].id.removing(T.self)
        let newArchetypeIndex: Int
        if let index = archetypeIndexByID[newArchetypeID] {
            newArchetypeIndex = index
        } else {
            newArchetypeIndex = archetypes.endIndex
            archetypes.append(archetypes[oldArchetypeIndex].removing(T.self))
            archetypeIndexByID[newArchetypeID] = newArchetypeIndex
        }

        if archetypes[newArchetypeIndex].count == 0 {
            archetypeLookup.add(newArchetypeIndex, for: newArchetypeID.componentIDs)
        }

        archetypes[newArchetypeIndex].append(
            from: archetypes[oldArchetypeIndex],
            at: oldEntityIndex
        )

        removeEntity(archetypeIndex: oldArchetypeIndex, entityIndex: oldEntityIndex)
        entityManager.update(
            entity,
            archetypeIndex: newArchetypeIndex,
            innerIndex: archetypes[newArchetypeIndex].endIndex - 1
        )
    }

    public func get<T>(_ type: T.Type, for entity: Entity) -> T? {
        guard isAlive(entity) else { return nil }
        let (archetypeIndex, entityIndex) = entityManager.unwrap(entity)
        guard archetypes[archetypeIndex].contains(T.self) else { return nil }
        return .some(archetypes[archetypeIndex][entityIndex])
    }

    public mutating func prepareArchetype<each T>(
        for t: repeat (each T).Type,
        minimumCapacity: Int
    ) {
        ensureUniqueID()
        var hasEntity = false
        for T in repeat (each T).self {
            if T == Entity.self {
                hasEntity = true
                break
            }
        }
        let archetypeID =
            hasEntity
            ? ArchetypeID(repeat (each T).self)
            : ArchetypeID(Entity.self, repeat (each T).self)

        if let index = archetypeIndexByID[archetypeID] {
            archetypes[index].reserveCapacity(minimumCapacity)
        } else {
            let index = archetypes.endIndex
            archetypes.append(
                hasEntity
                    ? Archetype(for: repeat (each T).self, capacity: minimumCapacity)
                    : Archetype(for: Entity.self, repeat (each T).self, capacity: minimumCapacity)
            )
            archetypeIndexByID[archetypeID] = index
            archetypeLookup.add(index, for: archetypeID.componentIDs)
        }
    }

    public func buffer<T>(
        of t: T.Type,
        fromArchetypeAt i: Int
    ) -> UnsafeBufferPointer<T> {
        return archetypes[i].buffer(of: T.self)
    }

    public mutating func buffer<T>(
        of t: T.Type,
        fromArchetypeAt i: Int
    ) -> UnsafeMutableBufferPointer<T> {
        ensureUniqueID()
        return archetypes[i].buffer(of: T.self)
    }

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

        entityManager.update(lastEntity, archetypeIndex: archetypeIndex, innerIndex: entityIndex)
        entityManager.update(entity, archetypeIndex: archetypeIndex, innerIndex: lastEntityIndex)

        if archetypes[archetypeIndex].count == 0 {
            archetypeLookup.remove(archetypeIndex, for: archetypes[archetypeIndex].id.componentIDs)
        }
    }
}
