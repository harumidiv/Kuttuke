import CoreMotion
import SpriteKit
import SwiftUI

/// 素材にかけるレアカード風のキラ加工。端末の傾きに合わせて光が動く
enum RareEffect: String, CaseIterable, Identifiable {
    case holo
    case glitter
    case gold
    /// 縁に沿ってラメの帯をつける。中の絵はそのまま
    case lameOutline
    /// 縁がネオン管のように光る
    case neon
    /// 水入りシール。傾けると中の気泡が浮いて動く
    case water
    /// 中で雪が降り、振ると舞い上がる
    case snowGlobe
    /// 顔にぎょろ目がつき、傾けたり揺らしたりすると黒目が転がる
    case googlyEyes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .holo: String(localized: "ホロ")
        case .glitter: String(localized: "キラキラ")
        case .gold: String(localized: "ゴールド")
        case .lameOutline: String(localized: "ラメ縁取り")
        case .neon: String(localized: "ネオン")
        case .water: String(localized: "水入り")
        case .snowGlobe: String(localized: "スノードーム")
        case .googlyEyes: String(localized: "ぎょろ目")
        }
    }

    /// シェーダーに渡す種類の番号（RareEffect.metal の rare::shade / rare::edge の分岐と合わせる）
    var shaderKind: Float {
        switch self {
        case .holo: 1
        case .glitter: 2
        case .gold: 3
        case .water: 4
        case .neon: 5
        case .lameOutline: 6
        case .snowGlobe: 7
        case .googlyEyes: 8
        }
    }
}

/// 端末の傾き。今の持ち方をゆっくり基準に取り込み、どんな姿勢でも「傾けた分だけ」光が動くようにする
final class TiltMotion {
    static let shared = TiltMotion()

    private let manager = CMMotionManager()
    private var clientCount = 0
    private var baseline: CMAcceleration?
    private var currentTilt: SIMD2<Float> = .zero
    /// 画面上の重力の向き（端末の座標。xが右、yが上）。立てて持つと (0, -1)
    private var currentGravity = SIMD2<Float>(0, -1)
    /// 端末を振った加速度（重力を除く。端末の座標）
    private var currentShake = SIMD2<Float>.zero

    private init() {}

    func start() {
        clientCount += 1
        guard clientCount == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let gravity = motion.gravity
            let shake = motion.userAcceleration
            MainActor.assumeIsolated { self?.update(gravity, shake: shake) }
        }
    }

    func stop() {
        clientCount = max(0, clientCount - 1)
        guard clientCount == 0 else { return }
        manager.stopDeviceMotionUpdates()
        baseline = nil
        currentTilt = .zero
        currentGravity = SIMD2(0, -1)
        currentShake = .zero
    }

    /// 現在の傾き（おおむね -1...1）。ジャイロのない環境（シミュレータ）では、見た目を確認できるようゆっくり揺らす
    func tilt(at time: TimeInterval) -> SIMD2<Float> {
        guard manager.isDeviceMotionAvailable else {
            return SIMD2(Float(sin(time * 0.9) * 0.6), Float(cos(time * 0.7) * 0.4))
        }
        return currentTilt
    }

    /// 気泡が浮かぶ向き（uv、y下向き）。持ち方を打ち消さない実際の重力の反対向きで、端末を水平に寝かせると0に近づく
    func rise(at time: TimeInterval) -> SIMD2<Float> {
        guard manager.isDeviceMotionAvailable else {
            // シミュレータでは、気泡の動きを確認できるよう向きをゆっくり回す
            let angle = Float(time * 0.5)
            return SIMD2(sin(angle), -cos(angle)) * 0.8
        }
        return SIMD2(-currentGravity.x, currentGravity.y)
    }

    /// 端末を振った加速度（uv、y下向き。単位はG）。シミュレータでは0
    func shake(at time: TimeInterval) -> SIMD2<Float> {
        SIMD2(currentShake.x, -currentShake.y)
    }

    private func update(_ gravity: CMAcceleration, shake: CMAcceleration) {
        var base = baseline ?? gravity
        // 約3秒かけて今の持ち方に馴染ませる
        let follow = 0.006
        base.x += (gravity.x - base.x) * follow
        base.y += (gravity.y - base.y) * follow
        baseline = base

        let gain = 2.4
        let target = SIMD2(
            Float(min(max((gravity.x - base.x) * gain, -1), 1)),
            Float(min(max((gravity.y - base.y) * gain, -1), 1))
        )
        // センサーの細かい揺れで光がちらつかないよう、少しなめらかにする
        currentTilt += (target - currentTilt) * 0.3
        currentGravity += (SIMD2(Float(gravity.x), Float(gravity.y)) - currentGravity) * 0.3
        currentShake += (SIMD2(Float(shake.x), Float(shake.y)) - currentShake) * 0.5
    }
}

