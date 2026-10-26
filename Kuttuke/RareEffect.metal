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

    float noise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash(i), hash(i + float2(1.0, 0.0)), u.x),
                   mix(hash(i + float2(0.0, 1.0)), hash(i + float2(1.0, 1.0)), u.x), u.y);
    }

    /// 細かさの違うノイズを5枚重ねたもの（0〜1くらい）
    float fbm(float2 p) {
        float v = 0.0;
        float a = 0.5;
        for (int i = 0; i < 5; i++) {
            v += a * noise(p);
            p = p * 2.03 + float2(17.1, 9.2);
            a *= 0.5;
        }
        return v;
    }

    float luma(float3 c) {
        return dot(c, float3(0.299, 0.587, 0.114));
    }

    float3 saturateColor(float3 c, float s) {
        return mix(float3(luma(c)), c, s);
    }

    /// 傾きに合わせて斜めに走る光の筋
    float sweep(float2 uv, float2 tilt, float sharpness) {
        float s = (uv.x + uv.y) * 0.5 - (0.5 + tilt.x * 0.7 + tilt.y * 0.5);
        return exp(-s * s * sharpness);
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
        float core = 1.0 - smoothstep(0.0, 0.18, length(p));
        float rays = (1.0 - smoothstep(0.0, 0.035, abs(p.x))) * (1.0 - smoothstep(0.0, 0.45, abs(p.y)))
            + (1.0 - smoothstep(0.0, 0.035, abs(p.y))) * (1.0 - smoothstep(0.0, 0.45, abs(p.x)));
        return step(1.0 - density, h) * twinkle * (core + rays);
    }

    /// ボロノイ。x: いちばん近い点までの距離、y: 2番目に近い点までの距離、zw: いちばん近い点（セルの中心）
    float4 voronoi(float2 p) {
        float2 n = floor(p);
        float2 f = fract(p);
        float d1 = 8.0;
        float d2 = 8.0;
        float2 center = float2(0.0);
        for (int j = -1; j <= 1; j++) {
            for (int i = -1; i <= 1; i++) {
                float2 g = float2(float(i), float(j));
                float2 o = float2(hash(n + g), hash(n + g + 19.7));
                float2 r = g + o - f;
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
        return float4(sqrt(d1), sqrt(d2), center);
    }

    /// 色だけを変える加工。c: 元の色（非プリマルチプライド）、uv: 左上原点の0〜1、tilt: 端末の傾き
    /// kind: 1シルバー / 2オイルスリック / 3ギャラクシー
    float3 shade(float3 c, float2 uv, float2 tilt, float time, float kind) {
        float lum = luma(c);
        float3 rgb;
        if (kind < 1.5) {
            // 横方向に細長いノイズで、ヘアラインの筋を作る
            float brush = noise(float2(uv.x * 6.0, uv.y * 420.0)) * 0.6 + noise(float2(uv.x * 40.0, uv.y * 900.0)) * 0.4;
            float sheen = 0.5 + 0.5 * sin((uv.y * 1.4 - uv.x * 0.5) * 7.0 + tilt.y * 6.0 + tilt.x * 3.0);
            float3 silver = float3(0.52, 0.55, 0.6) + (lum - 0.5) * 0.9 + (brush - 0.5) * 0.18 + pow(sheen, 4.0) * 0.55;
            silver += float3(0.6, 0.75, 1.0) * 0.12 * sheen;
            rgb = mix(c, silver, 0.72) + sweep(uv, tilt, 50.0) * 0.45;
        } else if (kind < 2.5) {
            // ノイズでノイズをゆがめて、渦を巻いた油膜の厚みにする
            float2 p = uv * 2.5;
            float2 w = float2(fbm(p + time * 0.05), fbm(p + 5.2 - time * 0.04));
            float thickness = fbm(p + w * 2.0) * 2.0 + dot(uv - 0.5, tilt) * 2.0 + lum * 0.6;
            float3 film = 0.5 + 0.5 * cos(6.28318 * (thickness * 1.6 + float3(0.0, 0.33, 0.67)));
            rgb = mix(c, c * 0.35 + film * 0.8, 0.56) + sweep(uv, tilt, 40.0) * 0.25;
        } else {
            float2 p = uv - tilt * 0.06;
            float nebula = fbm(p * 3.0 + float2(time * 0.02, 0.0));
            float nebula2 = fbm(p * 5.0 - float2(0.0, time * 0.03) + 3.1);
            float3 sky = float3(0.03, 0.02, 0.10)
                + float3(0.45, 0.10, 0.55) * smoothstep(0.35, 0.8, nebula)
                + float3(0.10, 0.35, 0.75) * pow(smoothstep(0.4, 0.9, nebula2), 1.5);
            // 手前の星ほど傾きで大きく動かし、奥行きを出す
            float stars = star(uv - tilt * 0.12, 26.0, 0.35, 3.0, tilt, time) * 1.4
                + star(uv - tilt * 0.04, 48.0, 0.25, 9.0, tilt, time);
            sky += float3(1.0, 0.95, 0.9) * stars;
            // 元の絵の明暗を少し残す
            sky *= 0.55 + 0.9 * lum;
            rgb = mix(c, sky, 0.81);
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

namespace rare {
    /// uv（左上原点の0〜1）の位置の色（プリマルチプライド）
    float4 tex(SwiftUI::Layer layer, float2 uv, float2 size) {
        return float4(layer.sample(uv * size));
    }

    float3 straight(float4 s) {
        return s.rgb / max(s.a, 0.004);
    }

    /// 周囲8方向・半径r（uv）の不透明度の最大と最小。縁の近くほど最小が小さくなる
    float2 ring(SwiftUI::Layer layer, float2 uv, float2 size, float r) {
        float d = r * 0.7071;
        float a1 = tex(layer, uv + float2(r, 0), size).a;
        float a2 = tex(layer, uv - float2(r, 0), size).a;
        float a3 = tex(layer, uv + float2(0, r), size).a;
        float a4 = tex(layer, uv - float2(0, r), size).a;
        float a5 = tex(layer, uv + float2(d, d), size).a;
        float a6 = tex(layer, uv - float2(d, d), size).a;
        float a7 = tex(layer, uv + float2(d, -d), size).a;
        float a8 = tex(layer, uv - float2(d, -d), size).a;
        float maxA = max(max(max(a1, a2), max(a3, a4)), max(max(a5, a6), max(a7, a8)));
        float minA = min(min(min(a1, a2), min(a3, a4)), min(min(a5, a6), min(a7, a8)));
        return float2(maxA, minA);
    }

    /// ステンドグラス（4）：ボロノイのセルの中心の色でガラスを塗り、鉛の枠で区切る
    float4 stainedGlass(SwiftUI::Layer layer, float2 uv, float2 size, float2 tilt) {
        float4 s = tex(layer, uv, size);
        if (s.a < 0.004) return float4(0.0);
        float scale = 13.4;
        float4 v = voronoi(uv * scale);
        float4 cell = tex(layer, v.zw / scale, size);
        float3 glass = cell.a > 0.1 ? straight(cell) : straight(s);
        glass = saturateColor(glass, 1.5) * 1.1;
        glass *= 0.75 + 0.5 * noise(uv * 6.0 + tilt * 3.0) + sweep(uv, tilt, 25.0) * 0.5;
        float lead = 1.0 - smoothstep(0.03, 0.07, v.y - v.x);
        // 外周にも鉛の枠をつける
        lead = max(lead, 1.0 - smoothstep(0.3, 0.9, ring(layer, uv, size, 0.01).y));
        float3 rgb = clamp(mix(glass, float3(0.12, 0.11, 0.1), lead), 0.0, 1.0);
        return float4(rgb * s.a, s.a);
    }

    /// ドット絵（5）：マス目に区切って色数を減らし、ドット1つぶんの黒い縁をつける
    float4 pixel(SwiftUI::Layer layer, float2 uv, float2 size) {
        float n = 50.0;
        float px = 1.0 / n;
        float2 cell = (floor(uv * n) + 0.5) * px;
        float4 s = tex(layer, cell, size);
        float on = step(0.5, s.a);
        float neighbor = max(max(tex(layer, cell + float2(px, 0.0), size).a, tex(layer, cell - float2(px, 0.0), size).a),
                             max(tex(layer, cell + float2(0.0, px), size).a, tex(layer, cell - float2(0.0, px), size).a));
        float outline = (1.0 - on) * step(0.5, neighbor);
        float3 c = floor(saturateColor(straight(s), 1.2) * 5.0 + 0.5) / 5.0;
        // ドットの左上を明るく、右下を暗くして粒を立たせる
        float2 f = fract(uv * n);
        c *= (f.x < 0.12 || f.y < 0.12) ? 1.08 : ((f.x > 0.88 || f.y > 0.88) ? 0.88 : 1.0);
        float3 rgb = clamp(mix(c, float3(0.1, 0.1, 0.12), outline), 0.0, 1.0);
        float alpha = max(on, outline);
        return float4(rgb * alpha, alpha);
    }

    /// 魚眼（6）：まん中をふくらませる。傾けるとふくらむ場所が動く
    float4 fisheye(SwiftUI::Layer layer, float2 uv, float2 size, float2 tilt) {
        float2 center = float2(0.5) + tilt * 0.25;
        float2 p = uv - center;
        float r = length(p);
        float radius = 0.45;
        float t = clamp(r / radius, 0.0001, 1.0);
        float2 q = r < radius ? center + p * pow(t, 0.72) : uv;
        float4 s = tex(layer, q, size);
        float3 c = straight(s);
        // レンズの映り込み
        c += (1.0 - smoothstep(0.0, 0.08, length(uv - center + float2(0.12, 0.12)))) * 0.21;
        return float4(clamp(c, 0.0, 1.0) * s.a, s.a);
    }

    /// 油絵（7）：場所ごとに決めた筆の向きに色を混ぜ、絵の具の凹凸をつける
    float4 oilPaint(SwiftUI::Layer layer, float2 uv, float2 size, float2 tilt) {
        float4 s = tex(layer, uv, size);
        if (s.a < 0.004) return float4(0.0);
        float angle = fbm(uv * 4.0) * 6.28;
        float2 dir = float2(cos(angle), sin(angle));
        float2 stepUV = dir * 0.0075;
        float4 sum = float4(0.0);
        for (int i = -3; i <= 3; i++) {
            sum += tex(layer, uv + stepUV * float(i), size);
        }
        float3 c = sum.rgb / max(sum.a, 0.004);
        c = mix(c, floor(saturateColor(c, 1.3) * 8.0 + 0.5) / 8.0, 0.5);
        float stroke = noise(float2(dot(uv, dir) * 30.0, dot(uv, float2(-dir.y, dir.x)) * 300.0));
        c *= 0.85 + 0.3 * stroke;
        c += sweep(uv, tilt, 30.0) * 0.15 * stroke;
        return float4(clamp(c, 0.0, 1.0) * s.a, s.a);
    }

    /// クロスステッチ（8）：マスごとに×の字の糸を刺す。糸のあいだから布が見える
    float4 crossStitch(SwiftUI::Layer layer, float2 uv, float2 size) {
        float n = 53.0;
        float2 cell = (floor(uv * n) + 0.5) / n;
        float4 s = tex(layer, cell, size);
        float alpha = step(0.5, s.a);
        float2 f = fract(uv * n) - 0.5;
        float2 holes = fract(uv * n * 4.0);
        float3 cloth = float3(0.95, 0.93, 0.86) * (0.9 + 0.1 * step(0.5, holes.x) * step(0.5, holes.y));
        float t1 = 1.0 - smoothstep(0.2, 0.3, abs(f.x - f.y));
        float t2 = 1.0 - smoothstep(0.2, 0.3, abs(f.x + f.y));
        float inside = step(max(abs(f.x), abs(f.y)), 0.47);
        float stitch = max(t1, t2) * inside;
        float3 yarn = floor(straight(s) * 4.0 + 0.5) / 4.0;
        // 上に重なる糸を明るく、糸のよりを細かい縞で出す
        yarn *= (t2 > t1 ? 1.0 : 0.82) * (0.85 + 0.15 * sin((t2 > t1 ? f.x - f.y : f.x + f.y) * 60.0));
        float3 rgb = clamp(mix(cloth, yarn, stitch), 0.0, 1.0);
        return float4(rgb * alpha, alpha);
    }

    /// サーモグラフィ（9）：明るさと縁からの深さを熱とみなし、赤外線カメラの色にする
    float4 thermal(SwiftUI::Layer layer, float2 uv, float2 size, float time) {
        float4 s = tex(layer, uv, size);
        if (s.a < 0.004) return float4(0.0);
        // 周りがどこまで不透明かで、縁からの深さを大まかに測る（真ん中ほど熱い）
        float depth = (ring(layer, uv, size, 0.04).y + ring(layer, uv, size, 0.08).y + ring(layer, uv, size, 0.12).y) / 3.0;
        float heat = luma(straight(s)) * 0.55 + depth * 0.5;
        heat = clamp(heat + (fbm(uv * 5.0 + time * 0.2) - 0.5) * 0.25, 0.0, 1.0);
        float3 cold = float3(0.05, 0.0, 0.2);
        float3 violet = float3(0.45, 0.0, 0.6);
        float3 red = float3(0.95, 0.1, 0.2);
        float3 orange = float3(1.0, 0.65, 0.0);
        float3 white = float3(1.0, 1.0, 0.8);
        float3 c = heat < 0.25 ? mix(cold, violet, heat / 0.25)
            : heat < 0.5 ? mix(violet, red, (heat - 0.25) / 0.25)
            : heat < 0.75 ? mix(red, orange, (heat - 0.5) / 0.25)
            : mix(orange, white, (heat - 0.75) / 0.25);
        // 走査線
        c *= 0.94 + 0.06 * sin(uv.y * 600.0);
        return float4(clamp(c, 0.0, 1.0) * s.a, s.a);
    }
}

// 周りの色を読む加工（4ステンドグラス / 5ドット絵 / 6魚眼 / 7油絵 / 8クロスステッチ / 9サーモグラフィ）
// RareEffect.swift の SpriteKit用シェーダー（sampleSource）と同じ計算。見た目を変えるときは両方を直す
[[ stitchable ]] half4 sampleEffect(float2 position, SwiftUI::Layer layer, float2 size, float2 tilt, float time, float kind) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = position / safeSize;
    float4 result;
    if (kind < 4.5) {
        result = rare::stainedGlass(layer, uv, safeSize, tilt);
    } else if (kind < 5.5) {
        result = rare::pixel(layer, uv, safeSize);
    } else if (kind < 6.5) {
        result = rare::fisheye(layer, uv, safeSize, tilt);
    } else if (kind < 7.5) {
        result = rare::oilPaint(layer, uv, safeSize, tilt);
    } else if (kind < 8.5) {
        result = rare::crossStitch(layer, uv, safeSize);
    } else {
        result = rare::thermal(layer, uv, safeSize, time);
    }
    return half4(result);
}

namespace rare {
    /// ぎょろ目1個。xyz: 色、w: 目の範囲。d と pupil は目の中心からの差（短い辺を1とした長さ）
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
