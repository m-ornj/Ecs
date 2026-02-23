public typealias EntityID = UInt32

public struct Entity: BitwiseCopyable, Hashable, Sendable {
    public let id: EntityID
    public let generation: UInt32

    fileprivate init(id: EntityID, generation: UInt32) {
        self.id = id
        self.generation = generation
    }

    static let componentID = ComponentID(Entity.self)
}

public struct EntityManager: Sendable {
    private var generations: [UInt32] = []
    private var recycled: [EntityID] = []

    public mutating func create() -> Entity {
        if let id = recycled.popLast() {
            return Entity(id: id, generation: generations[Int(id)])
        } else {
            let id = UInt32(generations.count)
            generations.append(0)
            return Entity(id: id, generation: 0)
        }
    }

    public mutating func destroy(_ entity: Entity) {
        guard isAlive(entity) else { return }
        generations[Int(entity.id)] += 1
        recycled.append(entity.id)
    }

    public func isAlive(_ entity: Entity) -> Bool {
        let index = Int(entity.id)
        return generations.indices.contains(index) && generations[index] == entity.generation
    }
}
