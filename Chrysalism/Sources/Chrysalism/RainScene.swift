import SpriteKit

/// The rain simulation. Renders with a transparent background so the desktop
/// wallpaper shows through, and simulates layered rainfall, splashes, dock
/// collisions and a whisper of ground mist.
final class RainScene: SKScene {

    // MARK: - Layers

    private struct LayerSpec {
        let fraction: Double
        let length: ClosedRange<CGFloat>
        let width: ClosedRange<CGFloat>
        let speed: ClosedRange<CGFloat>
        let alpha: ClosedRange<CGFloat>
        let windFactor: CGFloat
    }

    /// Far → near. Depth is sold through size, speed and opacity.
    private static let layerSpecs: [LayerSpec] = [
        LayerSpec(fraction: 0.55, length: 8...15, width: 0.8...1.3, speed: 240...380, alpha: 0.08...0.15, windFactor: 0.45),
        LayerSpec(fraction: 0.30, length: 15...28, width: 1.2...2.0, speed: 520...690, alpha: 0.14...0.22, windFactor: 0.75),
        LayerSpec(fraction: 0.15, length: 28...52, width: 1.6...2.8, speed: 780...960, alpha: 0.20...0.30, windFactor: 1.0),
    ]

    // MARK: - Actors

    private struct Drop {
        var node: SKSpriteNode
        var vx: CGFloat
        var vy: CGFloat
        var layer: Int
    }

    private struct FlyingDrop {
        var node: SKSpriteNode
        var vx: CGFloat
        var vy: CGFloat
        var bounces: Int
        var life: CGFloat
        var alpha0: CGFloat
    }

    private struct Ripple {
        var node: SKSpriteNode
        var t: CGFloat
        let duration: CGFloat
        let alpha0: CGFloat
    }

    // MARK: - Public state

    /// Scene-space rect of the Dock panel on this display when bounce is enabled.
    var dockRect: CGRect?

    /// Radius of the Dock panel's rounded top corners.
    var dockCornerRadius: CGFloat = 0

    var intensity: RainIntensity = .steady {
        didSet { targetCount = intensity.dropCount }
    }

    private var targetCount = RainIntensity.steady.dropCount

    /// Base slant of the rainfall in degrees — positive leans right.
    var angle: CGFloat = Settings.shared.rainAngle {
        didSet { slantSlope = tan(angle * .pi / 180) }
    }

    /// Horizontal distance travelled per point of fall (tan of the angle).
    private var slantSlope = tan(Settings.shared.rainAngle * .pi / 180)

    // MARK: - Private state

    private var drops: [Drop] = []
    private var flying: [FlyingDrop] = []
    private var ripples: [Ripple] = []
    private var fogNodes: [SKSpriteNode] = []
    private var dropPool: [SKSpriteNode] = []
    private var dropletPool: [SKSpriteNode] = []
    private var ripplePool: [SKSpriteNode] = []

    private var lastTime: TimeInterval = 0
    private var time: TimeInterval = 0
    private var windCurrent: CGFloat = 0
    private var windTarget: CGFloat = 0
    private var windChangeAt: TimeInterval = 0
    private var windInstant: CGFloat = 0

    private let gravity: CGFloat = 1250

    // MARK: - Lifecycle

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        targetCount = intensity.dropCount
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func didMove(to view: SKView) {
        setupFog()
    }

    // MARK: - Per-frame update

    override func update(_ currentTime: TimeInterval) {
        let dt: CGFloat = lastTime == 0 ? 1.0 / 60.0 : CGFloat(min(currentTime - lastTime, 0.1))
        lastTime = currentTime
        time += TimeInterval(dt)

        updateWind(dt)
        updateDrops(dt)
        updateSplashes(dt)
        maintainPopulation()
        updateFog(dt)
    }

    // MARK: - Wind

    private func updateWind(_ dt: CGFloat) {
        if time >= windChangeAt {
            windTarget = .random(in: -26...26)
            windChangeAt = time + .random(in: 4...10)
        }
        windCurrent += (windTarget - windCurrent) * min(1, dt * 0.6)
        let t = CGFloat(time)
        windInstant = windCurrent + sin(t * 0.7) * 7 + sin(t * 2.1 + 1.3) * 3.5
    }

    // MARK: - Drops

    private func updateDrops(_ dt: CGFloat) {
        let height = size.height
        for index in drops.indices {
            var drop = drops[index]
            let spec = Self.layerSpecs[drop.layer]
            let vx = drop.vx
                + windInstant * spec.windFactor
                + slantSlope * -drop.vy * spec.windFactor
            var pos = drop.node.position
            pos.x += vx * dt
            pos.y += drop.vy * dt
            drop.node.position = pos
            drop.node.zRotation = atan2(vx, -drop.vy)

            let (ground, isDock) = groundAt(pos.x)
            if pos.y - drop.node.size.height * 0.5 <= ground {
                splash(
                    at: CGPoint(x: pos.x, y: ground),
                    isDock: isDock,
                    speed: -drop.vy,
                    width: drop.node.size.width,
                    alpha: spec.alpha.upperBound,
                    layer: drop.layer
                )
                respawn(&drop, height: height)
            }
            drops[index] = drop
        }
    }

