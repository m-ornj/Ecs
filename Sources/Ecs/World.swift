import Synchronization

private let globalWorldID = Atomic<UInt64>(0)

public final class WorldID: Sendable {
    public let id = {
        let (value, _) = globalWorldID.add(1, ordering: .relaxed)
        return value
    }()
}

public struct EntityMetadata: Sendable {
    let archetypeIndex: UInt32
    let indexInArchetype: UInt32
}

public struct ComponentGraph: Sendable {
    public private(set) var archetypeIndices: [ComponentID: Set<UInt32>] = [:]
    public private(set) var version: UInt64 = 0

    public mutating func add(archetypeID: ArchetypeID, withIndex index: UInt32) {
        for id in archetypeID {
            archetypeIndices[id, default: []].insert(index)
        }
        version += 1
    }

    public mutating func remove(archetypeID: ArchetypeID, withIndex index: UInt32) {
        for id in archetypeID {
            archetypeIndices[id]?.remove(index)
        }
        version += 1
    }
}

public struct World: Sendable {
    private var _id = WorldID()
    public var id: UInt64 { _id.id }

    public private(set) var entityManager = EntityManager()

    public private(set) var entities: [EntityMetadata] = []

    public private(set) var archetypes: [Archetype] = []

    public private(set) var archetypeIndexByID: [ArchetypeID: UInt32] = [:]

    public private(set) var archetypeRegistry = ArchetypeRegistry()

    public private(set) var componentGraph = ComponentGraph()

    public init() {}

    private static let entityArchetypeSchema = ArchetypeSchema(componentType: Entity.self)
}

// public
extension World {
    public mutating func create<each T: Component>(
        with components: (repeat each T) = ()
    ) -> Entity {
        var schema = Self.entityArchetypeSchema
        for type in repeat (each T).self {
            precondition(type != Entity.self, "Cannot add Entity to an entity")
            schema = schema.adding(type)
        }

        ensureUniqueID()

        let entity = entityManager.create()
        var values: [ComponentID: Any] = [Entity.componentID: entity]
        for component in repeat each components {
            values[ComponentID(type(of: component))] = component
        }

        let archetypeIndex = archetypeRegistry.register(schema: schema)
        archetypeRegistry.archetypes[archetypeIndex].append([ComponentID : UnsafeRawPointer])
        // archetypeRegistry.
        archetypeRegistry.update(at: archetypeIndex) { archetype in
            archetype.append(values: values)
        }
        archetypes[archetypeIndex].append(values: values)

        componentGraph.add(archetypeID: schema.id, withIndex: archetypeIndex)

        let metadata = EntityMetadata(
            archetypeIndex: archetypeIndex,
            indexInArchetype: archetypes[archetypeIndex].count - 1
        )

        if entities.indices.contains(Int(entity.id)) {
            entities[Int(entity.id)] = metadata
        } else {
            entities.append(metadata)
        }
        if entities.indices.contains(entity.id) {
            entities[entity.id] = metadata
        } else {
            entities.append(metadata)
        }

        return entity
    }

    public func isAlive(_ entity: Entity) -> Bool {
        entityManager.isAlive(entity)
    }

    public mutating func destroy(_ entity: Entity) {
        guard isAlive(entity) else { return }

        ensureUniqueID()

        if let (archetypeIndex, entityIndex) = entities[entity.id] {
            removeEntity(archetypeIndex: archetypeIndex, entityIndex: entityIndex)
        }
        entityManager.destroy(entity)
    }

