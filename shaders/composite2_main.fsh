#include "/shader.h"
#include "/common/math.glsl"
#include "/common/depth_utils.glsl"
#include "/common/effect_metadata.glsl"

uniform float viewWidth, viewHeight, aspectRatio;

uniform vec3 cameraPosition, previousCameraPosition, shadowLightPosition;

uniform mat4 gbufferPreviousProjection, gbufferProjectionInverse, gbufferProjection;
uniform mat4 gbufferModelView, gbufferPreviousModelView, gbufferModelViewInverse;

uniform float frameTimeCounter;

uniform sampler2D texture;
uniform sampler2D colortex0;
uniform sampler2D colortex2; // hot-source mask from gbuffers_textured_lit
uniform sampler2D colortex3; // r = cloud mask, g = cloud alpha
uniform sampler2D colortex4; // quarter-res heat cache packed into top-left viewport
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D waterdropstex;

uniform float near;
uniform float far;
uniform int   isEyeInWater;
uniform ivec2 eyeBrightness;
uniform ivec2 eyeBrightnessSmooth;
uniform float rainStrength;
uniform float wetness;
uniform float rainbowWetMemory;
uniform float isCold;
uniform float isWarm;
uniform float timeBrightness; // 1.0 at noon, 0.0 at midnight
uniform float timeAngle;

#include "/common/transformations.fsh"

vec4 sampleComposite2Texture(sampler2D tex, vec2 uv) {
#if __VERSION__ < 130
    return texture2D(tex, uv);
#else
    return texture(tex, uv);
#endif
}

vec4 sampleComposite2ScreenNearest(sampler2D tex, vec2 uv) {
    vec2 texSize = vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));
    vec2 clampedUV = clamp(uv, vec2(0.0), vec2(1.0) - 0.5 / texSize);
    vec2 snappedUV = (floor(clampedUV * texSize) + 0.5) / texSize;
    return sampleComposite2Texture(tex, snappedUV);
}

vec4 sampleComposite2AtlasTexel(sampler2D tex, ivec2 texelCoord, vec2 texSize) {
    vec2 clampedTexel = clamp(vec2(texelCoord), vec2(0.0), texSize - vec2(1.0));
    return sampleComposite2Texture(tex, (clampedTexel + 0.5) / texSize);
}

float getHandMask(vec2 uv) {
    return getDepthHandMask(depthtex1, uv);
}

float getForegroundHandMask(vec2 uv) {
    return decodeEffectHandMask(sampleComposite2ScreenNearest(colortex2, uv).a);
}

#if ENABLE_HEAT_HAZE > 0
vec2 getHeatCacheUV(vec2 uv) {
    vec2 fullRes = vec2(viewWidth, viewHeight);
    vec2 cacheRes = max(floor(fullRes * 0.25), vec2(1.0));
    vec2 cachePixel = clamp(floor(uv * cacheRes), vec2(0.0), cacheRes - 1.0);
    return (cachePixel + 0.5) / fullRes;
}

vec2 sampleHeatCache(vec2 uv) {
    return sampleComposite2Texture(colortex4, getHeatCacheUV(uv)).rg;
}
#endif

#if ENABLE_BLOOM > 0
float getBloomEmissiveFactor(vec3 col) {
    float rOverG = col.r / max(col.g, 0.01);
    float gOverB = col.g / max(col.b, 0.01);
    float rFactor = smoothstep(1.1, 1.55, rOverG);
    float gFactor = smoothstep(1.35, 2.4, gOverB);
    return rFactor * gFactor;
}

vec3 extractBloomSource(vec3 col, vec2 coord) {
    #ifdef THE_END
    if (sampleComposite2Texture(depthtex0, coord).x >= 0.9999) return vec3(0.0);
    #endif

    float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
    float lumaExcess = max(lum - 0.82, 0.0) / 0.18;
    float lumaBloom = lumaExcess * lumaExcess;
    float emissiveBloom = getBloomEmissiveFactor(col) * lum * lum * 0.40;
    float totalBloom = lumaBloom + emissiveBloom;
    if (totalBloom < 0.001) return vec3(0.0);
    if (sampleComposite2Texture(colortex3, coord).r > 0.5) return vec3(0.0);
    return col * totalBloom;
}
#endif

// 6-band posterized spectral color for rainbow
// t: 0 = red (outer edge), 1 = violet (inner edge)
vec3 getRainbowColor(float t) {
    int band = clamp(int(floor(t * 6.0)), 0, 5);
    if (band == 0) return vec3(1.00, 0.08, 0.08); // Red
    if (band == 1) return vec3(1.00, 0.50, 0.00); // Orange
    if (band == 2) return vec3(0.90, 0.90, 0.00); // Yellow
    if (band == 3) return vec3(0.10, 0.80, 0.10); // Green
    if (band == 4) return vec3(0.10, 0.35, 1.00); // Blue
    return             vec3(0.55, 0.00, 0.90);    // Violet
}

