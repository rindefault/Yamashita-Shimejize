
#include "/shader.h"
#include "/common/math.glsl"
#include "/common/transformations.fsh"
#include "/common/effect_metadata.glsl"

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform sampler2D noisetex;
uniform sampler2D cloudstex;
uniform sampler2D colortex2; // hot/glow mask from gbuffers_textured_lit
#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex0;
#endif
uniform float viewWidth;
uniform float viewHeight;
uniform float timeAngle;
uniform float timeBrightness;
uniform float frameTimeCounter;
uniform float rainFactor;
uniform float rainStrength;
uniform float isCold;
uniform float isWarm;
uniform float fogEnd;
uniform float far;
uniform int   worldTime;
uniform vec3  cameraPosition;
uniform vec3  shadowLightPosition;
uniform vec3  fogColor;
uniform vec3  skyColor;
uniform mat4  gbufferProjectionInverse;
uniform mat4  gbufferModelViewInverse;
#ifdef DISTANT_HORIZONS
uniform mat4  dhProjectionInverse;
#endif
#ifdef HAND_DYNAMIC_LIGHTING
uniform int   heldBlockLightValue;
#endif

varying vec2 texcoord;

const vec3 upVec = vec3(0.0, 1.0, 0.0);
const vec3 sunVec = vec3(0.0, 1.0, 0.0);

#include "/common/getSkyAndFogColors.fsh"

/* RENDERTARGETS: 0,3 */
#define color gl_FragData[0]
#define cloudMaskOut gl_FragData[1]

vec4 sampleCompositeTexture(sampler2D tex, vec2 uv) {
#if __VERSION__ < 130
  return texture2D(tex, uv);
#else
  return texture(tex, uv);
#endif
}

vec2 getCloudMaskTextureSize() {
#if __VERSION__ < 130
  return vec2(256.0);
#else
  return vec2(ivec2(textureSize(cloudstex, 0)));
#endif
}

vec4 sampleEffectBufferNearest(vec2 uv) {
#if __VERSION__ < 130
  vec2 texSize = vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));
  vec2 clampedUV = clamp(uv, vec2(0.0), vec2(1.0) - 0.5 / texSize);
  vec2 snappedUV = (floor(clampedUV * texSize) + 0.5) / texSize;
  return sampleCompositeTexture(colortex2, snappedUV);
#else
  return sampleEffectDataNearest(colortex2, uv);
#endif
}

vec3 reconstructViewPos(mat4 projectionInverse, vec2 uv, float depth) {
  vec4 clip = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
  vec4 view = projectionInverse * clip;
  view /= view.w;
  return (gbufferModelViewInverse * view).xyz;
}

vec3 getSkyViewRay(vec2 uv) {
  vec4 clip = vec4(uv * 2.0 - 1.0, 1.0, 1.0);
  vec4 view = gbufferProjectionInverse * clip;
  view /= view.w;
  return (gbufferModelViewInverse * view).xyz;
}

void resolveSceneViewPos(vec2 uv, out vec3 sceneViewPos, out bool sceneHit) {
  float vanillaDepth = sampleCompositeTexture(depthtex0, uv).r;
  sceneHit = vanillaDepth < 0.9999;
  sceneViewPos = sceneHit ? reconstructViewPos(gbufferProjectionInverse, uv, vanillaDepth)
                          : getSkyViewRay(uv);

  #ifdef DISTANT_HORIZONS
    float dhDepth = sampleCompositeTexture(dhDepthTex0, uv).r;
    bool dhHit = dhDepth < 0.999999;

    if (dhHit) {
      vec3 dhViewPos = reconstructViewPos(dhProjectionInverse, uv, dhDepth);
      float dhDist = length(dhViewPos);
      float vanillaDist = sceneHit ? length(sceneViewPos) : 1e20;

      if (dhDist < vanillaDist) {
        sceneViewPos = dhViewPos;
        sceneHit = true;
      }
    }
  #endif
}

