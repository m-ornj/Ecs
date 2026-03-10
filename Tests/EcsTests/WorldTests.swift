import Testing
@testable import Ecs

@Suite
struct WorldTests {
    struct Position: Equatable { var x: Int, y: Int }
    struct Velocity: Equatable { var dx: Int, dy: Int }
    struct Health: Equatable { var value: Int }
    struct Damage: Equatable { var value: Int }

    @Test
    func createAndGet() {
        var world = World()

        let e1 = world.create(with: (Position(x: 10, y: 20), Velocity(dx: 1, dy: 2)))
        let e2 = world.create(with: Health(value: 100))
        let e3 = world.create()

        #expect(world.get(Position.self, for: e1) == Position(x: 10, y: 20))
        #expect(world.get(Velocity.self, for: e1) == Velocity(dx: 1, dy: 2))
        #expect(world.get(Health.self, for: e1) == nil)
        #expect(world.get(Damage.self, for: e1) == nil)

        #expect(world.get(Position.self, for: e2) == nil)
        #expect(world.get(Velocity.self, for: e2) == nil)
        #expect(world.get(Health.self, for: e2)?.value == 100)
        #expect(world.get(Damage.self, for: e2) == nil)

        #expect(world.get(Position.self, for: e3) == nil)
        #expect(world.get(Velocity.self, for: e3) == nil)
        #expect(world.get(Health.self, for: e3) == nil)
        #expect(world.get(Damage.self, for: e3) == nil)

        #expect(world.isAlive(e1) && world.isAlive(e2) && world.isAlive(e3))
    }

    @Test
    func destroyAndCleanup() {
        var world = World()

        let e1 = world.create(with: (Position(x: 1, y: 2), Velocity(dx: 3, dy: 4)))
        let e2 = world.create(with: Position(x: 5, y: 6))

        world.destroy(e1)

        #expect(!world.isAlive(e1))
        #expect(world.get(Position.self, for: e1) == nil)
        #expect(world.get(Velocity.self, for: e1) == nil)
        #expect(world.get(Health.self, for: e1) == nil)

        #expect(world.isAlive(e2))
        #expect(world.get(Position.self, for: e2) == Position(x: 5, y: 6))

        let view = ViewBuilder<Entity>().view(into: world)
        #expect(view.count() == 1)

        let entities = view.map { $1[$0] }
        #expect(entities == [e2])

        world.destroy(e2)
        #expect(!world.isAlive(e2))
        #expect(world.get(Position.self, for: e2) == nil)
        #expect(world.get(Velocity.self, for: e2) == nil)
        #expect(world.get(Health.self, for: e2) == nil)
    }

    @Test
    func archetypeTransitions() {
        var world = World()

        var id = ArchetypeID()
        #expect(world.archetypes.allSatisfy { $0.count == 0 })

        let entities = (0..<100).map { _ in world.create() }
        id = ArchetypeID(Entity.self)
        #expect(world.archetypes.first { $0.id == id }?.count == entities.count)
        #expect(world.archetypes.allSatisfy { $0.id == id || $0.count == 0 })

        for e in entities { world.insert(Position(x: 1, y: 1), for: e) }
        id = ArchetypeID(Entity.self, Position.self)
        #expect(world.archetypes.first { $0.id == id }?.count == entities.count)
        #expect(world.archetypes.allSatisfy { $0.id == id || $0.count == 0 })

        for e in entities { world.insert(Velocity(dx: 2, dy: 2), for: e) }
        id = ArchetypeID(Entity.self, Position.self, Velocity.self)
        #expect(world.archetypes.first { $0.id == id }?.count == entities.count)
        #expect(world.archetypes.allSatisfy { $0.id == id || $0.count == 0 })

        for e in entities { world.insert(Health(value: 100), for: e) }
        id = ArchetypeID(Entity.self, Position.self, Velocity.self, Health.self)
        #expect(world.archetypes.first { $0.id == id }?.count == entities.count)
        #expect(world.archetypes.allSatisfy { $0.id == id || $0.count == 0 })

        for e in entities { world.remove(Position.self, for: e) }
        id = ArchetypeID(Entity.self, Velocity.self, Health.self)
        #expect(world.archetypes.first { $0.id == id }?.count == entities.count)
        #expect(world.archetypes.allSatisfy { $0.id == id || $0.count == 0 })

        for e in entities { world.remove(Velocity.self, for: e) }
        id = ArchetypeID(Entity.self, Health.self)
        #expect(world.archetypes.first { $0.id == id }?.count == entities.count)
        #expect(world.archetypes.allSatisfy { $0.id == id || $0.count == 0 })

        for e in entities { world.remove(Health.self, for: e) }
        id = ArchetypeID(Entity.self)
        #expect(world.archetypes.first { $0.id == id }?.count == entities.count)
        #expect(world.archetypes.allSatisfy { $0.id == id || $0.count == 0 })

        for e in entities { world.destroy(e) }
        #expect(world.archetypes.allSatisfy { $0.count == 0 })
    }

