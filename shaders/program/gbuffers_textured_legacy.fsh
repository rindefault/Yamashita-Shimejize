#define gbuffers_textured_legacy

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
uniform int worldTime;
uniform int entityId;
uniform int isEyeInWater;
uniform int renderStage;
uniform sampler2D texture;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform vec4 entityColor;
uniform float far;
uniform ivec2 eyeBrightness;
uniform ivec2 eyeBrightnessSmooth;

uniform float viewHeight;
uniform float viewWidth;
uniform sampler2D noisetex;
uniform vec3 shadowLightPosition;

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
varying vec4 attrColor;
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

const int passType = PASS_TEXTURED;

#include "/common/transformations.fsh"
#include "/common/getTorchStrength.vsh"
#include "/common/getTorchColor.fsh"
#include "/common/getSkyAndFogColors.fsh"
#include "/common/getLightColor.fsh"
#include "/common/getSubmergedFogColor.glsl"
#include "/common/effect_metadata.glsl"
#include "/common/rain_particle_splash.glsl"

#ifndef MC_RENDER_STAGE_WORLD_BORDER
   #define MC_RENDER_STAGE_WORLD_BORDER 22
#endif

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

const int ENTITY_NAME_TAG = 11001;

float getPuddleMask(vec3 absWorldPos, vec3 worldGeoNormal, vec2 lightmapUV, vec4 albedo) {
   return 0.0;
}

vec3 normalizeWorldBorderTint(vec3 tint) {
   float tintMax = max(max(tint.r, tint.g), tint.b);
   return tint / max(tintMax, 0.001);
}

float getWorldBorderTintScore(vec3 tint) {
   float tintMax = max(max(tint.r, tint.g), tint.b);
   float tintMin = min(min(tint.r, tint.g), tint.b);
   float tintSat = (tintMax - tintMin) / max(tintMax, 0.001);
   return step(0.05, tintMax) * max(tintSat - 0.04, 0.0);
}

vec3 pickWorldBorderTint(vec3 attrTint, vec3 vertexTint) {
   float attrScore = getWorldBorderTintScore(attrTint);
   float vertexScore = getWorldBorderTintScore(vertexTint);

   if (attrScore >= vertexScore && attrScore > 0.0) {
      return normalizeWorldBorderTint(attrTint);
   }

   if (vertexScore > 0.0) {
      return normalizeWorldBorderTint(vertexTint);
   }

   return vec3(0.14, 0.40, 1.00);
}

float getColorSaturation(vec3 sampleColor) {
   float colorMax = max(max(sampleColor.r, sampleColor.g), sampleColor.b);
   float colorMin = min(min(sampleColor.r, sampleColor.g), sampleColor.b);
   return (colorMax - colorMin) / max(colorMax, 0.0001);
}

float getNameplateBackgroundMask(vec4 sampledAlbedo, vec4 vertexColor) {
   #ifndef IS_GBUFFERS_ENTITIES
      return 0.0;
   #endif

   if (entityId != ENTITY_NAME_TAG) {
      return 0.0;
   }

   float finalAlpha = sampledAlbedo.a * vertexColor.a;
   float texOpaque = step(0.95, sampledAlbedo.a);
   float texWhite = 1.0 - smoothstep(0.015, 0.060, max(max(abs(sampledAlbedo.r - 1.0), abs(sampledAlbedo.g - 1.0)), abs(sampledAlbedo.b - 1.0)));
   float darkTint = 1.0 - smoothstep(0.020, 0.120, luma(vertexColor.rgb));
   float lowSat = 1.0 - smoothstep(0.050, 0.220, getColorSaturation(vertexColor.rgb));
   float alphaBand = smoothstep(0.10, 0.18, finalAlpha) * (1.0 - smoothstep(0.38, 0.56, finalAlpha));
   return texOpaque * texWhite * darkTint * lowSat * alphaBand;
}

