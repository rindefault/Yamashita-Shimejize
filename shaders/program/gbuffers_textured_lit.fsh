#define gbuffers_textured_lit

#include "/shader.h"

uniform vec3 cameraPosition;
uniform sampler2D lightmap;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
// Declared outside #ifdef ENABLE_SHADOWS because it is also used for
// view-space fog reconstruction (lines below), which runs unconditionally.
uniform mat4 gbufferProjectionInverse;

uniform float rainStrength, rainFactor;
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
uniform sampler2D texture;
uniform vec3 fogColor, skyColor;
uniform vec4 entityColor;
uniform float far;
uniform ivec2 eyeBrightness;
uniform ivec2 eyeBrightnessSmooth;

uniform float viewHeight, viewWidth;
uniform sampler2D noisetex;
uniform vec3 shadowLightPosition;

float torchStrength;

in vec3 upVec;
in vec3 sunVec;
in vec2 lmcoord;
in vec3 normal;
flat in int time;
flat in int passType;
flat in int materialId;

in float fogMix;
in float isLava;
in vec2 lightUV;
in vec2 texUV;
in vec3 worldPos;
in vec4 color;
in float foliageWindMask;
in float hotSourceMask;
in float hotGlowSourceMask;

#ifdef IS_GBUFFERS_TERRAIN
in vec2 signMidCoordPos;
flat in vec2 absMidCoordPos;
flat in vec2 midCoord;
#endif

#ifdef GLOWING_ORES
   in float isOre;
#endif

#ifdef HAND_DYNAMIC_LIGHTING
   uniform int heldBlockLightValue;
   uniform int heldBlockLightValue2;
#endif

#include "/common/math.glsl"
#include "/common/material_ids.glsl"
#include "/common/pass_classes.glsl"
#include "/common/transformations.fsh"
#include "/common/getTorchStrength.vsh"
#include "/common/getTorchColor.fsh"
#include "/common/getSkyAndFogColors.fsh"
#include "/common/getLightColor.fsh"
#include "/common/getSubmergedFogColor.glsl"
#include "/common/effect_metadata.glsl"
#include "/common/rain_particle_splash.glsl"

#ifdef ENABLE_SHADOWS
   uniform mat4 shadowModelView;
   uniform mat4 shadowProjection;
   uniform sampler2D shadowtex1;

   in vec3 sunColor;
   in float diffuse;

   #include "/common/getSunStrength.fsh"
#endif

layout(location = 0) out vec4 fragColor0;
layout(location = 1) out vec4 hotMaskOut;
layout(location = 2) out vec4 infoOut;

