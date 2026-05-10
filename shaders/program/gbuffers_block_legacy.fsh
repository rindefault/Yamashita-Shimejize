#define gbuffers_block_legacy

#include "/shader.h"

uniform vec3 cameraPosition;
uniform sampler2D lightmap;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;

uniform float rainStrength;
uniform float rainFactor;
uniform float darknessLightFactor;
uniform float screenBrightness;
uniform float timeAngle;
uniform float frameTimeCounter;
uniform int worldTime;
uniform int isEyeInWater;
uniform int blockEntityId;
uniform sampler2D texture;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform float far;
uniform ivec2 eyeBrightness;
uniform ivec2 eyeBrightnessSmooth;

uniform sampler2D endportaltex;
uniform sampler2D endskytex;
uniform vec3 shadowLightPosition;

float torchStrength;

varying vec3 upVec;
varying vec3 sunVec;
varying vec3 eastVec;
varying vec2 lmcoord;
varying vec3 normal;
varying float fogMix;
varying vec2 lightUV;
varying vec2 texUV;
varying vec3 worldPos;
varying vec4 color;
varying vec4 portalProj0;

#ifdef HAND_DYNAMIC_LIGHTING
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;
#endif

#include "/common/math.glsl"
#include "/common/pass_classes.glsl"
const int passType = PASS_TEXTURED;
#include "/common/transformations.fsh"
#include "/common/getTorchStrength.vsh"
#include "/common/getTorchColor.fsh"
#include "/common/getSkyAndFogColors.fsh"
#include "/common/getLightColor.fsh"
#include "/common/getSubmergedFogColor.glsl"

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

const int BLOCK_ENTITY_END_PORTAL = 60025;
const mat4 END_PORTAL_SCALE_TRANSLATE = mat4(
   0.5, 0.0, 0.0, 0.25,
   0.0, 0.5, 0.0, 0.25,
   0.0, 0.0, 1.0, 0.0,
   0.0, 0.0, 0.0, 1.0
);

vec3 getEndPortalLayerColor(int idx) {
   if (idx == 0) return vec3(0.022087, 0.098399, 0.110818);
   if (idx == 1) return vec3(0.011892, 0.095924, 0.089485);
   if (idx == 2) return vec3(0.027636, 0.101689, 0.100326);
   if (idx == 3) return vec3(0.046564, 0.109883, 0.114838);
   if (idx == 4) return vec3(0.064901, 0.117696, 0.097189);
   if (idx == 5) return vec3(0.063761, 0.086895, 0.123646);
   if (idx == 6) return vec3(0.084817, 0.111994, 0.166380);
   if (idx == 7) return vec3(0.097489, 0.154120, 0.091064);
   if (idx == 8) return vec3(0.106152, 0.131144, 0.195191);
   if (idx == 9) return vec3(0.097721, 0.110188, 0.187229);
   if (idx == 10) return vec3(0.133516, 0.138278, 0.148582);
   if (idx == 11) return vec3(0.070006, 0.243332, 0.235792);
   if (idx == 12) return vec3(0.196766, 0.142899, 0.214696);
   if (idx == 13) return vec3(0.047281, 0.315338, 0.321970);
   if (idx == 14) return vec3(0.204675, 0.390010, 0.302066);
   return vec3(0.080955, 0.314821, 0.661491);
}

vec4 getEndPortalLayerProj(vec4 projCoord, float layer) {
   float portalTime = frameTimeCounter * END_STARS_SPEED * 0.011;
   float angle = radians((layer * layer * 4321.0 + layer * 9.0) * 2.0);
   float layerScale = (4.5 - layer / 4.0) * 2.0;
   float rotCos = cos(angle);
   float rotSin = sin(angle);

   mat4 scaleRotate = mat4(
      layerScale * rotCos, -layerScale * rotSin, 0.0, 0.0,
      layerScale * rotSin,  layerScale * rotCos, 0.0, 0.0,
      0.0, 0.0, 1.0, 0.0,
      0.0, 0.0, 0.0, 1.0
   );

   mat4 translate = mat4(
      1.0, 0.0, 0.0, 17.0 / layer,
      0.0, 1.0, 0.0, (2.0 + layer / 1.5) * (portalTime * 1.5),
      0.0, 0.0, 1.0, 0.0,
      0.0, 0.0, 0.0, 1.0
   );

   return projCoord * scaleRotate * translate * END_PORTAL_SCALE_TRANSLATE;
}