extension View {
    /// 素材画像にキラ加工をかける。透明な部分には何も描かないため、切り抜きの形に沿って光る。
    /// `.resizable().scaledToFit()` の直後に付け、ビューの大きさが画像と同じ縦横比になるようにする
    func rareEffect(_ effect: RareEffect?, image: UIImage) -> some View {
        modifier(RareEffectModifier(effect: effect, image: image))
    }
}

private struct RareEffectModifier: ViewModifier {
    let effect: RareEffect?
    let image: UIImage

    func body(content: Content) -> some View {
        switch effect {
        case .none:
            content
        case .water?:
            content.modifier(WaterEffectModifier(image: image))
        case .snowGlobe?:
            content.modifier(SnowEffectModifier())
        case .googlyEyes?:
            content.modifier(GooglyEffectModifier(image: image))
        case .neon?, .lameOutline?:
            content.modifier(EdgeEffectModifier(effect: effect!))
        case let effect?:
            content.modifier(ShineEffectModifier(effect: effect))
        }
    }
}

private struct ShineEffectModifier: ViewModifier {
    let effect: RareEffect

    func body(content: Content) -> some View {
        let kind = effect.shaderKind
            TimelineView(.animation) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let tilt = TiltMotion.shared.tilt(at: time)
                // Floatの精度で扱える範囲に時刻を収める
                let shaderTime = Float(time.truncatingRemainder(dividingBy: 600))
                content.visualEffect { content, proxy in
                    content.colorEffect(ShaderLibrary.rareEffect(
                        .float2(proxy.size),
                        .float2(tilt.x, tilt.y),
                        .float(shaderTime),
                        .float(kind)
                    ))
                }
            }
            .onAppear { TiltMotion.shared.start() }
            .onDisappear { TiltMotion.shared.stop() }
    }
}

private struct WaterEffectModifier: ViewModifier {
    let image: UIImage
    @State private var simulation: BubbleSimulation?

    func body(content: Content) -> some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let tilt = TiltMotion.shared.tilt(at: time)
            let shaderTime = Float(time.truncatingRemainder(dividingBy: 600))
            // 描画のたびに気泡を進める（TimelineViewが毎フレーム呼ぶ）
            let _ = simulation?.step(rise: TiltMotion.shared.rise(at: time), time: time)
            let bubbles = simulation?.packed ?? [0, 0, 0]
            content.visualEffect { content, proxy in
                content.layerEffect(
                    ShaderLibrary.waterEffect(
                        .float2(proxy.size),
                        .float2(tilt.x, tilt.y),
                        .float(shaderTime),
                        .floatArray(bubbles)
                    ),
                    // 気泡のレンズと水の揺らぎで、少し離れた位置の色を読む
                    maxSampleOffset: CGSize(width: 16, height: 16)
                )
            }
        }
        .onAppear {
            if simulation == nil {
                simulation = BubbleSimulation(mask: BubbleMask.cached(for: image))
            }
            TiltMotion.shared.start()
        }
        .onDisappear { TiltMotion.shared.stop() }
    }
}

private struct EdgeEffectModifier: ViewModifier {
    let effect: RareEffect

    func body(content: Content) -> some View {
        let kind = effect.shaderKind
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let tilt = TiltMotion.shared.tilt(at: time)
            let shaderTime = Float(time.truncatingRemainder(dividingBy: 600))
            content.visualEffect { content, proxy in
                content.layerEffect(
                    ShaderLibrary.edgeEffect(
                        .float2(proxy.size),
                        .float2(tilt.x, tilt.y),
                        .float(shaderTime),
                        .float(kind)
                    ),
                    // 縁を調べるため、短い辺の7%くらい離れた位置まで読む
                    maxSampleOffset: CGSize(
                        width: min(proxy.size.width, proxy.size.height) * 0.07,
                        height: min(proxy.size.width, proxy.size.height) * 0.07
                    )
                )
            }
        }
        .onAppear { TiltMotion.shared.start() }
        .onDisappear { TiltMotion.shared.stop() }
    }
}

