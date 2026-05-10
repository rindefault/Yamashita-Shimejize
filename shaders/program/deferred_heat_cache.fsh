#include "/shader.h"
#include "/common/math.glsl"
#include "/common/depth_utils.glsl"

uniform sampler2D colortex2;
uniform sampler2D depthtex0;
uniform float viewWidth, viewHeight;
uniform float near, far;

varying vec2 texcoord;

/* RENDERTARGETS: 4 */
#define heatCacheOut gl_FragData[0]

vec2 getHeatDir(int i) {
    if (i == 0) return vec2(1.0, 0.0);
    if (i == 1) return vec2(-1.0, 0.0);
    if (i == 2) return vec2(0.0, 1.0);
    if (i == 3) return vec2(0.0, -1.0);
    if (i == 4) return vec2(0.7071, 0.7071);
    if (i == 5) return vec2(-0.7071, 0.7071);
    if (i == 6) return vec2(0.7071, -0.7071);
    return vec2(-0.7071, -0.7071);
}

#if ENABLE_HEAT_HAZE > 0
struct HeatSample {
    vec2 mask;
    float depth;
    float linearDepth;
};

float getHeatDistanceFade(float linearDepth) {
    return 1.0 - smoothstep(30.0, 118.0, linearDepth);
}

HeatSample sampleHeat(vec2 uv) {
    HeatSample sample;
    vec4 heatMask = texture2D(colortex2, uv);
    sample.depth = texture2D(depthtex0, uv).r;
    sample.linearDepth = (sample.depth < 0.9999) ? linearizeDepthValue(sample.depth, near, far) : 0.0;
    float fade = (sample.depth < 0.9999) ? getHeatDistanceFade(sample.linearDepth) : 0.0;
    sample.mask = heatMask.rg * fade;
    return sample;
}

float getHeatOcclusionWeight(float centerDepth, float centerLinearDepth, HeatSample sample) {
    if (centerDepth >= 0.9999) return 1.0;
    if (sample.depth >= 0.9999) return 0.0;
    float depthTolerance = mix(1.2, 8.0, smoothstep(6.0, 72.0, centerLinearDepth));
    float behindDelta = sample.linearDepth - centerLinearDepth;
    return 1.0 - smoothstep(depthTolerance, depthTolerance * 2.6, behindDelta);
}

float getHeatField(vec2 coord, HeatSample centerSample) {
    vec2 pixel = vec2(1.0 / viewWidth, 1.0 / viewHeight);
    float centerDepth = centerSample.depth;
    float centerLinearDepth = centerSample.linearDepth;
    float c = centerSample.mask.r;
    if (c > 0.9) return c;

    float lin0 = (centerDepth < 0.9999) ? centerLinearDepth : 128.0;
    float distScale = clamp(28.0 / max(lin0, 1.0), 0.45, 2.1);

    float r1 = 8.0 * distScale;
    float r2 = 20.0 * distScale;
    float r3 = 40.0 * distScale;

    float hot = c * 0.45;
    for (int i = 0; i < 8; i++) {
        vec2 d = getHeatDir(i) * pixel;
        HeatSample s1 = sampleHeat(clamp(coord + d * r1, vec2(0.0), vec2(1.0)));
        HeatSample s2 = sampleHeat(clamp(coord + d * r2, vec2(0.0), vec2(1.0)));
        HeatSample s3 = sampleHeat(clamp(coord + d * r3, vec2(0.0), vec2(1.0)));
        hot = max(hot, s1.mask.r * getHeatOcclusionWeight(centerDepth, centerLinearDepth, s1) * 0.80);
        hot = max(hot, s2.mask.r * getHeatOcclusionWeight(centerDepth, centerLinearDepth, s2) * 0.55);
        hot = max(hot, s3.mask.r * getHeatOcclusionWeight(centerDepth, centerLinearDepth, s3) * 0.35);
    }

    return smoothstep(0.004, 0.34, clamp(hot, 0.0, 1.0));
}

float getGlowField(vec2 coord, HeatSample centerSample) {
    vec2 pixel = vec2(1.0 / viewWidth, 1.0 / viewHeight);
    float centerDepth = centerSample.depth;
    float centerLinearDepth = centerSample.linearDepth;
    float c = centerSample.mask.g;
    float g = c * 0.40;
    for (int i = 0; i < 8; i++) {
        vec2 d = getHeatDir(i) * pixel;
        HeatSample s1 = sampleHeat(clamp(coord + d * 8.0, vec2(0.0), vec2(1.0)));
        HeatSample s2 = sampleHeat(clamp(coord + d * 20.0, vec2(0.0), vec2(1.0)));
        HeatSample s3 = sampleHeat(clamp(coord + d * 36.0, vec2(0.0), vec2(1.0)));
        HeatSample s4 = sampleHeat(clamp(coord + d * 56.0, vec2(0.0), vec2(1.0)));
        g = max(g, s1.mask.g * getHeatOcclusionWeight(centerDepth, centerLinearDepth, s1) * 0.95);
        g = max(g, s2.mask.g * getHeatOcclusionWeight(centerDepth, centerLinearDepth, s2) * 0.78);
        g = max(g, s3.mask.g * getHeatOcclusionWeight(centerDepth, centerLinearDepth, s3) * 0.56);
        g = max(g, s4.mask.g * getHeatOcclusionWeight(centerDepth, centerLinearDepth, s4) * 0.38);
    }
    return clamp(g, 0.0, 1.0);
}
#endif

void main() {
#if ENABLE_HEAT_HAZE > 0
    HeatSample centerSample = sampleHeat(texcoord);
    float heatField = getHeatField(texcoord, centerSample);
    float glowField = getGlowField(texcoord, centerSample);
    heatCacheOut = vec4(heatField, glowField, 0.0, 1.0);
#else
    heatCacheOut = vec4(0.0);
#endif
}