// ---------------------------------------------------------------------------
// Soft shadow noise: bilinear interpolation between cell corners.
// Used for cloud ground shadows — gives diffuse/penumbra-like edges.
// ---------------------------------------------------------------------------
float sampleCloudMaskTexel(vec2 cell, float seed) {
  vec2 texSize = getCloudMaskTextureSize();
  vec2 wrapped = mod(cell + vec2(seed * 11.0, seed * 3.0), texSize);
  vec2 texel = (wrapped + 0.5) / texSize;
  vec4 cloudTexel = sampleCompositeTexture(cloudstex, texel);
  float lum = dot(cloudTexel.rgb, vec3(0.3333333));
  // Prefer alpha when present, otherwise use luma (for opaque clouds.png variants).
  return (cloudTexel.a < 0.999) ? cloudTexel.a : lum;
}

float getCloudShadowSoft(vec2 worldXZ, float seed) {
  float scroll  = frameTimeCounter * 1.75;
  vec2 shifted = worldXZ + vec2(scroll + seed, seed * 0.5);
  #if SHADOW_PIXEL > 0
    shifted = (floor(shifted * SHADOW_PIXEL + 0.01) + 0.5) / SHADOW_PIXEL;
  #endif
  vec2 g = shifted / 12.0;
  vec2 cell = floor(g);
  vec2 f = fract(g);
  f = f * f * (3.0 - 2.0 * f);

  float n00 = sampleCloudMaskTexel(cell + vec2(0.0, 0.0), seed);
  float n10 = sampleCloudMaskTexel(cell + vec2(1.0, 0.0), seed);
  float n01 = sampleCloudMaskTexel(cell + vec2(0.0, 1.0), seed);
  float n11 = sampleCloudMaskTexel(cell + vec2(1.0, 1.0), seed);
  float m = mix(mix(n00, n10, f.x), mix(n01, n11, f.x), f.y);
  return smoothstep(0.58, 0.86, m);
}

float getCloudNoise(vec2 worldXZ, float seed) {
  float scroll  = frameTimeCounter * 1.75;
  vec2 shifted = worldXZ + vec2(scroll + seed, seed * 0.5);
  vec2 cell = floor(shifted / 12.0);
  float mask = sampleCloudMaskTexel(cell, seed);
  return step(0.52, mask);
}

float getCloudRayMaxT(vec3 rayDir) {
  float cloudFogRange = clamp(max(fogEnd, far) * 6.0, 768.0, 2048.0);
  float xzLen = max(length(rayDir.xz), 0.08);
  return cloudFogRange / xzLen;
}

float getCloudDistanceFog(float hDist, float rayUp) {
  float horizonMask = 1.0 - smoothstep(0.05, 0.28, clamp(rayUp, 0.0, 1.0));
  float cloudFogRange = clamp(max(fogEnd, far) * 6.0, 768.0, 2048.0);
  float effectiveRange = cloudFogRange * mix(1.0, 0.82, horizonMask);
  float normalizedDist = clamp(hDist / max(effectiveRange, 1.0), 0.0, 2.0);
  float opticalDepth = pow(normalizedDist, mix(1.85, 1.15, horizonMask))
                     * mix(0.85, 1.75, horizonMask);
  return 1.0 - exp(-opticalDepth);
}

float getCloudFogDissolve(float cloudFog) {
  return pow(max(1.0 - cloudFog, 0.0), 0.65);
}

vec4 applyCloudAerialPerspective(vec4 cloudSample, float hitT, vec3 rayDir, vec3 fogTarget) {
  if (cloudSample.a <= 0.0 || hitT >= 1e19) return cloudSample;

  float hDist = length(rayDir.xz) * max(hitT, 0.0);
  float cloudFog = getCloudDistanceFog(hDist, rayDir.y);
  float cloudDissolve = getCloudFogDissolve(cloudFog);
  float nightFade = (1.0 - timeBrightness) * cloudFog * cloudFog * 0.16;

  cloudSample.rgb = mix(cloudSample.rgb, fogTarget, cloudFog * 0.58);
  cloudSample.a *= cloudDissolve * (1.0 - nightFade);

  return cloudSample;
}

