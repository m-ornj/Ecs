import Testing

@testable import Ecs

@Suite
struct EcsTests {
    var world = World()

    @Test
    mutating func multipleComponents() {
        struct Position { var x: Int, y: Int }
        struct Velocity { var dx: Int, dy: Int }
        struct Health { var value: Int }

        let entity1 = world.create()
        world.insert(Position(x: 10, y: 20), for: entity1)
        world.insert(Velocity(dx: 5, dy: 5), for: entity1)
        world.insert(Health(value: 100), for: entity1)

        let entity2 = world.create()
        world.insert(Position(x: 30, y: 40), for: entity2)
        world.insert(Velocity(dx: 2, dy: 2), for: entity2)

        let entity3 = world.create()
        world.insert(Position(x: 50, y: 60), for: entity3)

        let position1 = world.get(Position.self, for: entity1)
        let velocity1 = world.get(Velocity.self, for: entity1)
        let health1 = world.get(Health.self, for: entity1)

        let position2 = world.get(Position.self, for: entity2)
        let velocity2 = world.get(Velocity.self, for: entity2)

        let position3 = world.get(Position.self, for: entity3)

        #expect(position1 != nil)
        #expect(position1?.x == 10)
        #expect(position1?.y == 20)
        #expect(velocity1 != nil)
        #expect(velocity1?.dx == 5)
        #expect(velocity1?.dy == 5)
        #expect(health1 != nil)
        #expect(health1?.value == 100)

        #expect(position2 != nil)
        #expect(position2?.x == 30)
        #expect(position2?.y == 40)
        #expect(velocity2 != nil)
        #expect(velocity2?.dx == 2)
        #expect(velocity2?.dy == 2)

        #expect(position3 != nil)
        #expect(position3?.x == 50)
        #expect(position3?.y == 60)

        var entitiesWithPosition: [Entity] = []
        var entitiesWithVelocity: [Entity] = []

        ViewBuilder<Entity>()
            .including(Position.self)
            .view(into: world)
            .forEach(in: world) { entitiesWithPosition.append($0) }

        ViewBuilder<Entity>()
            .including(Velocity.self)
            .view(into: world)
            .forEach(in: world) { entitiesWithVelocity.append($0) }

        #expect(entitiesWithPosition.count == 3)
        #expect(entitiesWithPosition.contains(entity1))
        #expect(entitiesWithPosition.contains(entity2))
        #expect(entitiesWithPosition.contains(entity3))

        #expect(entitiesWithVelocity.count == 2)
        #expect(entitiesWithVelocity.contains(entity1))
        #expect(entitiesWithVelocity.contains(entity2))
        #expect(!entitiesWithVelocity.contains(entity3))

        world.destroy(entity2)

        let removedPosition2 = world.get(Position.self, for: entity2)
        let removedVelocity2 = world.get(Velocity.self, for: entity2)

        #expect(removedPosition2 == nil)
        #expect(removedVelocity2 == nil)

        entitiesWithPosition.removeAll()
        entitiesWithVelocity.removeAll()

        ViewBuilder<Entity>()
            .including(Position.self)
            .view(into: world)
            .forEach(in: world) { entitiesWithPosition.append($0) }

        ViewBuilder<Entity>()
            .including(Velocity.self)
            .view(into: world)
            .forEach(in: world) { entitiesWithVelocity.append($0) }

        #expect(entitiesWithPosition.count == 2)
        #expect(entitiesWithPosition.contains(entity1))
        #expect(!entitiesWithPosition.contains(entity2))
        #expect(entitiesWithPosition.contains(entity3))

        #expect(entitiesWithVelocity.count == 1)
        #expect(entitiesWithVelocity.contains(entity1))
        #expect(!entitiesWithVelocity.contains(entity2))

        world.destroy(entity1)
        world.destroy(entity2)
        world.destroy(entity3)
    }

