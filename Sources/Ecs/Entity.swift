// MARK: Entity
public struct Entity: Hashable, Sendable {
    public static let indexMask: UInt32 = 0x00FF_FFFF
    public static let generationShift: UInt32 = 24

    public let storage: UInt32

    public var index: Int { Int(storage & Self.indexMask) }
    public var generation: UInt8 { UInt8(storage >> Self.generationShift) }

    public init(index: UInt32, generation: UInt8) {
        precondition(index <= Self.indexMask, "Index greater than Entity.indexMask")
        storage = (index & Self.indexMask) | (UInt32(generation) << Self.generationShift)
    }
}

#if DEBUG
    extension Entity: CustomStringConvertible {
        public var description: String {
            "Entity(index: \(index), generation: \(generation))"
        }
    }
#endif

// MARK: EntityRecord
public struct EntityRecord: Sendable {
    public let archetypeIndex: UInt32
    public let storage: Entity

    // When ALIVE: This is the index of the entity in the archetype
    // When DEAD:  This is the index of the next dead entity in the recycle list
    public var innerIndex: Int { storage.index }
    public var generation: UInt8 { storage.generation }

    public init(archetypeIndex: UInt32, innerIndex: UInt32, generation: UInt8) {
        self.archetypeIndex = archetypeIndex
        self.storage = Entity(index: innerIndex, generation: generation)
    }
}

// MARK: EntityManager
public struct EntityManager: Sendable {
    public static let nullIndex = Int(Entity.indexMask)

    public private(set) var entities: [EntityRecord] = []
    public private(set) var recycleListHead: Int = Self.nullIndex

    public init() {}

    public mutating func create(archetypeIndex: Int, innerIndex: Int) -> Entity {
        if recycleListHead < Self.nullIndex {
            let record = entities[recycleListHead]
            let nextRecycleListHead = record.innerIndex

            let entity = Entity(index: UInt32(recycleListHead), generation: record.generation)
            entities[recycleListHead] = EntityRecord(
                archetypeIndex: UInt32(archetypeIndex),
                innerIndex: UInt32(innerIndex),
                generation: record.generation
            )

            recycleListHead = nextRecycleListHead
            return entity
        } else {
            let newIndex = entities.endIndex
            precondition(newIndex < Self.nullIndex, "Reached the limit for Entity index")
            entities.append(
                EntityRecord(
                    archetypeIndex: UInt32(archetypeIndex),
                    innerIndex: UInt32(innerIndex),
                    generation: 0
                )
            )
            return Entity(index: UInt32(newIndex), generation: 0)
        }
    }

    public mutating func destroy(_ entity: Entity) {
        assert(isAlive(entity))

        let index = entity.index
        let record = entities[index]

        entities[index] = EntityRecord(
            archetypeIndex: 0,
            innerIndex: UInt32(recycleListHead),
            generation: record.generation &+ 1
        )

        recycleListHead = index
    }

    public func isAlive(_ entity: Entity) -> Bool {
        let index = entity.index
        return entities.indices.contains(index) && entities[index].generation == entity.generation
    }

    public mutating func update(_ entity: Entity, archetypeIndex: Int, innerIndex: Int) {
        assert(isAlive(entity))
        entities[entity.index] = EntityRecord(
            archetypeIndex: UInt32(archetypeIndex),
            innerIndex: UInt32(innerIndex),
            generation: entity.generation
        )
    }

    public func unwrap(_ entity: Entity) -> (archetypeIndex: Int, entityIndex: Int) {
        assert(isAlive(entity))
        let record = entities[entity.index]
        return (Int(record.archetypeIndex), record.innerIndex)
    }
}
