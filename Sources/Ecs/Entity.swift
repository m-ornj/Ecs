public typealias EntityID = Int

public struct Entity: BitwiseCopyable {
    public let id: EntityID
    public let generation: Int

    fileprivate init(id: EntityID, generation: Int) {
        self.id = id
        self.generation = generation
    }

    static let componentID = ComponentID(Entity.self)
}

public class EntityManager {
    private var generations: [Int] = []
    private var recycled: [EntityID] = []

    public init() {}

    public func create() -> Entity {
        if let id = recycled.popLast() {
            return Entity(id: id, generation: generations[id])
        } else {
            let id = generations.count
            generations.append(0)
            return Entity(id: id, generation: 0)
        }
    }

    public func destroy(_ entity: Entity) {
        guard isAlive(entity) else { return }
        generations[entity.id] += 1
        recycled.append(entity.id)
    }

    public func isAlive(_ entity: Entity) -> Bool {
        generations.indices.contains(entity.id) && generations[entity.id] == entity.generation
    }
}