private struct SnowEffectModifier: ViewModifier {
    @State private var snow = SnowDrift()

    func body(content: Content) -> some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let tilt = TiltMotion.shared.tilt(at: time)
            let shaderTime = Float(time.truncatingRemainder(dividingBy: 600))
            let _ = snow.step(fall: -TiltMotion.shared.rise(at: time), shake: TiltMotion.shared.shake(at: time), time: time)
            let drift = snow.drift
            let agitation = snow.agitation
            content.visualEffect { content, proxy in
                content.colorEffect(ShaderLibrary.snowEffect(
                    .float2(proxy.size),
                    .float2(tilt.x, tilt.y),
                    .float(shaderTime),
                    .float2(drift.x, drift.y),
                    .float(agitation)
                ))
            }
        }
        .onAppear { TiltMotion.shared.start() }
        .onDisappear { TiltMotion.shared.stop() }
    }
}

private struct GooglyEffectModifier: ViewModifier {
    let image: UIImage
    @State private var eyes = GooglyEyesSimulation()

    func body(content: Content) -> some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let _ = eyes.step(fall: -TiltMotion.shared.rise(at: time), jolt: TiltMotion.shared.shake(at: time), time: time)
            let centers = eyes.eyeCenters
            let radius = eyes.radius
            let pupils = eyes.pupilOffsets
            content.visualEffect { content, proxy in
                content.colorEffect(ShaderLibrary.googlyEffect(
                    .float2(proxy.size),
                    .float4(centers.x, centers.y, centers.z, centers.w),
                    .float(radius),
                    .float4(pupils.x, pupils.y, pupils.z, pupils.w)
                ))
            }
        }
        // 目の位置の検出（Vision）は少し時間がかかるため、終わるまでは目を出さない
        .task(id: ObjectIdentifier(image)) { eyes.layout = await GooglyEyeDetector.layout(for: image) }
        .onAppear { TiltMotion.shared.start() }
        .onDisappear { TiltMotion.shared.stop() }
    }
}

/// ゲーム盤面（SpriteKit）用のキラ加工。種類ごとに1つ作り、同じ種類の素材で使い回す
final class RareEffectSpriteShaders {
    private var shaders: [RareEffect: SKShader] = [:]
    private var tiltUniforms: [SKUniform] = []

    func shader(for effect: RareEffect) -> SKShader {
        if let shader = shaders[effect] { return shader }
        let tilt = SKUniform(name: "u_tilt", vectorFloat2: .zero)
        let kind = SKUniform(name: "u_kind", float: effect.shaderKind)
        let shader: SKShader
        switch effect {
        case .water:
            shader = SKShader(source: Self.waterSource, uniforms: [tilt])
            shader.attributes = Self.bubbleAttributeNames.map { SKAttribute(name: $0, type: .vectorFloat4) }
        case .snowGlobe:
            shader = SKShader(source: Self.helpers + Self.snowSource, uniforms: [tilt])
            shader.attributes = [SKAttribute(name: "a_snow", type: .vectorFloat4)]
        case .googlyEyes:
            shader = SKShader(source: Self.googlySource, uniforms: [tilt])
            shader.attributes = [
                SKAttribute(name: "a_eyes", type: .vectorFloat4),
                SKAttribute(name: "a_eyeRadius", type: .float),
                SKAttribute(name: "a_pupils", type: .vectorFloat4)
            ]
        case .neon, .lameOutline:
            shader = SKShader(source: Self.helpers + Self.edgeSource, uniforms: [tilt, kind])
        case .holo, .glitter, .gold:
            shader = SKShader(source: Self.helpers + Self.source, uniforms: [tilt, kind])
        }
        shaders[effect] = shader
        tiltUniforms.append(tilt)
        return shader
    }

    func updateTilt(_ tilt: SIMD2<Float>) {
        for uniform in tiltUniforms {
            uniform.vectorFloat2Value = tilt
        }
    }

    /// 水入りの気泡の位置をノードごとに渡す属性。1つに気泡2個分（x, y, x, y）を入れる
    private static let bubbleAttributeNames = ["a_bubbles0", "a_bubbles1"]