vec3 addRainbow(vec3 col, vec2 coord) {
    float preDayFade = smoothstep(0.0, 0.18, timeBrightness);
    float preWarmFactor = clamp(1.0 - isCold, 0.0, 1.0);
    float rainNow = smoothstep(0.04, 0.18, rainStrength);
    float rainMemory = max(wetness, rainbowWetMemory);
    // Post-rain window: rainbow appears after rain and fades as wetness dries.
    float preRainbowStrength = smoothstep(0.08, 0.28, rainMemory) * (1.0 - rainNow);
    if (preRainbowStrength <= 0.0 || preDayFade <= 0.0 || preWarmFactor <= 0.0) return col;

    float depth = sampleComposite2Texture(depthtex0, coord).x;
    vec2  cloudData     = sampleComposite2Texture(colortex3, coord).rg;
    bool  isCloud       = cloudData.r > 0.5;
    float storedAlpha   = cloudData.g;

    // Skip non-cloud solid geometry; clouds get rainbow scaled by their transparency
    if (depth < 0.9999 && !isCloud) return col;
    float rainbowScale = isCloud ? (1.0 - storedAlpha) : 1.0;

    // Reconstruct view direction in world/player space (Y = world up)
    vec2 ndc = coord * 2.0 - 1.0;
    vec4 vDir4 = gbufferProjectionInverse * vec4(ndc, 1.0, 1.0);
    vec3 viewDirWorld = normalize(mat3(gbufferModelViewInverse) * normalize(vDir4.xyz / vDir4.w));

    // Clip below the horizon so the lower half of the circle stays underground
    if (viewDirWorld.y < -0.05) return col;

    // Rainbow side logic:
    // one fixed side before noon, mirrored fixed side after noon.
    // Around noon, blend side smoothly and dim intensity so no visible teleport.
    vec3 morningCenter = normalize(vec3(-1.0, -0.18, 0.0));
    vec3 afternoonCenter = normalize(vec3(1.0, -0.18, 0.0));
    float noonSideBlend = smoothstep(NOON - 0.03, NOON + 0.03, timeAngle);
    vec3 rainbowCenter = normalize(mix(morningCenter, afternoonCenter, noonSideBlend));
    float noonVisibility = smoothstep(0.0, 0.06, abs(timeAngle - NOON));

    // Fade rainbow out in cold/snow biomes. isCold is already smoothed by
    // shaders.properties (smooth(..., 10, 10)), so the transition is gradual
    // — same mechanism as the aurora. isCold can sum above 1.0, so clamp.
    float warmFactor = clamp(1.0 - isCold, 0.0, 1.0);

    // Arc-local coordinate frame in world space
    vec3 sideAxis  = normalize(cross(vec3(0.0, 1.0, 0.0), rainbowCenter));
    vec3 arcUpAxis = cross(rainbowCenter, sideAxis);

    // Perspective-project view direction onto a plane facing the rainbow center.
    // Equivalent to aurora's "wpos.xz /= wpos.y" — gives world-space 2D coords
    // that are FIXED IN THE SKY and don't swim when the camera rotates.
    float fwd = dot(viewDirWorld, rainbowCenter);
    if (fwd < 0.05) return col; // looking away from rainbow
    vec2 arcCoord = vec2(dot(viewDirWorld, sideAxis),
                         dot(viewDirWorld, arcUpAxis)) / fwd;

    const float CENTER = 39.0;
    const float HALFW  = 9.5;
    const float INNER  = CENTER - HALFW;
    const float OUTER  = CENTER + HALFW;

    // Aurora-style loop: 4 layers at different world-space grid scales.
    // Finer grids look "closer", coarser look "farther" → volumetric depth.
    const int LAYERS   = 4;
    const int LAYERS_P = LAYERS + 2; // same dither pattern as getAurora.fsh

    float dither  = bayer4(gl_FragCoord.xy * 0.5);
    float ditherM = dither + 1.0;
    vec3  rainbow = vec3(0.0);
    float rainbowAnimate = frameTimeCounter * 0.018;
    // Coherent breathing for the whole arc (smooth and clearly visible).
    float breatheA = 0.76 + 0.24 * (0.5 + 0.5 * sin(rainbowAnimate * 2.05));
    float breatheB = 0.90 + 0.10 * sin(rainbowAnimate * 1.11 + 1.4);
    float rainbowBreath = breatheA * breatheB;

    for (int i = 0; i < LAYERS; i++) {
        float f       = float(i);
        float current = pow2((f + ditherM) / float(LAYERS_P));

        // Each layer quantizes the 2-D world-space arc coordinates to a
        // different grid size. Because arcCoord is in world space (not screen
        // space), the resulting blocks are FIXED ON THE SKY like a texture —
        // they don't move or shimmer when you look around.
        float gridScale = 15.0 + f * 3.5; // smaller cells -> denser pixel grid
        float layerPhase = f * 1.37;
        vec2 arcDrift = vec2(
            sin(rainbowAnimate * (0.55 + f * 0.08) + layerPhase),
            cos(rainbowAnimate * (0.47 + f * 0.06) - layerPhase)
        ) * (0.012 + 0.004 * f);
        vec2 arcBlock   = floor((arcCoord + arcDrift) * gridScale) / gridScale;

        // Reconstruct the block-centre's angular distance from the arc centre
        vec3  blockDir   = normalize(arcBlock.x * sideAxis + arcBlock.y * arcUpAxis + rainbowCenter);
        float cosBlock   = clamp(dot(blockDir, rainbowCenter), -1.0, 1.0);
        float blockAngle = degrees(acos(cosBlock));

        float dist = abs(blockAngle - CENTER);
        if (dist > HALFW) continue;

        float layerFade = smoothstep(HALFW, HALFW * 0.65, dist);

        // Color from the block's angular position (outer = red, inner = violet)
        float t = clamp(1.0 - (blockAngle - INNER) / (OUTER - INNER), 0.0, 1.0);
        vec3  layerCol = getRainbowColor(t);
        // Per-block brightness variation (hash from world-space block position)
        // Makes individual blocks visually distinct — the "pixel art texture" look
        float blockHash = fract(sin(dot(arcBlock, vec2(12.9898, 78.233))) * 43758.5453);
        float blockPulse = 0.94 + 0.06 * sin(rainbowAnimate * 0.9 + blockHash * 6.28318530718 + f * 1.6);
        float blockCut = 0.92 + 0.08 * step(0.13, blockHash);
        float neonCore = 0.56 + 0.16 * pow(layerFade, 0.70);
        float blockBright = (0.46 + blockHash * 0.18) * blockPulse * blockCut * neonCore;
        // Smooth traveling wave along the arc, plus global breathing.
        float arcWave = 0.86 + 0.24 * (0.5 + 0.5 * sin(
            rainbowAnimate * (2.6 + f * 0.2) + arcBlock.x * 18.0 + arcBlock.y * 11.0
        ));
        blockBright *= arcWave * rainbowBreath;

        rainbow += layerCol * layerFade * blockBright * (1.0 - current);
        rainbow += layerCol * pow(layerFade, 2.0) * 0.026 * (1.0 - current);
    }

    rainbow /= float(LAYERS);
    rainbow = rainbow / (1.0 + rainbow * 0.35);

    float horizonFade = smoothstep(-0.05, 0.12, viewDirWorld.y);
    float dayFade = smoothstep(0.0, 0.18, timeBrightness); // fades out near sunset/sunrise

    // Post-rain visibility comes from wetness memory (and custom fallback memory),
    // while active rain suppresses the rainbow via rainNow above.
    float rainbowStrength = preRainbowStrength * noonVisibility;
    vec3 rainbowFx = rainbow * horizonFade * rainbowStrength * warmFactor * dayFade * rainbowScale * 1.28;
    // Transparent, clean composite: keep color hue and avoid hard boosting.
    float sceneLum = clamp(luma(col), 0.0, 1.0);
    rainbowFx *= (0.98 - 0.22 * sceneLum);
    return col + rainbowFx;
}

varying vec4 color;
varying vec2 texcoord;
varying vec2 lightPos;

#define fragColor gl_FragData[0]
#define fragColor1 gl_FragData[1]

float getNoise(vec2 pos) {
  float noise = fract(sin(dot(pos, vec2(18.9898f,28.633f))) * 4378.5453f);
	return noise;
}

vec2 getHeatDiag(int index) {
    if (index == 0) return vec2(0.7071, 0.7071);
    if (index == 1) return vec2(-0.7071, 0.7071);
    if (index == 2) return vec2(0.7071, -0.7071);
    return vec2(-0.7071, -0.7071);
}

vec2 getHeatAxial(int index) {
    if (index == 0) return vec2(1.0, 0.0);
    if (index == 1) return vec2(-1.0, 0.0);
    if (index == 2) return vec2(0.0, 1.0);
    return vec2(0.0, -1.0);
}

vec3 calcRays(vec3 color) {
    float land = 1.0 - near / far / far;
    float raysIntensity = 0.2;
    vec2 viewRes = vec2(viewWidth, viewHeight);
    vec2 invViewRes = 1.0 / viewRes;

    vec2 pixelBlockSize   = vec2(8.0, 8.0);
    vec2 pixelPos         = floor(gl_FragCoord.xy / pixelBlockSize) * pixelBlockSize;
    vec2 snappedTexcoord  = pixelPos * invViewRes;
    vec2 snappedLightPos  = floor(lightPos * viewRes / pixelBlockSize) * pixelBlockSize * invViewRes;
    vec2 deltatexcoord    = (snappedLightPos - snappedTexcoord) * 0.04;
    vec2 noisetc          = snappedTexcoord + deltatexcoord * getNoise(snappedTexcoord);

    float gr = 1.0;
    for (int i = 0; i < 20; i++) {
        vec2 samplePixel = floor((noisetc * viewRes) / pixelBlockSize) * pixelBlockSize;
        vec2 sampleCoord = clamp(samplePixel * invViewRes, 0.0, 1.0);
        float depth0     = sampleComposite2Texture(depthtex0, sampleCoord).x;
        float cloudOcc   = sampleComposite2Texture(colortex3, sampleCoord).r;
        noisetc += deltatexcoord;
        gr += step(land, depth0) * (1.0 - cloudOcc) * cdist(noisetc);
    }
    gr /= 20.0;

    // Godrays disappear during rain — sun is hidden behind overcast sky
    vec3 raysEffect = color * (gr * raysIntensity) * (1.0 - isEyeInWater) * (1.0 - rainStrength * 0.92);

    return (color + raysEffect) / 1.0;
}

