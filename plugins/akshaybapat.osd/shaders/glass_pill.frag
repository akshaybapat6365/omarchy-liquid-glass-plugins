#version 440

// Sculpted Liquid Glass pill fragment shader (Qt 6.12 / RHI).
// Renders an analytically anti-aliased capsule pill with smoked translucent
// obsidian tint, overhead Fresnel top-edge glass sheen, crisp 1px beveled
// specular rim, and subtle internal accent caustics.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 iResolution;
    vec4 tintColor;
    vec4 accentColor;
    float progress;
    float hasProgress;
};

float sdCapsule(vec2 p, vec2 size) {
    float r = 0.5 * min(size.x, size.y);
    vec2 b = max(0.5 * size - vec2(r), vec2(0.0));
    vec2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 res = max(iResolution, vec2(2.0));
    vec2 p = (qt_TexCoord0 - 0.5) * res;

    // Inset by 0.5 px so the anti-aliased outer edge never clips on item bounds.
    vec2 insetRes = max(res - vec2(1.0), vec2(2.0));
    float d = sdCapsule(p, insetRes);

    // Smooth 1px analytical anti-aliasing mask.
    float mask = 1.0 - smoothstep(-0.6, 0.6, d);
    if (mask <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    // Smooth outward unit normal via symmetric central differences (NaN-free).
    vec2 eps = vec2(0.5, 0.0);
    vec2 grad = vec2(
        sdCapsule(p + eps.xy, insetRes) - sdCapsule(p - eps.xy, insetRes),
        sdCapsule(p + eps.yx, insetRes) - sdCapsule(p - eps.yx, insetRes)
    );
    float gLen = max(length(grad), 1e-4);
    vec2 n = grad / gLen;

    // Normalized vertical position: 0 at top lip, 1 at bottom lip.
    float vy = clamp(qt_TexCoord0.y, 0.0, 1.0);

    // 1. Smoked optical glass base with gentle overhead dome shading.
    vec3 baseRgb = tintColor.rgb;
    float baseAlpha = tintColor.a;
    float domeLift = (1.0 - smoothstep(0.0, 0.55, vy)) * 0.045;
    vec3 glassRgb = baseRgb + vec3(domeLift);

    // 2. Quiet ambient accent caustic wash while a progress bar is active.
    if (hasProgress > 0.5) {
        float barCenter = clamp(0.26 + 0.44 * progress, 0.24, 0.72);
        vec2 cDelta = vec2((qt_TexCoord0.x - barCenter) * 1.8, (vy - 0.52) * 1.4);
        float caustic = exp(-dot(cDelta, cDelta) * 5.0) * (0.045 + 0.045 * progress);
        glassRgb += accentColor.rgb * caustic;
    }

    // 3. Soft internal top-edge glass sheen (optical meniscus under top bezel).
    float edgeDepth = max(-d, 0.0);
    float topFacing = pow(clamp(-n.y * 0.90 - n.x * 0.14 + 0.14, 0.0, 1.0), 1.6);
    float sheenFalloff = exp(-edgeDepth * 0.34);
    float topSheen = topFacing * sheenFalloff * 0.16;

    // 4. Crisp 1px Fresnel specular rim (top-left catchlight -> quiet bottom-right).
    float rimBand = smoothstep(-1.35, -0.35, d) * (1.0 - smoothstep(-0.20, 0.55, d));
    float fresnelDir = clamp(-n.y * 0.68 - n.x * 0.36 + 0.32, 0.0, 1.0);
    float rimIntensity = mix(0.07, 0.38, pow(fresnelDir, 1.35));

    // Subtle secondary dark bottom contact lip for physical thickness.
    float bottomShade = clamp(n.y, 0.0, 1.0) * exp(-edgeDepth * 0.5) * 0.10;
    glassRgb = max(glassRgb - vec3(bottomShade), vec3(0.0));

    // Composite glass body + optical sheen + specular rim.
    vec3 finalRgb = glassRgb + vec3(topSheen) + vec3(rimBand * rimIntensity);
    float finalAlpha = clamp(baseAlpha + rimBand * rimIntensity * 0.65 + topSheen * 0.35, 0.0, 1.0) * mask;

    // Qt Quick Scene Graph expects premultiplied alpha output.
    fragColor = vec4(finalRgb * finalAlpha, finalAlpha) * qt_Opacity;
}