    private func respawn(_ drop: inout Drop, height: CGFloat) {
        let spec = Self.layerSpecs[drop.layer]
        let margin = 20 + abs(slantSlope) * height
        drop.node.position = CGPoint(
            x: CGFloat.random(in: -margin...(size.width + margin)),
            y: height + CGFloat.random(in: 0...120)
        )
        drop.vx = CGFloat.random(in: -18...18)
        drop.vy = -CGFloat.random(in: spec.speed)
    }

    private func maintainPopulation() {
        if drops.count < targetCount {
            let add = min(6, targetCount - drops.count)
            for _ in 0..<add {
                drops.append(makeDrop(layer: randomLayer(), spawnAnywhere: false))
            }
        } else if drops.count > targetCount {
            let remove = min(6, drops.count - targetCount)
            for _ in 0..<remove {
                guard let drop = drops.popLast() else { break }
                drop.node.isHidden = true
                dropPool.append(drop.node)
            }
        }
    }

    private func randomLayer() -> Int {
        let roll = Double.random(in: 0...1)
        var cumulative = 0.0
        for (index, spec) in Self.layerSpecs.enumerated() {
            cumulative += spec.fraction
            if roll < cumulative { return index }
        }
        return Self.layerSpecs.count - 1
    }

    private func makeDrop(layer: Int, spawnAnywhere: Bool) -> Drop {
        let spec = Self.layerSpecs[layer]
        let node = dropPool.popLast() ?? SKSpriteNode(texture: RainTextures.streak)
        if node.parent == nil { addChild(node) }
        node.isHidden = false
        node.texture = RainTextures.streak
        node.size = CGSize(width: CGFloat.random(in: spec.width), height: CGFloat.random(in: spec.length))
        node.alpha = CGFloat.random(in: spec.alpha)
        node.zPosition = CGFloat(layer + 1)

        let y: CGFloat = spawnAnywhere
            ? CGFloat.random(in: 0...size.height)
            : size.height + CGFloat.random(in: 0...120)
        let vx = CGFloat.random(in: -18...18)
        let vy = -CGFloat.random(in: spec.speed)
        let margin = 20 + abs(slantSlope) * size.height
        node.position = CGPoint(x: CGFloat.random(in: -margin...(size.width + margin)), y: y)
        let slantVX = slantSlope * -vy * spec.windFactor
        node.zRotation = atan2(vx + slantVX, -vy)
        return Drop(node: node, vx: vx, vy: vy, layer: layer)
    }

    // MARK: - Ground

    /// Ground height at a horizontal position, accounting for the Dock
    /// panel's rounded corners: within the straight top span drops bounce;
    /// in the corner bands they splash on the curved glass but don't hop
    /// (a straight-up bounce off a steeply angled surface would look wrong).
    private func groundAt(_ x: CGFloat) -> (ground: CGFloat, isDock: Bool) {
        guard let dock = dockRect, x >= dock.minX, x <= dock.maxX else {
            return (0, false)
        }
        let r = min(dockCornerRadius, dock.width / 2, dock.height / 2)
        if x >= dock.minX + r && x <= dock.maxX - r {
            return (dock.maxY, true)
        }
        // Top corner arcs: circle centres sit just inside each corner.
        let centerX = x < dock.midX ? dock.minX + r : dock.maxX - r
        let dx = abs(x - centerX)
        guard dx <= r else { return (0, false) }
        let cy = dock.maxY - r
        let height = (r * r - dx * dx).squareRoot()
        return (cy + height, false)
    }

    // MARK: - Splashes

    private func splash(at point: CGPoint, isDock: Bool, speed: CGFloat, width: CGFloat, alpha: CGFloat, layer: Int) {
        let energy = min(1, speed / 950)
        let diameter = width * .random(in: 4...7) * (isDock ? 0.8 : 1.0)
        spawnRipple(
            at: point,
            diameter: diameter,
            alpha: min(0.5, alpha * 2.2),
            duration: .random(in: 0.3...0.55)
        )

        var dropletCount: Int
        switch layer {
        case 0: dropletCount = Int.random(in: 0...1)
        case 1: dropletCount = Int.random(in: 0...2)
        default: dropletCount = Int.random(in: 1...3)
        }
        if isDock { dropletCount = max(1, dropletCount) }
        for _ in 0..<dropletCount {
            spawnFlyingDrop(at: point, energy: energy, layer: layer, isDock: isDock)
        }
    }