    static func applyBubbles(_ positions: [SIMD2<Float>], to node: SKSpriteNode) {
        for (index, name) in bubbleAttributeNames.enumerated() where index * 2 + 1 < positions.count {
            let first = positions[index * 2]
            let second = positions[index * 2 + 1]
            node.setValue(SKAttributeValue(vectorFloat4: SIMD4(first.x, first.y, second.x, second.y)), forAttribute: name)
        }
    }

    static func applySnow(_ snow: SnowDrift, to node: SKSpriteNode) {
        node.setValue(SKAttributeValue(vectorFloat4: SIMD4(snow.drift.x, snow.drift.y, snow.agitation, 0)), forAttribute: "a_snow")
    }

    static func applyEyes(_ eyes: GooglyEyesSimulation, to node: SKSpriteNode) {
        node.setValue(SKAttributeValue(vectorFloat4: eyes.eyeCenters), forAttribute: "a_eyes")
        node.setValue(SKAttributeValue(float: eyes.radius), forAttribute: "a_eyeRadius")
        node.setValue(SKAttributeValue(vectorFloat4: eyes.pupilOffsets), forAttribute: "a_pupils")
    }

    /// 複数のシェーダーで使う関数（RareEffect.metal の rare::hash / rainbow / star と同じ）
    private static let helpers = """
    float rareHash(vec2 p) {
        p = fract(p * vec2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    vec3 rareRainbow(float t) {
        return 0.5 + 0.5 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67)));
    }

    float rareStar(vec2 uv, float scale, float density, float seed, vec2 tilt, float time) {
        vec2 grid = uv * scale;
        vec2 cell = floor(grid);
        float h = rareHash(cell + seed);
        vec2 offset = vec2(rareHash(cell + seed + 7.1), rareHash(cell + seed + 3.7)) - 0.5;
        vec2 p = fract(grid) - 0.5 - offset * 0.5;
        float twinkle = pow(0.5 + 0.5 * sin(h * 50.0 + tilt.x * 9.0 + tilt.y * 7.0 + time * 2.0), 3.0);
        float core = smoothstep(0.18, 0.0, length(p));
        float rays = smoothstep(0.035, 0.0, abs(p.x)) * smoothstep(0.45, 0.0, abs(p.y))
            + smoothstep(0.035, 0.0, abs(p.y)) * smoothstep(0.45, 0.0, abs(p.x));
        return step(1.0 - density, h) * twinkle * (core + rays);
    }

    """

