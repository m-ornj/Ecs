import Testing

@testable import Ecs

// MARK: ViewBuilderTests
@Suite
struct ViewBuilderTests {
    var world = World()

    mutating func test<each T>(_ viewBuilder: ViewBuilder<repeat each T>, expectedCount: Int) {
        let view = viewBuilder.view(into: world)
        let mutableView = viewBuilder.view(into: &world)
        #expect(expectedCount == view.count())
        #expect(expectedCount == mutableView.count())
    }

    @Test
    mutating func filterCombinations() {
        struct DivBy2 {}
        struct DivBy3 {}
        struct DivBy5 {}

        let count = 100

        let entities = (0..<count).map { i in
            let e = world.create()
            if i % 2 == 0 { world.insert(DivBy2(), for: e) }
            if i % 3 == 0 { world.insert(DivBy3(), for: e) }
            if i % 5 == 0 { world.insert(DivBy5(), for: e) }
            return e
        }

        test(ViewBuilder<Entity>(), expectedCount: entities.count)

        test(
            ViewBuilder<DivBy2, DivBy3, DivBy5>(),
            expectedCount: (0..<count).filter { $0 % 2 == 0 && $0 % 3 == 0 && $0 % 5 == 0 }.count
        )
        test(
            ViewBuilder<DivBy5, DivBy2, DivBy3>(),
            expectedCount: (0..<count).filter { $0 % 2 == 0 && $0 % 3 == 0 && $0 % 5 == 0 }.count
        )
        test(
            ViewBuilder<DivBy2, DivBy3>(),
            expectedCount: (0..<count).filter { $0 % 2 == 0 && $0 % 3 == 0 }.count
        )
        test(
            ViewBuilder<DivBy2, DivBy5>().excluding(DivBy3.self),
            expectedCount: (0..<count).filter { $0 % 2 == 0 && $0 % 3 != 0 && $0 % 5 == 0 }.count
        )
        test(
            ViewBuilder<Entity>(
                included: [ComponentID(DivBy2.self), ComponentID(DivBy5.self)],
                excluded: [ComponentID(DivBy3.self)]
            ),
            expectedCount: (0..<count).filter { $0 % 2 == 0 && $0 % 3 != 0 && $0 % 5 == 0 }.count
        )
        test(
            ViewBuilder<DivBy5>().excluding(DivBy2.self, DivBy3.self),
            expectedCount: (0..<count).filter { $0 % 2 != 0 && $0 % 3 != 0 && $0 % 5 == 0 }.count
        )
        test(
            ViewBuilder<Entity>().including(DivBy2.self, DivBy3.self, DivBy5.self),
            expectedCount: (0..<count).filter { $0 % 2 == 0 && $0 % 3 == 0 && $0 % 5 == 0 }.count
        )
        test(
            ViewBuilder<Entity>().excluding(DivBy2.self, DivBy3.self, DivBy5.self),
            expectedCount: (0..<count).filter { $0 % 2 != 0 && $0 % 3 != 0 && $0 % 5 != 0 }.count
        )
        test(
            ViewBuilder<DivBy2>().excluding(DivBy2.self),
            expectedCount: 0
        )
        test(
            ViewBuilder<Entity>().including(DivBy2.self).excluding(DivBy2.self),
            expectedCount: 0
        )
        test(
            ViewBuilder<DivBy2, DivBy2, DivBy2>().including(DivBy2.self),
            expectedCount: (0..<count).filter { $0 % 2 == 0 }.count
        )
        test(
            ViewBuilder<Entity, DivBy2, DivBy3, DivBy5>(),
            expectedCount: (0..<count).filter { $0 % 2 == 0 && $0 % 3 == 0 && $0 % 5 == 0 }.count
        )
        test(
            ViewBuilder<DivBy2, DivBy3, DivBy5>().including(Entity.self),
            expectedCount: (0..<count).filter { $0 % 2 == 0 && $0 % 3 == 0 && $0 % 5 == 0 }.count
        )
        test(
            ViewBuilder<DivBy2, DivBy3, DivBy5>().excluding(Entity.self),
            expectedCount: 0
        )

        for e in entities { world.destroy(e) }
    }
}