float getCloudHitHeight(float layerBot, float layerTop, float hitY) {
  float thickness = max(layerTop - layerBot, 0.001);
  return clamp((hitY - layerBot) / thickness, 0.0, 1.0);
}

float getCloudTopViewWeight(float layerBot, float layerTop, float alphaMul, vec3 camPos, vec3 rayDir) {
  float thickness = max(layerTop - layerBot, 0.001);
  float camH = (camPos.y - layerBot) / thickness;
  float insideUpper = smoothstep(0.22, 0.80, camH);
  float aboveLayer = smoothstep(0.80, 1.12, camH);
  float verticalWeight = max(insideUpper * 0.95, aboveLayer);
  float lookDown = smoothstep(-0.12, 0.20, -rayDir.y);
  float denseLayer = mix(0.58, 1.0, smoothstep(0.20, 0.82, alphaMul));
  return clamp(verticalWeight * lookDown * denseLayer, 0.0, 1.0);
}

float getCloudColumnCoverage(float h) {
  return clamp((h - 0.5 * h * h) * 2.0, 0.0, 1.0);
}

vec3 getCloudWorldSunDir() {
  return normalize(mat3(gbufferModelViewInverse) * normalize(shadowLightPosition));
}

vec3 getRainOvercastTarget() {
  vec3 overcastSky = mix(skyColor, fogColor, 0.45);
  return mix(overcastSky, vec3(luma(overcastSky)), 0.35);
}

vec3 applyRainOvercastSky(vec3 sourceColor) {
  return mix(sourceColor, getRainOvercastTarget(), rainStrength * 0.58);
}

vec3 getCloudSkyGradientColor(vec3 rayDir) {
  vec3 ray = normalize(rayDir);
  vec3 sunDir = getCloudWorldSunDir();
  float horizon = 1.0 - smoothstep(0.10, 0.78, abs(ray.y));
  float downView = smoothstep(0.08, 0.80, -ray.y);

  float VdotU = dot(ray, vec3(0.0, 1.0, 0.0));
  float VdotS = dot(ray, sunDir);
  vec3 skyGradient = getSkyFromVectors(VdotU, VdotS, 0.0, sunDir, vec3(0.0, 1.0, 0.0));

  vec3 airySky = mix(skyGradient, fogColor, 0.16 + rainStrength * 0.08);
  vec3 fogHaze = mix(skyGradient, fogColor, 0.40 + horizon * 0.24 + downView * 0.12 + rainStrength * 0.10);
  float hazeMix = clamp(0.18 + horizon * 0.54 + downView * 0.10, 0.0, 1.0);

  vec3 cloudSky = mix(airySky, fogHaze, hazeMix);
  return applyRainOvercastSky(cloudSky);
}

vec3 getCloudFogTarget(vec3 rayDir) {
  vec3 skyGradient = getCloudSkyGradientColor(rayDir);
  float horizon = 1.0 - smoothstep(0.12, 0.72, abs(rayDir.y));
  float fogMix = clamp(0.28 + horizon * 0.20 + rainStrength * 0.10, 0.0, 1.0);
  return mix(skyGradient, fogColor, fogMix);
}