vec4 resolveFoliageWindTexels(vec4 baseAlbedo, vec4 shiftedAlbedo, float phase) {
   phase = clamp(phase, 0.0, 1.0);
   float alpha = mix(baseAlbedo.a, shiftedAlbedo.a, phase);

   float baseMask = step(0.1, baseAlbedo.a);
   float shiftedMask = step(0.1, shiftedAlbedo.a);
   float enteringEdge = (1.0 - baseMask) * shiftedMask;
   float enteringBlend = enteringEdge * smoothstep(0.22, 0.82, phase);

   // Keep interior texels stable; only let the neighbor color take over when a
   // new silhouette pixel is actually entering from the wind direction.
   vec3 rgb = mix(baseAlbedo.rgb, shiftedAlbedo.rgb, enteringBlend);
   return vec4(rgb, alpha);
}

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
      // Broad oval with uneven shoulders.
      float main = ellipseBlobMask(p, vec2(0.00, 0.00), vec2(mix(0.30, 0.44, sizeSeedA), mix(0.18, 0.27, sizeSeedB)));
      float bulgeA = ellipseBlobMask(p, vec2(-0.16, 0.08), vec2(mix(0.14, 0.20, sizeSeedC), mix(0.12, 0.17, sizeSeedD)));
      float bulgeB = ellipseBlobMask(p, vec2(0.18, -0.05), vec2(mix(0.16, 0.22, sizeSeedB), mix(0.11, 0.16, sizeSeedA)));
      puddle = max(main, max(bulgeA * 0.94, bulgeB * 0.94));
   } else if (shapeSeed < 0.50) {
      // Bean / peanut silhouette.
      float lobeA = ellipseBlobMask(p, vec2(-0.22, 0.04), vec2(mix(0.20, 0.27, sizeSeedA), mix(0.16, 0.21, sizeSeedB)));
      float lobeB = ellipseBlobMask(p, vec2(0.10, -0.03), vec2(mix(0.25, 0.33, sizeSeedC), mix(0.15, 0.20, sizeSeedD)));
      float bridge = ellipseBlobMask(p, vec2(-0.04, 0.00), vec2(0.20, 0.12));
      float tailGate = step(0.42, random(macroCell + vec2(18.0, 29.0)));
      float tail = ellipseBlobMask(p, vec2(0.30, -0.14), vec2(0.12, 0.09));
      puddle = max(max(lobeA, lobeB), max(bridge, tail * tailGate * 0.88));
   } else if (shapeSeed < 0.75) {
      // Bent L-shaped puddle with a soft elbow.
      float armA = roundedRectBlobMask(p, vec2(-0.08, 0.18), vec2(mix(0.28, 0.36, sizeSeedA), 0.12), 0.09);
      float armB = roundedRectBlobMask(p, vec2(0.18, -0.08), vec2(0.12, mix(0.26, 0.34, sizeSeedB)), 0.09);
      float elbow = ellipseBlobMask(p, vec2(0.02, 0.02), vec2(0.18, 0.18));
      float spurGate = step(0.55, random(macroCell + vec2(5.0, 35.0)));
      float spur = ellipseBlobMask(p, vec2(-0.28, 0.28), vec2(0.12, 0.09));
      puddle = max(max(armA, armB), max(elbow, spur * spurGate * 0.86));
   } else {
      // Crooked chain / hook-like blob.
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
      if (isLava > 0.5 || materialId == 10068) return 0.0;
      if (!isTerrainPass(passType) || foliageWindMask > 0.5 || albedo.a < 0.95) return 0.0;

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
      // Keep puddles outdoors, but do not let a nearby torch erase them.
      // Local block light should only soften the puddle a bit, not zero it out.
      float blockFade = 1.0 - smoothstep(0.34, 0.92, lightmapUV.s);
      float surfaceMask = flatMask * skyMask * mix(1.0, blockFade, 0.35);
      if (surfaceMask <= 0.0) return 0.0;

      // Build puddles as larger 6x6-block inkblots with shape archetypes.
      // Sample neighboring macro cells near the borders so large blobs do not
      // get hard-clipped by the underlying 6x6 generation grid.
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
   vec2 sampleUV = texUV;
   bool foliageWarpActive = false;
   float foliageWarpPhase = 0.0;
   ivec2 baseTexelCoord = ivec2(0);
   ivec2 warpedTexelCoord = ivec2(0);
#if PIXEL_FOLIAGE_WIND > 0
   if (isTerrainPass(passType) && foliageWindMask > 0.5) {
      float rawSkyExposure = clamp(float(eyeBrightness.y) / 240.0, 0.0, 1.0);
      float smoothSkyExposure = clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0);
      float windOutdoorMask = smoothstep(0.72, 0.93, mix(smoothSkyExposure, rawSkyExposure, 0.18));

      if (windOutdoorMask > 0.01) {
      ivec2 atlasSizeI = ivec2(textureSize(texture, 0));
      vec2 atlasSize = vec2(atlasSizeI);
      vec2 atlasTexel = 1.0 / atlasSize;
      vec2 safeUV = clamp(sampleUV, atlasTexel * 0.5, vec2(1.0) - atlasTexel * 0.5);

      // Coarser virtual pixel grid (2x2 atlas texels per step) to match
      // the intended 16x16-like chunky motion instead of overly fine 24/32 feel.
      float windPixelScale = max(1.0, float(FOLIAGE_WIND_RES) * 0.125);
      vec2 coarseCoord = floor((safeUV * atlasSize) / windPixelScale);

      vec2 absWorldXZ = floor(worldPos.xz + cameraPosition.xz + vec2(0.001));
      float rowPhase = random(absWorldXZ * 0.25 + vec2(13.0, 7.0)) * 6.28318530718;
      // Original motion profile: keep the old feel.
      float t = frameTimeCounter * 0.84;
      float rowWave = sin(coarseCoord.y * 0.16 + t + rowPhase);

      float rawShiftX = rowWave * windOutdoorMask;
      float shiftMag = abs(rawShiftX);
      int shiftSignX = rawShiftX > 0.0 ? 1 : (rawShiftX < 0.0 ? -1 : 0);
      if (shiftMag <= 0.01) {
         shiftSignX = 0;
      }
      ivec2 shiftDir = ivec2(shiftSignX, 0);
      float shiftPhase = smoothstep(0.08, 0.92, shiftMag);

      // Pixel-perfect sampling: snap both source and shifted UVs to texel centers.
      ivec2 baseTexel = ivec2(floor(safeUV * atlasSize));
      // Prevent crossing sprite tile edges in the atlas (16x16 texel tile),
      // which causes one-sided seam stripes on foliage in 1.21.5.
      const int windTile = FOLIAGE_WIND_RES;
      int localX = baseTexel.x % windTile;
      int localY = baseTexel.y % windTile;
      if ((shiftDir.x > 0 && localX >= windTile - 1) || (shiftDir.x < 0 && localX <= 0)) shiftDir.x = 0;
      if ((shiftDir.y > 0 && localY >= windTile - 1) || (shiftDir.y < 0 && localY <= 0)) shiftDir.y = 0;

      ivec2 shiftedTexel = clamp(baseTexel + shiftDir, ivec2(0), atlasSizeI - ivec2(1));
      baseTexelCoord = baseTexel;
      warpedTexelCoord = shiftedTexel;
      foliageWarpPhase = shiftDir.x != 0 ? shiftPhase : 0.0;
      foliageWarpActive = foliageWarpPhase > 0.0;
      }
   }