// ---------------------------------------------------------------------------
// Heat haze around hot blocks (lava/fire):
// screen-space refraction with a soft radius and dithered turbulence.
// ---------------------------------------------------------------------------
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
    vec4 heatMask = sampleComposite2Texture(colortex2, uv);
    sample.depth = sampleComposite2Texture(depthtex0, uv).r;
    sample.linearDepth = (sample.depth < 0.9999) ? linearizeDepthValue(sample.depth, near, far) : 0.0;
    float fade = (sample.depth < 0.9999) ? getHeatDistanceFade(sample.linearDepth) : 0.0;
    sample.mask = heatMask.rg * fade;
    return sample;
}

float getHeatOcclusionWeight(float centerDepth, float centerLinearDepth, float sampleDepth, float sampleLinearDepth) {
    if (centerDepth >= 0.9999) return 1.0;
    if (sampleDepth >= 0.9999) return 0.0;
    float depthTolerance = mix(1.2, 8.0, smoothstep(6.0, 72.0, centerLinearDepth));
    float behindDelta = sampleLinearDepth - centerLinearDepth;
    return 1.0 - smoothstep(depthTolerance, depthTolerance * 2.6, behindDelta);
}

float getHeatOcclusionWeight(float centerDepth, float centerLinearDepth, HeatSample sample) {
    return getHeatOcclusionWeight(centerDepth, centerLinearDepth, sample.depth, sample.linearDepth);
}

vec3 sampleHeatColor(vec2 uv, float centerDepth, float centerLinearDepth) {
    HeatSample sample = sampleHeat(uv);
    float m = sample.mask.g * getHeatOcclusionWeight(centerDepth, centerLinearDepth, sample);
    return sampleComposite2Texture(texture, uv).rgb * m;
}

vec3 sampleScenePixel(vec2 uv, vec3 centerColor, float centerDepth, float centerLinearDepth) {
    vec2 res = vec2(viewWidth, viewHeight);
    vec2 p = floor(clamp(uv, vec2(0.0), vec2(1.0)) * res);
    vec2 suv = (p + 0.5) / res;
    float sampleDepth = sampleComposite2Texture(depthtex0, suv).r;
    float sampleLinearDepth = (sampleDepth < 0.9999) ? linearizeDepthValue(sampleDepth, near, far) : 0.0;
    float occ = getHeatOcclusionWeight(centerDepth, centerLinearDepth, sampleDepth, sampleLinearDepth);
    vec3 sampleColor = sampleComposite2Texture(texture, suv).rgb;
    return mix(centerColor, sampleColor, occ);
}

vec3 addHeatGlow(vec3 col, vec2 coord) {
    if (max(getHandMask(coord), getForegroundHandMask(coord)) > 0.5) return col;

    vec2 pixel = 1.0 / vec2(viewWidth, viewHeight);
    HeatSample centerSample = sampleHeat(coord);
    float centerDepth = centerSample.depth;
    float centerLinearDepth = centerSample.linearDepth;
    float source = centerSample.mask.g;
    float heat = sampleHeatCache(coord).g;
    float glowMask = smoothstep(0.001, 0.38, max(heat, source));
    if (glowMask < 0.01) return col;

    // Strong distance clamp: local glow should not smear into distant copies.
    float lin = (centerDepth < 0.9999) ? centerLinearDepth : 128.0;
    float nearFadeRaw = 1.0 - smoothstep(10.0, 42.0, lin);
    // Pixel/dither distance fade (no smooth noisy tail).
    float dDist = bayer4(gl_FragCoord.xy / 2.0);
    const float DIST_LEVELS = 4.0;
    float nearFade = floor(nearFadeRaw * DIST_LEVELS + dDist) / DIST_LEVELS;
    glowMask *= nearFade;
    if (glowMask < 0.08) return col;

    // X-shaped streaks first (diagonals), then a faint round halo.
    float dither = bayer4(gl_FragCoord.xy / 2.0) - 0.5;
    float r1 = 5.0 + dither * 0.9;
    float r2 = 14.0 + dither * 1.5;
    float r3 = 26.0 + dither * 2.1;
    float r4 = 42.0 + dither * 2.8;

    // Radius shrinks with distance so far sources don't produce huge streaks.
    float rMul = mix(0.55, 1.0, nearFade);
    r1 *= rMul; r2 *= rMul; r3 *= rMul; r4 *= rMul;

    vec3 glowX = vec3(0.0);
    float wX = 0.0;
    for (int i = 0; i < 4; i++) {
        vec2 d = getHeatDiag(i) * pixel;
        vec2 p1 = clamp(coord + d * r1, vec2(0.0), vec2(1.0));
        vec2 p2 = clamp(coord + d * r2, vec2(0.0), vec2(1.0));
        vec2 p3 = clamp(coord + d * r3, vec2(0.0), vec2(1.0));
        vec2 p4 = clamp(coord + d * r4, vec2(0.0), vec2(1.0));
        glowX += sampleHeatColor(p1, centerDepth, centerLinearDepth) * 0.36; wX += 0.36;
        glowX += sampleHeatColor(p2, centerDepth, centerLinearDepth) * 0.28; wX += 0.28;
        glowX += sampleHeatColor(p3, centerDepth, centerLinearDepth) * 0.21; wX += 0.21;
        glowX += sampleHeatColor(p4, centerDepth, centerLinearDepth) * 0.14; wX += 0.14;
    }
    glowX /= max(wX, 0.001);

    vec3 glowH = vec3(0.0);
    float wH = 0.0;
    for (int i = 0; i < 4; i++) {
        vec2 d = getHeatAxial(i) * pixel;
        vec2 p1 = clamp(coord + d * (r1 * 0.85), vec2(0.0), vec2(1.0));
        vec2 p2 = clamp(coord + d * (r2 * 0.85), vec2(0.0), vec2(1.0));
        glowH += sampleHeatColor(p1, centerDepth, centerLinearDepth) * 0.18; wH += 0.18;
        glowH += sampleHeatColor(p2, centerDepth, centerLinearDepth) * 0.12; wH += 0.12;
    }
    glowH /= max(wH, 0.001);

    vec3 glow = mix(glowH, glowX, 0.72);
    // Warm tint so glow reads as emissive heat, not random yellow pixels.
    glow *= vec3(1.06, 0.94, 0.80);

    float coreBoost = smoothstep(0.05, 0.78, source) * nearFade;
    float d = bayer4(gl_FragCoord.xy / 2.0);
    // Dither the intensity term (like bloom), not the RGB itself.
    float strength = (2.20 + 2.60 * glowMask + 1.80 * coreBoost);
    float sQ = floor(strength * 4.0 + d) / 4.0;
    vec3 centerScene = sampleComposite2Texture(texture, coord).rgb;
    vec3 localCore = centerScene * source * (2.2 + 2.4 * coreBoost);
    return col + glow * sQ + localCore;
}

