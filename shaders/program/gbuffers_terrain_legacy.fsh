#define gbuffers_terrain_legacy

#include "/shader.h"

uniform vec3 cameraPosition;
uniform sampler2D lightmap;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;

uniform float rainStrength;
uniform float rainFactor;
uniform float wetness;
uniform float isCold;
uniform float isWarm;
uniform float darknessLightFactor;
uniform float screenBrightness;
uniform float timeAngle;
uniform float frameTimeCounter;
uniform int isEyeInWater;
uniform sampler2D texture;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform ivec2 eyeBrightness;
uniform ivec2 eyeBrightnessSmooth;

uniform float viewHeight;
uniform float viewWidth;

float torchStrength;

varying vec3 upVec;
varying vec3 sunVec;
varying vec2 lmcoord;
varying vec3 normal;
varying float fogMix;
varying float isLava;
varying vec2 lightUV;
varying vec2 texUV;
varying vec3 worldPos;
varying vec4 color;
varying float foliageWindMask;
varying float hotSourceMask;
varying float hotGlowSourceMask;

#ifdef GLOWING_ORES
varying float isOre;
#endif

#ifdef HAND_DYNAMIC_LIGHTING
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;
#endif

#include "/common/math.glsl"
#include "/common/material_ids.glsl"
#include "/common/pass_classes.glsl"

const int passType = PASS_TERRAIN;

#include "/common/transformations.fsh"
#include "/common/getTorchStrength.vsh"
#include "/common/getTorchColor.fsh"
#include "/common/getSkyAndFogColors.fsh"
#include "/common/getLightColor.fsh"
#include "/common/getSubmergedFogColor.glsl"
#include "/common/effect_metadata.glsl"
#include "/common/getFoliageWindUV.glsl"

#ifdef ENABLE_SHADOWS
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform sampler2D shadowtex1;

varying vec3 sunColor;
varying float diffuse;

#include "/common/getSunStrength.fsh"
#endif

#define fragColor0 gl_FragData[0]
#define hotMaskOut gl_FragData[1]
#define infoOut gl_FragData[2]

vec2 rotateBlob(vec2 p, float angle) {
   float s = sin(angle);
   float c = cos(angle);
   return mat2(c, -s, s, c) * p;
}

float ellipseBlobMask(vec2 p, vec2 center, vec2 radius) {
   vec2 q = (p - center) / max(radius, vec2(0.001));
   return 1.0 - smoothstep(0.86, 1.06, length(q));
}

float roundedRectBlobMask(vec2 p, vec2 center, vec2 halfSize, float radius) {
   vec2 d = abs(p - center) - halfSize;
   float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
   return 1.0 - smoothstep(-0.035, 0.040, dist);
}