#endif

   vec4 albedo;
   if (foliageWarpActive) {
      vec4 baseAlbedo = texelFetch(texture, baseTexelCoord, 0);
      vec4 warpedAlbedo = texelFetch(texture, warpedTexelCoord, 0);
      albedo = resolveFoliageWindTexels(baseAlbedo, warpedAlbedo, foliageWarpPhase);
   } else {
      albedo = texture(texture, sampleUV);
   }
   if (albedo.a < 0.1) {
      discard;
   }

   vec4 texelSample = albedo;

   vec2 pixelationOffset = ComputeTexelOffset(texture, texUV);
   vec2 pixelatedLightUV = clamp(TexelSnap(lightUV, pixelationOffset), 0.0, 1.0);
   vec2 runtimeLightUV = pixelatedLightUV;
   #ifdef IS_GBUFFERS_TEXTURED_LIT
      // Particles behave better with the raw lightmap coordinates here.
      // Pixel-snapping the lightmap is desirable for terrain, but it can crush
      // local torch light on particle-like draws.
      runtimeLightUV = clamp(lightUV, 0.0, 1.0);
   #endif

   vec4 ambient = texture(lightmap, vec2(AMBIENT_UV.s, runtimeLightUV.t));

   #ifdef GLOWING_ORES

      ambient.rgb = mix(
         ambient.rgb,
         vec3(1.0, 0.9, 0.9),
         isOre * 0.3333*squaredLength(rescale(albedo.rgb, vec3(0.59), vec3(1.0)))
      );

   #endif

   // Apply vertex colour to RGB only — do not let color.a (AO/vertex alpha)
   // contaminate albedo.a, which must stay as the texture transparency value.
   // In Iris 1.21.x, color.a can be 0.0 for some faces, making them vanish.
   albedo.rgb *= color.rgb;

   // Use interpolated world position from vertex stage to build stable
   // player/view-space positions. Reconstructing from gl_FragCoord with z=1.0
   // makes lighting angle-dependent and can cause entity shadow flicker.
   vec3 playerPos = worldPos;
   float playerDist = length(playerPos);
   vec3 viewPos = world2screen(playerPos);
   #ifdef HAND_DYNAMIC_LIGHTING
      float heldLightDistDenom = pow2(playerDist + 1.5);
   #endif
   float dayBright = max(sin(timeAngle * 6.28318530718), 0.0);

   #ifdef ENABLE_SHADOWS

      // dayFactor mirrors shaders.properties timeBrightness: 1 at noon, 0 at night.
      // Multiplying getSunStrength() by it prevents the shadow system from
      // using the moon's shadow map at night, which would cause surfaces that
      // face the moon (formerly sun-shadowed) to appear lit — the "anti-shadow".
      float sunStrength = max(0.75*isLava, getSunStrength() * dayBright);
      
      float shadowFactor = 1.0 - sunStrength;
      if (isTexturedPass(passType)) {
         // Stable entity lighting: no shadowmap receive, but preserve dark fit.
         sunStrength *= 0.50;
         shadowFactor = 0.35;
      }
      
      const float SHADOW_MAX_BLACKNESS = 0.6;
      
      vec3 shadowColor = vec3(1.0);
      
      ambient.rgb *= shadowColor * (1.0 - shadowFactor * SHADOW_MAX_BLACKNESS);
      
      float blueness = shadowFactor * SHADOW_BLUENESS;

      ambient.g *= 1.0 + 0.3333*blueness;
      ambient.b *= 1.0 + blueness;

      float sunBrightness = max(0.0, SUN_BRIGHTNESS - 0.5*pow3(luma(albedo.rgb)));

      ambient.rgb += (sunBrightness * sunStrength) * sunColor;

   #endif

   // Fog mix
   const int bands = 16;
   float bandSize = 1.0 / float(bands);
   
   // Current band base value
   float bandBase = floor(fogMix * bands) * bandSize;
   
   // Position within current band (0..1)
   float posInBand = fract(fogMix * bands);
   
   // Apply dithering pattern
   float dither = bayer4(gl_FragCoord.xy / 2.0);
   float ditheredFog = bandBase + (posInBand > dither ? bandSize : 0.0);

   vec3 viewRay = viewPos / max(playerDist, 0.0001);
   float VoU = clamp(dot(viewRay, upVec), 0.0, 1.0);
   float VoL = clamp(dot(viewRay, sunVec), 0.0, 1.0);
   float rainAmtFog = max(rainStrength, rainFactor);
   float lowSun = 1.0 - dayBright;
   // Rainy fog should not keep strong solar glow at dawn/dusk when sun disk
   // is effectively hidden by overcast.
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
         // In Nether/End use the game-provided biome fog directly.
         // This avoids forcing Overworld sky tint (orange wash) in all biomes.
         finalFogColor = fogColor;
      }
   #endif

   // do lighting
   // Use pixel-snapped lightmap coordinates so block-light quantization
   // matches between dimensions (Overworld/Nether/End).
   vec2 lmCoordM = runtimeLightUV;
   float blockLight = runtimeLightUV.s;
   float skyLight = runtimeLightUV.t;
   #ifdef IS_GBUFFERS_TEXTURED_LIT
      // Particle-like draws in the generic textured routes can report a weaker
      // packed lightmap than terrain. Fold in the normalized lmcoord fallback
      // so torch/block light remains visible, closer to Complementary.
      blockLight = max(blockLight, mix(TORCH_UV_SCALE.x, TORCH_UV_SCALE.y, clamp(lmcoord.x, 0.0, 1.0)));
      blockLight = max(blockLight, clamp(lightUV.s, 0.0, 1.0));
   #endif
   vec3 normalM = normal, shadowMult = vec3(1.0);
   vec3 worldGeoNormal = mat3(gbufferModelViewInverse) * normal;
   float puddleMask = 0.0;
   #if defined OVERWORLD && ENABLE_PUDDLES > 0
      vec3 absWorldPos = worldPos + cameraPosition;
      puddleMask = getPuddleMask(absWorldPos, worldGeoNormal, lmCoordM, albedo);
   #endif

   // Save the unlit albedo before directional lighting is applied.
   // This is used later to add torch contribution additively, preventing it
   // from being crushed by the near-zero directional factor at night.
   vec3 albedoUnlit = albedo.rgb;

   doLighting(albedo, shadowMult, normalM, worldGeoNormal, lmCoordM);

   // render thunder
   albedo.a = entityId == 11000.0 ? 0.15 : albedo.a;

   // render ao
   float ambientOcclusion = isTexturedPass(passType) ? 1.0 : TexelSnap(color.a, pixelationOffset);

   // Compute pixelated block light contribution using sky-only ambient as reference.
   // getTorchColor uses luma(ambient) to attenuate torch in bright daylight.
   torchStrength = getTorchStrength(blockLight);
   vec3 torchContrib = getTorchColor(ambient.rgb);

   // Apply sky ambient to RGB only — lightmap alpha must not touch albedo.a.
   albedo.rgb *= ambient.rgb;
   if (isTexturedPass(passType)) {
      // Small ambient fit term so entities still sit in dark places naturally.
      float envFit = mix(0.70, 0.90, skyLight);
      albedo.rgb *= envFit;
   }

   // Add torch/block light ADDITIVELY using the pre-lighting albedo.
   // This ensures torch remains visible at night even though the directional
   // night light factor is very small (~0.04), which would otherwise make
   // torch-lit surfaces appear nearly black.
   albedo.rgb += albedoUnlit * torchContrib;

   albedo.rgb *= ambientOcclusion;

   // Apply entity damage tint after lighting so it remains readable on bright
   // surfaces, but is still toned down in darkness.
   float sceneLum = luma(albedo.rgb);
   float brightFactor = smoothstep(0.12, 0.65, sceneLum);
   float hitTint = clamp(entityColor.a * mix(0.30, 1.00, brightFactor), 0.0, 1.0);
   vec3 hurtColor = mix(albedo.rgb, entityColor.rgb, 0.75);
   albedo.rgb = mix(albedo.rgb, hurtColor, hitTint);

   float fogMixFinal = clamp(ditheredFog, 0.0, 1.0);
   float rainFogBoost = rainAmtFog * smoothstep(0.22, 0.76, fogMixFinal) * 0.36;
   fogMixFinal = clamp(fogMixFinal + rainFogBoost, 0.0, 1.0);
   // In dense rainy fog, gently flatten distant scene contrast so
   // far geometry does not read as a 3D silhouette through fog.
   float rainReliefKill = rainAmtFog * smoothstep(0.26, 0.84, fogMixFinal);
   albedo.rgb = mix(albedo.rgb, vec3(luma(albedo.rgb)), rainReliefKill * 0.84);

   albedo.rgb = mix(albedo.rgb, finalFogColor, fogMixFinal);

   // Rain splash particles in Iris opaque particle path.
   // Only target actual rain/water particle atlas sprites so block-atlas
   // break particles (for example blue wool) are never recolored.
   if (rainAmtFog > 0.02) {
      float lumP = luma(albedo.rgb);
      float waterLike = getWaterSplashLikeParticleMask(texelSample.rgb, albedo.a);
      float physicsRainLike = getPhysicsRainLikeParticleMask(texelSample.rgb, albedo.a);
      float rainLike = max(waterLike, physicsRainLike);
      if (rainLike > 0.01) {
         // Block light from lightmap (torches) plus current particle brightness.
         float blockL = clamp(blockLight * 1.25, 0.0, 1.0);
         #ifdef HAND_DYNAMIC_LIGHTING
            int heldLight = max(heldBlockLightValue, heldBlockLightValue2);
            if (heldLight > 0) {
               float heldMaskWorld = min(1.0, float(heldLight) / heldLightDistDenom);
               // Particle world position can be noisy for splash. Reconstruct view-space
               // depth from the current fragment as a stable fallback for held-light falloff.
               vec2 heldScreenUV = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
               vec4 heldClipPos = vec4(heldScreenUV * 2.0 - 1.0, gl_FragCoord.z * 2.0 - 1.0, 1.0);
               vec4 heldViewPos = gbufferProjectionInverse * heldClipPos;
               float heldDistView = length(heldViewPos.xyz / max(heldViewPos.w, 0.0001));
               float heldMaskView = min(1.0, float(heldLight) / pow2(heldDistView + 1.5));

               float heldMask = max(heldMaskWorld, heldMaskView);
               // Small floor keeps hand-light visible when splash depth/position jitters.
               float heldFloor = (float(heldLight) / 15.0) * 0.22;
               blockL = max(blockL, max(heldMask * 2.4, heldFloor));
            }
         #endif
         float lightInfluence = max(lumP, blockL);
         float shade = smoothstep(0.06, 0.88, lightInfluence);
         shade = shade * shade * (3.0 - 2.0 * shade);
         vec3 splashColor = getRainSplashParticleColor(shade);
         albedo.rgb = mix(albedo.rgb, splashColor, rainLike);

         // Vanilla water splash in this pass behaves effectively opaque, so
         // mimic Complementary and fake translucency via dithered coverage.
         if (waterLike > 0.01) {
            float splashCoverage = getVanillaRainSplashCoverage(shade);
            if (bayer4(gl_FragCoord.xy) > splashCoverage) {
               discard;
            }
         }

         // Physics-mod rain style particles can still use alpha directly.
         if (physicsRainLike > 0.01) {
            float splashOpacity = WEATHER_OPACITY;
            albedo.a *= mix(1.0, splashOpacity, physicsRainLike);
         }
      }
   }

   float hotMaskHaze = 0.0;
   float hotMaskGlow = 0.0;
   // Per-pixel illumination area mask for cloud-shadow suppression.
   // Include both baked block light and the actual added torch light energy.
   float torchEnergy = luma(albedoUnlit * torchContrib);
   float lightAreaMask = clamp(max(blockLight * 1.15, torchEnergy * 10.0), 0.0, 1.0);
   #ifdef HAND_DYNAMIC_LIGHTING
      // Explicit hand-held light contribution: depends on distance to camera,
      // not only on baked block lightmap, so torch in hand affects cloud shadow too.
      float heldMask = 0.0;
      if (heldBlockLightValue > 0) {
         heldMask = min(1.0, float(heldBlockLightValue) / heldLightDistDenom);
      }
      lightAreaMask = max(lightAreaMask, heldMask * 1.55);
   #endif
   if (max(hotSourceMask, hotGlowSourceMask) > 0.0) {
      // Heat source mask: block-filtered (via mc_Entity in vsh) and then
      // refined by per-pixel "hot color" so only emissive parts drive haze.
      float hotLum = luma(albedo.rgb);
      float hotWarm = albedo.r / max(albedo.g * 0.70 + albedo.b * 0.30, 0.001);
      float hotSat = length(albedo.rgb - vec3(hotLum));
      float hotColorMask =
         smoothstep(1.08, 2.45, hotWarm) *
         smoothstep(0.04, 0.95, hotLum) *
         smoothstep(0.03, 0.42, hotSat);
      // Stricter mask for torch-like sources so wooden shaft does not glow.
      float hotTorchMask =
         smoothstep(1.30, 2.80, hotWarm) *
         smoothstep(0.16, 0.80, albedo.r - albedo.g) *
         smoothstep(0.06, 0.65, albedo.g - albedo.b) *
         smoothstep(0.14, 1.05, hotLum) *
         smoothstep(0.07, 0.45, hotSat);
      // Lantern-like sources: bright warm emissive core without strict fire-only gating.
      float hotLanternMask =
         smoothstep(0.18, 1.05, hotLum) *
         smoothstep(1.02, 2.20, hotWarm) *
         smoothstep(0.02, 0.30, hotSat);
      // Stabilize animated hot textures (fire) with a small floor only on
      // strong hot-source IDs (lava/fire group), while keeping torches selective.
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
