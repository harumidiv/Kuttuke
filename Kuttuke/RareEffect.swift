import CoreMotion
import SpriteKit
import SwiftUI

/// 素材にかけるレアカード風の加工。端末の傾きに合わせて光や模様が動く
enum RareEffect: String, CaseIterable, Identifiable {
    /// 水たまりに浮いた油膜のような、うねる虹色
    case oilSlick
    /// ボロノイで区切ったステンドグラス。傾けると光の差しこむ位置が変わる
    case stainedGlass
    /// 中身が宇宙になる。星は奥と手前の2層で、傾けると奥行きが出る
    case galaxy
    /// ヘアライン加工の銀箔。傾けると光沢の縞が走る
    case silver
    /// 色数を減らしたドット絵。ドット1つぶんの黒い縁がつく
    case pixel
    /// まん中がふくらむ魚眼レンズ。傾けるとふくらむ場所が動く
    case fisheye
    /// 筆でなでたように色が流れる油絵
    case oilPaint
    /// 布に×の字で糸を刺したクロスステッチ
    case crossStitch
    /// 赤外線カメラで撮ったような色。真ん中ほど熱く、熱がゆらゆら動く
    case thermal
    /// 顔にぎょろ目がつき、傾けたり揺らしたりすると黒目が転がる
    case googlyEyes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oilSlick: String(localized: "オイルスリック")
        case .stainedGlass: String(localized: "ステンドグラス")
        case .galaxy: String(localized: "ギャラクシー")
        case .silver: String(localized: "シルバー")
        case .pixel: String(localized: "ドット絵")
        case .fisheye: String(localized: "魚眼")
        case .oilPaint: String(localized: "油絵")
        case .crossStitch: String(localized: "クロスステッチ")
        case .thermal: String(localized: "サーモグラフィ")
        case .googlyEyes: String(localized: "ぎょろ目")
        }
    }

    /// シェーダーに渡す種類の番号（RareEffect.metal の rare::shade / sampleEffect の分岐と合わせる）
    var shaderKind: Float {
        switch self {
        case .silver: 1
        case .oilSlick: 2
        case .galaxy: 3
        case .stainedGlass: 4
        case .pixel: 5
        case .fisheye: 6
        case .oilPaint: 7
        case .crossStitch: 8
        case .thermal: 9
        case .googlyEyes: 10
        }
    }

    /// 周りの色を読む加工か。SwiftUIでは layerEffect が要り、SpriteKitでは種類ごとにシェーダーを分ける
    var readsNearbyPixels: Bool {
        switch self {
        case .stainedGlass, .pixel, .fisheye, .oilPaint, .crossStitch, .thermal: true
        case .silver, .oilSlick, .galaxy, .googlyEyes: false
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
        case .googlyEyes?:
            content.modifier(GooglyEffectModifier(image: image))
        case let effect? where effect.readsNearbyPixels:
            content.modifier(SampleEffectModifier(effect: effect))
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

private struct SampleEffectModifier: ViewModifier {
    let effect: RareEffect

    func body(content: Content) -> some View {
        let kind = effect.shaderKind
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let tilt = TiltMotion.shared.tilt(at: time)
            let shaderTime = Float(time.truncatingRemainder(dividingBy: 600))
            content.visualEffect { content, proxy in
                content.layerEffect(
                    ShaderLibrary.sampleEffect(
                        .float2(proxy.size),
                        .float2(tilt.x, tilt.y),
                        .float(shaderTime),
                        .float(kind)
                    ),
                    // 魚眼のレンズやステンドグラスのセルの中心など、短い辺の15%くらい離れた位置まで読む
                    maxSampleOffset: CGSize(
                        width: min(proxy.size.width, proxy.size.height) * 0.15,
                        height: min(proxy.size.width, proxy.size.height) * 0.15
                    )
                )
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
        let shader: SKShader
        switch effect {
        case .googlyEyes:
            shader = SKShader(source: Self.googlySource, uniforms: [tilt])
            shader.attributes = [
                SKAttribute(name: "a_eyes", type: .vectorFloat4),
                SKAttribute(name: "a_eyeRadius", type: .float),
                SKAttribute(name: "a_pupils", type: .vectorFloat4)
            ]
        case .silver, .oilSlick, .galaxy:
            let kind = SKUniform(name: "u_kind", float: effect.shaderKind)
            shader = SKShader(source: Self.helpers + Self.source, uniforms: [tilt, kind])
        case .stainedGlass, .pixel, .fisheye, .oilPaint, .crossStitch, .thermal:
            shader = SKShader(source: Self.helpers + Self.sampleSource(for: effect), uniforms: [tilt])
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

    static func applyEyes(_ eyes: GooglyEyesSimulation, to node: SKSpriteNode) {
        node.setValue(SKAttributeValue(vectorFloat4: eyes.eyeCenters), forAttribute: "a_eyes")
        node.setValue(SKAttributeValue(float: eyes.radius), forAttribute: "a_eyeRadius")
        node.setValue(SKAttributeValue(vectorFloat4: eyes.pupilOffsets), forAttribute: "a_pupils")
    }

    /// 複数のシェーダーで使う関数（RareEffect.metal の rare::hash / noise / fbm / star / voronoi などと同じ）
    private static let helpers = """
    float rareHash(vec2 p) {
        p = fract(p * vec2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    float rareNoise(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        vec2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(rareHash(i), rareHash(i + vec2(1.0, 0.0)), u.x),
                   mix(rareHash(i + vec2(0.0, 1.0)), rareHash(i + vec2(1.0, 1.0)), u.x), u.y);
    }

    float rareFbm(vec2 p) {
        float v = 0.0;
        float a = 0.5;
        for (int i = 0; i < 5; i++) {
            v += a * rareNoise(p);
            p = p * 2.03 + vec2(17.1, 9.2);
            a *= 0.5;
        }
        return v;
    }

    float rareLuma(vec3 c) {
        return dot(c, vec3(0.299, 0.587, 0.114));
    }

    vec3 rareSaturate(vec3 c, float s) {
        return mix(vec3(rareLuma(c)), c, s);
    }

    float rareSweep(vec2 uv, vec2 tilt, float sharpness) {
        float s = (uv.x + uv.y) * 0.5 - (0.5 + tilt.x * 0.7 + tilt.y * 0.5);
        return exp(-s * s * sharpness);
    }

    float rareStar(vec2 uv, float scale, float density, float seed, vec2 tilt, float time) {
        vec2 grid = uv * scale;
        vec2 cell = floor(grid);
        float h = rareHash(cell + seed);
        vec2 offset = vec2(rareHash(cell + seed + 7.1), rareHash(cell + seed + 3.7)) - 0.5;
        vec2 p = fract(grid) - 0.5 - offset * 0.5;
        float twinkle = pow(0.5 + 0.5 * sin(h * 50.0 + tilt.x * 9.0 + tilt.y * 7.0 + time * 2.0), 3.0);
        float core = 1.0 - smoothstep(0.0, 0.18, length(p));
        float rays = (1.0 - smoothstep(0.0, 0.035, abs(p.x))) * (1.0 - smoothstep(0.0, 0.45, abs(p.y)))
            + (1.0 - smoothstep(0.0, 0.035, abs(p.y))) * (1.0 - smoothstep(0.0, 0.45, abs(p.x)));
        return step(1.0 - density, h) * twinkle * (core + rays);
    }

    vec4 rareVoronoi(vec2 p) {
        vec2 n = floor(p);
        vec2 f = fract(p);
        float d1 = 8.0;
        float d2 = 8.0;
        vec2 center = vec2(0.0);
        for (int j = -1; j <= 1; j++) {
            for (int i = -1; i <= 1; i++) {
                vec2 g = vec2(float(i), float(j));
                vec2 o = vec2(rareHash(n + g), rareHash(n + g + 19.7));
                vec2 r = g + o - f;
                float d = dot(r, r);
                if (d < d1) {
                    d2 = d1;
                    d1 = d;
                    center = n + g + o;
                } else if (d < d2) {
                    d2 = d;
                }
            }
        }
        return vec4(sqrt(d1), sqrt(d2), center);
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

        float lum = rareLuma(c);
        vec3 rgb;
        if (u_kind < 1.5) {
            float brush = rareNoise(vec2(uv.x * 6.0, uv.y * 420.0)) * 0.6 + rareNoise(vec2(uv.x * 40.0, uv.y * 900.0)) * 0.4;
            float sheen = 0.5 + 0.5 * sin((uv.y * 1.4 - uv.x * 0.5) * 7.0 + tilt.y * 6.0 + tilt.x * 3.0);
            vec3 silver = vec3(0.52, 0.55, 0.6) + (lum - 0.5) * 0.9 + (brush - 0.5) * 0.18 + pow(sheen, 4.0) * 0.55;
            silver += vec3(0.6, 0.75, 1.0) * 0.12 * sheen;
            rgb = mix(c, silver, 0.72) + rareSweep(uv, tilt, 50.0) * 0.45;
        } else if (u_kind < 2.5) {
            vec2 p = uv * 2.5;
            vec2 w = vec2(rareFbm(p + time * 0.05), rareFbm(p + 5.2 - time * 0.04));
            float thickness = rareFbm(p + w * 2.0) * 2.0 + dot(uv - 0.5, tilt) * 2.0 + lum * 0.6;
            vec3 film = 0.5 + 0.5 * cos(6.28318 * (thickness * 1.6 + vec3(0.0, 0.33, 0.67)));
            rgb = mix(c, c * 0.35 + film * 0.8, 0.56) + rareSweep(uv, tilt, 40.0) * 0.25;
        } else {
            vec2 p = uv - tilt * 0.06;
            float nebula = rareFbm(p * 3.0 + vec2(time * 0.02, 0.0));
            float nebula2 = rareFbm(p * 5.0 - vec2(0.0, time * 0.03) + 3.1);
            vec3 sky = vec3(0.03, 0.02, 0.10)
                + vec3(0.45, 0.10, 0.55) * smoothstep(0.35, 0.8, nebula)
                + vec3(0.10, 0.35, 0.75) * pow(smoothstep(0.4, 0.9, nebula2), 1.5);
            float stars = rareStar(uv - tilt * 0.12, 26.0, 0.35, 3.0, tilt, time) * 1.4
                + rareStar(uv - tilt * 0.04, 48.0, 0.25, 9.0, tilt, time);
            sky += vec3(1.0, 0.95, 0.9) * stars;
            sky *= 0.55 + 0.9 * lum;
            rgb = mix(c, sky, 0.81);
        }
        vec4 shaded = vec4(clamp(rgb, 0.0, 1.0) * color.a, color.a);
        gl_FragColor = color.a < 0.004 ? color : shaded;
    }
    """

    /// uv（左上原点）の位置の色を読む式。SpriteKitのテクスチャ座標は左下原点なので上下を反転する
    private static func sample(_ uv: String) -> String {
        "texture2D(u_texture, vec2((\(uv)).x, 1.0 - (\(uv)).y))"
    }

    /// 周囲8方向・半径r（uv）の不透明度の最大と最小（RareEffect.metal の rare::ring と同じ）。
    /// SpriteKitの変換では main 以外の関数から u_texture を読めないため、main の中にそのまま展開する
    private static func ringCode(_ name: String, center: String, radius: Double) -> String {
        let d = radius * 0.7071
        let offsets = [(radius, 0.0), (-radius, 0.0), (0.0, radius), (0.0, -radius), (d, d), (-d, -d), (d, -d), (-d, d)]
        let samples = offsets.enumerated().map { index, offset in
            "float \(name)_\(index) = \(sample("\(center) + vec2(\(offset.0), \(offset.1))")).a;"
        }
        let values = (0..<8).map { "\(name)_\($0)" }
        func fold(_ function: String) -> String {
            values.dropFirst().reduce(values[0]) { "\(function)(\($0), \($1))" }
        }
        return (samples + ["vec2 \(name) = vec2(\(fold("max")), \(fold("min")));"]).joined(separator: "\n        ")
    }

    /// 周りの色を読む加工の共通の前置き。ドット絵の縁のように元の絵の外側にも描くため、ノードの透明度は別に掛ける
    private static let samplePrologue = """
        vec4 base = SKDefaultShading();
        vec4 original = texture2D(u_texture, v_tex_coord);
        // アイテムのフェードインなどで薄くなっている分
        float nodeAlpha = original.a < 0.004 ? 1.0 : min(base.a / max(original.a, 0.004), 1.0);
        vec2 uv = vec2(v_tex_coord.x, 1.0 - v_tex_coord.y);
        vec2 tilt = u_tilt;
    """

    // RareEffect.metal の rare::stainedGlass / pixel / fisheye / oilPaint / crossStitch / thermal と同じ計算。
    // 見た目を変えるときは両方を直す
    private static func sampleSource(for effect: RareEffect) -> String {
        let body: String
        switch effect {
        case .stainedGlass:
            body = """
                float scale = 13.4;
                vec4 v = rareVoronoi(uv * scale);
                vec2 cellUV = v.zw / scale;
                vec4 cell = \(sample("cellUV"));
                vec3 glass = cell.a > 0.1 ? cell.rgb / cell.a : original.rgb / max(original.a, 0.004);
                glass = rareSaturate(glass, 1.5) * 1.1;
                glass *= 0.75 + 0.5 * rareNoise(uv * 6.0 + tilt * 3.0) + rareSweep(uv, tilt, 25.0) * 0.5;
                float lead = 1.0 - smoothstep(0.03, 0.07, v.y - v.x);
                \(ringCode("n1", center: "uv", radius: 0.01))
                lead = max(lead, 1.0 - smoothstep(0.3, 0.9, n1.y));
                vec3 rgb = clamp(mix(glass, vec3(0.12, 0.11, 0.1), lead), 0.0, 1.0);
                vec4 result = original.a < 0.004 ? vec4(0.0) : vec4(rgb * original.a, original.a);
            """
        case .pixel:
            body = """
                float n = 50.0;
                float px = 1.0 / n;
                vec2 cell = (floor(uv * n) + 0.5) * px;
                vec4 s = \(sample("cell"));
                float on = step(0.5, s.a);
                float neighbor = max(max(\(sample("cell + vec2(px, 0.0)")).a, \(sample("cell - vec2(px, 0.0)")).a),
                                     max(\(sample("cell + vec2(0.0, px)")).a, \(sample("cell - vec2(0.0, px)")).a));
                float outline = (1.0 - on) * step(0.5, neighbor);
                vec3 c = floor(rareSaturate(s.rgb / max(s.a, 0.004), 1.2) * 5.0 + 0.5) / 5.0;
                vec2 f = fract(uv * n);
                c *= (f.x < 0.12 || f.y < 0.12) ? 1.08 : ((f.x > 0.88 || f.y > 0.88) ? 0.88 : 1.0);
                vec3 rgb = clamp(mix(c, vec3(0.1, 0.1, 0.12), outline), 0.0, 1.0);
                float alpha = max(on, outline);
                vec4 result = vec4(rgb * alpha, alpha);
            """
        case .fisheye:
            body = """
                vec2 center = vec2(0.5) + tilt * 0.25;
                vec2 p = uv - center;
                float r = length(p);
                float radius = 0.45;
                float t = clamp(r / radius, 0.0001, 1.0);
                vec2 q = r < radius ? center + p * pow(t, 0.72) : uv;
                vec4 s = \(sample("q"));
                vec3 c = s.rgb / max(s.a, 0.004);
                c += (1.0 - smoothstep(0.0, 0.08, length(uv - center + vec2(0.12, 0.12)))) * 0.21;
                vec4 result = vec4(clamp(c, 0.0, 1.0) * s.a, s.a);
            """
        case .oilPaint:
            body = """
                float angle = rareFbm(uv * 4.0) * 6.28;
                vec2 dir = vec2(cos(angle), sin(angle));
                vec2 stepUV = dir * 0.0075;
                vec4 sum = \(sample("uv - stepUV * 3.0")) + \(sample("uv - stepUV * 2.0")) + \(sample("uv - stepUV"))
                    + original + \(sample("uv + stepUV")) + \(sample("uv + stepUV * 2.0")) + \(sample("uv + stepUV * 3.0"));
                vec3 c = sum.rgb / max(sum.a, 0.004);
                c = mix(c, floor(rareSaturate(c, 1.3) * 8.0 + 0.5) / 8.0, 0.5);
                float stroke = rareNoise(vec2(dot(uv, dir) * 30.0, dot(uv, vec2(-dir.y, dir.x)) * 300.0));
                c *= 0.85 + 0.3 * stroke;
                c += rareSweep(uv, tilt, 30.0) * 0.15 * stroke;
                vec4 result = original.a < 0.004 ? vec4(0.0) : vec4(clamp(c, 0.0, 1.0) * original.a, original.a);
            """
        case .crossStitch:
            body = """
                float n = 53.0;
                vec2 cell = (floor(uv * n) + 0.5) / n;
                vec4 s = \(sample("cell"));
                float alpha = step(0.5, s.a);
                vec2 f = fract(uv * n) - 0.5;
                vec2 holes = fract(uv * n * 4.0);
                vec3 cloth = vec3(0.95, 0.93, 0.86) * (0.9 + 0.1 * step(0.5, holes.x) * step(0.5, holes.y));
                float t1 = 1.0 - smoothstep(0.2, 0.3, abs(f.x - f.y));
                float t2 = 1.0 - smoothstep(0.2, 0.3, abs(f.x + f.y));
                float inside = step(max(abs(f.x), abs(f.y)), 0.47);
                float stitch = max(t1, t2) * inside;
                vec3 yarn = floor(s.rgb / max(s.a, 0.004) * 4.0 + 0.5) / 4.0;
                yarn *= (t2 > t1 ? 1.0 : 0.82) * (0.85 + 0.15 * sin((t2 > t1 ? f.x - f.y : f.x + f.y) * 60.0));
                vec3 rgb = clamp(mix(cloth, yarn, stitch), 0.0, 1.0);
                vec4 result = vec4(rgb * alpha, alpha);
            """
        default:
            body = """
                vec4 s = original;
                \(ringCode("n1", center: "uv", radius: 0.04))
                \(ringCode("n2", center: "uv", radius: 0.08))
                \(ringCode("n3", center: "uv", radius: 0.12))
                float depth = (n1.y + n2.y + n3.y) / 3.0;
                float heat = rareLuma(s.rgb / max(s.a, 0.004)) * 0.55 + depth * 0.5;
                heat = clamp(heat + (rareFbm(uv * 5.0 + u_time * 0.2) - 0.5) * 0.25, 0.0, 1.0);
                vec3 cold = vec3(0.05, 0.0, 0.2);
                vec3 violet = vec3(0.45, 0.0, 0.6);
                vec3 red = vec3(0.95, 0.1, 0.2);
                vec3 orange = vec3(1.0, 0.65, 0.0);
                vec3 white = vec3(1.0, 1.0, 0.8);
                vec3 c = heat < 0.25 ? mix(cold, violet, heat / 0.25)
                    : heat < 0.5 ? mix(violet, red, (heat - 0.25) / 0.25)
                    : heat < 0.75 ? mix(red, orange, (heat - 0.5) / 0.25)
                    : mix(orange, white, (heat - 0.75) / 0.25);
                c *= 0.94 + 0.06 * sin(uv.y * 600.0);
                vec4 result = s.a < 0.004 ? vec4(0.0) : vec4(clamp(c, 0.0, 1.0) * s.a, s.a);
            """
        }
        return "void main() {\n" + samplePrologue + "\n" + body + "\n    gl_FragColor = result * nodeAlpha;\n}\n"
    }

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