float getPuddleCellShape(vec2 macroCell, vec2 localCoord) {
   const float PUDDLE_GRID = 96.0;

   float regionGate = max(
      step(0.60, random(macroCell + vec2(7.0, 19.0))),
      step(0.76, random(macroCell * 0.5 + vec2(31.0, 11.0)))
   );
   if (regionGate < 0.5) return 0.0;

   vec2 macroPixel = floor(localCoord * PUDDLE_GRID);
   vec2 blobUV = (macroPixel + 0.5) / PUDDLE_GRID;

   vec2 center = vec2(0.5) + (vec2(
      random(macroCell + vec2(4.0, 24.0)),
      random(macroCell + vec2(17.0, 8.0))
   ) - 0.5) * 0.22;
   float angle = random(macroCell + vec2(28.0, 6.0)) * 6.28318530718;
   vec2 p = rotateBlob(blobUV - center, angle);

   float shapeSeed = random(macroCell + vec2(9.0, 33.0));
   float sizeSeedA = random(macroCell + vec2(2.0, 14.0));
   float sizeSeedB = random(macroCell + vec2(20.0, 6.0));
   float sizeSeedC = random(macroCell + vec2(12.0, 7.0));
   float sizeSeedD = random(macroCell + vec2(25.0, 10.0));
   float puddle = 0.0;

   if (shapeSeed < 0.25) {
      float main = ellipseBlobMask(p, vec2(0.00, 0.00), vec2(mix(0.30, 0.44, sizeSeedA), mix(0.18, 0.27, sizeSeedB)));
      float bulgeA = ellipseBlobMask(p, vec2(-0.16, 0.08), vec2(mix(0.14, 0.20, sizeSeedC), mix(0.12, 0.17, sizeSeedD)));
      float bulgeB = ellipseBlobMask(p, vec2(0.18, -0.05), vec2(mix(0.16, 0.22, sizeSeedB), mix(0.11, 0.16, sizeSeedA)));
      puddle = max(main, max(bulgeA * 0.94, bulgeB * 0.94));
   } else if (shapeSeed < 0.50) {
      float lobeA = ellipseBlobMask(p, vec2(-0.22, 0.04), vec2(mix(0.20, 0.27, sizeSeedA), mix(0.16, 0.21, sizeSeedB)));
      float lobeB = ellipseBlobMask(p, vec2(0.10, -0.03), vec2(mix(0.25, 0.33, sizeSeedC), mix(0.15, 0.20, sizeSeedD)));
      float bridge = ellipseBlobMask(p, vec2(-0.04, 0.00), vec2(0.20, 0.12));
      float tailGate = step(0.42, random(macroCell + vec2(18.0, 29.0)));
      float tail = ellipseBlobMask(p, vec2(0.30, -0.14), vec2(0.12, 0.09));
      puddle = max(max(lobeA, lobeB), max(bridge, tail * tailGate * 0.88));
   } else if (shapeSeed < 0.75) {
      float armA = roundedRectBlobMask(p, vec2(-0.08, 0.18), vec2(mix(0.28, 0.36, sizeSeedA), 0.12), 0.09);
      float armB = roundedRectBlobMask(p, vec2(0.18, -0.08), vec2(0.12, mix(0.26, 0.34, sizeSeedB)), 0.09);
      float elbow = ellipseBlobMask(p, vec2(0.02, 0.02), vec2(0.18, 0.18));
      float spurGate = step(0.55, random(macroCell + vec2(5.0, 35.0)));
      float spur = ellipseBlobMask(p, vec2(-0.28, 0.28), vec2(0.12, 0.09));
      puddle = max(max(armA, armB), max(elbow, spur * spurGate * 0.86));
   } else {
      float lobeA = ellipseBlobMask(p, vec2(-0.24, 0.16), vec2(0.18, 0.15));
      float lobeB = ellipseBlobMask(p, vec2(-0.02, 0.02), vec2(mix(0.22, 0.28, sizeSeedA), mix(0.16, 0.21, sizeSeedB)));
      float lobeC = ellipseBlobMask(p, vec2(0.22, -0.16), vec2(0.18, 0.14));
      float tip = ellipseBlobMask(p, vec2(0.36, -0.28), vec2(0.10, 0.08));
      puddle = max(max(lobeA, lobeB), max(lobeC, tip * 0.84));
   }

   float satelliteGate = step(0.72, random(macroCell + vec2(22.0, 27.0)));
   vec2 satellitePos = vec2(
      mix(-0.34, 0.34, random(macroCell + vec2(30.0, 14.0))),
      mix(-0.28, 0.28, random(macroCell + vec2(6.0, 25.0)))
   );
   float satellite = ellipseBlobMask(p, satellitePos, vec2(0.10, 0.08));
   puddle = max(puddle, satellite * satelliteGate * 0.84);

   vec2 chunk3 = floor(macroPixel / 3.0);
   vec2 chunk5 = floor(macroPixel / 5.0);
   float edgeNoiseA = random(macroCell * 17.0 + chunk3 + vec2(3.0, 23.0));
   float edgeNoiseB = random(macroCell * 9.0 + chunk5 + vec2(13.0, 5.0));
   float edgeCut = step(0.18, edgeNoiseA) * mix(0.74, 1.0, step(0.52, edgeNoiseB));
   float coreMask = smoothstep(0.26, 0.62, puddle);
   puddle *= mix(edgeCut, 1.0, coreMask);
   return smoothstep(0.14, 0.52, puddle);
}