    private func spawnFlyingDrop(at point: CGPoint, energy: CGFloat, layer: Int, isDock: Bool) {
        let node = dropletPool.popLast() ?? SKSpriteNode(texture: RainTextures.streak)
        if node.parent == nil { addChild(node) }
        node.isHidden = false
        node.texture = RainTextures.streak
        let w = CGFloat.random(in: 1.4...2.6) * (layer == 2 ? 1.2 : 1.0)
        node.size = CGSize(width: w, height: w * 2.5)
        node.zPosition = 10
        node.position = point

        let alpha0 = CGFloat.random(in: 0.45...0.75)
        node.alpha = alpha0
        let vy = -CGFloat.random(in: 40...150) * (0.5 + energy * 0.5) * (isDock ? 1.2 : 1.0)
        let vx = CGFloat.random(in: -80...80) * (0.3 + energy * 0.7)
            + windInstant * 0.5
            + slantSlope * 60
        node.zRotation = atan2(vx, -vy)

        flying.append(
            FlyingDrop(
                node: node,
                vx: vx,
                vy: vy,
                bounces: isDock ? Int.random(in: 1...2) : 1,
                life: .random(in: 0.5...0.9),
                alpha0: alpha0
            )
        )
    }

    private func spawnRipple(at point: CGPoint, diameter: CGFloat, alpha: CGFloat, duration: CGFloat) {
        guard alpha > 0.02, diameter > 1 else { return }
        let node = ripplePool.popLast() ?? SKSpriteNode(texture: RainTextures.ripple)
        if node.parent == nil { addChild(node) }
        node.isHidden = false
        node.texture = RainTextures.ripple
        node.size = CGSize(width: diameter, height: diameter * 0.45)
        node.position = point
        node.zPosition = 5
        node.setScale(0.25)
        node.alpha = alpha
        ripples.append(Ripple(node: node, t: 0, duration: duration, alpha0: alpha))
    }

    private func updateSplashes(_ dt: CGFloat) {
        var liveRipples: [Ripple] = []
        for var ripple in ripples {
            ripple.t += dt
            let k = ripple.t / ripple.duration
            if k >= 1 {
                ripple.node.isHidden = true
                ripplePool.append(ripple.node)
                continue
            }
            let eased = 1 - (1 - k) * (1 - k)
            ripple.node.setScale(0.25 + 0.75 * eased)
            ripple.node.alpha = ripple.alpha0 * (1 - k * k)
            liveRipples.append(ripple)
        }
        ripples = liveRipples

        var liveFlying: [FlyingDrop] = []
        for var drop in flying {
            drop.life -= dt
            drop.vy -= gravity * dt
            var pos = drop.node.position
            pos.x += drop.vx * dt
            pos.y += drop.vy * dt
            drop.node.position = pos
            drop.node.zRotation = atan2(drop.vx, -drop.vy)

            if drop.life <= 0 {
                drop.node.isHidden = true
                dropletPool.append(drop.node)
                continue
            }

            let (ground, isDock) = groundAt(pos.x)
            if pos.y <= ground + 1 {
                let landedHard = drop.vy < -120
                if isDock && drop.bounces > 0 && landedHard {
                    pos.y = ground + 1
                    drop.node.position = pos
                    drop.vy = -drop.vy * 0.45
                    drop.vx = drop.vx * 0.6 + .random(in: -20...20)
                    drop.bounces -= 1
                    drop.node.zRotation = atan2(drop.vx, -drop.vy)
                    spawnRipple(at: pos, diameter: .random(in: 5...9), alpha: 0.22, duration: 0.28)
                } else {
                    drop.node.isHidden = true
                    dropletPool.append(drop.node)
                    continue
                }
            }
            drop.node.alpha = drop.alpha0 * min(1, drop.life / 0.35)
            liveFlying.append(drop)
        }
        flying = liveFlying
    }

    // MARK: - Mist

    private func setupFog() {
        guard fogNodes.isEmpty else { return }
        for _ in 0..<5 {
            let node = SKSpriteNode(texture: RainTextures.fog)
            node.size = CGSize(
                width: size.width * .random(in: 0.35...0.6),
                height: .random(in: 60...110)
            )
            node.alpha = .random(in: 0.05...0.09)
            node.position = CGPoint(
                x: .random(in: 0...size.width),
                y: .random(in: -10...40)
            )
            node.zPosition = 0
            addChild(node)
            fogNodes.append(node)
        }
    }

    private func updateFog(_ dt: CGFloat) {
        for node in fogNodes {
            var pos = node.position
            pos.x += (8 + windInstant * 0.05) * dt
            if pos.x - node.size.width / 2 > size.width {
                pos.x = -node.size.width / 2
            }
            node.position = pos
        }
    }
}