vec3 addHeatHaze(vec3 col, vec2 coord) {
    if (max(getHandMask(coord), getForegroundHandMask(coord)) > 0.5) return col;

    vec2 res = vec2(viewWidth, viewHeight);
    // Return to strict pixel haze (no smooth layer leaking through).
    const float HAZE_PIXEL = 4.0;
    vec2 cell = floor(gl_FragCoord.xy / HAZE_PIXEL);
    vec2 cellUV = (cell * HAZE_PIXEL + HAZE_PIXEL * 0.5) / res;

    HeatSample centerSample = sampleHeat(cellUV);
    float centerDepth = centerSample.depth;
    float centerLinearDepth = centerSample.linearDepth;
    float source = centerSample.mask.r;
    float heat = sampleHeatCache(cellUV).r;
    float maskRaw = clamp(max(smoothstep(0.012, 0.64, heat), smoothstep(0.08, 0.84, source) * 0.30), 0.0, 1.0);
    if (maskRaw < 0.01) return col;

    // Distance attenuation (close wider/stronger, far weaker).
    float lin = (centerDepth < 0.9999) ? centerLinearDepth : 128.0;
    float nearBoost = clamp(1.0 - smoothstep(14.0, 72.0, lin), 0.0, 1.0);
    maskRaw *= mix(0.35, 1.20, nearBoost);
    maskRaw = clamp(maskRaw, 0.0, 1.0);

    // Pure quantization (no dither) to keep effect hard-pixel.
    const float MASK_LEVELS = 4.0;
    float maskQ = floor(maskRaw * MASK_LEVELS + 0.5) / MASK_LEVELS;
    if (maskQ <= 0.0) return col;

    float t = floor(frameTimeCounter * 14.0) / 14.0;
    float vx = sin(cell.y * 0.27 + t * 1.55);
    float vy = sin(cell.x * 0.21 - t * 1.18);
    vec2 v = normalize(vec2(vy, vx) + vec2(0.0001, 0.0));
    float angle = atan(v.y, v.x);
    float oct = floor((angle + PI) / (PI * 0.25) + 0.5);
    float qAng = oct * (PI * 0.25) - PI;
    vec2 dir = vec2(cos(qAng), sin(qAng));

    float ampPx = floor(mix(2.0, 10.0, maskQ) * mix(0.75, 1.24, nearBoost) + 0.5);
    vec2 offUV = (dir * ampPx) / res;

    // Preserve already-applied effects from current chain (godrays, etc.).
    vec3 basePix = col;
    vec3 centerScene = sampleComposite2Texture(texture, cellUV).rgb;
    vec3 deformedPix = (
        sampleScenePixel(cellUV + offUV, centerScene, centerDepth, centerLinearDepth) +
        sampleScenePixel(cellUV - offUV * 0.35, centerScene, centerDepth, centerLinearDepth) +
        sampleScenePixel(cellUV + vec2(-offUV.y, offUV.x) * 0.25, centerScene, centerDepth, centerLinearDepth)
    ) / 3.0;

    return mix(basePix, deformedPix, maskQ);
}
#endif

// ---------------------------------------------------------------------------
// Shooting stars — projected onto the screen as a snapped pixel trail instead
// of matching quantized sky directions. This keeps the star itself perfectly
// pixelated without inheriting odd cuts from the underlying sky geometry.
// ---------------------------------------------------------------------------
#if ENABLE_SHOOTING_STARS > 0
bool projectSkyDirection(vec3 worldDir, out vec2 uv) {
    vec3 viewDir = normalize(mat3(gbufferModelView) * worldDir);
    if (viewDir.z >= -0.001) return false;

    vec4 clipPos = gbufferProjection * vec4(viewDir * 256.0, 1.0);
    if (clipPos.w <= 0.0) return false;

    uv = clipPos.xy / clipPos.w * 0.5 + 0.5;
    return all(greaterThanEqual(uv, vec2(-0.15))) && all(lessThanEqual(uv, vec2(1.15)));
}

vec2 snapStarBlock(vec2 uv, float blockSize, vec2 viewRes) {
    return floor(clamp(uv, vec2(0.0), vec2(1.0)) * viewRes / blockSize) + 0.5;
}

float pixelTrailMask(vec2 blockCoord, vec2 blockA, vec2 blockB, float halfWidth) {
    vec2 seg = blockB - blockA;
    float segLen2 = dot(seg, seg);
    vec2 closest = blockA;
    if (segLen2 > 0.0001) {
        float h = clamp(dot(blockCoord - blockA, seg) / segLen2, 0.0, 1.0);
        closest = blockA + seg * h;
    }

    vec2 delta = abs(blockCoord - closest);
    float cheb = max(delta.x, delta.y);
    const float softness = 0.18;
    return 1.0 - smoothstep(max(halfWidth - softness, 0.0), halfWidth + softness, cheb);
}

float pixelPointMask(vec2 blockCoord, vec2 pointCoord, float radius) {
    vec2 delta = abs(blockCoord - pointCoord);
    float cheb = max(delta.x, delta.y);
    float softness = radius > 0.7 ? 0.18 : 0.12;
    return 1.0 - smoothstep(max(radius - softness, 0.0), radius + softness, cheb);
}

vec3 addShootingStars(vec3 col, vec2 coord) {
    #if defined(THE_END) || defined(THE_NETHER)
    return col;
    #endif

    float nightStrength = clamp(1.0 - timeBrightness * 5.0, 0.0, 1.0);
    if (nightStrength < 0.01) return col;

    float depth = sampleComposite2Texture(depthtex0, coord).x;
    vec2 cloudData = sampleComposite2Texture(colortex3, coord).rg;
    bool isCloud = cloudData.r > 0.5;
    float storedAlpha = cloudData.g;
    if (depth < 0.9999 && !isCloud) return col;         // solid geometry in front
    float cloudScale = isCloud ? (1.0 - storedAlpha) : 1.0;
    if (cloudScale <= 0.001) return col;

    // Safe baseline fade with normal fade-out edges.
    const float PERIOD = 55.0;
    const float DURATION = 1.6;
    float t = mod(frameTimeCounter, PERIOD);
    float fadeIn = smoothstep(0.0, 0.15, t);
    float fadeOut = 1.0 - smoothstep(DURATION - 0.15, DURATION, t);
    float visible = fadeIn * fadeOut;
    if (visible < 0.01) return col;

    // Star travels along a fixed world-space arc seeded by the period index.
    float seed       = floor(frameTimeCounter / PERIOD);
    float startPhi   = fract(sin(seed * 127.1) * 43758.5453) * 6.28318;
    float startTheta = 0.45 + fract(sin(seed * 311.7) * 43758.5453) * 0.4; // 0.45..0.85 rad from zenith
    float travelArc  = (fract(sin(seed * 74.3) * 43758.5453) - 0.5) * 1.2;
    float phase      = t / DURATION;

    vec2 viewRes = vec2(viewWidth, viewHeight);
    const float BLOCK = 4.0;
    vec2 blockCoord = floor(coord * viewRes / BLOCK) + 0.5;

    const int MAIN_TRAIL = 10;
    const float MAIN_SEGMENT_STEP = 0.13;
    const int EXT_TRAIL = 16;
    const float EXT_SEGMENT_STEP = 0.0145;
    const int TOTAL_TRAIL = MAIN_TRAIL + EXT_TRAIL;
    vec3 result = vec3(0.0);
    vec2 prevBlock = vec2(0.0);
    bool hasPrev = false;

    for (int s = 0; s < TOTAL_TRAIL; s++) {
        float segmentIndex = float(s);
        bool isExtension = s >= MAIN_TRAIL;
        int extIndex = s - MAIN_TRAIL;
        float backNorm = isExtension
            ? float(extIndex) / float(max(EXT_TRAIL - 1, 1))
            : float(s) / float(max(MAIN_TRAIL - 1, 1));
        float totalNorm = segmentIndex / float(TOTAL_TRAIL - 1);

        float segPhase = isExtension
            ? phase - MAIN_SEGMENT_STEP - float(extIndex) * EXT_SEGMENT_STEP
            : phase - backNorm * MAIN_SEGMENT_STEP;

        if (segPhase < 0.0) break;

        float segPhi   = startPhi   + travelArc * segPhase;
        float segTheta = startTheta + 0.31       * segPhase;
        vec3 segDir = normalize(vec3(
            sin(segTheta) * cos(segPhi),
            cos(segTheta),
            sin(segTheta) * sin(segPhi)
        ));

        if (segDir.y < 0.05) continue;

        vec2 segUV;
        if (!projectSkyDirection(segDir, segUV)) {
            hasPrev = false;
            continue;
        }

        if (any(lessThan(segUV, vec2(0.0))) || any(greaterThan(segUV, vec2(1.0)))) {
            hasPrev = false;
            continue;
        }

        vec2 segBlock = snapStarBlock(segUV, BLOCK, viewRes);
        float tailFade = isExtension
            ? pow(1.0 - backNorm, 1.35)
            : (1.0 - backNorm);
        float pointMask = (!isExtension && s == 0) ? pixelPointMask(blockCoord, segBlock, 0.90) : 0.0;
        float segmentMask = 0.0;

        if (hasPrev) {
            float halfWidth = mix(0.56, 0.16, smoothstep(0.28, 1.0, totalNorm));
            segmentMask = pixelTrailMask(blockCoord, prevBlock, segBlock, halfWidth);
        }

        float starMask = max(pointMask, segmentMask);
        if (starMask > 0.0) {
            vec3 headTint      = vec3(1.00, 0.86, 0.10);
            vec3 tailStartTint = vec3(1.00, 0.90, 0.26);
            vec3 seamTint      = vec3(0.92, 0.88, 0.56);
            vec3 trailTint     = vec3(0.74, 0.84, 1.00);

            vec3 tint = mix(tailStartTint, seamTint, smoothstep(0.16, 0.52, totalNorm));
            tint = mix(tint, trailTint, smoothstep(0.42, 1.0, totalNorm));
            if (s == 0) tint = headTint;

            float intensity = mix(1.0, 0.03, pow(totalNorm, 0.82));

            if (s == 0) {
                intensity = 1.20;
            } else {
                intensity *= mix(1.00, 0.86, smoothstep(0.45, 1.0, totalNorm));
            }

            result += tint * intensity * starMask;
        }

        prevBlock = segBlock;
        hasPrev = true;
    }

    result = min(result, vec3(1.35));
    return col + result * visible * nightStrength * cloudScale * 1.16;
}
#endif

