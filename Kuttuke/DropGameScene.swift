import SpriteKit
import UIKit

final class DropGameScene: SKScene, SKPhysicsContactDelegate {
    static let maximumLevel = 10

    var onScore: ((Int) -> Void)?
    var onNextLevels: (([Int]) -> Void)?
    var onGameOver: (() -> Void)?
    var onMerge: (() -> Void)?

    private let textures: [SKTexture]
    private let itemCategory: UInt32 = 1 << 0
    private let wallCategory: UInt32 = 1 << 1
    private var currentNode: SKSpriteNode?
    private var upcomingLevels: [Int] = []
    private var canDrop = true
    private var isGameFinished = false
    private var score = 0
    private var overflowStartedAt: TimeInterval?
    private var sceneTime: TimeInterval = 0
    private var didBuildBoard = false

    private let itemName = "drop-item"
    private let previewName = "preview-item"
    private let dangerLineName = "danger-line"
    private let boardInset: CGFloat = 11

    init(images: [UIImage]) {
        textures = images.map {
            let texture = SKTexture(image: $0)
            texture.filteringMode = .linear
            return texture
        }
        super.init(size: CGSize(width: 390, height: 650))
        scaleMode = .resizeFill
        backgroundColor = KuttukeTheme.uiCream
        physicsWorld.gravity = CGVector(dx: 0, dy: -7.7)
        physicsWorld.contactDelegate = self
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = false
        view.backgroundColor = .clear
        buildBoard()
        prepareNextRound()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard didBuildBoard else { return }
        rebuildBoardGeometry()
        if let currentNode {
            currentNode.position.y = dropHeight
            currentNode.position.x = clampedX(currentNode.position.x, for: currentNode)
        }
    }

    func resetGame() {
        removeAllActions()
        enumerateChildNodes(withName: itemName) { node, _ in node.removeFromParent() }
        currentNode?.removeFromParent()
        currentNode = nil
        score = 0
        canDrop = true
        isGameFinished = false
        overflowStartedAt = nil
        sceneTime = 0
        onScore?(0)
        upcomingLevels.removeAll(keepingCapacity: true)
        prepareNextRound()
    }

    func endGame() {
        finishGame()
    }

    private var dangerHeight: CGFloat { size.height * 0.79 }
    private var dropHeight: CGFloat { size.height - 48 }

    private func buildBoard() {
        didBuildBoard = true
        rebuildBoardGeometry()
    }