// MARK: ViewTests
@Suite
struct ViewTests {
    struct Position: Equatable { var x: Int, y: Int }
    struct Velocity: Equatable { var dx: Int, dy: Int }
    struct Health { var value: Int }
    struct Noise1 { var value: Int }
    struct Noise2 { var value: Int }

    var world = World()

    @Test
    mutating func bufferIntegrity() {
        let entities: [Entity] = [
            world.create(with: (Position(x: 10, y: 20), Velocity(dx: 1, dy: 2))),
            world.create(with: (Position(x: 30, y: 40), Velocity(dx: 3, dy: 4))),
            world.create(with: (Position(x: 50, y: 60), Velocity(dx: 5, dy: 6))),
        ]

        var foundPositions: Set<Int> = []
        for (i, (positions, velocities)) in ViewBuilder<Position, Velocity>().view(into: world) {
            #expect(positions.indices.contains(i))
            #expect(velocities.indices.contains(i))

            let pos = positions[i]
            let vel = velocities[i]

            #expect(pos.x == vel.dx * 10)
            #expect(pos.y == vel.dy * 10)

            foundPositions.insert(Int(pos.x))
        }

        #expect(foundPositions.count == 3)
        #expect(foundPositions.contains(10))
        #expect(foundPositions.contains(30))
        #expect(foundPositions.contains(50))

        for e in entities { world.destroy(e) }
    }

    @Test
    mutating func entityComponentMapping() {
        let count = 10
        let entities = (0..<count).map { i in
            world.create(with: (Position(x: i * 10, y: 0), Health(value: i * 100)))
        }

        var entityHealthMap: [Entity: Int] = [:]
        let view = ViewBuilder<Entity, Position, Health>().view(into: world)
        for (i, (entities, positions, healths)) in view {
            let entity = entities[i]
            let health = healths[i].value
            let posX = positions[i].x

            entityHealthMap[entity] = health

            #expect(health == posX * 10)
        }

        #expect(entityHealthMap.count == count)
        for (entity, health) in entityHealthMap {
            #expect(health == world.get(Health.self, for: entity)?.value)
        }

        for e in entities { world.destroy(e) }
    }

    @Test
    mutating func multipleArchetypesIteration() {
        let entities: [Entity] = [
            world.create(with: Position(x: 1, y: 1)),
            world.create(with: Position(x: 2, y: 2)),
            world.create(with: (Position(x: 3, y: 3), Velocity(dx: 1, dy: 1))),
            world.create(with: (Position(x: 4, y: 4), Velocity(dx: 1, dy: 1))),
            world.create(with: (Position(x: 5, y: 5), Health(value: 100))),
        ]

        let view = ViewBuilder<Position>().view(into: world)

        var xValues: Set<Int> = []
        for (i, positions) in view {
            #expect(positions.indices.contains(i))
            xValues.insert(Int(positions[i].x))
        }

        #expect(xValues.count == 5)
        #expect(xValues == Set([1, 2, 3, 4, 5]))

        for e in entities { world.destroy(e) }
    }

    @Test
    mutating func emptyViewNeverIterates() {
        let entities: [Entity] = [
            world.create(with: Position(x: 100, y: 100)),
            world.create(with: Position(x: 200, y: 200)),
        ]

        let view = ViewBuilder<Velocity>().view(into: world)
        #expect(view.count() == 0)

        var iterationCount = 0
        for _ in view {
            iterationCount += 1
            #expect(Bool(false))
        }

        #expect(iterationCount == 0)

        for e in entities { world.destroy(e) }
    }