void shadeCloudHit(float layerBot, float layerTop, float alphaMul, vec3 camPos, vec3 rayDir, vec3 baseCloudCol, float entryY, float hitY, out vec4 cloudSample) {
  float thickness = max(layerTop - layerBot, 0.001);
  float camH = clamp((camPos.y - layerBot) / thickness, 0.0, 1.25);
  float hitH = getCloudHitHeight(layerBot, layerTop, hitY);
  float entryH = getCloudHitHeight(layerBot, layerTop, entryY);
  float topViewWeight = getCloudTopViewWeight(layerBot, layerTop, alphaMul, camPos, rayDir);
  float coverH = mix(hitH, max(max(hitH, entryH), camH * 0.88), topViewWeight);

  float localAlpha = (1.0 - hitH) * alphaMul;
  float columnCoverage = getCloudColumnCoverage(coverH);
  float topViewAlpha = alphaMul * mix(0.56, 0.92, sqrt(columnCoverage));

  // Coverage and colour are separate: from above we still hide terrain better,
  // but the visible cap should transition from cloud colour into sky colour.
  float colorH = hitH;
  float colorLift = smoothstep(0.40, 0.92, camH) * topViewWeight;
  float colorReach = smoothstep(-0.04, 0.24, -rayDir.y);
  colorH = mix(colorH, min(1.0, hitH + (1.0 - hitH) * 0.22), colorLift * colorReach);
  float skyBlend = smoothstep(0.52, 0.98, colorH);
  vec3 topViewColor = mix(baseCloudCol, getCloudSkyGradientColor(rayDir), skyBlend * 0.82);
  float topViewColorWeight = topViewWeight * (0.26 + 0.50 * skyBlend);

  cloudSample.a = mix(localAlpha, max(localAlpha, topViewAlpha), topViewWeight);
  cloudSample.rgb = mix(baseCloudCol, topViewColor, topViewColorWeight);
}

bool getCloudLayerSegment(float layerBot, float layerTop, vec3 camPos, vec3 rayDir, out float tStart, out float tEnd) {
  float rayY = rayDir.y;

  if (abs(rayY) < 0.001) {
    if (camPos.y < layerBot || camPos.y > layerTop) return false;
    tStart = 0.0;
    tEnd = getCloudRayMaxT(rayDir);
    return tEnd > 0.0;
  }

  float t0 = (layerBot - camPos.y) / rayY;
  float t1 = (layerTop - camPos.y) / rayY;
  tStart = min(t0, t1);
  tEnd = max(t0, t1);

  if (tEnd <= 0.0) return false;
  tStart = max(tStart, 0.0);
  return tEnd > tStart;
}

float getNextCloudBoundary(float originCoord, float dirCoord, float cellCoord) {
  if (abs(dirCoord) < 1e-5) return 1e20;

  float boundary = dirCoord > 0.0 ? cellCoord + 1.0 : cellCoord;
  return (boundary - originCoord) / dirCoord;
}

bool traceCloudLayerGrid(float layerBot, float layerTop, float alphaMul, float seed, vec3 camPos, vec3 rayDir, float sceneT, vec3 baseCloudCol, out vec4 cloudSample, out float hitT) {
  cloudSample = vec4(0.0);
  hitT = 1e20;

  float tStart = 0.0;
  float tEnd = 0.0;
  if (!getCloudLayerSegment(layerBot, layerTop, camPos, rayDir, tStart, tEnd)) return false;

  float tVisibleEnd = min(min(tEnd, sceneT), getCloudRayMaxT(rayDir));
  if (tVisibleEnd <= tStart + 0.0001) return false;

  const float CLOUD_CELL = 12.0;
  const int MAX_CLOUD_CELLS = 96;
  const float HIT_EPS = 0.0001;

  vec2 scroll = vec2(frameTimeCounter * 1.75 + seed, seed * 0.5);
  vec2 gridOrigin = (camPos.xz + scroll) / CLOUD_CELL;
  vec2 gridDir = rayDir.xz / CLOUD_CELL;

  float currentT = tStart + HIT_EPS;
  vec2 gridPos = gridOrigin + gridDir * currentT;
  vec2 cell = floor(gridPos);
  vec2 stepDir = sign(gridDir);
  vec2 tDelta = vec2(abs(gridDir.x) > 1e-5 ? abs(1.0 / gridDir.x) : 1e20,
                     abs(gridDir.y) > 1e-5 ? abs(1.0 / gridDir.y) : 1e20);
  vec2 tMax = vec2(getNextCloudBoundary(gridOrigin.x, gridDir.x, cell.x),
                   getNextCloudBoundary(gridOrigin.y, gridDir.y, cell.y));

  for (int i = 0; i < MAX_CLOUD_CELLS; i++) {
    float cellExitT = min(min(tMax.x, tMax.y), tVisibleEnd);
    float mask = sampleCloudMaskTexel(cell, seed);

    if (mask > 0.52) {
      float entryY = camPos.y + rayDir.y * tStart;
      vec3 pos = camPos + rayDir * currentT;
      shadeCloudHit(layerBot, layerTop, alphaMul, camPos, rayDir, baseCloudCol, entryY, pos.y, cloudSample);
      hitT = currentT;
      return true;
    }

    if (cellExitT >= tVisibleEnd - HIT_EPS) break;

    if (tMax.x < tMax.y) {
      cell.x += stepDir.x;
      currentT = tMax.x + HIT_EPS;
      tMax.x += tDelta.x;
    } else {
      cell.y += stepDir.y;
      currentT = tMax.y + HIT_EPS;
      tMax.y += tDelta.y;
    }
  }

  return false;
}