vec3 sampleEndSkyTexture(vec4 projCoord) {
   return texture2DProj(endskytex, projCoord).rgb;
}

vec3 sampleEndPortalTexture(vec4 projCoord) {
   return texture2DProj(endportaltex, projCoord).rgb;
}

vec3 getEndPortalEffectColor(float fogMixFinal, vec3 finalFogColor) {
   vec3 portalColor = sampleEndSkyTexture(portalProj0) * getEndPortalLayerColor(0);

   for (int i = 0; i < 16; ++i) {
      float layer = float(i + 1);
      vec4 layerProj = getEndPortalLayerProj(portalProj0, layer);
      vec3 layerColor = sampleEndPortalTexture(layerProj) * getEndPortalLayerColor(i);
      portalColor += layerColor;
   }

   portalColor = clamp(portalColor * 1.15, 0.0, 1.0);
   return mix(portalColor, finalFogColor, fogMixFinal * 0.05);
}

void main() {
   vec2 sampleUV = texUV;
   vec4 albedo = texture2D(texture, sampleUV);

   vec3 playerPos = worldPos;
   float playerDist = length(playerPos);
   vec3 viewPos = world2screen(playerPos);
   #ifdef HAND_DYNAMIC_LIGHTING
      float heldLightDistDenom = pow2(playerDist + 1.5);
   #endif
   float dayBright = max(sin(timeAngle * 6.28318530718), 0.0);

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
         finalFogColor = getSky(VoU, VoLfog, bayer4(gl_FragCoord.xy / 2.0));
         vec3 rainSkyOvercast = mix(skyColor, fogColor, 0.45);
         rainSkyOvercast = mix(rainSkyOvercast, vec3(luma(rainSkyOvercast)), 0.35);
         finalFogColor = mix(finalFogColor, rainSkyOvercast, rainAmtFog * 0.58);
      }
   #else
      if (isEyeInWater == 0) {
         finalFogColor = fogColor;
      }
   #endif

   float fogMixFinal = clamp(fogMix, 0.0, 1.0);

   if (blockEntityId == BLOCK_ENTITY_END_PORTAL) {
      vec3 portalColor = getEndPortalEffectColor(fogMixFinal, finalFogColor);

      /* DRAWBUFFERS:027 */
      fragColor0 = vec4(portalColor, 1.0);
      hotMaskOut = vec4(0.0, clamp(luma(portalColor) * 0.12 + 0.02, 0.0, 1.0), 0.0, 0.82);
      infoOut = vec4(0.0);
      return;
   }

   if (albedo.a < 0.1) {
      discard;
   }

   vec2 runtimeLightUV = clamp(lightUV, 0.0, 1.0);
   vec4 ambient = texture2D(lightmap, vec2(AMBIENT_UV.s, runtimeLightUV.t));

   albedo.rgb *= color.rgb;

   #ifdef ENABLE_SHADOWS
      float sunStrength = getSunStrength() * dayBright;
      float shadowFactor = 1.0 - sunStrength;

      ambient.rgb *= 1.0 - shadowFactor * 0.6;

      float blueness = shadowFactor * SHADOW_BLUENESS;
      ambient.g *= 1.0 + 0.3333 * blueness;
      ambient.b *= 1.0 + blueness;

      float sunBrightness = max(0.0, SUN_BRIGHTNESS - 0.5 * pow3(luma(albedo.rgb)));
      ambient.rgb += (sunBrightness * sunStrength) * sunColor;
   #endif

   vec3 worldGeoNormal = mat3(gbufferModelViewInverse) * normal;
   vec3 shadowMult = vec3(1.0);
   vec3 albedoUnlit = albedo.rgb;
   doLighting(albedo, shadowMult, normal, worldGeoNormal, runtimeLightUV);

   torchStrength = getTorchStrength(runtimeLightUV.x);
   vec3 torchContrib = getTorchColor(ambient.rgb);

   albedo.rgb *= ambient.rgb;
   albedo.rgb *= mix(0.70, 0.90, runtimeLightUV.y);
   albedo.rgb += albedoUnlit * torchContrib;
   albedo.rgb = mix(albedo.rgb, finalFogColor, fogMixFinal);

   /* DRAWBUFFERS:027 */
   fragColor0 = albedo;
   hotMaskOut = vec4(0.0, 0.0, clamp(max(runtimeLightUV.x * 1.15, luma(albedoUnlit * torchContrib) * 10.0), 0.0, 1.0), 0.82);
   infoOut = vec4(0.0);
}