    @Test
    mutating func insertReinsert() {
        struct Flag { var value: Bool }

        let e1 = world.create()
        let e2 = world.create()

        world.insert(Flag(value: false), for: e1)
        world.insert(Flag(value: true), for: e2)

        #expect(world.get(Flag.self, for: e1)?.value == false)
        #expect(world.get(Flag.self, for: e2)?.value == true)

        world.insert(Flag(value: true), for: e1)
        #expect(world.get(Flag.self, for: e1)?.value == true)

        world.update(Flag.self, for: e2) { $0.value = false }
        #expect(world.get(Flag.self, for: e2)?.value == false)

        world.destroy(e1)
        world.destroy(e2)
    }

    @Test
    mutating func complexView() {
        struct DivBy2 { var n: Int }
        struct DivBy3 { var n: Int }
        struct DivBy5 { var n: Int }

        var entities: [Entity] = []

        for i in 0..<100 {
            let e = world.create()
            if i % 2 == 0 { world.insert(DivBy2(n: i), for: e) }
            if i % 3 == 0 { world.insert(DivBy3(n: i), for: e) }
            if i % 5 == 0 { world.insert(DivBy5(n: i), for: e) }
            entities.append(e)
        }

        var count: Int
        var expected: Int

        count = 0
        ViewBuilder<DivBy2, DivBy3, DivBy5>()
            .view(into: world)
            .forEach(in: world) { a, b, c in
                #expect(a.n == b.n && b.n == c.n)
                let n = a.n
                #expect(n % 2 == 0)
                #expect(n % 3 == 0)
                #expect(n % 5 == 0)
                count += 1
            }
        expected = (0..<100).filter { $0 % 2 == 0 && $0 % 3 == 0 && $0 % 5 == 0 }.count
        #expect(count == expected)

        count = 0
        ViewBuilder<DivBy2, DivBy5>()
            .excluding(DivBy3.self)
            .view(into: world)
            .forEach(in: world) { a, b in
                #expect(a.n == b.n)
                let n = a.n
                #expect(n % 2 == 0)
                #expect(n % 3 != 0)
                #expect(n % 5 == 0)
                count += 1
            }
        expected = (0..<100).filter { $0 % 2 == 0 && $0 % 3 != 0 && $0 % 5 == 0 }.count
        #expect(count == expected)

        count = 0
        ViewBuilder<DivBy5>()
            .excluding(DivBy2.self, DivBy3.self)
            .view(into: world)
            .forEach(in: world) { a in
                #expect(a.n % 2 != 0)
                #expect(a.n % 3 != 0)
                #expect(a.n % 5 == 0)
                count += 1
            }
        expected = (0..<100).filter { $0 % 2 != 0 && $0 % 3 != 0 && $0 % 5 == 0 }.count
        #expect(count == expected)

        count = 0
        ViewBuilder<Entity>()
            .including(DivBy3.self)
            .excluding(DivBy5.self)
            .view(into: world)
            .forEach(in: world) { _ in count += 1 }
        expected = (0..<100).filter { $0 % 3 == 0 && $0 % 5 != 0 }.count
        #expect(count == expected)

        count = 0
        ViewBuilder<Entity>()
            .excluding(DivBy2.self, DivBy3.self, DivBy5.self)
            .view(into: world)
            .forEach(in: world) { _ in count += 1 }
        expected = (0..<100).filter { $0 % 2 != 0 && $0 % 3 != 0 && $0 % 5 != 0 }.count
        #expect(count == expected)

        count = 0
        ViewBuilder<DivBy2>()
            .excluding(Entity.self)
            .view(into: world)
            .forEach(in: world) { _ in count += 1 }
        expected = 0
        #expect(count == expected)

        for e in entities { world.destroy(e) }
    }