    // RareEffect.metal の rare::shade と同じ計算。見た目を変えるときは両方を直す
    private static let source = """
    void main() {
        // SpriteKitの変換でmain内の早期returnが使えないため、透明部分も計算して最後に元の色へ戻す
        vec4 color = SKDefaultShading();
        vec3 c = color.rgb / max(color.a, 0.004);
        // SwiftUI側と同じく左上を原点にする
        vec2 uv = vec2(v_tex_coord.x, 1.0 - v_tex_coord.y);
        vec2 tilt = u_tilt;
        float time = u_time;

        float lum = dot(c, vec3(0.299, 0.587, 0.114));
        float sweep = (uv.x + uv.y) * 0.5 - (0.5 + tilt.x * 0.7 + tilt.y * 0.5);
        float band = exp(-sweep * sweep * 60.0);
        vec3 rgb;
        if (u_kind < 1.5) {
            vec3 rb = rareRainbow((uv.x * 0.8 + uv.y * 1.2) * 1.6 + tilt.x * 1.2 - tilt.y * 0.8);
            rgb = mix(c, c * 0.7 + rb * 0.45, 0.35) + band * 0.5;
        } else if (u_kind < 2.5) {
            vec2 fine = uv * 70.0;
            vec2 fineCell = floor(fine);
            float hf = rareHash(fineCell);
            // 粒の位置と大きさをばらつかせ、網目模様に見えないようにする
            vec2 jitter = (vec2(rareHash(fineCell + 1.3), rareHash(fineCell + 5.9)) - 0.5) * 0.6;
            float dotSize = 0.32 + 0.25 * rareHash(fineCell + 9.2);
            float fineTwinkle = pow(0.5 + 0.5 * sin(hf * 80.0 + tilt.x * 14.0 + tilt.y * 11.0 + time * 2.5), 4.0);
            float fineDot = step(0.05, hf) * smoothstep(dotSize, 0.0, length(fract(fine) - 0.5 - jitter));
            vec3 fineSpark = vec3(1.0, 0.97, 0.88) * fineDot * fineTwinkle * 1.6;
            float stars = rareStar(uv, 12.0, 0.85, 0.0, tilt, time) * 2.2
                + rareStar(uv, 18.0, 0.75, 19.3, tilt, time) * 1.6;
            rgb = c * (1.0 + band * 0.4) + fineSpark + vec3(1.0, 0.98, 0.92) * stars + band * 0.3;
        } else {
            vec3 gold = mix(vec3(0.42, 0.26, 0.06), vec3(1.0, 0.88, 0.5), smoothstep(0.05, 0.95, lum));
            float sheen = 0.5 + 0.5 * sin((uv.x - uv.y) * 8.0 + tilt.x * 4.0 - tilt.y * 3.0);
            rgb = mix(c, gold * (0.8 + 0.4 * sheen), 0.75) + band * vec3(1.0, 0.95, 0.75) * 0.55;
        }
        vec4 shaded = vec4(clamp(rgb, 0.0, 1.0) * color.a, color.a);
        gl_FragColor = color.a < 0.004 ? color : shaded;
    }
    """
    // RareEffect.metal の rare::bubble / rare::water と同じ計算。気泡の数と半径は BubbleSimulation.radii と合わせる
    private static let waterSource = """
    vec4 rareBubble(vec2 uv, vec2 center, float r) {
        vec2 d = uv - center;
        float dist = length(d);
        float inside = 1.0 - smoothstep(r * 0.92, r, dist);
        float lens = max(1.0 - (dist * dist) / (r * r), 0.0);
        vec2 offset = -d * 0.45 * lens * inside;
        float rim = smoothstep(r * 0.7, r * 0.95, dist) * inside;
        float spot = (1.0 - smoothstep(0.0, r * 0.28, length(d + vec2(0.38, 0.38) * r))) * inside;
        float outline = smoothstep(r * 0.95, r * 1.02, dist) * (1.0 - smoothstep(r * 1.02, r * 1.12, dist));
        return vec4(offset, rim + spot * 1.2, outline);
    }

    void main() {
        // SpriteKitの変換でmain内の早期returnが使えないため、透明部分も計算して最後に元の色へ戻す
        vec4 base = SKDefaultShading();
        vec2 uv = vec2(v_tex_coord.x, 1.0 - v_tex_coord.y);
        vec2 tilt = u_tilt;
        float time = u_time;

        vec4 bubbles = rareBubble(uv, a_bubbles0.xy, 0.085)
            + rareBubble(uv, a_bubbles0.zw, 0.066)
            + rareBubble(uv, a_bubbles1.xy, 0.052)
            + rareBubble(uv, a_bubbles1.zw, 0.042);
        vec2 wave = vec2(sin(uv.y * 18.0 + time * 1.6 + tilt.x * 3.0), cos(uv.x * 16.0 + time * 1.3 + tilt.y * 3.0)) * 0.004;
        vec2 sampleUV = uv + wave + bubbles.xy;
        vec4 original = texture2D(u_texture, v_tex_coord);
        vec4 moved = texture2D(u_texture, vec2(sampleUV.x, 1.0 - sampleUV.y));
        // 縁の外の透明な色を拾ったときは元の色を使う
        vec4 source = moved.a > original.a * 0.5 ? moved : original;
        vec3 c = source.rgb / max(source.a, 0.004);

        c = mix(c, c * vec3(0.92, 0.98, 1.06) + 0.04, 0.6);
        float sweep = (uv.x + uv.y) * 0.5 - (0.5 + tilt.x * 0.7 + tilt.y * 0.5);
        float gloss = exp(-sweep * sweep * 30.0) * 0.22;
        c = c * (1.0 - bubbles.w * 0.35) + bubbles.z * 0.65 + gloss;

        vec4 shaded = vec4(clamp(c, 0.0, 1.0) * base.a, base.a);
        gl_FragColor = base.a < 0.004 ? base : shaded;
    }
    """