    @Test
    mutating func viewReusability() {
        let count = 100
        let entities = (0..<count).map { i in
            let entity = world.create(with: Health(value: i))
            if i % 2 == 0 { world.insert(Noise1(value: i), for: entity) }
            if i % 3 == 0 { world.insert(Noise2(value: i), for: entity) }
            return entity
        }

        let view = ViewBuilder<Health>().view(into: world)

        var sum1 = 0
        for (i, healths) in view {
            sum1 += healths[i].value
        }

        var sum2 = 0
        for (i, healths) in view {
            sum2 += healths[i].value
        }

        var sum3 = 0
        for (i, healths) in view {
            sum3 += healths[i].value
        }

        #expect(sum1 == sum2)
        #expect(sum2 == sum3)
        #expect(sum1 == (0..<count).reduce(0, +))

        for e in entities { world.destroy(e) }
    }

    @Test
    mutating func sequenceConformance() {
        let range = (0..<100)

        let entities = range.map { health in
            world.create(with: Health(value: health))
        }

        let healths = ViewBuilder<Health>()
            .view(into: world)
            .map { $1[$0].value }
        #expect(healths == range.map { $0 })

        let lowHealths = ViewBuilder<Health>()
            .view(into: world)
            .filter { $1[$0].value <= 50 }
            .map { $1[$0].value }
        #expect(lowHealths == range.filter { $0 <= 50 }.map { $0 })

        let totalHealth = ViewBuilder<Health>()
            .view(into: world)
            .reduce(0) { $0 + $1.1[$1.0].value }
        #expect(totalHealth == range.reduce(0, +))

        let sorted = ViewBuilder<Health>()
            .view(into: world)
            .sorted { $0.1[$0.0].value > $1.1[$1.0].value }
            .map { $1[$0].value }
        #expect(sorted == range.sorted { $0 > $1 })

        for e in entities { world.destroy(e) }
    }

    @Test
    func emptyWorld() {
        #expect(ViewBuilder<Position>().view(into: world).count() == 0)
        #expect(ViewBuilder<Position, Velocity>().view(into: world).count() == 0)
        #expect(ViewBuilder<Entity>().view(into: world).count() == 0)

        var iterated = false
        for _ in ViewBuilder<Position, Velocity>().view(into: world) {
            iterated = true
            #expect(Bool(false))
        }
        #expect(!iterated)
    }
}

// MARK: MutableViewTests
@Suite
struct MutableViewTests {
    struct Position: Equatable { var x: Int, y: Int }
    struct Velocity: Equatable { var dx: Int, dy: Int }
    struct Health { var value: Int }
    struct Damage { var value: Int }
    struct Noise1 { var value: Int }
    struct Noise2 { var value: Int }

    var world = World()

    @Test
    mutating func bufferIntegrity() {
        let entities: [Entity] = [
            world.create(with: (Position(x: 10, y: 20), Velocity(dx: 1, dy: 2))),
            world.create(with: (Position(x: 30, y: 40), Velocity(dx: 3, dy: 4))),
            world.create(with: (Position(x: 50, y: 60), Velocity(dx: 5, dy: 6))),
        ]

        var foundPositions: Set<Int> = []
        for (i, (positions, velocities)) in ViewBuilder<Position, Velocity>().view(into: &world) {
            #expect(positions.indices.contains(i))
            #expect(velocities.indices.contains(i))

            let pos = positions[i]
            let vel = velocities[i]

            #expect(pos.x == vel.dx * 10)
            #expect(pos.y == vel.dy * 10)

            foundPositions.insert(Int(pos.x))
        }

        #expect(foundPositions.count == 3)
        #expect(foundPositions.contains(10))
        #expect(foundPositions.contains(30))
        #expect(foundPositions.contains(50))

        for e in entities { world.destroy(e) }
    }

    @Test
    mutating func entityComponentMapping() {
        let count = 10
        let entities = (0..<count).map { i in
            world.create(with: (Position(x: i * 10, y: 0), Health(value: i * 100)))
        }

        var entityHealthMap: [Entity: Int] = [:]
        let view = ViewBuilder<Entity, Position, Health>().view(into: &world)
        for (i, (entities, positions, healths)) in view {
            let entity = entities[i]
            let health = healths[i].value
            let posX = positions[i].x

            entityHealthMap[entity] = health

            #expect(health == posX * 10)
        }

        #expect(entityHealthMap.count == count)
        for (entity, health) in entityHealthMap {
            #expect(health == world.get(Health.self, for: entity)?.value)
        }

        for e in entities { world.destroy(e) }
    }