    @Test
    mutating func tags() {
        struct Actor {}
        struct Player {}
        struct Enemy {}

        let entity1 = world.create()
        let entity2 = world.create()
        let entity3 = world.create()

        world.insert(Actor(), for: entity1)
        world.insert(Player(), for: entity1)
        world.insert(Actor(), for: entity2)
        world.insert(Enemy(), for: entity2)
        world.insert(Actor(), for: entity3)

        #expect(world.get(Actor.self, for: entity1) != nil)
        #expect(world.get(Actor.self, for: entity2) != nil)
        #expect(world.get(Actor.self, for: entity3) != nil)

        #expect(world.get(Player.self, for: entity1) != nil)
        #expect(world.get(Player.self, for: entity2) == nil)
        #expect(world.get(Player.self, for: entity3) == nil)

        #expect(world.get(Enemy.self, for: entity1) == nil)
        #expect(world.get(Enemy.self, for: entity2) != nil)
        #expect(world.get(Enemy.self, for: entity3) == nil)

        var actors: [Entity] = []
        ViewBuilder<Entity>()
            .including(Actor.self)
            .view(into: world)
            .forEach(in: world) { actors.append($0) }
        #expect(actors.count == 3)
        #expect(actors.contains(entity1))
        #expect(actors.contains(entity2))
        #expect(actors.contains(entity3))

        var players: [Entity] = []
        ViewBuilder<Entity>()
            .including(Player.self)
            .view(into: world)
            .forEach(in: world) { players.append($0) }
        #expect(players.count == 1)
        #expect(players.contains(entity1))

        var enemies: [Entity] = []
        ViewBuilder<Entity>()
            .including(Enemy.self)
            .view(into: world)
            .forEach(in: world) { enemies.append($0) }
        #expect(enemies.count == 1)
        #expect(enemies.contains(entity2))

        var neutrals: [Entity] = []
        ViewBuilder<Entity>()
            .including(Actor.self)
            .excluding(Enemy.self, Player.self)
            .view(into: world)
            .forEach(in: world) { neutrals.append($0) }
        #expect(neutrals.count == 1)
        #expect(neutrals.contains(entity3))

        world.remove(Enemy.self, for: entity2)

        neutrals.removeAll()
        ViewBuilder<Entity>()
            .including(Actor.self)
            .excluding(Enemy.self, Player.self)
            .view(into: world)
            .forEach(in: world) { neutrals.append($0) }
        #expect(neutrals.count == 2)
        #expect(neutrals.contains(entity2))
        #expect(neutrals.contains(entity3))

        world.destroy(entity1)
        world.destroy(entity2)
        world.destroy(entity3)
    }

    @Test
    mutating func viewCaching() {
        struct Foo { var value: Int }
        struct Bar { var value: Int }

        let entities = (0..<10).map { _ in
            world.create()
        }

        for (i, e) in entities.enumerated() {
            world.insert(Foo(value: i), for: e)
            #expect(world.get(Foo.self, for: e)?.value == i)
        }

        var view = ViewBuilder<Entity, Foo>().view(into: world)
        #expect(view.count == entities.count)

        var visited: Int

        visited = 0
        view.forEach(in: world) { _, _ in visited += 1 }
        #expect(visited == entities.count)
        #expect(view.isValid(for: world))

        let increase = 100
        view.forEach(in: &world) { entity, foo in
            foo.pointee.value += increase
        }
        #expect(view.isValid(for: world))
        for (i, e) in entities.enumerated() {
            #expect(world.get(Foo.self, for: e)?.value == i + increase)
        }

        for (i, e) in entities.dropLast(5).enumerated() {
            world.insert(Bar(value: i), for: e)
        }
        #expect(!view.isValid(for: world))
        view.rebuild(for: world)
        #expect(view.isValid(for: world))
        #expect(view.count == entities.count)

        visited = 0
        view.forEach(in: world) { _, _ in visited += 1 }
        #expect(visited == entities.count)

        for entity in entities {
            world.destroy(entity)
        }

        #expect(!view.isValid(for: world))
        view.rebuild(for: world)
        #expect(view.count == 0)
        visited = 0
        view.forEach(in: world) { _, _ in visited += 1 }
        #expect(visited == 0)
    }