float getPuddleMask(vec3 absWorldPos, vec3 worldGeoNormal, vec2 lightmapUV, vec4 albedo) {
   #if !defined OVERWORLD || ENABLE_PUDDLES == 0
      return 0.0;
   #else
      if (isLava > 0.5 || foliageWindMask > 0.5 || albedo.a < 0.95) return 0.0;

      float rainMemory = max(rainStrength, wetness);
      if (rainMemory <= 0.10) return 0.0;

      float coldBiomeMask = 1.0 - smoothstep(0.18, 0.48, clamp(isCold, 0.0, 1.0));
      float dryWarmBiomeMask = 1.0 - smoothstep(0.18, 0.48, clamp(isWarm, 0.0, 1.0));
      float biomeWetMask = coldBiomeMask * dryWarmBiomeMask;
      if (biomeWetMask <= 0.0) return 0.0;

      float wetMask = smoothstep(0.10, 0.30, rainMemory);
      wetMask *= biomeWetMask;

      float worldUp = clamp(worldGeoNormal.y, 0.0, 1.0);
      if (worldUp <= 0.93 || lightmapUV.t <= 0.62) return 0.0;

      float flatMask = smoothstep(0.93, 0.995, worldUp);
      float skyMask = smoothstep(0.62, 0.96, lightmapUV.t);
      float blockFade = 1.0 - smoothstep(0.34, 0.92, lightmapUV.s);
      float surfaceMask = flatMask * skyMask * mix(1.0, blockFade, 0.35);
      if (surfaceMask <= 0.0) return 0.0;

      vec2 macroWorld = absWorldPos.xz / 6.0;
      vec2 macroCell = floor(macroWorld);
      vec2 macroFrac = fract(macroWorld);
      const float CELL_SPILL = 0.22;

      float puddle = getPuddleCellShape(macroCell, macroFrac);

      bool sampleLeft = macroFrac.x < CELL_SPILL;
      bool sampleRight = macroFrac.x > 1.0 - CELL_SPILL;
      bool sampleDown = macroFrac.y < CELL_SPILL;
      bool sampleUp = macroFrac.y > 1.0 - CELL_SPILL;

      if (sampleLeft) {
         puddle = max(puddle, getPuddleCellShape(macroCell + vec2(-1.0, 0.0), macroFrac + vec2(1.0, 0.0)));
      }
      if (sampleRight) {
         puddle = max(puddle, getPuddleCellShape(macroCell + vec2(1.0, 0.0), macroFrac - vec2(1.0, 0.0)));
      }
      if (sampleDown) {
         puddle = max(puddle, getPuddleCellShape(macroCell + vec2(0.0, -1.0), macroFrac + vec2(0.0, 1.0)));
      }
      if (sampleUp) {
         puddle = max(puddle, getPuddleCellShape(macroCell + vec2(0.0, 1.0), macroFrac - vec2(0.0, 1.0)));
      }
      if (sampleLeft && sampleDown) {
         puddle = max(puddle, getPuddleCellShape(macroCell + vec2(-1.0, -1.0), macroFrac + vec2(1.0, 1.0)));
      }
      if (sampleLeft && sampleUp) {
         puddle = max(puddle, getPuddleCellShape(macroCell + vec2(-1.0, 1.0), macroFrac + vec2(1.0, -1.0)));
      }
      if (sampleRight && sampleDown) {
         puddle = max(puddle, getPuddleCellShape(macroCell + vec2(1.0, -1.0), macroFrac + vec2(-1.0, 1.0)));
      }
      if (sampleRight && sampleUp) {
         puddle = max(puddle, getPuddleCellShape(macroCell + vec2(1.0, 1.0), macroFrac - vec2(1.0, 1.0)));
      }

      puddle *= surfaceMask * wetMask;
      return floor(puddle * 4.0 + 0.5) * 0.25;
   #endif
}