    @Test
    mutating func multipleArchetypesIteration() {
        let entities: [Entity] = [
            world.create(with: Position(x: 1, y: 1)),
            world.create(with: Position(x: 2, y: 2)),
            world.create(with: (Position(x: 3, y: 3), Velocity(dx: 1, dy: 1))),
            world.create(with: (Position(x: 4, y: 4), Velocity(dx: 1, dy: 1))),
            world.create(with: (Position(x: 5, y: 5), Health(value: 100))),
        ]

        let view = ViewBuilder<Position>().view(into: &world)

        var xValues: Set<Int> = []
        for (i, positions) in view {
            #expect(positions.indices.contains(i))
            xValues.insert(Int(positions[i].x))
        }

        #expect(xValues.count == 5)
        #expect(xValues == Set([1, 2, 3, 4, 5]))

        for e in entities { world.destroy(e) }
    }

    @Test
    mutating func emptyViewNeverIterates() {
        let entities: [Entity] = [
            world.create(with: Position(x: 100, y: 100)),
            world.create(with: Position(x: 200, y: 200)),
        ]

        let view = ViewBuilder<Velocity>().view(into: &world)
        #expect(view.count() == 0)

        var iterationCount = 0
        for _ in view {
            iterationCount += 1
            #expect(Bool(false))
        }

        #expect(iterationCount == 0)

        for e in entities { world.destroy(e) }
    }

    @Test
    mutating func viewReusability() {
        let count = 100
        let entities = (0..<count).map { i in
            let entity = world.create(with: Health(value: i))
            if i % 2 == 0 { world.insert(Noise1(value: i), for: entity) }
            if i % 3 == 0 { world.insert(Noise2(value: i), for: entity) }
            return entity
        }

        let view = ViewBuilder<Health>().view(into: &world)

        var sum1 = 0
        for (i, healths) in view {
            sum1 += healths[i].value
        }

        var sum2 = 0
        for (i, healths) in view {
            sum2 += healths[i].value
        }

        var sum3 = 0
        for (i, healths) in view {
            sum3 += healths[i].value
        }

        #expect(sum1 == sum2)
        #expect(sum2 == sum3)
        #expect(sum1 == (0..<count).reduce(0, +))

        for e in entities { world.destroy(e) }
    }

    @Test
    mutating func sequenceConformance() {
        let range = (0..<100)

        let entities = range.map { health in
            world.create(with: Health(value: health))
        }

        let healths = ViewBuilder<Health>()
            .view(into: &world)
            .map { $1[$0].value }
        #expect(healths == range.map { $0 })

        let lowHealths = ViewBuilder<Health>()
            .view(into: &world)
            .filter { $1[$0].value <= 50 }
            .map { $1[$0].value }
        #expect(lowHealths == range.filter { $0 <= 50 }.map { $0 })

        let totalHealth = ViewBuilder<Health>()
            .view(into: &world)
            .reduce(0) { $0 + $1.1[$1.0].value }
        #expect(totalHealth == range.reduce(0, +))

        let sorted = ViewBuilder<Health>()
            .view(into: &world)
            .sorted { $0.1[$0.0].value > $1.1[$1.0].value }
            .map { $1[$0].value }
        #expect(sorted == range.sorted { $0 > $1 })

        for e in entities { world.destroy(e) }
    }

    @Test
    mutating func emptyWorld() {
        #expect(ViewBuilder<Position>().view(into: &world).count() == 0)
        #expect(ViewBuilder<Position, Velocity>().view(into: &world).count() == 0)
        #expect(ViewBuilder<Entity>().view(into: &world).count() == 0)

        var iterated = false
        for _ in ViewBuilder<Position, Velocity>().view(into: &world) {
            iterated = true
            #expect(Bool(false))
        }
        #expect(!iterated)
    }