    /// 周囲8方向・半径rの不透明度の最大と最小（RareEffect.metal の rare::ring と同じ）。
    /// SpriteKitの変換では main 以外の関数から u_texture を読めないため、main の中にそのまま展開する
    private static func ringCode(_ name: String, radius: Double) -> String {
        let d = radius * 0.7071
        let offsets = [(radius, 0.0), (-radius, 0.0), (0.0, radius), (0.0, -radius), (d, d), (-d, -d), (d, -d), (-d, d)]
        let samples = offsets.enumerated().map { index, offset in
            "float \(name)_\(index) = texture2D(u_texture, v_tex_coord + vec2(\(offset.0), \(offset.1))).a;"
        }
        let values = (0..<8).map { "\(name)_\($0)" }
        func fold(_ function: String) -> String {
            values.dropFirst().reduce(values[0]) { "\(function)(\($0), \($1))" }
        }
        return (samples + ["vec2 \(name) = vec2(\(fold("max")), \(fold("min")));"]).joined(separator: "\n        ")
    }

    // RareEffect.metal の rare::ring / rare::edge と同じ計算。見た目を変えるときは両方を直す
    private static let edgeSource = """
    void main() {
        vec4 base = SKDefaultShading();
        vec4 original = texture2D(u_texture, v_tex_coord);
        // アイテムのフェードインなどで薄くなっている分
        float nodeAlpha = base.a / max(original.a, 0.004);
        nodeAlpha = original.a < 0.004 ? 1.0 : min(nodeAlpha, 1.0);
        float a0 = original.a;
        vec2 uv = vec2(v_tex_coord.x, 1.0 - v_tex_coord.y);
        vec2 tilt = u_tilt;
        float time = u_time;
    \(ringCode("n1", radius: 0.010))
    \(ringCode("n2", radius: 0.018))
    \(ringCode("n3", radius: 0.040))
    \(ringCode("n4", radius: 0.065))
        vec3 c = original.rgb / max(a0, 0.004);

        float maxNear = max(a0, max(n1.x, n2.x));
        float minNear = min(a0, min(n1.y, n2.y));
        float band = clamp(maxNear * (1.0 - minNear), 0.0, 1.0);
        vec4 result;
        if (u_kind < 5.5) {
            float core = clamp(max(a0, n1.x) * (1.0 - min(a0, n1.y)), 0.0, 1.0);
            float tube = clamp(core * 0.6 + band * 0.5, 0.0, 1.0);
            float glow = (n3.x * 0.55 + n4.x * 0.35) * (1.0 - a0);
            float hue = 0.5 + 0.5 * sin(time * 0.7 + tilt.x * 2.0);
            vec3 neon = mix(vec3(1.0, 0.25, 0.75), vec3(0.25, 0.85, 1.0), hue);
            float flicker = 1.0 - 0.55 * step(0.93, rareHash(vec2(floor(time * 9.0), 3.1)));
            float emissionAlpha = clamp(max(tube, glow * 0.9) * flicker, 0.0, 1.0);
            vec3 emission = (neon * (tube * 1.3 + glow) + vec3(1.0) * core * 0.55) * flicker;
            float alpha = a0 + emissionAlpha * (1.0 - a0);
            vec3 rgb = c * 0.72 * a0 * (1.0 - emissionAlpha) + emission;
            result = vec4(clamp(rgb, 0.0, alpha), alpha);
        } else {
            float bandAlpha = smoothstep(0.15, 0.6, band);
            vec3 lameBase = mix(vec3(0.78, 0.66, 0.38), vec3(0.96, 0.94, 0.9),
                                0.5 + 0.5 * sin((uv.x - uv.y) * 12.0 + tilt.x * 4.0 - tilt.y * 3.0));
            vec2 fine = uv * 90.0;
            vec2 cell = floor(fine);
            float h = rareHash(cell);
            vec2 jitter = vec2(rareHash(cell + 1.3), rareHash(cell + 5.9)) - 0.5;
            float dotMask = step(0.2, h) * smoothstep(0.45, 0.0, length(fract(fine) - 0.5 - jitter * 0.5));
            float twinkle = pow(0.5 + 0.5 * sin(h * 70.0 + tilt.x * 12.0 + tilt.y * 9.0 + time * 2.2), 4.0);
            vec3 lame = lameBase * 0.85 + vec3(1.0) * dotMask * twinkle * 1.2
                + vec3(1.0, 0.98, 0.92) * rareStar(uv, 24.0, 0.6, 5.0, tilt, time) * 1.6;
            float alpha = a0 + bandAlpha * (1.0 - a0);
            vec3 rgb = c * a0 * (1.0 - bandAlpha) + clamp(lame, 0.0, 1.0) * bandAlpha;
            result = vec4(clamp(rgb, 0.0, alpha), alpha);
        }
        gl_FragColor = result * nodeAlpha;
    }
    """

