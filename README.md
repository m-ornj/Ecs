# Ecs
A lightweight and minimalistic Entity-Component-System (ECS) framework written in Swift. It uses an archetype-based design to organize components efficiently and provides fast and flexible iteration over entities.

This project was built as an exploration of how an ECS could look and feel in native Swift. It’s not designed to be better than any other existing engine and focuses more on minimalism and simplicity, aiming to provide a clean and natural Swift experience.

### Features

- Archetype-based storage for dense and cache-friendly layout.
- Copy-on-write struct semantics for controllable mutations.
- Parameter packs for expressive and type-safe iteration.
- No component registration, macros or extra boilerplate.
- Built with Swift 6 strict concurrency in mind.

### Usage

You start by creating a `World`. It allows you to `create` and `destroy` entities.
```swift
var world = World()

let entity: Entity = world.create()

world.destroy(entity)
```

You can `insert` and `remove` components for a specific `Entity`. You can also `get` individual components of entities. 
```swift
struct Position { var x: Float, y: Float }
struct Velocity { var dx: Float, dy: Float }

world.insert(Position(x: 0, y: 0), for: entity)
world.insert(Velocity(dx: 1, dy: 5), for: entity)

if var position = world.get(Position.self, for: entity),
    let velocity = world.get(Velocity.self, for: entity)
{
    position.x += velocity.dx
    position.y += velocity.dy
    world.insert(position, for: entity)
}

world.remove(Position.self, for: entity)

let position = world.get(Position.self, for: entity) // nil
```

Any type can be a component. Technically, `Entity` itself is a component, which is useful in iterations. You can even `get` an `Entity`, but it has no real point. However, you're **not allowed** to `insert` or `remove` an `Entity`. Doing this will trigger a runtime error.
```swift
if let other = world.get(Entity.self, for: entity) {
    // other == entity 
}

// DON'T DO THIS
world.insert(other, for: entity)
world.remove(Entity.self, for: entity)
```

To iterate over entities with specific components, use a `View` created by `ViewBuilder`. `View` conforms to `Sequence` so you can use iterate in a for loop. The iteration yields a tuple containing an index and a tuple of `UnsafeBufferPointer` for each component type. Use the index to access the corresponding component data from each buffer.
```swift
let view = ViewBuilder<Position, Velocity>().view(into: world)
for (i, (positions, velocities)) in view {
    print(position[i], velocities[i])
}
```

Because `Entity` is treated as a component, you can add it to `ViewBuilder` generic parameters to access entities during iteration.
```swift
let view = ViewBuilder<Entity, Position, Velocity>().view(into: world)
for (i, (entities, positions, velocities)) in view {
    print("\(entities[i]) has \(positions[i]) and \(velocities[i])")
}
```

In order to modify components while iterating, you should use `MutableView`. It's created by `ViewBuilder` the same way as `View` with the exception of `World` being passed there as an `inout` argument. Iteration over `MutableView` yields `UnsafeMutableBufferPointer` instead of `UnsafeBufferPointer`.
```swift
let view = ViewBuilder<Position, Velocity>().view(into: &world)
for (i, (positions, velocities)) in view {
    positions[i].x += velocities[i].x
    positions[i].y += velocities[i].y
}
```

You only get access to the components included in `ViewBuilder` generic parameters, but you can `include` or `exclude` additional components.
```swift
let view = ViewBuilder<Entity>()
    .including(Enemy.self)
    .excluding(Dead.self)
    .view(into: world)

for (i, entities) in view {
    print("\(entities[i]) is an Enemy and isn't Dead")
}
```