    public mutating func insert<T: Component>(_ component: T, for entity: Entity) {
        precondition(T.self != Entity.self, "Cannot add Entity to an entity")

        guard isAlive(entity), let (oldArchetypeIndex, oldEntityIndex) = entities[entity.id]
        else { return }

        ensureUniqueID()

        let newSchema = archetypes[oldArchetypeIndex].schema.adding(T.self)
        let newArchetypeIndex = archetypeIndex(newSchema)
        guard newArchetypeIndex != oldArchetypeIndex else {
            archetypes[oldArchetypeIndex][oldEntityIndex] = component
            return
        }

        var data = archetypes[oldArchetypeIndex].read(at: oldEntityIndex)
        var component = component
        withUnsafeMutableBytes(of: &component) {
            data[ComponentID(T.self)] = UnsafeRawPointer($0.baseAddress)
        }
        archetypes[newArchetypeIndex].append(data)
        addToGroups(archetypeIndex: newArchetypeIndex)

        removeEntity(archetypeIndex: oldArchetypeIndex, entityIndex: oldEntityIndex)
        entities[entity.id] = (
            archetypeIndex: newArchetypeIndex,
            entityIndex: archetypes[newArchetypeIndex].count - 1
        )
    }

    public mutating func remove<T: Component>(_ type: T.Type, for entity: Entity) {
        precondition(T.self != Entity.self, "Cannot remove Entity from an entity")

        guard isAlive(entity), let (oldArchetypeIndex, oldEntityIndex) = entities[entity.id]
        else { return }

        guard archetypes[oldArchetypeIndex].contains(T.self) else { return }

        ensureUniqueID()

        let newSchema = archetypes[oldArchetypeIndex].schema.removing(T.self)
        let newArchetypeIndex = archetypeIndex(newSchema)

        let data = archetypes[oldArchetypeIndex].read(at: oldEntityIndex)
        archetypes[newArchetypeIndex].append(data)
        addToGroups(archetypeIndex: newArchetypeIndex)

        removeEntity(archetypeIndex: oldArchetypeIndex, entityIndex: oldEntityIndex)
        entities[entity.id] = (
            archetypeIndex: newArchetypeIndex,
            entityIndex: archetypes[newArchetypeIndex].count - 1
        )
    }

    public func get<T: Component>(_ type: T.Type, for entity: Entity) -> T? {
        guard isAlive(entity), let (archetypeIndex, entityIndex) = entities[entity.id]
        else { return nil }
        return archetypes[archetypeIndex].get(T.self, at: entityIndex)
    }

    public mutating func update<T: Component>(
        _ type: T.Type,
        for entity: Entity,
        _ body: (inout T) throws -> Void
    ) rethrows {
        precondition(T.self != Entity.self, "Cannot update Entity of an entity")
        guard isAlive(entity), let (archetypeIndex, entityIndex) = entities[entity.id]
        else { return }
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

    private mutating func archetypeIndex(_ schema: ArchetypeSchema) -> UInt32 {
        if let index = indices[schema.id] {
            return index
        }
        let archetype = Archetype(schema: schema)
        archetypes.append(archetype)
        let index = archetypes.count - 1
        indices[archetype.schema.id] = index
        return index
    }

    private mutating func removeEntity(archetypeIndex: Int, entityIndex: Int) {
        let lastEntityIndex = archetypes[archetypeIndex].count - 1
        let entity: Entity = archetypes[archetypeIndex][entityIndex]
        let lastEntity: Entity = archetypes[archetypeIndex][lastEntityIndex]
        if entityIndex != lastEntityIndex {
            archetypes[archetypeIndex].moveLast(to: entityIndex)
            entities[lastEntity.id] = (archetypeIndex: archetypeIndex, entityIndex: entityIndex)
        }
        archetypes[archetypeIndex].removeLast()
        entities[entity.id] = nil

        if archetypes[archetypeIndex].count == 0 {
            removeFromGroups(archetypeIndex: archetypeIndex)
        }
    }

    private mutating func addToGroups(archetypeIndex: Int) {
        for id in archetypes[archetypeIndex].schema.id {
            groups[id, default: []].insert(archetypeIndex)
        }
        groupsVersion += 1
    }

    private mutating func removeFromGroups(archetypeIndex: Int) {
        for id in archetypes[archetypeIndex].schema.id {
            groups[id]?.remove(archetypeIndex)
        }
        groupsVersion += 1
    }
}
