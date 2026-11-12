//
//  Fire.metal
//  Audio Vusualizer
//
//  Procedural fire: fractal noise that scrolls upward, shaped by a height
//  envelope coming from Swift (normal-distributed tongues × bell × loudness).
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1, 0));
    float c = hash21(i + float2(0, 1));
    float d = hash21(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float s = 0.0;
    float a = 0.5;
    const float2x2 m = float2x2(1.6, 1.2, -1.2, 1.6);
    for (int i = 0; i < 5; i++) {
        s += a * vnoise(p);
        p = m * p;
        a *= 0.5;
    }
    return s / 0.96875;
}

/// Catmull–Rom interpolation of the envelope: smooth, no flat steps at nodes.
static float envelope(float x, device const float *hs, int count) {
    float fx = clamp(x, 0.0, 1.0) * float(count - 1);
    int i1 = int(floor(fx));
    int i0 = max(i1 - 1, 0);
    int i2 = min(i1 + 1, count - 1);
    int i3 = min(i1 + 2, count - 1);
    float t = fx - float(i1);
    float p0 = hs[i0], p1 = hs[i1], p2 = hs[i2], p3 = hs[i3];
    float t2 = t * t, t3 = t2 * t;
    float v = 0.5 * ((2.0 * p1) + (-p0 + p2) * t
                     + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
                     + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3);
    return max(v, 0.0);
}

/// Temperature (0...1) → fire colour: black → dark red → orange → yellow → pale white.
static float3 fireColor(float t) {
    float3 c = float3(0.0);
    c = mix(c, float3(0.45, 0.03, 0.00), smoothstep(0.00, 0.18, t));
    c = mix(c, float3(0.92, 0.22, 0.02), smoothstep(0.15, 0.42, t));
    c = mix(c, float3(1.00, 0.52, 0.08), smoothstep(0.38, 0.65, t));
    c = mix(c, float3(1.00, 0.80, 0.35), smoothstep(0.62, 0.86, t));
    c = mix(c, float3(1.00, 0.95, 0.80), smoothstep(0.85, 1.00, t));
    return c;
}

[[ stitchable ]] half4 fire(float2 pos, half4 color,
                            float2 size, float time, float loud,
                            device const float *hs, int count) {
    float2 uv = pos / size;
    float aspect = size.x / size.y;
    float h = 1.0 - uv.y;                       // 0 at the bottom, 1 at the top

    // Hot air sways the flame more the higher it goes.
    float sway = (fbm(float2(uv.x * aspect * 1.5, h * 1.2 - time * 0.6)) - 0.5) * 0.22 * h;
    float x = uv.x + sway / aspect;

    float H = max(envelope(x, hs, count), 0.002);

    // Noise in view-height units so tongues keep their shape at any aspect ratio.
    float2 q = float2(x * aspect * 3.2, h * 2.4 - time * 1.5);
    float n1 = fbm(q);
    float n2 = fbm(q * 2.1 + float2(3.7, -time * 1.1));
    float n = smoothstep(0.15, 0.85, n1 * 0.7 + n2 * 0.3);

    // Distance into the flame: 1 at the base, ≤0 above the tip.
    // The noise lets tips reach well above or stay below the envelope.
    float rel = h / H;
    float v = 1.0 - rel * (1.75 - 1.25 * n);
    // Higher up the flame breaks into separate licks.
    v -= (1.0 - n) * rel * 0.35;

    // Cut the faint, far-reaching tail so the tips end cleanly instead of in dark bands.
    float t = smoothstep(0.06, 1.0, clamp(v, 0.0, 1.0));
    t = pow(t, 0.8) * (0.8 + 0.25 * n);
    float3 col = fireColor(clamp(t, 0.0, 1.0));

    // Soft red halo above the flames and a warm glow from the embers below.
    float bright = 0.35 + 0.65 * loud;
    float halo = exp(-max(h - H * 0.9, 0.0) * 9.0) * 0.12 * bright;
    col += float3(0.55, 0.10, 0.01) * halo * (1.0 - t);
    col += float3(0.6, 0.15, 0.02) * exp(-h * 14.0) * 0.35 * bright;

    // Dither to hide 8-bit banding in the dark gradients.
    col += (hash21(pos + fract(time) * 61.0) - 0.5) / 255.0;

    return half4(half3(max(col, 0.0)), 1.0h);
}