void main() {
   vec2 sampleUV = texUV;
   vec4 albedo = texture2D(texture, sampleUV);
   vec3 particleSampleColor = albedo.rgb;

   if (albedo.a < 0.1) {
      discard;
   }

   if (renderStage == MC_RENDER_STAGE_WORLD_BORDER) {
      vec3 worldBorderTint = pickWorldBorderTint(attrColor.rgb, color.rgb);
      vec3 worldBorderColor = particleSampleColor * worldBorderTint;
      worldBorderColor = mix(worldBorderColor, worldBorderTint, 0.18);

      fragColor0 = vec4(worldBorderColor, albedo.a);
      hotMaskOut = vec4(0.0, 0.0, 0.0, 1.0);
      infoOut = vec4(0.0, 0.0, 0.0, 1.0);
      return;
   }

   float nameplateBackgroundMask = getNameplateBackgroundMask(albedo, color);
   if (nameplateBackgroundMask > 0.5) {
      vec4 nameplateBackground = vec4(albedo.rgb * color.rgb, albedo.a * color.a);
      nameplateBackground.a *= 0.62;

      fragColor0 = nameplateBackground;
      hotMaskOut = vec4(0.0, 0.0, 0.0, 1.0);
      infoOut = vec4(0.0, 0.0, 0.0, 1.0);
      return;
   }

   vec2 runtimeLightUV = clamp(lightUV, 0.0, 1.0);

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
      sunStrength *= 0.50;
      float shadowFactor = 0.35;

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
   float skyLight = runtimeLightUV.t;
   blockLight = max(blockLight, mix(TORCH_UV_SCALE.x, TORCH_UV_SCALE.y, clamp(lmcoord.x, 0.0, 1.0)));
   blockLight = max(blockLight, clamp(lightUV.s, 0.0, 1.0));

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

   albedo.a = entityId == 11000 ? 0.15 : albedo.a;

   float ambientOcclusion = 1.0;
   torchStrength = getTorchStrength(blockLight);
   vec3 torchContrib = getTorchColor(ambient.rgb);

   albedo.rgb *= ambient.rgb;
   float envFit = mix(0.70, 0.90, skyLight);
   albedo.rgb *= envFit;

   albedo.rgb += albedoUnlit * torchContrib * 1.35;
   albedo.rgb *= ambientOcclusion;

   float sceneLum = luma(albedo.rgb);
   float brightFactor = smoothstep(0.12, 0.65, sceneLum);
   float hitTint = clamp(entityColor.a * mix(0.30, 1.00, brightFactor), 0.0, 1.0);
   vec3 hurtColor = mix(albedo.rgb, entityColor.rgb, 0.75);
   albedo.rgb = mix(albedo.rgb, hurtColor, hitTint);

   float fogMixFinal = clamp(ditheredFog, 0.0, 1.0);
   float rainFogBoost = rainAmtFog * smoothstep(0.22, 0.76, fogMixFinal) * 0.36;
   fogMixFinal = clamp(fogMixFinal + rainFogBoost, 0.0, 1.0);
   float rainReliefKill = rainAmtFog * smoothstep(0.26, 0.84, fogMixFinal);
   albedo.rgb = mix(albedo.rgb, vec3(luma(albedo.rgb)), rainReliefKill * 0.84);
   albedo.rgb = mix(albedo.rgb, finalFogColor, fogMixFinal);

   if (rainAmtFog > 0.02) {
      float lumP = luma(albedo.rgb);
      float waterLike = getWaterSplashLikeParticleMask(particleSampleColor, albedo.a);
      float physicsRainLike = getPhysicsRainLikeParticleMask(particleSampleColor, albedo.a);
      float rainLike = max(waterLike, physicsRainLike);
      if (rainLike > 0.01) {
         float blockL = clamp(blockLight * 1.25, 0.0, 1.0);
         #ifdef HAND_DYNAMIC_LIGHTING
            int heldLight = max(heldBlockLightValue, heldBlockLightValue2);
            if (heldLight > 0) {
               float heldMaskWorld = min(1.0, float(heldLight) / heldLightDistDenom);
               vec2 heldScreenUV = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
               vec4 heldClipPos = vec4(heldScreenUV * 2.0 - 1.0, gl_FragCoord.z * 2.0 - 1.0, 1.0);
               vec4 heldViewPos = gbufferProjectionInverse * heldClipPos;
               float heldDistView = length(heldViewPos.xyz / max(heldViewPos.w, 0.0001));
               float heldMaskView = min(1.0, float(heldLight) / pow2(heldDistView + 1.5));

               float heldMask = max(heldMaskWorld, heldMaskView);
               float heldFloor = (float(heldLight) / 15.0) * 0.22;
               blockL = max(blockL, max(heldMask * 2.4, heldFloor));
            }
         #endif
         float lightInfluence = max(lumP, blockL);
         float shade = smoothstep(0.06, 0.88, lightInfluence);
         shade = shade * shade * (3.0 - 2.0 * shade);
         vec3 splashColor = getRainSplashParticleColor(shade);
         albedo.rgb = mix(albedo.rgb, splashColor, rainLike);

         if (waterLike > 0.01) {
            float splashCoverage = getVanillaRainSplashCoverage(shade);
            if (bayer4(gl_FragCoord.xy) > splashCoverage) {
               discard;
            }
         }

         if (physicsRainLike > 0.01) {
            float splashOpacity = WEATHER_OPACITY;
            albedo.a *= mix(1.0, splashOpacity, physicsRainLike);
         }
      }
   }

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

   float foregroundMarker = 0.0;
   #ifdef IS_GBUFFERS_ENTITIES
      foregroundMarker = step(0.1, albedo.a);
   #endif
   float handMarker = 0.0;
   #ifdef IS_GBUFFERS_HAND
      handMarker = step(0.1, albedo.a);
   #endif
   float effectMaskData = encodeEffectMetadata(puddleMask, foregroundMarker, handMarker);

   /* DRAWBUFFERS:027 */
   fragColor0 = albedo;
   hotMaskOut = vec4(hotMaskHaze, hotMaskGlow, lightAreaMask, effectMaskData);
   infoOut = vec4(0.0);
}
