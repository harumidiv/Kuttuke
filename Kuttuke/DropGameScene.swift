import SpriteKit
import UIKit

final class DropGameScene: SKScene, SKPhysicsContactDelegate {
    /// レベルごとの大きさ（盤面幅に対する基準サイズの倍率）。最大11個分
    private static let growth: [CGFloat] = [1.0, 1.18, 1.39, 1.64, 1.94, 2.29, 2.70, 3.19, 3.76, 4.44, 5.24]
    private static let baseSideRatio: CGFloat = 0.105
    /// 盤面の縦横比（幅:高さ = 3:5）。どの端末でも同じ比率にして有利不利をなくす
    static let boardAspectRatio: CGFloat = 3.0 / 5.0
    /// 調整の基準にした盤面の幅（iPhoneでの実寸）。これを1倍として各サイズを拡大縮小する
    private static let referenceBoardWidth: CGFloat = 311
    private static let referenceGravity: CGFloat = -7.7

    var onScore: ((Int) -> Void)?
    var onNextLevels: (([Int]) -> Void)?
    var onGameOver: (() -> Void)?
    var onMerge: (() -> Void)?

    private let textures: [SKTexture]
    // 当たり判定用の低解像度テクスチャ。輪郭の頂点数を減らし、アイテムが増えても衝突計算を軽くする
    private let physicsTextures: [SKTexture]
    private static let physicsTexturePixelSize: CGFloat = 64
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
    // テクスチャからの当たり判定生成は重いため、レベルごとに一度だけ作ってコピーして使う
    private var physicsBodyTemplates: [Int: (side: CGFloat, body: SKPhysicsBody)] = [:]

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
        physicsTextures = images.map { SKTexture(image: Self.downscaled($0, to: Self.physicsTexturePixelSize)) }
        super.init(size: CGSize(width: 390, height: 650))
        scaleMode = .resizeFill
        backgroundColor = KuttukeTheme.uiCream
        physicsWorld.gravity = CGVector(dx: 0, dy: Self.referenceGravity * boardScale)
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
        warmUpPhysicsBodies()
        warmUpScoreLabelFont()
        prepareNextRound()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // 盤面が大きいほど重力も強め、落下の見た目の速さを端末によらず揃える
        physicsWorld.gravity = CGVector(dx: 0, dy: Self.referenceGravity * boardScale)
        guard didBuildBoard else { return }
        rebuildBoardGeometry()
        if oldSize.width != size.width {
            warmUpPhysicsBodies()
        }
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
    private var dropHeight: CGFloat { size.height - 48 * boardScale }
    private var boardScale: CGFloat { max(size.width, 1) / Self.referenceBoardWidth }

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
        let maximumSpawnLevel = self.maximumSpawnLevel
        while upcomingLevels.count < count {
            upcomingLevels.append(Int.random(in: 0...maximumSpawnLevel))
        }
    }

    /// 盤面にある最大レベルの2つ下まで出現させる（最低でも下から3番目までは出る）
    private var maximumSpawnLevel: Int {
        let minimumSpawnLevel = 2
        var highestLevelOnBoard = 0
        enumerateChildNodes(withName: itemName) { [weak self] node, _ in
            guard let self else { return }
            highestLevelOnBoard = max(highestLevelOnBoard, self.level(of: node))
        }
        return min(max(minimumSpawnLevel, highestLevelOnBoard - 2), highestLevel)
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
        shadow.position = CGPoint(x: 0, y: -4 * boardScale)
        shadow.zPosition = -1
        node.addChild(shadow)

        if dynamic {
            attachPhysics(to: node)
        }
        return node
    }

    private func warmUpPhysicsBodies() {
        guard !textures.isEmpty else { return }
        for level in 0...highestLevel {
            _ = physicsBodyTemplate(for: level)
        }
    }

    private func physicsBodyTemplate(for level: Int) -> SKPhysicsBody {
        let side = itemSide(for: level)
        if let cached = physicsBodyTemplates[level], cached.side == side {
            return cached.body
        }
        let texture = physicsTextures[min(level, physicsTextures.count - 1)]
        let body = SKPhysicsBody(texture: texture, alphaThreshold: 0.5, size: CGSize(width: side, height: side))
        physicsBodyTemplates[level] = (side, body)
        return body
    }

    private static func downscaled(_ image: UIImage, to pixelSize: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: pixelSize, height: pixelSize)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func attachPhysics(to node: SKSpriteNode) {
        guard node.physicsBody == nil,
              let body = physicsBodyTemplate(for: level(of: node)).copy() as? SKPhysicsBody else { return }
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

    /// 最後の素材が進化の終点（これ同士は合体しない）
    private var highestLevel: Int {
        max(min(textures.count, Self.growth.count) - 1, 0)
    }

    private func itemSide(for level: Int) -> CGFloat {
        // 素材が11個未満のときは大きい方から割り当て、最後の素材が常に最大サイズになるようにする
        let offset = Self.growth.count - 1 - highestLevel
        let index = min(max(level, 0) + offset, Self.growth.count - 1)
        return size.width * Self.baseSideRatio * Self.growth[index]
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
        guard firstLevel == level(of: second), firstLevel < highestLevel else { return }
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

    /// SKLabelNodeはフォントを初めて描画するときに重い読み込みが走るため、最初の合体前に済ませておく
    private func warmUpScoreLabelFont() {
        let label = SKLabelNode(text: "+0123456789")
        label.fontName = "AvenirNext-Heavy"
        label.fontSize = 16
        label.alpha = 0.01
        label.position = CGPoint(x: -200, y: -200)
        addChild(label)
        label.run(.sequence([.wait(forDuration: 0.1), .removeFromParent()]))
    }

    private func showScoreBurst(_ points: Int, at position: CGPoint) {
        let label = SKLabelNode(text: "+\(points)")
        label.fontName = "AvenirNext-Heavy"
        label.fontSize = 16 * boardScale
        label.fontColor = KuttukeTheme.uiOrange
        label.position = CGPoint(x: position.x, y: position.y + 12 * boardScale)
        label.zPosition = 30
        addChild(label)
        label.run(.sequence([
            .group([.moveBy(x: 0, y: 34 * boardScale, duration: 0.55), .fadeOut(withDuration: 0.55)]),
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
