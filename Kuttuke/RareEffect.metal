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

namespace rare {
    /// 気泡1個ぶんの影響。xy: レンズで読む位置のずれ、z: 縁の輪とハイライトの明るさ、w: 外側の細い影
    /// d は気泡の中心からの差（画像の短い辺を1とした長さ）
    float4 bubble(float2 d, float r) {
        float dist = length(d);
        float inside = 1.0 - smoothstep(r * 0.92, r, dist);
        float lens = max(1.0 - (dist * dist) / (r * r), 0.0);
        float2 offset = -d * 0.45 * lens * inside;
        float rim = smoothstep(r * 0.7, r * 0.95, dist) * inside;
        float spot = (1.0 - smoothstep(0.0, r * 0.28, length(d + float2(0.38, 0.38) * r))) * inside;
        float outline = smoothstep(r * 0.95, r * 1.02, dist) * (1.0 - smoothstep(r * 1.02, r * 1.12, dist));
        return float4(offset, rim + spot * 1.2, outline);
    }

    /// 水の層の色味と、ぷっくりした表面の光沢
    float3 water(float3 c, float2 uv, float2 tilt, float light, float outline) {
        c = mix(c, c * float3(0.92, 0.98, 1.06) + 0.04, 0.6);
        float sweep = (uv.x + uv.y) * 0.5 - (0.5 + tilt.x * 0.7 + tilt.y * 0.5);
        float gloss = exp(-sweep * sweep * 30.0) * 0.22;
        c = c * (1.0 - outline * 0.35) + light * 0.65 + gloss;
        return clamp(c, 0.0, 1.0);
    }
}

[[ stitchable ]] half4 rareEffect(float2 position, half4 color, float2 size, float2 tilt, float time, float kind) {
    if (color.a < 0.004h) return color;
    float alpha = float(color.a);
    float2 uv = position / max(size, float2(1.0));
    float3 rgb = rare::shade(float3(color.rgb) / alpha, uv, tilt, time, kind);
    return half4(half3(rgb * alpha), color.a);
}

// 水入りシール。bubbles は x, y, 半径 の繰り返し（BubbleSimulation.packed）
// RareEffect.swift の SpriteKit用シェーダー（waterSource）と同じ計算。見た目を変えるときは両方を直す
[[ stitchable ]] half4 waterEffect(float2 position, SwiftUI::Layer layer, float2 size, float2 tilt, float time, device const float *bubbles, int count) {
    half4 original = layer.sample(position);
    if (original.a < 0.004h) return original;
    float2 safeSize = max(size, float2(1.0));
    float2 uv = position / safeSize;
    // 縦横比が違っても気泡が丸くなるよう、短い辺を1とした長さで測る
    float2 aspect = safeSize / min(safeSize.x, safeSize.y);

    float4 sum = float4(0.0);
    for (int i = 0; i + 2 < count; i += 3) {
        float4 b = rare::bubble((uv - float2(bubbles[i], bubbles[i + 1])) * aspect, bubbles[i + 2]);
        sum += float4(b.xy / aspect, b.zw);
    }
    float2 wave = float2(sin(uv.y * 18.0 + time * 1.6 + tilt.x * 3.0), cos(uv.x * 16.0 + time * 1.3 + tilt.y * 3.0)) * 0.004;
    half4 moved = layer.sample((uv + wave + sum.xy) * safeSize);
    // 縁の外の透明な色を拾ったときは元の色を使う
    half4 source = moved.a > original.a * 0.5h ? moved : original;
    float3 c = float3(source.rgb) / max(float(source.a), 0.004);
    float3 rgb = rare::water(c, uv, tilt, sum.z, sum.w);
    return half4(half3(rgb * float(original.a)), original.a);
}

namespace rare {
    /// 周囲8方向・半径rの不透明度の最大と最小。縁の近くほど両者の差が大きくなる
    float2 ring(SwiftUI::Layer layer, float2 position, float r) {
        float d = r * 0.7071;
        float a1 = layer.sample(position + float2(r, 0)).a;
        float a2 = layer.sample(position - float2(r, 0)).a;
        float a3 = layer.sample(position + float2(0, r)).a;
        float a4 = layer.sample(position - float2(0, r)).a;
        float a5 = layer.sample(position + float2(d, d)).a;
        float a6 = layer.sample(position - float2(d, d)).a;
        float a7 = layer.sample(position + float2(d, -d)).a;
        float a8 = layer.sample(position - float2(d, -d)).a;
        float maxA = max(max(max(a1, a2), max(a3, a4)), max(max(a5, a6), max(a7, a8)));
        float minA = min(min(min(a1, a2), min(a3, a4)), min(min(a5, a6), min(a7, a8)));
        return float2(maxA, minA);
    }