// ---------------------------------------------------------------------------
// Lens flare — pixel-art ghost orbs along the lens axis.
// Architecture mirrors Complementary Reimagined (BaseLens / PointLens style)
// but all coordinates are snapped to a 4-pixel block grid before distance
// computation, so the orb edges look hard and blocky.
//
// lightPos convention (like Complementary): sun offset from screen centre in
// [-0.5, 0.5].  dist < 0 → ghost near the sun; dist > 0 → ghost past centre.
//
// Occlusion: 8 depth samples around the sun position — if geometry covers the
// sun (indoors, underground) the flare fades to zero.
// ---------------------------------------------------------------------------
#if ENABLE_LENS_FLARE > 0
vec2 getLensOcclusionOffset(int index) {
    if (index == 0) return vec2(1.0, 0.0);
    if (index == 1) return vec2(-1.0, 1.0);
    if (index == 2) return vec2(0.0, 1.0);
    return vec2(1.0, 1.0);
}

vec3 lensSpectrum(float t) {
    return clamp(vec3(
        0.55 + 0.45 * cos(6.28318 * (t + 0.000)),
        0.55 + 0.45 * cos(6.28318 * (t + 0.333)),
        0.55 + 0.45 * cos(6.28318 * (t + 0.667))
    ), 0.0, 1.0);
}

// Hollow iridescent ring. whiteness=0 → full spectrum; whiteness=1 → white.
// thickness is fraction of radius → pixel-snapped ring band.
vec3 pixelRing(vec2 lightPos, vec2 bc, float radius, float thickness, float dist, float phase, float whiteness) {
    vec2  lc   = ((bc - 0.5) + lightPos * dist) * vec2(aspectRatio, 1.0);
    float d    = length(lc) / radius;
    float ring = smoothstep(thickness, 0.0, abs(d - 1.0));
    if (ring < 0.001) return vec3(0.0);
    float angle = atan(lc.y, lc.x) * 0.15915 + 0.5; // → 0..1
    vec3  c     = mix(lensSpectrum(angle + phase), vec3(1.0), whiteness);
    return c * ring;
}

// Soft single-color blob: bright at centre, fades quickly to transparent at edge.
float pixelBlob(vec2 lightPos, vec2 bc, float size, float dist) {
    vec2  lc = ((bc - 0.5) + lightPos * dist) * vec2(aspectRatio, 1.0);
    float d  = length(lc) / size;
    if (d >= 1.0) return 0.0;
    float inv = 1.0 - d;
    return inv * inv * inv; // cubic: nearly invisible past ~70% of radius
}

// Thin pixel streak along the lens axis (sun → screen centre → beyond).
vec3 pixelStreak(vec2 lightPos, vec2 bc) {
    vec2  axisDir  = -normalize(lightPos * vec2(aspectRatio, 1.0)); // unit vec sun→centre
    vec2  lc       = ((bc - 0.5) - lightPos) * vec2(aspectRatio, 1.0); // coord from sun
    float along    = dot(lc, axisDir);                     // signed dist along axis
    float perp     = abs(dot(lc, vec2(-axisDir.y, axisDir.x))); // off-axis dist
    float sunLen   = length(lightPos * vec2(aspectRatio, 1.0));

    float crossFade = smoothstep(0.010, 0.003, perp);      // very thin band
    float axialFade = smoothstep(-0.02, 0.06, along)        // starts at sun
                    * smoothstep(1.30, 0.55, along);         // fades past centre

    float t = clamp(along / max(sunLen, 0.001), 0.0, 1.0);
    vec3  c = mix(vec3(1.1, 1.0, 0.85), lensSpectrum(t * 0.35 + 0.05), t * 0.45);
    return c * crossFade * axialFade;
}

// 6-ray starburst centred on the sun. White near center, spectrum at tips.
vec3 pixelStarburst(vec2 lightPos, vec2 bc, float maxRadius) {
    vec2  lc = ((bc - 0.5) - lightPos) * vec2(aspectRatio, 1.0);
    float r  = length(lc);
    if (r < 0.002 || r > maxRadius) return vec3(0.0);

    float angle    = atan(lc.y, lc.x);
    float rayStep  = 3.14159265 / 6.0;
    float sector   = mod(angle + 3.14159265, rayStep) / rayStep;
    float angDist  = min(sector, 1.0 - sector);

    float spike    = smoothstep(0.07, 0.0, angDist);
    float invRad   = 1.0 - r / maxRadius;
    float radFade  = invRad * invRad;
    float t        = r / maxRadius;
    // White at base, spectrum at tips
    vec3  c        = mix(vec3(1.0), lensSpectrum(angle * 0.15915 * 0.5 + t * 0.4), t * 0.8);

    return c * spike * radFade;
}