    @Test
    mutating func gravitySample() {
        struct Position { var y: Float }
        struct Velocity { var dy: Float }
        struct Grounded {}

        let entities = (0..<10).map { _ in world.create() }
        for (i, entity) in entities.enumerated() {
            world.insert(Position(y: Float(i + 1) * 2), for: entity)
            world.insert(Velocity(dy: -1), for: entity)
        }

        let update: (inout World) -> Void = { world in
            var grounded: [Entity] = []
            ViewBuilder<Position, Velocity>()
                .excluding(Grounded.self)
                .view(into: world)
                .forEach(in: &world) { pos, vel in
                    pos.pointee.y += vel.pointee.dy
                }

            ViewBuilder<Position, Entity>()
                .excluding(Grounded.self)
                .view(into: world)
                .forEach(in: world) { pos, entity in
                    if pos.y <= 0 {
                        grounded.append(entity)
                    }
                }

            for entity in grounded {
                world.insert(Grounded(), for: entity)
            }
        }

        for _ in 0..<10 { update(&world) }

        var groundedCount = 0
        ViewBuilder<Grounded>().view(into: world).forEach(in: world) { _ in groundedCount += 1 }
        #expect(groundedCount == 5)

        for _ in 0..<10 { update(&world) }

        groundedCount = 0
        ViewBuilder<Grounded>().view(into: world).forEach(in: world) { _ in groundedCount += 1 }
        #expect(groundedCount == 10)

        for entity in entities {
            world.destroy(entity)
        }
    }

    @Test
    mutating func immutableConcurrency() async {
        struct Distance { var value: Float }
        struct Enemy {}
        struct Friend {}

        var entities: [Entity] = []

        let friendsCount = 10
        let enemiesCount = 10

        var expectedAverageFriendDistance: Float = 0
        var expectedNearestFriendDistance: Float = Float.greatestFiniteMagnitude

        var expectedAverageEnemyDistance: Float = 0
        var expectedNearestEnemyDistance: Float = Float.greatestFiniteMagnitude

        for i in 0..<friendsCount {
            let e = world.create()
            let distance = Float(i) * 5
            world.insert(Distance(value: distance), for: e)
            world.insert(Friend(), for: e)
            expectedAverageFriendDistance += distance
            expectedNearestFriendDistance = min(distance, expectedNearestFriendDistance)
            entities.append(e)
        }
        expectedAverageFriendDistance /= Float(friendsCount)

        for i in 0..<enemiesCount {
            let e = world.create()
            let distance = Float(i) * 8
            world.insert(Distance(value: distance), for: e)
            world.insert(Enemy(), for: e)
            expectedAverageEnemyDistance += distance
            expectedNearestEnemyDistance = min(distance, expectedNearestEnemyDistance)
            entities.append(e)
        }
        expectedAverageEnemyDistance /= Float(enemiesCount)

        do {
            let snapshot = world

            let friendsTask = Task {
                var totalDistance: Float = 0
                var nearestDistance = Float.greatestFiniteMagnitude
                var count = 0

                ViewBuilder<Distance, Friend>()
                    .view(into: snapshot)
                    .forEach(in: snapshot) { distance, _ in
                        totalDistance += distance.value
                        nearestDistance = min(distance.value, nearestDistance)
                        count += 1
                    }

                return (
                    averageDistance: count > 0 ? totalDistance / Float(count) : 0.0,
                    nearestDistance: nearestDistance
                )
            }

            let enemiesTask = Task {
                var totalDistance: Float = 0
                var nearestDistance = Float.greatestFiniteMagnitude
                var count = 0

                ViewBuilder<Distance, Enemy>()
                    .view(into: snapshot)
                    .forEach(in: snapshot) { distance, _ in
                        totalDistance += distance.value
                        nearestDistance = min(distance.value, nearestDistance)
                        count += 1
                    }

                return (
                    averageDistance: count > 0 ? totalDistance / Float(count) : 0.0,
                    nearestDistance: nearestDistance
                )
            }

            let (friendsResult, enemiesResult) = await (friendsTask.value, enemiesTask.value)

            #expect(friendsResult.averageDistance == expectedAverageFriendDistance)
            #expect(friendsResult.nearestDistance == expectedNearestFriendDistance)

            #expect(enemiesResult.averageDistance == expectedAverageEnemyDistance)
            #expect(enemiesResult.nearestDistance == expectedNearestEnemyDistance)

            #expect(world.id == snapshot.id)
        }

        for entity in entities {
            world.destroy(entity)
        }
    }