    /// 縁を使う加工（5ネオン / 6ラメ縁取り）。プリマルチプライドの色を返し、絵の外側にも光を描く
    /// c: 元の色（非プリマルチプライド）、a0: その位置の不透明度、n1〜n4: 半径の小さい順の ring
    float4 edge(float3 c, float a0, float2 n1, float2 n2, float2 n3, float2 n4, float2 uv, float2 tilt, float time, float kind) {
        float maxNear = max(a0, max(n1.x, n2.x));
        float minNear = min(a0, min(n1.y, n2.y));
        float band = clamp(maxNear * (1.0 - minNear), 0.0, 1.0);
        if (kind < 5.5) {
            // ネオン管：縁に沿った明るい線と、外側へ広がる光
            float core = clamp(max(a0, n1.x) * (1.0 - min(a0, n1.y)), 0.0, 1.0);
            float tube = clamp(core * 0.6 + band * 0.5, 0.0, 1.0);
            float glow = (n3.x * 0.55 + n4.x * 0.35) * (1.0 - a0);
            float hue = 0.5 + 0.5 * sin(time * 0.7 + tilt.x * 2.0);
            float3 neon = mix(float3(1.0, 0.25, 0.75), float3(0.25, 0.85, 1.0), hue);
            // ときどき一瞬ちらつく
            float flicker = 1.0 - 0.55 * step(0.93, hash(float2(floor(time * 9.0), 3.1)));
            float emissionAlpha = clamp(max(tube, glow * 0.9) * flicker, 0.0, 1.0);
            float3 emission = (neon * (tube * 1.3 + glow) + float3(1.0) * core * 0.55) * flicker;
            float alpha = a0 + emissionAlpha * (1.0 - a0);
            // ネオンが映えるよう、中の絵は少し暗くする
            float3 rgb = c * 0.72 * a0 * (1.0 - emissionAlpha) + emission;
            return float4(clamp(rgb, 0.0, alpha), alpha);
        }
        // ラメ縁取り：縁に沿ってラメの帯をつける。中の絵はそのまま
        float bandAlpha = smoothstep(0.15, 0.6, band);
        float3 lameBase = mix(float3(0.78, 0.66, 0.38), float3(0.96, 0.94, 0.9),
                              0.5 + 0.5 * sin((uv.x - uv.y) * 12.0 + tilt.x * 4.0 - tilt.y * 3.0));
        float2 fine = uv * 90.0;
        float2 cell = floor(fine);
        float h = hash(cell);
        float2 jitter = float2(hash(cell + 1.3), hash(cell + 5.9)) - 0.5;
        float dotMask = step(0.2, h) * smoothstep(0.45, 0.0, length(fract(fine) - 0.5 - jitter * 0.5));
        float twinkle = pow(0.5 + 0.5 * sin(h * 70.0 + tilt.x * 12.0 + tilt.y * 9.0 + time * 2.2), 4.0);
        float3 lame = lameBase * 0.85 + float3(1.0) * dotMask * twinkle * 1.2
            + float3(1.0, 0.98, 0.92) * star(uv, 24.0, 0.6, 5.0, tilt, time) * 1.6;
        float alpha = a0 + bandAlpha * (1.0 - a0);
        float3 rgb = c * a0 * (1.0 - bandAlpha) + clamp(lame, 0.0, 1.0) * bandAlpha;
        return float4(clamp(rgb, 0.0, alpha), alpha);
    }

    /// 雪1層ぶん。drift の分だけ模様ごと流し、粒ごとにふわふわ揺らす
    float flakes(float2 uv, float2 drift, float scale, float speed, float size, float seed, float time, float agitation) {
        float2 g = (uv - drift * speed) * scale;
        float2 cell = floor(g);
        float h = hash(cell + seed);
        float2 jitter = float2(hash(cell + seed + 4.3), hash(cell + seed + 8.1)) - 0.5;
        float2 p = fract(g) - 0.5 - jitter * 0.3;
        float wobble = 0.06 + agitation * 0.08;
        p += float2(sin(time * 1.7 + h * 20.0), cos(time * 1.3 + h * 15.0)) * wobble;
        return step(0.4, h) * (1.0 - smoothstep(size * 0.35, size, length(p)));
    }