    private func rebuildBoardGeometry() {
        childNode(withName: "walls")?.removeFromParent()
        childNode(withName: dangerLineName)?.removeFromParent()

        let walls = SKNode()
        walls.name = "walls"
        let wallThickness: CGFloat = 22

        let left = staticWall(
            size: CGSize(width: wallThickness, height: size.height * 2),
            position: CGPoint(x: boardInset - wallThickness / 2, y: size.height / 2)
        )
        let right = staticWall(
            size: CGSize(width: wallThickness, height: size.height * 2),
            position: CGPoint(x: size.width - boardInset + wallThickness / 2, y: size.height / 2)
        )
        let floor = staticWall(
            size: CGSize(width: size.width, height: wallThickness),
            position: CGPoint(x: size.width / 2, y: boardInset - wallThickness / 2)
        )
        walls.addChild(left)
        walls.addChild(right)
        walls.addChild(floor)
        addChild(walls)

        let line = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: boardInset + 10, y: dangerHeight))
        path.addLine(to: CGPoint(x: size.width - boardInset - 10, y: dangerHeight))
        line.path = path
        line.strokeColor = KuttukeTheme.uiOrange.withAlphaComponent(0.43)
        line.lineWidth = 2
        line.name = dangerLineName
        let label = SKLabelNode(text: "LIMIT")
        label.fontName = "AvenirNext-Bold"
        label.fontSize = 9
        label.fontColor = KuttukeTheme.uiOrange.withAlphaComponent(0.65)
        label.horizontalAlignmentMode = .right
        label.position = CGPoint(x: size.width - boardInset - 12, y: dangerHeight + 7)
        line.addChild(label)
        addChild(line)
    }

    private func staticWall(size: CGSize, position: CGPoint) -> SKNode {
        let node = SKNode()
        node.position = position
        node.physicsBody = SKPhysicsBody(rectangleOf: size)
        node.physicsBody?.isDynamic = false
        node.physicsBody?.categoryBitMask = wallCategory
        node.physicsBody?.collisionBitMask = itemCategory
        return node
    }

    private func prepareNextRound() {
        guard !isGameFinished, currentNode == nil, !textures.isEmpty else { return }
        fillUpcomingLevels(to: 4)
        let level = upcomingLevels.removeFirst()
        fillUpcomingLevels(to: 3)
        onNextLevels?(Array(upcomingLevels.prefix(3)))

        let node = makeItem(level: level, dynamic: false)
        node.name = previewName
        node.position = CGPoint(x: size.width / 2, y: dropHeight)
        node.alpha = 0
        node.setScale(0.72)
        addChild(node)
        currentNode = node
        node.run(.group([
            .fadeIn(withDuration: 0.16),
            .scale(to: 1, duration: 0.22)
        ]))
    }

    private func fillUpcomingLevels(to count: Int) {
        while upcomingLevels.count < count {
            upcomingLevels.append(Int.random(in: 0...2))
        }
    }

    private func makeItem(level: Int, dynamic: Bool) -> SKSpriteNode {
        let texture = textures[min(level, textures.count - 1)]
        let side = itemSide(for: level)
        let node = SKSpriteNode(texture: texture, size: CGSize(width: side, height: side))
        node.userData = NSMutableDictionary()
        node.userData?["level"] = level
        node.zPosition = 5

        let shadow = SKSpriteNode(texture: texture, size: node.size)
        shadow.color = .black
        shadow.colorBlendFactor = 1
        shadow.alpha = 0.13
        shadow.position = CGPoint(x: 0, y: -4)
        shadow.zPosition = -1
        node.addChild(shadow)

        if dynamic {
            attachPhysics(to: node, texture: texture)
        }
        return node
    }

    private func attachPhysics(to node: SKSpriteNode, texture: SKTexture? = nil) {
        guard node.physicsBody == nil else { return }
        let physicsTexture = texture ?? node.texture!
        let body = SKPhysicsBody(texture: physicsTexture, size: node.size)
        body.isDynamic = true
        body.affectedByGravity = true
        body.allowsRotation = true
        body.restitution = 0.08
        body.friction = 0.72
        body.linearDamping = 0.32
        body.angularDamping = 0.55
        body.density = 0.9 + CGFloat(level(of: node)) * 0.09
        body.categoryBitMask = itemCategory
        body.collisionBitMask = itemCategory | wallCategory
        body.contactTestBitMask = itemCategory
        node.physicsBody = body
    }

    private func itemSide(for level: Int) -> CGFloat {
        let base = min(size.width, 430) * 0.09
        let growth: [CGFloat] = [1.0, 1.18, 1.39, 1.64, 1.94, 2.29, 2.70, 3.19, 3.76, 4.44, 5.24]
        return base * growth[min(level, growth.count - 1)]
    }

    private func level(of node: SKNode) -> Int {
        node.userData?["level"] as? Int ?? 0
    }

    private func clampedX(_ x: CGFloat, for node: SKSpriteNode) -> CGFloat {
        let radius = node.size.width * 0.36
        return min(max(x, boardInset + radius), size.width - boardInset - radius)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard canDrop, let touch = touches.first, let currentNode else { return }
        currentNode.position.x = clampedX(touch.location(in: self).x, for: currentNode)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard canDrop, let touch = touches.first, let currentNode else { return }
        currentNode.position.x = clampedX(touch.location(in: self).x, for: currentNode)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard canDrop, !isGameFinished, let currentNode else { return }
        if let touch = touches.first {
            currentNode.position.x = clampedX(touch.location(in: self).x, for: currentNode)
        }
        drop(currentNode)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let currentNode else { return }
        drop(currentNode)
    }

    private func drop(_ node: SKSpriteNode) {
        guard canDrop else { return }
        canDrop = false
        node.removeAllActions()
        node.setScale(1)
        node.alpha = 1
        node.name = itemName
        node.userData?["dropTime"] = sceneTime
        node.userData?["enteredBoard"] = false
        attachPhysics(to: node)
        currentNode = nil

        run(.sequence([
            .wait(forDuration: 0.48),
            .run { [weak self] in
                guard let self, !self.isGameFinished else { return }
                self.canDrop = true
                self.prepareNextRound()
            }
        ]))
    }

    func didBegin(_ contact: SKPhysicsContact) {
        guard !isGameFinished else { return }
        let first = contact.bodyA.node
        let second = contact.bodyB.node
        guard let first, let second,
              first.name == itemName, second.name == itemName,
              first.parent != nil, second.parent != nil else { return }

        let firstLevel = level(of: first)
        guard firstLevel == level(of: second), firstLevel < Self.maximumLevel else { return }
        guard first.action(forKey: "merging") == nil,
              second.action(forKey: "merging") == nil else { return }

        first.run(.wait(forDuration: 10), withKey: "merging")
        second.run(.wait(forDuration: 10), withKey: "merging")

        let position = CGPoint(
            x: (first.position.x + second.position.x) / 2,
            y: (first.position.y + second.position.y) / 2
        )
        let velocity = CGVector(
            dx: ((first.physicsBody?.velocity.dx ?? 0) + (second.physicsBody?.velocity.dx ?? 0)) / 2,
            dy: max(1.6, ((first.physicsBody?.velocity.dy ?? 0) + (second.physicsBody?.velocity.dy ?? 0)) / 2)
        )
        first.removeFromParent()
        second.removeFromParent()

        let merged = makeItem(level: firstLevel + 1, dynamic: true)
        merged.name = itemName
        merged.position = position
        merged.userData?["dropTime"] = sceneTime
        merged.userData?["enteredBoard"] = position.y < dangerHeight
        merged.alpha = 0
        merged.setScale(0.62)
        merged.physicsBody?.velocity = velocity
        addChild(merged)
        merged.run(.group([
            .fadeIn(withDuration: 0.12),
            .sequence([
                .scale(to: 1.12, duration: 0.13),
                .scale(to: 1, duration: 0.10)
            ])
        ]))

        let earned = Int(pow(2.0, Double(firstLevel + 1))) * 10
        score += earned
        onScore?(score)
        onMerge?()
        showScoreBurst(earned, at: position)
    }

    private func showScoreBurst(_ points: Int, at position: CGPoint) {
        let label = SKLabelNode(text: "+\(points)")
        label.fontName = "AvenirNext-Heavy"
        label.fontSize = 16
        label.fontColor = KuttukeTheme.uiOrange
        label.position = CGPoint(x: position.x, y: position.y + 12)
        label.zPosition = 30
        addChild(label)
        label.run(.sequence([
            .group([.moveBy(x: 0, y: 34, duration: 0.55), .fadeOut(withDuration: 0.55)]),
            .removeFromParent()
        ]))
    }

    override func update(_ currentTime: TimeInterval) {
        guard !isGameFinished else { return }
        sceneTime = currentTime

        var hasOverflow = false
        enumerateChildNodes(withName: itemName) { [weak self] node, stop in
            guard let self,
                  let sprite = node as? SKSpriteNode,
                  let body = sprite.physicsBody else { return }
            let visibleTop = sprite.position.y + sprite.size.height * 0.34
            let enteredBoard = sprite.userData?["enteredBoard"] as? Bool ?? false
            if !enteredBoard && visibleTop < self.dangerHeight {
                sprite.userData?["enteredBoard"] = true
            }

            let dropTime = sprite.userData?["dropTime"] as? TimeInterval ?? currentTime
            let hasSettledSinceDrop = currentTime - dropTime > 1.4 && abs(body.velocity.dy) < 3
            if visibleTop > self.dangerHeight && (enteredBoard || hasSettledSinceDrop) {
                hasOverflow = true
                stop.pointee = true
            }
        }

        if hasOverflow {
            if let overflowStartedAt {
                if currentTime - overflowStartedAt > 1.8 { finishGame() }
            } else {
                overflowStartedAt = currentTime
            }
        } else {
            overflowStartedAt = nil
        }
    }

    private func finishGame() {
        guard !isGameFinished else { return }
        isGameFinished = true
        canDrop = false
        currentNode?.removeFromParent()
        currentNode = nil
        enumerateChildNodes(withName: itemName) { node, _ in
            node.physicsBody?.isResting = true
        }
        run(.sequence([.wait(forDuration: 0.25), .run { [weak self] in self?.onGameOver?() }]))
    }
}
