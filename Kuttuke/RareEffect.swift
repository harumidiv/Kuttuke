import CoreMotion
import SpriteKit
import SwiftUI

/// 素材にかけるレアカード風のキラ加工。端末の傾きに合わせて光が動く
enum RareEffect: String, CaseIterable, Identifiable {
    case holo
    case glitter
    case gold

    var id: String { rawValue }

    var title: String {
        switch self {
        case .holo: String(localized: "ホロ")
        case .glitter: String(localized: "キラキラ")
        case .gold: String(localized: "ゴールド")
        }
    }

    /// シェーダーに渡す種類の番号（RareEffect.metal と `spriteKitShaderSource` の分岐と合わせる）
    var shaderKind: Float {
        switch self {
        case .holo: 1
        case .glitter: 2
        case .gold: 3
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

    private init() {}

    func start() {
        clientCount += 1
        guard clientCount == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let gravity = motion?.gravity else { return }
            MainActor.assumeIsolated { self?.update(gravity) }
        }
    }

    func stop() {
        clientCount = max(0, clientCount - 1)
        guard clientCount == 0 else { return }
        manager.stopDeviceMotionUpdates()
        baseline = nil
        currentTilt = .zero
    }

    /// 現在の傾き（おおむね -1...1）。ジャイロのない環境（シミュレータ）では、見た目を確認できるようゆっくり揺らす
    func tilt(at time: TimeInterval) -> SIMD2<Float> {
        guard manager.isDeviceMotionAvailable else {
            return SIMD2(Float(sin(time * 0.9) * 0.6), Float(cos(time * 0.7) * 0.4))
        }
        return currentTilt
    }

    private func update(_ gravity: CMAcceleration) {
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
    }
}

extension View {
    /// 素材画像にキラ加工をかける。透明な部分には何も描かないため、切り抜きの形に沿って光る
    func rareEffect(_ effect: RareEffect?) -> some View {
        modifier(RareEffectModifier(effect: effect))
    }
}

private struct RareEffectModifier: ViewModifier {
    let effect: RareEffect?

    func body(content: Content) -> some View {
        if let effect {
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
        } else {
            content
        }
    }
}

/// ゲーム盤面（SpriteKit）用のキラ加工。種類ごとに1つ作り、同じ種類の素材で使い回す
final class RareEffectSpriteShaders {
    private var shaders: [RareEffect: SKShader] = [:]
    private var tiltUniforms: [SKUniform] = []

    func shader(for effect: RareEffect) -> SKShader {
        if let shader = shaders[effect] { return shader }
        let tilt = SKUniform(name: "u_tilt", vectorFloat2: .zero)
        let shader = SKShader(source: Self.source, uniforms: [
            tilt,
            SKUniform(name: "u_kind", float: effect.shaderKind)
        ])
        shaders[effect] = shader
        tiltUniforms.append(tilt)
        return shader
    }

    func updateTilt(_ tilt: SIMD2<Float>) {
        for uniform in tiltUniforms {
            uniform.vectorFloat2Value = tilt
        }
    }

    // RareEffect.metal の rare::shade と同じ計算。見た目を変えるときは両方を直す
    private static let source = """
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
}
