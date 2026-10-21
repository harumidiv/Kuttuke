#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// RareEffect.swift の SpriteKit用シェーダー（GLSL）と同じ計算。見た目を変えるときは両方を直す
namespace rare {
    float hash(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    float3 rainbow(float t) {
        return 0.5 + 0.5 * cos(6.28318 * (t + float3(0.0, 0.33, 0.67)));
    }

    /// 十字の光芒つきの星。scaleが大きいほど細かく、densityが大きいほど星の出るマスが増える
    float star(float2 uv, float scale, float density, float seed, float2 tilt, float time) {
        float2 grid = uv * scale;
        float2 cell = floor(grid);
        float h = hash(cell + seed);
        // マスごとに位置をずらし、格子状に並んで見えないようにする
        float2 offset = float2(hash(cell + seed + 7.1), hash(cell + seed + 3.7)) - 0.5;
        float2 p = fract(grid) - 0.5 - offset * 0.5;
        float twinkle = pow(0.5 + 0.5 * sin(h * 50.0 + tilt.x * 9.0 + tilt.y * 7.0 + time * 2.0), 3.0);
        float core = smoothstep(0.18, 0.0, length(p));
        float rays = smoothstep(0.035, 0.0, abs(p.x)) * smoothstep(0.45, 0.0, abs(p.y))
            + smoothstep(0.035, 0.0, abs(p.y)) * smoothstep(0.45, 0.0, abs(p.x));
        return step(1.0 - density, h) * twinkle * (core + rays);
    }

    /// c: 元の色（非プリマルチプライド）、uv: 左上原点の0〜1、tilt: 端末の傾き、kind: 1ホロ / 2キラキラ / 3ゴールド
    float3 shade(float3 c, float2 uv, float2 tilt, float time, float kind) {
        float lum = dot(c, float3(0.299, 0.587, 0.114));
        // 傾きに合わせて斜めに走る光の筋
        float sweep = (uv.x + uv.y) * 0.5 - (0.5 + tilt.x * 0.7 + tilt.y * 0.5);
        float band = exp(-sweep * sweep * 60.0);
        float3 rgb;
        if (kind < 1.5) {
            float3 rb = rainbow((uv.x * 0.8 + uv.y * 1.2) * 1.6 + tilt.x * 1.2 - tilt.y * 0.8);
            rgb = mix(c, c * 0.7 + rb * 0.45, 0.35) + band * 0.5;
        } else if (kind < 2.5) {
            // 細かいラメ：ほぼ全面に敷き詰め、傾けるとざらっと光る
            float2 fine = uv * 70.0;
            float2 fineCell = floor(fine);
            float hf = hash(fineCell);
            // 粒の位置と大きさをばらつかせ、網目模様に見えないようにする
            float2 jitter = (float2(hash(fineCell + 1.3), hash(fineCell + 5.9)) - 0.5) * 0.6;
            float dotSize = 0.32 + 0.25 * hash(fineCell + 9.2);
            float fineTwinkle = pow(0.5 + 0.5 * sin(hf * 80.0 + tilt.x * 14.0 + tilt.y * 11.0 + time * 2.5), 4.0);
            float fineDot = step(0.05, hf) * smoothstep(dotSize, 0.0, length(fract(fine) - 0.5 - jitter));
            float3 fineSpark = float3(1.0, 0.97, 0.88) * fineDot * fineTwinkle * 1.6;
            // 大きな星と中くらいの星を重ね、元の絵が少し見えにくくなるくらい散らす
            float stars = star(uv, 12.0, 0.85, 0.0, tilt, time) * 2.2
                + star(uv, 18.0, 0.75, 19.3, tilt, time) * 1.6;
            rgb = c * (1.0 + band * 0.4) + fineSpark + float3(1.0, 0.98, 0.92) * stars + band * 0.3;
        } else {
            float3 gold = mix(float3(0.42, 0.26, 0.06), float3(1.0, 0.88, 0.5), smoothstep(0.05, 0.95, lum));
            float sheen = 0.5 + 0.5 * sin((uv.x - uv.y) * 8.0 + tilt.x * 4.0 - tilt.y * 3.0);
            rgb = mix(c, gold * (0.8 + 0.4 * sheen), 0.75) + band * float3(1.0, 0.95, 0.75) * 0.55;
        }
        return clamp(rgb, 0.0, 1.0);
    }
}

[[ stitchable ]] half4 rareEffect(float2 position, half4 color, float2 size, float2 tilt, float time, float kind) {
    if (color.a < 0.004h) return color;
    float alpha = float(color.a);
    float2 uv = position / max(size, float2(1.0));
    float3 rgb = rare::shade(float3(color.rgb) / alpha, uv, tilt, time, kind);
    return half4(half3(rgb * alpha), color.a);
}