    // RareEffect.metal の rare::flakes / rare::snow と同じ計算。見た目を変えるときは両方を直す
    private static let snowSource = """
    float rareFlakes(vec2 uv, vec2 drift, float scale, float speed, float size, float seed, float time, float agitation) {
        vec2 g = (uv - drift * speed) * scale;
        vec2 cell = floor(g);
        float h = rareHash(cell + seed);
        vec2 jitter = vec2(rareHash(cell + seed + 4.3), rareHash(cell + seed + 8.1)) - 0.5;
        vec2 p = fract(g) - 0.5 - jitter * 0.3;
        float wobble = 0.06 + agitation * 0.08;
        p += vec2(sin(time * 1.7 + h * 20.0), cos(time * 1.3 + h * 15.0)) * wobble;
        return step(0.4, h) * (1.0 - smoothstep(size * 0.35, size, length(p)));
    }

    void main() {
        vec4 color = SKDefaultShading();
        vec3 c = color.rgb / max(color.a, 0.004);
        vec2 uv = vec2(v_tex_coord.x, 1.0 - v_tex_coord.y);
        vec2 tilt = u_tilt;
        float time = u_time;
        vec2 drift = a_snow.xy;
        float agitation = a_snow.z;

        float f = rareFlakes(uv, drift, 6.0, 1.0, 0.2, 0.0, time, agitation)
            + rareFlakes(uv, drift, 11.0, 0.7, 0.17, 13.7, time, agitation) * 0.8
            + rareFlakes(uv, drift, 19.0, 0.45, 0.15, 27.1, time, agitation) * 0.6;
        c = mix(c, c * vec3(0.95, 0.98, 1.05) + 0.03, 0.5);
        float sweep = (uv.x + uv.y) * 0.5 - (0.5 + tilt.x * 0.7 + tilt.y * 0.5);
        float gloss = exp(-sweep * sweep * 30.0) * 0.2;
        vec3 rgb = clamp(mix(c, vec3(1.0), min(f, 1.0) * 0.92) + gloss, 0.0, 1.0);

        vec4 shaded = vec4(rgb * color.a, color.a);
        gl_FragColor = color.a < 0.004 ? color : shaded;
    }
    """

    // RareEffect.metal の rare::eye と同じ計算。見た目を変えるときは両方を直す
    private static let googlySource = """
    vec4 rareEye(vec2 d, float r, vec2 pupil) {
        float radius = max(r, 0.0001);
        float dist = length(d);
        float cover = (1.0 - smoothstep(radius * 0.96, radius, dist)) * step(0.001, r);
        vec3 col = vec3(1.0 - 0.18 * smoothstep(radius * 0.3, radius, dist));
        float rim = smoothstep(radius * 0.86, radius * 0.93, dist);
        col = mix(col, vec3(0.08), rim);
        float pupilRadius = radius * 0.5;
        float pupilMask = 1.0 - smoothstep(pupilRadius * 0.92, pupilRadius, length(d - pupil));
        col = mix(col, vec3(0.05), pupilMask * (1.0 - rim));
        float gloss = 1.0 - smoothstep(0.0, radius * 0.22, length(d + vec2(0.35, 0.35) * radius));
        col += gloss * 0.8;
        return vec4(clamp(col, 0.0, 1.0), cover);
    }

    void main() {
        vec4 result = SKDefaultShading();
        vec2 uv = vec2(v_tex_coord.x, 1.0 - v_tex_coord.y);
        vec4 e1 = rareEye(uv - a_eyes.xy, a_eyeRadius, a_pupils.xy);
        vec4 e2 = rareEye(uv - a_eyes.zw, a_eyeRadius, a_pupils.zw);
        result = vec4(result.rgb * (1.0 - e1.w) + e1.rgb * e1.w, result.a + e1.w * (1.0 - result.a));
        result = vec4(result.rgb * (1.0 - e2.w) + e2.rgb * e2.w, result.a + e2.w * (1.0 - result.a));
        gl_FragColor = result;
    }
    """
}