vec3 addLensFlare(vec3 col, vec2 coord) {
    float dayStrength = smoothstep(0.0, 0.15, timeBrightness);
    if (dayStrength < 0.01) return col;

    vec3 sunViewDir = normalize(shadowLightPosition);
    if (sunViewDir.z > 0.0) return col;

    vec4 sunClip  = gbufferProjection * vec4(sunViewDir * 1000.0, 1.0);
    vec2 lightPos = sunClip.xy / sunClip.w * 0.5; // sun in [-0.5, 0.5]
    vec2 sunUV    = lightPos + 0.5;                // sun in [0, 1]

    if (any(lessThan(sunUV, vec2(-0.3))) || any(greaterThan(sunUV, vec2(1.3)))) return col;

    // ---- Occlusion: 8 fixed depth samples around the sun ----
    // Checks both solid geometry (depthtex0) and composite-rendered clouds (colortex3.r).
    float flareFactor = 1.0;
    vec2 cScale = 40.0 / vec2(viewWidth, viewHeight);
    for (int i = 0; i < 4; i++) {
        vec2 off = getLensOcclusionOffset(i) * cScale;
        vec2 uvP = clamp(sunUV + off, 0.0, 1.0);
        vec2 uvN = clamp(sunUV - off, 0.0, 1.0);
        if (sampleComposite2Texture(depthtex0, uvP).r < 0.9999 || sampleComposite2Texture(colortex3, uvP).r > 0.5) flareFactor -= 0.125;
        if (sampleComposite2Texture(depthtex0, uvN).r < 0.9999 || sampleComposite2Texture(colortex3, uvN).r > 0.5) flareFactor -= 0.125;
    }
    if (flareFactor < 0.01) return col;

    float sunDist = length(lightPos * vec2(aspectRatio, 1.0));
    float sunDistClamped = clamp(sunDist * 8.0, 0.0, 1.0);
    flareFactor  *= (sunDistClamped * sunDistClamped) - clamp(sunDist * 3.0 - 1.5, 0.0, 1.0);
    // Lens flare nearly gone in rain — overcast sky blocks direct sun
    flareFactor  *= dayStrength * (1.0 - rainStrength * 0.96);
    if (flareFactor < 0.005) return col;

    // Snap to 8-pixel block grid → hard, visible pixelization on ring edges
    const float BLOCK = 8.0;
    vec2 viewRes = vec2(viewWidth, viewHeight);
    vec2 bc = (floor(coord * viewRes / BLOCK) + 0.5) * BLOCK / viewRes;

    vec3 flare = vec3(0.0);

    // ---- Starburst at sun (6-point, white center → spectrum tips) ----
    flare += pixelStarburst(lightPos, bc, 0.28) * 0.60;

    // ---- Streak along lens axis ----
    flare += pixelStreak(lightPos, bc) * 0.55;

    // ---- Soft white haze blobs — barely visible ----
    flare += pixelBlob(lightPos, bc, 0.20, -0.30) * vec3(1.0) * 0.06;
    flare += pixelBlob(lightPos, bc, 0.14,  0.35) * vec3(1.0) * 0.05;
    flare += pixelBlob(lightPos, bc, 0.10,  0.72) * vec3(1.0) * 0.04;
    flare += pixelBlob(lightPos, bc, 0.08,  1.05) * vec3(1.0) * 0.03;

    // ---- White blobs — same fade as colored blobs ----
    flare += pixelBlob(lightPos, bc, 0.18, -0.48) * vec3(1.0) * 0.30;
    flare += pixelBlob(lightPos, bc, 0.16,  0.18) * vec3(1.0) * 0.28;
    flare += pixelBlob(lightPos, bc, 0.18,  0.40) * vec3(1.0) * 0.28;
    flare += pixelBlob(lightPos, bc, 0.16,  0.58) * vec3(1.0) * 0.30;
    flare += pixelBlob(lightPos, bc, 0.18,  0.78) * vec3(1.0) * 0.28;
    flare += pixelBlob(lightPos, bc, 0.16,  0.98) * vec3(1.0) * 0.30;

    // ---- Medium rings — white, barely visible ----
    flare += pixelRing(lightPos, bc, 0.07, 0.12, -0.62, 0.10, 1.0) * 0.12;
    flare += pixelRing(lightPos, bc, 0.06, 0.12, -0.42, 0.45, 1.0) * 0.10;
    flare += pixelRing(lightPos, bc, 0.08, 0.12,  0.47, 0.20, 1.0) * 0.12;
    flare += pixelRing(lightPos, bc, 0.06, 0.12,  0.65, 0.70, 1.0) * 0.10;
    flare += pixelRing(lightPos, bc, 0.07, 0.12,  0.74, 0.88, 1.0) * 0.12;
    flare += pixelRing(lightPos, bc, 0.05, 0.12,  1.08, 0.30, 1.0) * 0.09;

    // ---- Tiny accent rings — white, barely visible ----
    flare += pixelRing(lightPos, bc, 0.035, 0.18,  0.30, 0.62, 1.0) * 0.10;
    flare += pixelRing(lightPos, bc, 0.030, 0.18,  0.54, 0.27, 1.0) * 0.09;
    flare += pixelRing(lightPos, bc, 0.035, 0.18,  0.85, 0.92, 1.0) * 0.10;
    flare += pixelRing(lightPos, bc, 0.025, 0.18,  1.18, 0.05, 1.0) * 0.08;

    return col + flare * flareFactor * 0.55;
}
#endif

#if ENABLE_RAIN_DROPS > 0
struct RainDropLayerSample {
    vec2 offset;
    float offsetWeight;
    float wetMask;
    float lensMask;
    float bodyMask;
    float trailMask;
    float highlight;
};

RainDropLayerSample makeRainDropLayerSample() {
    RainDropLayerSample sample;
    sample.offset = vec2(0.0);
    sample.offsetWeight = 0.0;
    sample.wetMask = 0.0;
    sample.lensMask = 0.0;
    sample.bodyMask = 0.0;
    sample.trailMask = 0.0;
    sample.highlight = 0.0;
    return sample;
}

vec2 hash22(vec2 p) {
    return fract(sin(vec2(
        dot(p, vec2(127.1, 311.7)),
        dot(p, vec2(269.5, 183.3))
    )) * 43758.5453);
}

const float RAIN_DROP_BLOCK = 8.0;
const vec2 RAIN_DROP_ATLAS_SIZE = vec2(54.0, 18.0);
const vec2 RAIN_DROP_TILE_SIZE = vec2(18.0, 18.0);

vec2 getRainDropSubpixel(int index) {
    if (index == 0) return vec2(-0.28, -0.28);
    if (index == 1) return vec2(0.28, -0.28);
    if (index == 2) return vec2(-0.28, 0.28);
    return vec2(0.28, 0.28);
}

vec2 snapRainDropUV(vec2 uv, vec2 viewRes) {
    return (floor(clamp(uv, vec2(0.0), vec2(1.0)) * viewRes / RAIN_DROP_BLOCK) + 0.5) * RAIN_DROP_BLOCK / viewRes;
}

float quantizeRainCoverage(float v) {
    return floor(clamp(v, 0.0, 1.0) * 4.0 + 0.5) * 0.25;
}

vec2 getRainDropSpriteAnchor() {
    return vec2(RAIN_DROP_TILE_SIZE.x * 0.5, RAIN_DROP_TILE_SIZE.y * 0.58);
}

ivec2 getRainDropSpriteTexelCoord(vec2 localBlocks, vec2 offset) {
    vec2 anchor = getRainDropSpriteAnchor();
    return ivec2(floor(localBlocks + offset + anchor + 0.5));
}

vec4 sampleRainDropSpriteTexel(int spriteIndex, vec2 spritePx) {
    if (any(lessThan(spritePx, vec2(0.0))) || any(greaterThanEqual(spritePx, RAIN_DROP_TILE_SIZE))) {
        return vec4(0.0);
    }

    ivec2 atlasTexel = ivec2(int(float(spriteIndex) * RAIN_DROP_TILE_SIZE.x + floor(spritePx.x)), int(floor(spritePx.y)));
    return sampleComposite2AtlasTexel(waterdropstex, atlasTexel, RAIN_DROP_ATLAS_SIZE);
}

