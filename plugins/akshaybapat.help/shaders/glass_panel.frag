#version 440

// Sculpted Liquid Glass overlay sheet fragment shader (Qt 6.12 / RHI).
// Renders an analytically anti-aliased machined rounded rectangle with:
//   - Smoked obsidian translucent optical glass body (#101218 ~0.86 alpha)
//   - Gentle overhead studio dome lift + subtle bottom physical contact lip
//   - 45-degree Fresnel top-edge meniscus sheen
//   - Quiet ambient accent caustic glow near the active segmented tab
//   - Crisp 1px directional specular glass bezel rim (top-left -> bottom-right)

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 iResolution;
    vec4 tintColor;
    vec4 accentColor;
    float cornerRadius;
    float activeTabPos;
    float causticStrength;
};

float sdRoundedBox(vec2 p, vec2 halfSize, float radius) {
    float r = min(radius, min(halfSize.x, halfSize.y));
    vec2 q = abs(p) - halfSize + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main() {
    vec2 res = max(iResolution, vec2(4.0));
    vec2 uv = qt_TexCoord0;
    vec2 p = (uv - 0.5) * res;

    // Inset by 0.5 px so the analytical anti-aliased edge never clips item bounds.
    vec2 halfSize = max(0.5 * res - vec2(0.5), vec2(2.0));
    float r = clamp(cornerRadius, 2.0, min(halfSize.x, halfSize.y));
    float d = sdRoundedBox(p, halfSize, r);

    // Smooth 1px analytical anti-aliasing mask.
    float mask = 1.0 - smoothstep(-0.6, 0.6, d);
    if (mask <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    // Smooth outward unit normal via symmetric central differences (NaN-free).
    vec2 eps = vec2(0.65, 0.0);
    vec2 grad = vec2(
        sdRoundedBox(p + eps.xy, halfSize, r) - sdRoundedBox(p - eps.xy, halfSize, r),
        sdRoundedBox(p + eps.yx, halfSize, r) - sdRoundedBox(p - eps.yx, halfSize, r)
    );
    float gLen = max(length(grad), 1e-4);
    vec2 n = grad / gLen;

    float vx = clamp(uv.x, 0.0, 1.0);
    float vy = clamp(uv.y, 0.0, 1.0);

    // 1. Smoked obsidian optical glass base with subtle overhead studio lift.
    vec3 baseRgb = tintColor.rgb;
    float baseAlpha = tintColor.a;
    float domeLift = (1.0 - smoothstep(0.0, 0.50, vy)) * 0.044;
    // Gentle 45-degree diagonal glass sheen across the upper-left third.
    float diag = clamp(1.0 - (vx * 0.56 + vy * 0.84), 0.0, 1.0);
    float diagSheen = pow(diag, 2.3) * 0.046;
    vec3 glassRgb = baseRgb + vec3(domeLift + diagSheen);

    // 2. Quiet ambient accent caustic glow behind the active segmented tab.
    float tabX = clamp(activeTabPos, 0.08, 0.92);
    vec2 cDelta = vec2((vx - tabX) * 2.1, (vy - 0.13) * 3.3);
    float caustic = exp(-dot(cDelta, cDelta) * 3.6) * clamp(causticStrength, 0.0, 1.0) * 0.115;
    glassRgb += accentColor.rgb * caustic;

    // 3. 45-degree overhead Fresnel optical meniscus tucked under the top bezel.
    float edgeDepth = max(-d, 0.0);
    float topFacing = pow(clamp(-n.y * 0.84 - n.x * 0.38 + 0.18, 0.0, 1.0), 1.55);
    float meniscusFalloff = exp(-edgeDepth * 0.15);
    float topSheen = topFacing * meniscusFalloff * 0.145;

    // 4. Crisp 1px specular glass bezel rim (brighter top-left catchlight -> quiet bottom-right).
    float rimBand = smoothstep(-1.45, -0.35, d) * (1.0 - smoothstep(-0.20, 0.55, d));
    float fresnelDir = clamp(-n.y * 0.64 - n.x * 0.44 + 0.34, 0.0, 1.0);
    float rimIntensity = mix(0.09, 0.42, pow(fresnelDir, 1.3));

    // Subtle accent tint blended softly into the top rim near the active tab.
    float rimTabProx = exp(-pow((vx - tabX) * 3.6, 2.0)) * clamp(-n.y, 0.0, 1.0);
    vec3 rimColor = mix(vec3(1.0), mix(vec3(1.0), accentColor.rgb * 1.25 + vec3(0.25), 0.55), rimTabProx * 0.65);

    // Subtle dark lower contact thickness lip for physical glass weight.
    float bottomShade = clamp(n.y, 0.0, 1.0) * exp(-edgeDepth * 0.38) * 0.085;
    glassRgb = max(glassRgb - vec3(bottomShade), vec3(0.0));

    // Composite glass body + Fresnel meniscus + directional specular bezel.
    vec3 finalRgb = glassRgb + vec3(topSheen) + rimColor * (rimBand * rimIntensity);
    float finalAlpha = clamp(baseAlpha + rimBand * rimIntensity * 0.55 + topSheen * 0.28, 0.0, 1.0) * mask;

    // Qt Quick Scene Graph expects premultiplied alpha output.
    fragColor = vec4(finalRgb * finalAlpha, finalAlpha) * qt_Opacity;
}