void main() {
   vec2 sampleUV = getFoliageWindUV(texUV);
   vec4 albedo = texture2D(texture, sampleUV);
   if (albedo.a < 0.1) {
      discard;
   }

   vec2 pixelationOffset = ComputeTexelOffset(texture, texUV);
   vec2 runtimeLightUV = clamp(TexelSnap(lightUV, pixelationOffset), 0.0, 1.0);

   vec4 ambient = texture2D(lightmap, vec2(AMBIENT_UV.s, runtimeLightUV.t));

   #ifdef GLOWING_ORES
      ambient.rgb = mix(
         ambient.rgb,
         vec3(1.0, 0.9, 0.9),
         isOre * 0.3333 * squaredLength(rescale(albedo.rgb, vec3(0.59), vec3(1.0)))
      );
   #endif

   albedo.rgb *= color.rgb;

   vec3 playerPos = worldPos;
   float playerDist = length(playerPos);
   vec3 viewPos = world2screen(playerPos);
   #ifdef HAND_DYNAMIC_LIGHTING
      float heldLightDistDenom = pow2(playerDist + 1.5);
   #endif
   float dayBright = max(sin(timeAngle * 6.28318530718), 0.0);

   #ifdef ENABLE_SHADOWS
      float sunStrength = max(0.75 * isLava, getSunStrength() * dayBright);
      float shadowFactor = 1.0 - sunStrength;

      const float SHADOW_MAX_BLACKNESS = 0.6;
      vec3 shadowColor = vec3(1.0);

      ambient.rgb *= shadowColor * (1.0 - shadowFactor * SHADOW_MAX_BLACKNESS);

      float blueness = shadowFactor * SHADOW_BLUENESS;
      ambient.g *= 1.0 + 0.3333 * blueness;
      ambient.b *= 1.0 + blueness;

      float sunBrightness = max(0.0, SUN_BRIGHTNESS - 0.5 * pow3(luma(albedo.rgb)));
      ambient.rgb += (sunBrightness * sunStrength) * sunColor;
   #endif

   const int bands = 16;
   float bandSize = 1.0 / float(bands);
   float bandBase = floor(fogMix * bands) * bandSize;
   float posInBand = fract(fogMix * bands);
   float dither = bayer4(gl_FragCoord.xy / 2.0);
   float ditheredFog = bandBase + (posInBand > dither ? bandSize : 0.0);

   vec3 viewRay = viewPos / max(playerDist, 0.0001);
   float VoU = clamp(dot(viewRay, upVec), 0.0, 1.0);
   float VoL = clamp(dot(viewRay, sunVec), 0.0, 1.0);
   float rainAmtFog = max(rainStrength, rainFactor);
   float lowSun = 1.0 - dayBright;
   float sunDirDamp = rainAmtFog * mix(0.42, 0.82, lowSun);
   float VoLfog = mix(VoL, VoL * 0.22, sunDirDamp);

   vec3 finalFogColor;
   if (isEyeInWater != 0) {
      finalFogColor = getSubmergedFogColor(isEyeInWater, fogColor);
   }
   #if defined OVERWORLD
      else {
         finalFogColor = getSky(VoU, VoLfog, dither);
         vec3 rainSkyOvercast = mix(skyColor, fogColor, 0.45);
         rainSkyOvercast = mix(rainSkyOvercast, vec3(luma(rainSkyOvercast)), 0.35);
         finalFogColor = mix(finalFogColor, rainSkyOvercast, rainAmtFog * 0.58);
      }
   #else
      if (isEyeInWater == 0) {
         finalFogColor = fogColor;
      }
   #endif

   vec2 lmCoordM = runtimeLightUV;
   float blockLight = runtimeLightUV.s;
   vec3 normalM = normal;
   vec3 shadowMult = vec3(1.0);
   vec3 worldGeoNormal = mat3(gbufferModelViewInverse) * normal;
   float puddleMask = 0.0;
   #if defined OVERWORLD && ENABLE_PUDDLES > 0
      vec3 absWorldPos = worldPos + cameraPosition;
      puddleMask = getPuddleMask(absWorldPos, worldGeoNormal, lmCoordM, albedo);
   #endif

   vec3 albedoUnlit = albedo.rgb;
   doLighting(albedo, shadowMult, normalM, worldGeoNormal, lmCoordM);

   float ambientOcclusion = TexelSnap(color.a, pixelationOffset);
   torchStrength = getTorchStrength(blockLight);
   vec3 torchContrib = getTorchColor(ambient.rgb);

   albedo.rgb *= ambient.rgb;
   albedo.rgb += albedoUnlit * torchContrib;
   albedo.rgb *= ambientOcclusion;

   float fogMixFinal = clamp(ditheredFog, 0.0, 1.0);
   float rainFogBoost = rainAmtFog * smoothstep(0.22, 0.76, fogMixFinal) * 0.36;
   fogMixFinal = clamp(fogMixFinal + rainFogBoost, 0.0, 1.0);
   float rainReliefKill = rainAmtFog * smoothstep(0.26, 0.84, fogMixFinal);
   albedo.rgb = mix(albedo.rgb, vec3(luma(albedo.rgb)), rainReliefKill * 0.84);
   albedo.rgb = mix(albedo.rgb, finalFogColor, fogMixFinal);

   float hotMaskHaze = 0.0;
   float hotMaskGlow = 0.0;
   float torchEnergy = luma(albedoUnlit * torchContrib);
   float lightAreaMask = clamp(max(blockLight * 1.15, torchEnergy * 10.0), 0.0, 1.0);
   #ifdef HAND_DYNAMIC_LIGHTING
      float heldMask = 0.0;
      if (heldBlockLightValue > 0) {
         heldMask = min(1.0, float(heldBlockLightValue) / heldLightDistDenom);
      }
      lightAreaMask = max(lightAreaMask, heldMask * 1.55);
   #endif
   if (max(hotSourceMask, hotGlowSourceMask) > 0.0) {
      float hotLum = luma(albedo.rgb);
      float hotWarm = albedo.r / max(albedo.g * 0.70 + albedo.b * 0.30, 0.001);
      float hotSat = length(albedo.rgb - vec3(hotLum));
      float hotColorMask =
         smoothstep(1.08, 2.45, hotWarm) *
         smoothstep(0.04, 0.95, hotLum) *
         smoothstep(0.03, 0.42, hotSat);
      float hotTorchMask =
         smoothstep(1.30, 2.80, hotWarm) *
         smoothstep(0.16, 0.80, albedo.r - albedo.g) *
         smoothstep(0.06, 0.65, albedo.g - albedo.b) *
         smoothstep(0.14, 1.05, hotLum) *
         smoothstep(0.07, 0.45, hotSat);
      float hotLanternMask =
         smoothstep(0.18, 1.05, hotLum) *
         smoothstep(1.02, 2.20, hotWarm) *
         smoothstep(0.02, 0.30, hotSat);
      float strongHotSource = smoothstep(0.85, 0.95, hotSourceMask);
      float hotFloor = strongHotSource * 0.28;
      float torchLikeSource = smoothstep(0.45, 0.62, hotSourceMask) * (1.0 - smoothstep(0.62, 0.82, hotSourceMask));
      float lanternLikeSource = smoothstep(0.78, 0.88, hotSourceMask);
      float refinedHotMask = max(hotColorMask, hotFloor);
      refinedHotMask = mix(refinedHotMask, hotTorchMask, torchLikeSource);
      refinedHotMask = mix(refinedHotMask, max(hotLanternMask, hotFloor * 0.75), lanternLikeSource);
      float alphaGate = step(0.1, albedo.a);
      hotMaskHaze = hotSourceMask * refinedHotMask * alphaGate;
      hotMaskGlow = hotGlowSourceMask * max(refinedHotMask, hotLanternMask) * alphaGate;
   }

   float effectMaskData = encodeEffectMetadata(puddleMask, 0.0, 0.0);

   /* DRAWBUFFERS:027 */
   fragColor0 = albedo;
   hotMaskOut = vec4(hotMaskHaze, hotMaskGlow, lightAreaMask, effectMaskData);
   infoOut = vec4(0.0);
}