vec4 sampleRainDropSpriteTexel(int spriteIndex, ivec2 spriteTexel) {
    if (any(lessThan(spriteTexel, ivec2(0))) || any(greaterThanEqual(spriteTexel, ivec2(RAIN_DROP_TILE_SIZE)))) {
        return vec4(0.0);
    }

    ivec2 atlasTexel = ivec2(int(float(spriteIndex) * RAIN_DROP_TILE_SIZE.x) + spriteTexel.x, spriteTexel.y);
    return sampleComposite2AtlasTexel(waterdropstex, atlasTexel, RAIN_DROP_ATLAS_SIZE);
}

float sampleRainDropSpriteCoverage(int spriteIndex, vec2 localBlocks, vec2 offset) {
    ivec2 spriteTexel = getRainDropSpriteTexelCoord(localBlocks, offset);
    return min(sampleRainDropSpriteTexel(spriteIndex, spriteTexel).a * 0.65, 1.0);
}

float sampleRainDropSpriteRawCoverage(int spriteIndex, vec2 localBlocks, vec2 offset) {
    ivec2 spriteTexel = getRainDropSpriteTexelCoord(localBlocks, offset);
    return sampleRainDropSpriteTexel(spriteIndex, spriteTexel).a;
}

float getRainDropSpriteRadius(int spriteIndex) {
    if (spriteIndex == 0) return 0.86;
    if (spriteIndex == 1) return 1.10;
    return 1.38;
}

float sampleRainBodyCoverage(int spriteIndex, vec2 localBlocks) {
    return sampleRainDropSpriteCoverage(spriteIndex, localBlocks, vec2(0.0));
}

float sampleRainLensCoverage(int spriteIndex, vec2 localBlocks) {
    float center = sampleRainDropSpriteRawCoverage(spriteIndex, localBlocks, vec2(0.0));
    float up = sampleRainDropSpriteRawCoverage(spriteIndex, localBlocks, vec2(0.0, -1.0)) * 0.98;
    float up2 = sampleRainDropSpriteRawCoverage(spriteIndex, localBlocks, vec2(0.0, -2.0)) * 0.52;
    float down = sampleRainDropSpriteRawCoverage(spriteIndex, localBlocks, vec2(0.0, 1.0)) * 0.86;
    float left = sampleRainDropSpriteRawCoverage(spriteIndex, localBlocks, vec2(-1.0, 0.0)) * 0.88;
    float right = sampleRainDropSpriteRawCoverage(spriteIndex, localBlocks, vec2(1.0, 0.0)) * 0.88;
    float diagA = sampleRainDropSpriteRawCoverage(spriteIndex, localBlocks, vec2(-1.0, -1.0)) * 0.76;
    float diagB = sampleRainDropSpriteRawCoverage(spriteIndex, localBlocks, vec2(1.0, -1.0)) * 0.76;
    float diagC = sampleRainDropSpriteRawCoverage(spriteIndex, localBlocks, vec2(-1.0, 1.0)) * 0.64;
    float diagD = sampleRainDropSpriteRawCoverage(spriteIndex, localBlocks, vec2(1.0, 1.0)) * 0.64;
    float raw = max(
        max(center, max(up, up2)),
        max(
            max(down, max(left, right)),
            max(diagA, max(diagB, max(diagC, diagD)))
        )
    );
    return clamp(raw * 1.12, 0.0, 1.0);
}

float sampleRainTrailCoverage(vec2 localBlocks, float radius, float stretch, float trailLenBlocks, float trailLife, float rnd) {
    float trailY = -localBlocks.y;
    float trailStart = radius * stretch * 0.60;
    float trailEnd = trailStart + trailLenBlocks;
    float trailT = clamp((trailY - trailStart) / max(trailEnd - trailStart, 0.001), 0.0, 1.0);
    float drift = sin((trailY - trailStart) * 0.040 + rnd * 6.28318) * radius * mix(0.12, 0.04, trailT);
    float coverage = 0.0;
    vec2 trailA = vec2(drift * 0.80, -trailEnd);
    vec2 trailB = vec2(drift * 0.28, -trailStart);

    for (int i = 0; i < 4; i++) {
        vec2 sp = localBlocks + getRainDropSubpixel(i);
        vec2 seg = trailB - trailA;
        float segLen2 = dot(seg, seg);
        vec2 closest = trailA;
        if (segLen2 > 0.0001) {
            float h = clamp(dot(sp - trailA, seg) / segLen2, 0.0, 1.0);
            closest = trailA + seg * h;
        }

        float localTrailY = -sp.y;
        float localT = clamp((localTrailY - trailStart) / max(trailEnd - trailStart, 0.001), 0.0, 1.0);
        float width = mix(radius * 0.11, radius * 0.018, localT);
        float core = 1.0 - smoothstep(width, width + 0.08, length(sp - closest));
        coverage += core * mix(1.0, 0.18, localT);
    }

    return quantizeRainCoverage(coverage * 0.25) * trailLife;
}

RainDropLayerSample sampleRainDropLayer(vec2 coord, vec2 viewRes, vec2 cellSizePx, float speed, float densityCut, float seedBias, vec2 trailRangePx, float layerStrength) {
    RainDropLayerSample sample = makeRainDropLayerSample();
    vec2 snappedCoord = snapRainDropUV(coord, viewRes);
    vec2 fragPx = vec2(snappedCoord.x * viewRes.x, (1.0 - snappedCoord.y) * viewRes.y);
    vec2 baseCell = floor(fragPx / cellSizePx);

    for (int oy = -1; oy <= 1; oy++) {
        for (int ox = -1; ox <= 1; ox++) {
            vec2 cell = baseCell + vec2(float(ox), float(oy));
            vec2 rndA = hash22(cell + vec2(seedBias, seedBias * 0.37));
            vec2 rndB = hash22(cell + vec2(seedBias + 19.3, seedBias + 47.1));

            if (rndA.x < densityCut) continue;

            float speedScale = mix(0.96, 1.65, rndA.y);
            float t = fract(frameTimeCounter * speed * speedScale + rndA.y * 11.37 + rndB.x * 5.13);
            float appear = smoothstep(0.02, 0.08, t);
            float bodyLife = appear * (1.0 - smoothstep(0.74, 0.92, t));
            float trailLife = smoothstep(0.10, 0.18, t) * (1.0 - smoothstep(0.84, 1.0, t));
            float life = max(bodyLife, trailLife);
            if (life <= 0.001) continue;

            float flow = smoothstep(0.05, 0.90, t);
            float mergePulse = step(0.74, rndB.y) * smoothstep(0.34, 0.56, flow) * (1.0 - smoothstep(0.62, 0.86, flow));
            float fall = pow(flow, 1.7) * (1.0 + 0.28 * mergePulse);
            float velocity = pow(clamp(flow, 0.0, 1.0), 1.25);
            vec2 cellOrigin = cell * cellSizePx;

            int spriteIndex = min(int(floor(fract(rndA.x * 13.17 + rndB.y * 7.31) * 3.0)), 2);
            float radiusBlocks = getRainDropSpriteRadius(spriteIndex);
            float stretchAmount = velocity * velocity * (0.12 + 0.10 * mergePulse) * mix(0.92, 1.12, rndA.y);
            float stretch = 1.0 + stretchAmount;
            float trailLenPx = mix(trailRangePx.x, trailRangePx.y, rndB.x) * mix(0.30, 1.0, flow) * (1.0 + 0.16 * mergePulse) * mix(0.92, 1.12, float(spriteIndex) / 2.0);
            float baseX = cellOrigin.x + mix(cellSizePx.x * 0.22, cellSizePx.x * 0.78, rndB.x);
            float driftPhase = flow * 4.71239 * (1.0 + rndB.y * 0.6) + rndA.y * 6.28318;
            float driftAmount = sin(driftPhase) * mix(0.7, 2.2, rndB.x) * (0.24 + 0.76 * velocity);
            driftAmount += sin(driftPhase * 0.53 + 1.7) * 0.28;
            float baseY = cellOrigin.y + mix(-cellSizePx.y * 0.18, cellSizePx.y * 1.10, fall);
            vec2 center = vec2(baseX + driftAmount, baseY);
            vec2 localPx = fragPx - center;
            float trailLenBlocks = (trailLenPx / RAIN_DROP_BLOCK) * mix(0.88, 1.18, float(spriteIndex) / 2.0);
            vec2 bodyBlocks = localPx / RAIN_DROP_BLOCK;
            float bodyShape = sampleRainBodyCoverage(spriteIndex, bodyBlocks);
            float lensShape = sampleRainLensCoverage(spriteIndex, bodyBlocks);
            float body = min(bodyShape * bodyLife * 1.18, 1.0);
            float lens = min(mix(bodyShape, lensShape, 0.72) * bodyLife * 1.10, 1.0);
            float trail = sampleRainTrailCoverage(bodyBlocks, radiusBlocks, stretch, trailLenBlocks, trailLife, rndA.x);

            float dropMask = max(lens, trail * 0.52);
            if (dropMask <= 0.001) continue;

            float highlight = body * 0.16;

            vec2 distort = vec2(
                bodyBlocks.x / max(radiusBlocks * 2.1, 0.001),
                -bodyBlocks.y / max(radiusBlocks * stretch * 2.1, 0.001)
            );
            vec2 blockUV = vec2(RAIN_DROP_BLOCK / viewRes.x, RAIN_DROP_BLOCK / viewRes.y);
            vec2 refractOffset = distort * (lens * 1.56 + trail * 0.16) * layerStrength * blockUV;

            sample.offset += refractOffset * (lens * 2.54 + trail * 0.24);
            sample.offsetWeight += lens * 2.54 + trail * 0.24;
            sample.wetMask = max(sample.wetMask, max(body * 0.92, max(lens * 0.96, trail * 0.26)));
            sample.lensMask = max(sample.lensMask, lens);
            sample.bodyMask = max(sample.bodyMask, body);
            sample.trailMask = max(sample.trailMask, trail);
            sample.highlight = max(sample.highlight, highlight);
        }
    }

    return sample;
}