    @Test
    mutating func mutationPersistence() {
        let entities = [
            world.create(with: (Position(x: 0, y: 0), Velocity(dx: 10, dy: 20))),
            world.create(with: (Position(x: 100, y: 200), Velocity(dx: 5, dy: 15))),
        ]

        for (i, (positions, velocities)) in ViewBuilder<Position, Velocity>().view(into: &world) {
            positions[i].x += velocities[i].dx
            positions[i].y += velocities[i].dy
        }

        var newPositions: [Position] = []
        for (i, (entities, positions)) in ViewBuilder<Entity, Position>().view(into: world) {
            newPositions.append(positions[i])
            #expect(positions[i] == world.get(Position.self, for: entities[i]))
        }

        #expect(newPositions.count == 2)
        #expect(newPositions.contains { $0 == Position(x: 10, y: 20) })
        #expect(newPositions.contains { $0 == Position(x: 105, y: 215) })

        for e in entities { world.destroy(e) }
    }

    @Test
    mutating func conditionalEntityMutation() {
        struct Player {}
        struct Enemy {}

        let entities = [
            world.create(with: (Health(value: 100), Player())),
            world.create(with: (Health(value: 100), Enemy())),
            world.create(with: (Health(value: 100), Enemy())),
        ]
        let player = entities[0]

        for (i, healths) in ViewBuilder<Health>().including(Enemy.self).view(into: &world) {
            healths[i].value -= 50
        }

        for (i, (entities, healths)) in ViewBuilder<Entity, Health>().view(into: world) {
            if entities[i] == player {
                #expect(healths[i].value == 100)
            } else {
                #expect(healths[i].value == 50)
            }
        }
        for e in entities { world.destroy(e) }
    }

    @Test
    mutating func sequentialMutations() {
        let entity = world.create(with: Position(x: 10, y: 10))

        for (i, positions) in ViewBuilder<Position>().view(into: &world) {
            positions[i].x *= 2
            positions[i].y *= 2
        }

        for (i, positions) in ViewBuilder<Position>().view(into: &world) {
            positions[i].x += 5
            positions[i].y += 5
        }

        for (i, positions) in ViewBuilder<Position>().view(into: &world) {
            positions[i].x /= 5
            positions[i].y /= 5
        }

        // (10 * 2 + 5) / 5 = 5
        for (i, positions) in ViewBuilder<Position>().view(into: world) {
            #expect(positions[i].x == 5)
            #expect(positions[i].y == 5)
        }

        world.destroy(entity)
    }

    @Test
    mutating func parallelMutations() async {
        let initialPosition = Position(x: 100, y: 100)
        let initialHealth = Health(value: 100)

        let entities = (0..<100).map { i in
            return world.create(
                with: (
                    initialPosition,
                    initialHealth,
                    Velocity(dx: i * 10, dy: i * 10),
                    Damage(value: i)
                )
            )
        }

        do {
            let view1 = ViewBuilder<Position, Velocity>().view(into: &world)
            let task1 = Task {
                for (i, (positions, velocities)) in view1 {
                    positions[i].x += velocities[i].dx
                    positions[i].y += velocities[i].dy
                }
            }

            let view2 = ViewBuilder<Health, Damage>().view(into: &world)
            let task2 = Task {
                for (i, (healths, damages)) in view2 {
                    healths[i].value -= damages[i].value
                }
            }

            #expect(view1.count() == entities.count)
            #expect(view2.count() == entities.count)

            await (_, _) = (task1.value, task2.value)
        }

        for (i, (positions, velocities)) in ViewBuilder<Position, Velocity>().view(into: world) {
            #expect(positions[i].x - velocities[i].dx == initialPosition.x)
            #expect(positions[i].y - velocities[i].dy == initialPosition.y)
        }

        for (i, (healths, damages)) in ViewBuilder<Health, Damage>().view(into: world) {
            #expect(healths[i].value + damages[i].value == initialHealth.value)
        }

        for e in entities { world.destroy(e) }
    }
}
