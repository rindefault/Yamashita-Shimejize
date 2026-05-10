#define gbuffers_skytextured

#include "/shader.h"
#include "/common/math.glsl"

uniform float rainStrength;
uniform int isEyeInWater;

uniform sampler2D texture;
uniform float viewWidth, viewHeight;
uniform int renderStage;

varying vec2 texUV;
varying vec4 glColor;

#ifndef MC_RENDER_STAGE_MOON
#define MC_RENDER_STAGE_MOON 1
#endif

const vec2 MOON_ATLAS_GRID = vec2(4.0, 2.0);

vec2 getUvFootprint() {
  vec2 dx = abs(dFdx(texUV));
  vec2 dy = abs(dFdy(texUV));
  return max(dx + dy, vec2(0.00035));
}

float getMoonPassMask() {
  return float(renderStage == MC_RENDER_STAGE_MOON);
}

vec4 getMoonTileBounds() {
  vec2 tileIndex = floor(texUV * MOON_ATLAS_GRID);
  vec2 tileMin = tileIndex / MOON_ATLAS_GRID;
  vec2 tileMax = (tileIndex + 1.0) / MOON_ATLAS_GRID;
  vec2 pad = getUvFootprint() * 4.0;
  return vec4(tileMin + pad, tileMax - pad);
}

float getMoonLitMask(vec3 rgb) {
  return smoothstep(0.03, 0.18, luma(rgb));
}

vec3 getMoonHaloTint() {
  return vec3(1.08, 1.01, 0.68) + MOON_COLOR * vec3(0.14, 0.08, 0.00);
}

vec3 getMoonTintedColor(vec3 rgb, float litMask) {
  vec3 surfaceTint = vec3(1.06, 1.01, 0.82) + MOON_COLOR * vec3(0.16, 0.10, 0.00);
  vec3 goldTint = normalize(vec3(1.00, 0.92, 0.58) + MOON_COLOR * vec3(0.35, 0.20, 0.00) + vec3(0.0001));
  float energy = max(luma(rgb), max(max(rgb.r, rgb.g), rgb.b) * 0.92);
  vec3 warmSurface = rgb * surfaceTint;
  vec3 warmCore = energy * goldTint * 1.22;
  vec3 warmMoon = mix(warmSurface, warmCore, 0.68);
  return mix(rgb, warmMoon, litMask);
}

vec4 sampleSkyTex(vec2 uv, float moonPassMask) {
  if (moonPassMask > 0.5) {
    vec4 tileBounds = getMoonTileBounds();
    uv = clamp(uv, tileBounds.xy, tileBounds.zw);
  }

  #if __VERSION__ < 130
    return texture2D(texture, uv);
  #else
    return texture(texture, uv);
  #endif
}

float getBlurWeight(int index) {
  if (index == 0) return 0.10855;
  if (index == 1) return 0.13135;
  if (index == 2) return 0.10406;
  if (index == 3) return 0.07216;
  if (index == 4) return 0.04380;
  if (index == 5) return 0.02328;
  if (index == 6) return 0.01083;
  if (index == 7) return 0.00441;
  return 0.00157;
}

vec3 applyBlur(vec2 coord, vec2 direction, float moonPassMask) {
  vec2 texelSize = 1.0 / vec2(viewWidth, viewHeight);
  vec3 result = vec3(0.0);
  float blurWeight = 0.0;

  for (int i = 0; i < 9; ++i) {
    float baseWeight = getBlurWeight(i);
    vec4 tap = sampleSkyTex(coord + direction * texelSize * float(i), moonPassMask);
    vec3 tapColor = tap.rgb * glColor.rgb;
    float tapMask = tap.a;

    if (moonPassMask > 0.5) {
      float litMask = getMoonLitMask(tapColor);
      tapColor = getMoonTintedColor(tapColor, litMask * 0.78);
      tapMask = litMask;
    }

    float w = baseWeight * tapMask;
    result += tapColor * w;
    blurWeight += w;

    if (i > 0) {
      tap = sampleSkyTex(coord - direction * texelSize * float(i), moonPassMask);
      tapColor = tap.rgb * glColor.rgb;
      tapMask = tap.a;

      if (moonPassMask > 0.5) {
        float litMask = getMoonLitMask(tapColor);
        tapColor = getMoonTintedColor(tapColor, litMask * 0.78);
        tapMask = litMask;
      }

      w = baseWeight * tapMask;
      result += tapColor * w;
      blurWeight += w;
    }
  }

  return result / max(blurWeight, 0.0001);
}

void main() {
  if (isEyeInWater != 0) {
    discard;
  }

  float moonPassMask = getMoonPassMask();

  vec4 color = sampleSkyTex(texUV, moonPassMask);
  color.rgb *= glColor.rgb;

  // Keep the blur fully radial, but clamp moon samples inside the current
  // atlas tile so waxing/waning phases do not bleed adjacent purple tiles.
  vec3 blur = vec3(0.0);
  blur += applyBlur(texUV, vec2(4.0, 0.0), moonPassMask);
  blur += applyBlur(texUV, vec2(0.0, 4.0), moonPassMask);
  blur += applyBlur(texUV, vec2(2.828, 2.828), moonPassMask);
  blur += applyBlur(texUV, vec2(2.828, -2.828), moonPassMask);

  float moonLitMask = moonPassMask * getMoonLitMask(color.rgb);
  float blurMask = mix(color.a, moonLitMask, moonPassMask);
  vec3 blurContribution = blur * blurMask;

  if (moonPassMask > 0.5) {
    vec3 haloTint = getMoonHaloTint();
    float haloLuma = luma(blurContribution);
    float haloWarmMask = smoothstep(0.002, 0.055, haloLuma);
    blurContribution = mix(blurContribution, haloLuma * haloTint, 0.82 * haloWarmMask);
  }

  color.rgb += blurContribution;

  // Keep the moon warm and golden, but still softer than the stars/comets.
  color.rgb = getMoonTintedColor(color.rgb, moonLitMask * 0.90);

  float dither = bayer4(gl_FragCoord.xy / 2.0);
  color.rgb = floor(color.rgb * 12.0 + dither) / 12.0;

  color *= 1.0 - rainStrength;

  /* DRAWBUFFERS:0 */
  gl_FragData[0] = color;
}
