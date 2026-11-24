#version 440

// Sculpted Liquid Glass Window Switcher HUD fragment shader (Qt 6.12 / RHI).
// Renders an analytically anti-aliased optical glass capsule with:
//   - Smoked obsidian translucent glass body (#101219 @ ~0.86 alpha)
//   - Overhead studio dome lift + 45-degree diagonal refraction sheen
//   - 45-degree Fresnel top-edge optical meniscus
//   - Ambient accent caustic smoothly tracking the active card's normalized X (focusX)
//   - Crisp 1px directional specular glass bezel rim with focus-tracked catchlight
//   - Subtle lower physical contact shadow lip

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 iResolution;
    vec4 tintColor;
    vec4 accentColor;
    float cornerRadius;
    float focusX;
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

    // 1. Smoked obsidian optical glass base with gentle overhead studio lift.
    vec3 baseRgb = tintColor.rgb;
    float baseAlpha = tintColor.a;
    float domeLift = (1.0 - smoothstep(0.0, 0.52, vy)) * 0.048;

    // 45-degree diagonal glass sheen across the upper-left optical plane.
    float diag = clamp(1.0 - (vx * 0.52 + vy * 0.86), 0.0, 1.0);
    float diagSheen = pow(diag, 2.2) * 0.052;
    vec3 glassRgb = baseRgb + vec3(domeLift + diagSheen);

    // 2. Ambient accent caustic softly following the selected card's focusX.
    float fx = clamp(focusX, 0.06, 0.94);
    float aspect = clamp(res.x / max(res.y, 1.0), 1.0, 5.5);
    vec2 cDelta = vec2((vx - fx) * (aspect * 0.84), (vy - 0.50) * 2.05);
    float cStr = clamp(causticStrength, 0.0, 1.0);
    float cardCaustic = exp(-dot(cDelta, cDelta) * 1.95) * cStr * 0.180;

    // Subtle secondary overhead refraction pool aligned with focusX.
    vec2 topDelta = vec2((vx - fx) * (aspect * 1.12), (vy - 0.06) * 4.0);
    float topCaustic = exp(-dot(topDelta, topDelta) * 2.6) * cStr * 0.115;
    glassRgb += accentColor.rgb * (cardCaustic + topCaustic);

    // 3. 45-degree overhead Fresnel optical meniscus tucked under the top bezel.
    float edgeDepth = max(-d, 0.0);
    float topFacing = pow(clamp(-n.y * 0.86 - n.x * 0.36 + 0.16, 0.0, 1.0), 1.5);
    float meniscusFalloff = exp(-edgeDepth * 0.135);
    float topSheen = topFacing * meniscusFalloff * 0.175;

    // 4. Crisp 1px specular glass bezel rim (bright top-left catchlight -> quiet bottom-right).
    float rimBand = smoothstep(-1.45, -0.35, d) * (1.0 - smoothstep(-0.20, 0.55, d));
    float fresnelDir = clamp(-n.y * 0.66 - n.x * 0.42 + 0.34, 0.0, 1.0);
    float rimIntensity = mix(0.10, 0.44, pow(fresnelDir, 1.25));

    // Focus-tracked subtle accent shimmer blended into the top & bottom specular bezel.
    float rimFocusProx = exp(-pow((vx - fx) * (aspect * 1.35), 2.0)) * clamp(abs(n.y), 0.0, 1.0);
    vec3 accentBright = min(vec3(1.0), accentColor.rgb * 1.32 + vec3(0.26));
    vec3 rimColor = mix(vec3(1.0), accentBright, rimFocusProx * 0.55 * cStr);
    rimIntensity += rimFocusProx * 0.14 * cStr;

    // 5. Subtle lower contact thickness lip for physical glass weight.
    float bottomShade = clamp(n.y, 0.0, 1.0) * exp(-edgeDepth * 0.36) * 0.095;
    glassRgb = max(glassRgb - vec3(bottomShade), vec3(0.0));

    // Composite glass body + Fresnel meniscus + directional specular bezel.
    vec3 finalRgb = glassRgb + vec3(topSheen) + rimColor * (rimBand * rimIntensity);
    float finalAlpha = clamp(baseAlpha + rimBand * rimIntensity * 0.56 + topSheen * 0.28, 0.0, 1.0) * mask;

    // Qt Quick Scene Graph expects premultiplied alpha output.
    fragColor = vec4(finalRgb * finalAlpha, finalAlpha) * qt_Opacity;
}