vec3 addRainDrops(vec3 col, vec2 coord) {
    if (isEyeInWater != 0) return col;

    float rainAmount = smoothstep(0.05, 0.16, rainStrength);
    float biomeRainMask = 1.0 - clamp(max(isCold, isWarm), 0.0, 1.0);
    float rawSkyExposure = clamp(float(eyeBrightness.y) / 240.0, 0.0, 1.0);
    float smoothSkyExposure = clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0);
    float skyExposure = mix(smoothSkyExposure, rawSkyExposure, 0.18);
    float outdoorMask = smoothstep(0.74, 0.95, skyExposure);
    rainAmount *= biomeRainMask * outdoorMask;
    if (rainAmount <= 0.01) return col;

    vec2 viewRes = vec2(viewWidth, viewHeight);
    RainDropLayerSample largeDrops = sampleRainDropLayer(coord, viewRes, vec2(184.0, 224.0), 0.095, 0.92, 0.0, vec2(56.0, 108.0), 1.0);
    RainDropLayerSample mediumDrops = sampleRainDropLayer(coord, viewRes, vec2(140.0, 172.0), 0.132, 0.970, 31.7, vec2(34.0, 68.0), 0.84);

    float wetMask = clamp(max(largeDrops.wetMask, mediumDrops.wetMask), 0.0, 1.0);
    if (wetMask <= 0.001) return col;

    vec2 offset = largeDrops.offset + mediumDrops.offset;
    float offsetWeight = largeDrops.offsetWeight + mediumDrops.offsetWeight;
    if (offsetWeight > 0.001) {
        offset /= offsetWeight;
    }
    offset *= rainAmount * 0.88;

    vec2 snappedCoord = snapRainDropUV(coord, viewRes);
    vec2 sampleUV = clamp(snappedCoord + offset, vec2(0.0), vec2(1.0));
    sampleUV = snapRainDropUV(sampleUV, viewRes);
    vec3 refracted = sampleComposite2Texture(texture, sampleUV).rgb;
    float lensMask = clamp(max(largeDrops.lensMask, mediumDrops.lensMask), 0.0, 1.0);
    float bodyMask = clamp(max(largeDrops.bodyMask, mediumDrops.bodyMask), 0.0, 1.0);
    float trailMask = clamp(max(largeDrops.trailMask, mediumDrops.trailMask), 0.0, 1.0);
    float highlight = clamp(max(largeDrops.highlight, mediumDrops.highlight), 0.0, 1.0);
    float rainDropOpacity = RAIN_DROPS_OPACITY;

    float bodyOpacity = clamp(bodyMask * (0.64 + 0.12 * rainAmount) * rainDropOpacity, 0.0, 1.0);
    float trailOpacity = clamp(trailMask * (0.14 + 0.04 * rainAmount) * rainDropOpacity, 0.0, 0.44);
    vec3 dropletBodyTint = mix(refracted, vec3(0.76, 0.84, 0.94), 0.62);

    float opticsMask = clamp(max(bodyMask * 0.98, lensMask * 1.02), 0.0, 1.0);
    vec3 wetColor = mix(col, refracted, clamp(lensMask * (1.54 + 0.18 * rainAmount) + bodyMask * 0.28 + trailMask * (0.22 + 0.05 * rainAmount), 0.0, 1.0));
    wetColor = mix(wetColor, dropletBodyTint, bodyOpacity * 0.82);
    wetColor = mix(wetColor, dropletBodyTint * vec3(0.96, 0.98, 1.0), trailOpacity * 0.18);

    float rim = clamp(max(wetMask, lensMask) - bodyMask * 0.82, 0.0, 1.0);
    vec3 dropletHighlight = vec3(1.0, 0.98, 0.95);
    wetColor += dropletHighlight * highlight * (0.44 + 0.20 * rainAmount);
    wetColor += dropletHighlight * rim * (0.018 + 0.010 * rainAmount);

    float finalMix = clamp((max(bodyMask * (1.34 + 0.14 * rainAmount), opticsMask * 1.08) + trailMask * (0.16 + 0.05 * rainAmount)) * rainDropOpacity, 0.0, 1.0);
    return mix(col, wetColor, finalMix);
}
#endif

void main() {
  vec4 tex = sampleComposite2Texture(texture, texcoord.xy) * color;

  #if ENABLE_GODRAYS > 0

    tex.rgb = calcRays(tex.rgb);

  #endif

  #if ENABLE_HEAT_HAZE > 0
 
    tex.rgb = addHeatHaze(tex.rgb, texcoord.xy);
    tex.rgb = addHeatGlow(tex.rgb, texcoord.xy);
 
  #endif

  #if ENABLE_RAINBOW > 0

    tex.rgb = addRainbow(tex.rgb, texcoord.xy);

  #endif

  #if ENABLE_SHOOTING_STARS > 0

    tex.rgb = addShootingStars(tex.rgb, texcoord.xy);

  #endif

  #if ENABLE_RAIN_DROPS > 0

    tex.rgb = addRainDrops(tex.rgb, texcoord.xy);

  #endif

  #if ENABLE_LENS_FLARE > 0

    tex.rgb = addLensFlare(tex.rgb, texcoord.xy);

  #endif

  vec3 bloomSource = vec3(0.0);
  #if ENABLE_BLOOM > 0
    bloomSource = extractBloomSource(tex.rgb, texcoord.xy);
  #endif

  /*DRAWBUFFERS:01*/
  fragColor = tex;
  fragColor1 = vec4(bloomSource, 0.0);
}