    @Test
    func destroyIdempotent() {
        var world = World()

        let entity = world.create(with: Position(x: 1, y: 2))

        world.destroy(entity)
        #expect(!world.isAlive(entity))

        world.destroy(entity)
        #expect(!world.isAlive(entity))

        world.insert(Health(value: 100), for: entity)
        world.remove(Position.self, for: entity)

        #expect(!world.isAlive(entity))

        #expect(world.get(Health.self, for: entity) == nil)
        #expect(world.get(Position.self, for: entity) == nil)
    }

    @Test
    func insertOverwrites() {
        var world = World()

        let entity = world.create(with: (Health(value: 100), Position(x: 10, y: 10)))
        #expect(world.get(Health.self, for: entity)?.value == 100)

        world.insert(Health(value: 50), for: entity)
        #expect(world.get(Health.self, for: entity)?.value == 50)

        world.insert(Position(x: 99, y: 99), for: entity)
        #expect(world.get(Position.self, for: entity) == Position(x: 99, y: 99))
    }

    @Test
    func entityReuse() {
        var world = World()

        let e1 = world.create(with: Health(value: 100))
        world.destroy(e1)

        let e2 = world.create(with: Health(value: 200))

        #expect(!world.isAlive(e1))
        #expect(world.get(Health.self, for: e1) == nil)

        #expect(world.isAlive(e2))
        #expect(world.get(Health.self, for: e2)?.value == 200)
    }

    @Test func createWithEntity() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            let entity = world.create()
            world.create(with: entity)
        }
    }

    @Test func addEntity() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            let e1 = world.create()
            let e2 = world.create()
            world.insert(e2, for: e1)
        }
    }

    @Test func removeEntity() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            let entity = world.create()
            world.remove(Entity.self, for: entity)
        }
    }

    @Test func createWithDuplicates() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            world.create(with: (Position(x: 10, y: 10), Position(x: 20, y: 20)))
        }
        await #expect(processExitsWith: .failure) {
            var world = World()
            world.create(with: (Damage(value: 1), Health(value: 100), Damage(value: 2)))
        }
    }

    @Test
    func prepareArchetype() {
        var world = World()

        let count = 1000
        world.prepareArchetype(for: Position.self, Velocity.self, minimumCapacity: count)

        let id = ArchetypeID(Entity.self, Position.self, Velocity.self)
        #expect(world.archetypes.first { $0.id == id }!.capacity >= count)
        #expect(world.archetypes.allSatisfy { $0.count == 0 })

        for i in 0..<count {
            let entity = world.create(
                with: (
                    Position(x: i, y: i),
                    Velocity(dx: 1, dy: 1)
                ))
            #expect(world.isAlive(entity))
        }

        #expect(world.archetypes.first { $0.id == id }!.count == count)
        #expect(world.archetypes.first { $0.id == id }!.capacity >= count)

        world.prepareArchetype(for: Position.self, Velocity.self, minimumCapacity: count / 2)
        #expect(world.archetypes.first { $0.id == id }!.count == count)
        #expect(world.archetypes.first { $0.id == id }!.capacity >= count)
        world.prepareArchetype(for: Position.self, Velocity.self, minimumCapacity: count * 2)
        #expect(world.archetypes.first { $0.id == id }!.count == count)
        #expect(world.archetypes.first { $0.id == id }!.capacity >= count * 2)
    }

    @Test
    mutating func zeroSizeComponents() {
        struct Flag {}
        #expect(MemoryLayout<Flag>.size == 0)

        var world = World()

        let entities = (0..<100).map { i in world.create(with: (Flag(), Position(x: i, y: i))) }

        let id = ArchetypeID(Entity.self, Flag.self, Position.self)
        #expect(world.archetypes.first { $0.id == id }!.count == entities.count)

        for e in entities.dropLast(entities.count / 2) {
            #expect(world.get(Flag.self, for: e) != nil)
        }

        for e in entities.dropLast(entities.count / 2) { world.remove(Flag.self, for: e) }

        #expect(world.archetypes.first { $0.id == id }!.count == entities.count / 2)

        for e in entities.dropFirst(entities.count / 2) {
            #expect(world.get(Flag.self, for: e) != nil)
        }
    }
}