    @Test
    mutating func mutableConcurrency() async throws {
        struct Position { var x: Float, y: Float }
        struct Velocity { var dx: Float, dy: Float }
        struct Health { var value: Float }
        struct Damage { var value: Float }

        let initialPosition = Position(x: 100, y: 100)
        let initialHealth = Health(value: 100)

        let entities = (0..<100).map { _ in world.create() }
        for (i, e) in entities.enumerated() {
            let i = Float(i)
            world.insert(initialPosition, for: e)
            world.insert(initialHealth, for: e)
            world.insert(Velocity(dx: i * -0.5, dy: i * -0.5), for: e)
            world.insert(Damage(value: i * 0.1), for: e)
        }

        do {
            let view1 = ViewBuilder<Position, Velocity>().unsafeView(into: &world)
            #expect(view1.count == entities.count)
            let task1 = Task {
                for (position, velocity) in view1 {
                    position.pointee.x += velocity.pointee.dx
                    position.pointee.y += velocity.pointee.dy
                }
            }

            let view2 = ViewBuilder<Health, Damage>().unsafeView(into: &world)
            #expect(view2.count == entities.count)
            let task2 = Task {
                for (health, damage) in view2 {
                    health.pointee.value -= damage.pointee.value
                }
            }

            await (_, _) = (task1.value, task2.value)
        }

        ViewBuilder<Position, Velocity>()
            .view(into: world)
            .forEach(in: world) { position, velocity in
                #expect(position.x - velocity.dx == initialPosition.x)
                #expect(position.y - velocity.dy == initialPosition.y)
            }

        ViewBuilder<Health, Damage>()
            .view(into: world)
            .forEach(in: world) { health, damage in
                #expect(health.value + damage.value == initialHealth.value)
            }

        for entity in entities {
            world.destroy(entity)
        }
    }

    @Test
    mutating func createWithComponents() {
        struct Position { var x: Float, y: Float }
        struct Velocity { var x: Float, y: Float }

        let initialPosition = Position(x: 100, y: 100)
        let entities = (0..<1000).map { i in
            let i = Float(i)
            let e = world.create(
                with: (
                    initialPosition,
                    Velocity(x: i * -0.5, y: i * -0.5)
                )
            )
            return e
        }

        #expect(ViewBuilder<Entity>().view(into: world).count == entities.count)
        #expect(ViewBuilder<Position>().view(into: world).count == entities.count)
        #expect(ViewBuilder<Velocity>().view(into: world).count == entities.count)

        var view = ViewBuilder<Position, Velocity>().view(into: world)
        #expect(view.count == entities.count)

        view.forEach(in: &world) { position, velocity in
            position.pointee.x += velocity.pointee.x
            position.pointee.y += velocity.pointee.y
        }

        view.forEach(in: world) { position, velocity in
            #expect(position.x - velocity.x == initialPosition.x)
            #expect(position.y - velocity.y == initialPosition.y)
        }

        for entity in entities {
            world.destroy(entity)
        }

        view.rebuild(for: world)
        #expect(view.count == 0)
        #expect(ViewBuilder<Entity>().view(into: world).count == 0)
        #expect(ViewBuilder<Position>().view(into: world).count == 0)
        #expect(ViewBuilder<Velocity>().view(into: world).count == 0)
    }
}