    /// スノードーム（7）：大小3層の雪と、ガラスのドームの光沢
    float3 snow(float3 c, float2 uv, float2 tilt, float time, float2 drift, float agitation) {
        float f = flakes(uv, drift, 6.0, 1.0, 0.2, 0.0, time, agitation)
            + flakes(uv, drift, 11.0, 0.7, 0.17, 13.7, time, agitation) * 0.8
            + flakes(uv, drift, 19.0, 0.45, 0.15, 27.1, time, agitation) * 0.6;
        c = mix(c, c * float3(0.95, 0.98, 1.05) + 0.03, 0.5);
        float sweep = (uv.x + uv.y) * 0.5 - (0.5 + tilt.x * 0.7 + tilt.y * 0.5);
        float gloss = exp(-sweep * sweep * 30.0) * 0.2;
        return clamp(mix(c, float3(1.0), min(f, 1.0) * 0.92) + gloss, 0.0, 1.0);
    }

    /// ぎょろ目1個（8）。xyz: 色、w: 目の範囲。d と pupil は目の中心からの差（短い辺を1とした長さ）
    float4 eye(float2 d, float r, float2 pupil) {
        float radius = max(r, 0.0001);
        float dist = length(d);
        float cover = (1.0 - smoothstep(radius * 0.96, radius, dist)) * step(0.001, r);
        float3 col = float3(1.0 - 0.18 * smoothstep(radius * 0.3, radius, dist));
        float rim = smoothstep(radius * 0.86, radius * 0.93, dist);
        col = mix(col, float3(0.08), rim);
        float pupilRadius = radius * 0.5;
        float pupilMask = 1.0 - smoothstep(pupilRadius * 0.92, pupilRadius, length(d - pupil));
        col = mix(col, float3(0.05), pupilMask * (1.0 - rim));
        // プラスチックのカバーの映り込み（黒目が動いても位置は変わらない）
        float gloss = 1.0 - smoothstep(0.0, radius * 0.22, length(d + float2(0.35, 0.35) * radius));
        col += gloss * 0.8;
        return float4(clamp(col, 0.0, 1.0), cover);
    }
}

// ネオン / ラメ縁取り。縁を調べるため周囲の色を読み、絵の外側の透明な部分にも光を描く
// RareEffect.swift の SpriteKit用シェーダー（edgeSource）と同じ計算。見た目を変えるときは両方を直す
[[ stitchable ]] half4 edgeEffect(float2 position, SwiftUI::Layer layer, float2 size, float2 tilt, float time, float kind) {
    float2 safeSize = max(size, float2(1.0));
    float unit = min(safeSize.x, safeSize.y);
    half4 original = layer.sample(position);
    float a0 = float(original.a);
    float2 n4 = rare::ring(layer, position, 0.065 * unit);
    if (a0 < 0.004 && n4.x < 0.004) return original;
    float2 n1 = rare::ring(layer, position, 0.010 * unit);
    float2 n2 = rare::ring(layer, position, 0.018 * unit);
    float2 n3 = rare::ring(layer, position, 0.040 * unit);
    float3 c = a0 > 0.004 ? float3(original.rgb) / a0 : float3(0.0);
    return half4(rare::edge(c, a0, n1, n2, n3, n4, position / safeSize, tilt, time, kind));
}

// スノードーム。drift は雪が流れた量（SnowDrift）、agitation は振ったときの舞い上がり具合
// RareEffect.swift の SpriteKit用シェーダー（snowSource）と同じ計算。見た目を変えるときは両方を直す
[[ stitchable ]] half4 snowEffect(float2 position, half4 color, float2 size, float2 tilt, float time, float2 drift, float agitation) {
    if (color.a < 0.004h) return color;
    float alpha = float(color.a);
    float2 uv = position / max(size, float2(1.0));
    float3 rgb = rare::snow(float3(color.rgb) / alpha, uv, tilt, time, drift, agitation);
    return half4(half3(rgb * alpha), color.a);
}

// ぎょろ目。eyes は2つの目の中心（uv）、radius は目の半径、pupils は黒目のずれ（短い辺を1とした長さ）
// RareEffect.swift の SpriteKit用シェーダー（googlySource）と同じ計算。見た目を変えるときは両方を直す
[[ stitchable ]] half4 googlyEffect(float2 position, half4 color, float2 size, float4 eyes, float radius, float4 pupils) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = position / safeSize;
    float2 aspect = safeSize / min(safeSize.x, safeSize.y);
    float4 result = float4(color);
    float4 e1 = rare::eye((uv - eyes.xy) * aspect, radius, pupils.xy);
    float4 e2 = rare::eye((uv - eyes.zw) * aspect, radius, pupils.zw);
    result = float4(result.rgb * (1.0 - e1.w) + e1.rgb * e1.w, result.a + e1.w * (1.0 - result.a));
    result = float4(result.rgb * (1.0 - e2.w) + e2.rgb * e2.w, result.a + e2.w * (1.0 - result.a));
    return half4(result);
}