void main() {
  vec2 screenTexcoord = texcoord;
  vec2 shadowTexcoord = screenTexcoord;
  #if __VERSION__ < 130
    vec2 screenSize = vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));
    shadowTexcoord = clamp(gl_FragCoord.xy / screenSize, vec2(0.0), vec2(1.0));
  #endif

  // ---------------------------------------------------------------------------
  // Chromatic aberration (ENABLE_ANAGLYPH): sample R and B channels at
  // opposing radial offsets from screen centre. Gives a lens-distortion look
  // that is most visible at the screen corners.
  // ---------------------------------------------------------------------------
  vec4 texColor;
  #if ENABLE_ANAGLYPH > 0
    const float CHROMA = 0.0018;
    vec2 chromaOff = (screenTexcoord - 0.5) * CHROMA;
    vec4 baseColor;
    baseColor.rgb = sampleCompositeTexture(colortex0, screenTexcoord).rgb;
    baseColor.a = 1.0;

    vec4 chromaColor;
    chromaColor.r = sampleCompositeTexture(colortex0, screenTexcoord + chromaOff).r;
    chromaColor.g = baseColor.g;
    chromaColor.b = sampleCompositeTexture(colortex0, screenTexcoord - chromaOff).b;
    chromaColor.a = 1.0;

    // Prevent chromatic aberration from appearing on dense fog bands.
    float caMask = 1.0;
    vec3 playerPos;
    bool hasSceneDepth;
    resolveSceneViewPos(screenTexcoord, playerPos, hasSceneDepth);

    if (hasSceneDepth) {
      float viewDist = length(playerPos);

      float transitionFog = clamp(1.0 - OVERWORLD_FOG_MIN, 0.0, 1.0);
      float baseFog = clamp(OVERWORLD_FOG_MAX, 0.0, 1.0);
      float farPlane = max(far, 1.0);
      float fogBase = rescale(viewDist, 0.9 * baseFog * farPlane, farPlane);
      float softBandStart = mix(0.92, 0.48, transitionFog) * farPlane;
      float transitionHaze = rescale(viewDist, softBandStart, farPlane) * (0.06 + 0.42 * transitionFog);
      float distanceHaze = (0.0008 + 0.0014 * transitionFog) * max(0.0, viewDist - 96.0);
      float fogApprox = min(1.0, fogBase + transitionHaze + distanceHaze);
      caMask = 1.0 - smoothstep(0.30, 0.70, fogApprox);
    }

    texColor = mix(baseColor, chromaColor, caMask);
  #else
    texColor = sampleCompositeTexture(colortex0, screenTexcoord);
  #endif

  vec3 sceneViewPos;
  bool sceneHasGeometry;
  resolveSceneViewPos(shadowTexcoord, sceneViewPos, sceneHasGeometry);
  cloudMaskOut = vec4(0.0);

  #if ENHANCED_CLOUDS > 0 && !defined(THE_NETHER) && !defined(THE_END) && !defined(NETHER) && !defined(END)
  float cloudSceneDepth = sampleCompositeTexture(depthtex0, shadowTexcoord).r;
  bool cloudSceneHasGeometry = cloudSceneDepth < 0.9999;
  vec3 cloudPlayerPos = cloudSceneHasGeometry
                      ? reconstructViewPos(gbufferProjectionInverse, shadowTexcoord, cloudSceneDepth)
                      : getSkyViewRay(shadowTexcoord);

  // Cloud layer extents (Story Mode two-layer style)
  const float L1_BOT = 192.0;
  const float L1_TOP = 216.0;
  const float L2_BOT = 264.0;
  const float L2_TOP = 294.0;
  float _depth = sceneHasGeometry ? 0.0 : 1.0;
  vec3  _playerPos = sceneViewPos;

  // ---------------------------------------------------------------------------
  // Cloud shadows on terrain
  // Only active during the day (timeBrightness > 0.01) — no shadow at night.
  // Shadow blocks sunlight only: torch/fire-lit pixels are detected by their
  // warm colour profile and resist the darkening (real shade ≠ darkness).
  // ---------------------------------------------------------------------------
  #if CLOUD_SHADOWS > 0
  if (_depth < 0.9999 && timeBrightness > 0.01) {
    vec3 absWorld = _playerPos + cameraPosition;
    vec3 sunDir   = normalize(mat3(gbufferModelViewInverse) * normalize(shadowLightPosition));

    if (absWorld.y < L1_BOT && sunDir.y > 0.01) {
      float t        = (L1_BOT - absWorld.y) / sunDir.y;
      vec2  shadowXZ = absWorld.xz + sunDir.xz * t;

      // Two diagonal samples — half the cost of the 4-tap cross, still diffuse
      float shadowL1 = getCloudShadowSoft(shadowXZ, 0.0);

      float shadowL2 = 0.0;
      float t2 = (L2_BOT - absWorld.y) / sunDir.y;
      if (t2 > 0.0) {
        vec2 shadowXZ2 = absWorld.xz + sunDir.xz * t2;
        shadowL2 = getCloudShadowSoft(shadowXZ2, 1500.0);
      }

      float shadowSample = clamp(shadowL1 + shadowL2 * 0.42, 0.0, 1.0);

      float density = shadowSample;
      #if __VERSION__ >= 130
        // Derivative-based texel snapping is stable in the original modern path,
        // but in the legacy fullscreen composite it causes angular popping and
        // edge halos on cloud shadows.
        vec2 pOffset = ComputeTexelOffset(colortex0, screenTexcoord);
        density = TexelSnap(shadowSample, pOffset);
      #endif

      // Torch/fire heuristic: warm orange-ish pixels are block-light-dominated.
      // Cloud shadow only affects sunlight → reduce shadow strength here.
      float pixelWarmth = texColor.r / max(texColor.g, 0.001);
      float pixelBright = dot(texColor.rgb, vec3(0.333));
      float isTorchLit  = smoothstep(1.08, 1.40, pixelWarmth)
                        * smoothstep(0.04, 0.20, pixelBright);
      vec4 effectData = sampleEffectBufferNearest(shadowTexcoord);
      float torchMask = effectData.b;
      float foregroundMask = decodeEffectForegroundMask(effectData.a);
      float torchArea = smoothstep(0.08, 0.34, torchMask);
      torchArea *= torchArea;
      torchArea *= 1.0 - foregroundMask;
      isTorchLit = max(isTorchLit, torchArea);
      #ifdef HAND_DYNAMIC_LIGHTING
      // Dynamic light from held torch/item: affect cloud shadow on nearby terrain
      // even when no placed light source writes into the surface mask.
      if (heldBlockLightValue > 0) {
        float heldStrength = min(1.0, float(heldBlockLightValue) / pow2(length(_playerPos) + 1.5));
        float heldArea = smoothstep(0.10, 0.42, heldStrength);
        heldArea *= heldArea;
        isTorchLit = max(isTorchLit, heldArea);
      }
      #endif

      float viewDist = length(_playerPos);
      float transitionFog = clamp(1.0 - OVERWORLD_FOG_MIN, 0.0, 1.0);
      float baseFog = clamp(OVERWORLD_FOG_MAX, 0.0, 1.0);
      float farPlane = max(far, 1.0);

      // Approximate the same distance fog response as getFogMix OVERWORLD branch
      // so cloud shadows dissolve in the same zone where fog dominates.
      float fogBase = rescale(viewDist, 0.9 * baseFog * farPlane, farPlane);
      float softBandStart = mix(0.92, 0.48, transitionFog) * farPlane;
      float transitionHaze = rescale(viewDist, softBandStart, farPlane) * (0.06 + 0.42 * transitionFog);
      float distanceHaze = (0.0008 + 0.0014 * transitionFog) * max(0.0, viewDist - 96.0);
      float fogApprox = min(1.0, fogBase + transitionHaze + distanceHaze);
      float fogSuppress = smoothstep(0.35, 0.75, fogApprox);

      float shadowRaw = density * CLOUD_SHADOW_STRENGTH * timeBrightness
                      * (1.0 - rainStrength * 0.65)
                      * (1.0 - fogSuppress)
                      * (1.0 - isTorchLit * 0.90);

      // Match regular shadow behaviour more closely: softer darkness scaling
      // plus optional slight blue shift from SHADOW_BLUENESS.
      float shadow = shadowRaw * mix(0.45, 0.75, SHADOW_DARKNESS);
      float blueness = shadow * SHADOW_BLUENESS * 0.5;
      float darkMul = 1.0 - shadow;

      texColor.r *= darkMul;
      texColor.g *= darkMul * (1.0 + 0.3333 * blueness);
      texColor.b *= darkMul * (1.0 + blueness);
    }
  }
  #endif

  // ---------------------------------------------------------------------------
  // Day/dusk/night colour for cloud rendering.
  // horizon: warm orange tint at dawn/dusk.
  // nightF:  deep blue-grey at night.
  // Both modulated by timeBrightness so clouds dim towards midnight.
  // ---------------------------------------------------------------------------
  float phase   = fract(timeAngle - 0.25);
  float sunH    = cos(phase * 6.283185);
  float nightF  = smoothstep(-0.2, -0.6, sunH);
  float horizon = smoothstep(0.5, 0.0, abs(sunH + 0.2)) * smoothstep(-0.4, -0.1, sunH);

  vec3 baseCloudCol = mix(vec3(0.95), vec3(1.1, 0.5, 0.3), horizon);
  baseCloudCol      = mix(baseCloudCol, vec3(0.05, 0.06, 0.09), nightF);
  baseCloudCol     *= max(timeBrightness, 0.25);

  // Morning recovery window (around 2000-3000 ticks):
  // keep clouds a bit brighter while sky is still relatively light,
  // so they don't collapse into a flat grey blend with the background.
  float wt = float(worldTime);
  float morningLift = smoothstep(1700.0, 2200.0, wt) * (1.0 - smoothstep(3000.0, 3600.0, wt));
  // Start earlier than before to prevent the pre-sunset brightness dip
  // around 8000-8900 ticks.
  float eveningLift = smoothstep(7600.0, 8400.0, wt) * (1.0 - smoothstep(10000.0, 10800.0, wt));
  float transitionLift = max(morningLift, eveningLift);
  baseCloudCol = mix(baseCloudCol, vec3(0.98, 1.0, 1.04), transitionLift * 0.42);
  baseCloudCol *= 1.0 + 0.12 * transitionLift;
  float rainCloudFade = smoothstep(0.05, 0.85, rainStrength);
  vec3 rainBaseCloudCol = mix(getRainOvercastTarget(), fogColor, 0.18) * vec3(1.02, 1.02, 1.04);
  baseCloudCol = mix(baseCloudCol, rainBaseCloudCol, rainCloudFade * 0.72);

  // ---------------------------------------------------------------------------
  // Cloud sky rendering (sky pixels only, depth ≥ 0.9999).
  // Per-layer ray marching keeps L1 stable even if L2 is much higher.
  // Layer 1 (low, thick): main cloud body — alpha decreases from bottom to top
  //   → the "Story Mode gradient" effect where clouds fade to sky at their cap.
  // Layer 2 (high, thin): cirrus-like wisps above the main layer.
  // Rain: sky desaturated/darkened to overcast grey as rainStrength increases.
  // ---------------------------------------------------------------------------
  bool isSkyPixel = !cloudSceneHasGeometry;
  vec3 rayDir = normalize(cloudPlayerPos);
  float sceneT = isSkyPixel ? 1e20 : length(cloudPlayerPos);

  float tL1Start = 0.0;
  float tL1End = 0.0;
  float tL2Start = 0.0;
  float tL2End = 0.0;
  bool hitL1 = getCloudLayerSegment(L1_BOT, L1_TOP, cameraPosition, rayDir, tL1Start, tL1End);
  bool hitL2 = getCloudLayerSegment(L2_BOT, L2_TOP, cameraPosition, rayDir, tL2Start, tL2End);

  bool hitL1Visible = hitL1 && tL1Start < sceneT;
  bool hitL2Visible = hitL2 && tL2Start < sceneT;

  if (hitL1Visible || hitL2Visible) {
      vec4 res1 = vec4(0.0);
      vec4 res2 = vec4(0.0);

      float res1T = 1e20;
      float res2T = 1e20;

      // Trace occupied cloud cells directly instead of probing a giant slab
      // with a tiny fixed step budget. This keeps horizon clouds from ending
      // in a fake wall just because intermediate mask cells were skipped.
      if (hitL1Visible) traceCloudLayerGrid(L1_BOT, L1_TOP, 0.9, 0.0, cameraPosition, rayDir, sceneT, baseCloudCol, res1, res1T);
      if (hitL2Visible) traceCloudLayerGrid(L2_BOT, L2_TOP, 0.4, 1500.0, cameraPosition, rayDir, sceneT, baseCloudCol, res2, res2T);

      vec3 cloudFogTarget = getCloudFogTarget(rayDir);
      res1 = applyCloudAerialPerspective(res1, res1T, rayDir, cloudFogTarget);
      res2 = applyCloudAerialPerspective(res2, res2T, rayDir, cloudFogTarget);

      // Composite the two layers (painter's algorithm: L1 in front of L2)
      vec4 finalClouds;
      finalClouds.a = res1.a + res2.a * (1.0 - res1.a);
      if (finalClouds.a > 0.0) {
        finalClouds.rgb = (res1.rgb * res1.a + res2.rgb * res2.a * (1.0 - res1.a))
                        / finalClouds.a;
        // During rain, thin out cloud alpha slightly so weather particles
        // remain visually in front instead of being drowned by cloud layer.
        finalClouds.a *= mix(1.0, 0.76, rainStrength);

        texColor.rgb  = mix(texColor.rgb, finalClouds.rgb, finalClouds.a);
        cloudMaskOut  = vec4(1.0, finalClouds.a, 0.0, 1.0);
      }
  }
  #endif

  float dither = bayer4(gl_FragCoord.xy * 0.5) / POSTERIZE_STRENGTH;
  color.rgb = clamp(floor(texColor.rgb * POSTERIZE_STRENGTH + dither) / POSTERIZE_STRENGTH, 0.0, 1.0);
}
