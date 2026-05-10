#define gbuffers_water

#include "/shader.h"

uniform vec3 fogColor;
uniform vec3 cameraPosition;
uniform sampler2D texture;
uniform mat4  gbufferModelViewInverse;
uniform mat4  gbufferProjectionInverse;

uniform float timeAngle;
uniform float rainStrength, rainFactor;
uniform float darknessLightFactor;
uniform float screenBrightness;
uniform float viewHeight, viewWidth;
uniform vec3  skyColor;
uniform int   isEyeInWater;

in vec2 texUV;
in vec2 lightUV;
in vec3 worldPos;
in vec3 viewPos;
in vec4 color;
in vec4 normal;
in vec3 shadingNormal;
in vec4 ambient;
in float fogMix;
in float isWater;
in float isNetherPortal;
in float torchStrength;
in vec3  upVec, sunVec;

#ifdef HAND_DYNAMIC_LIGHTING
   uniform int heldBlockLightValue;
#endif

#include "/common/math.glsl"
#include "/common/pass_classes.glsl"
const int passType = PASS_TERRAIN;
#include "/common/getSkyAndFogColors.fsh"
#include "/common/getLightColor.fsh"
#include "/common/getTorchColor.fsh"
#include "/common/getSubmergedFogColor.glsl"

#ifdef ENABLE_SHADOWS
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform sampler2D shadowtex1;

in vec3 sunColor;
in float diffuse;

#include "/common/getSunStrength.fsh"
#endif

layout(location = 0) out vec4 fragColor0;
layout(location = 1) out vec4 fragColor1;
layout(location = 2) out vec4 fragColor2;

void main() {
   vec4 albedo = texture(texture, texUV);

   float isPortal = isNetherPortal;
   float waterSurfaceMask = clamp(isWater, 0.0, 1.0);
   vec2 runtimeLightUV = clamp(lightUV, 0.0, 1.0);

   albedo.rgb *= color.rgb;
   vec3 albedoUnlit = albedo.rgb;

   vec4 lightingColor = albedo;
   vec3 shadowMult = vec3(1.0);
   vec3 normalM = shadingNormal;
   vec3 worldGeoNormal = mat3(gbufferModelViewInverse) * shadingNormal;
   doLighting(lightingColor, shadowMult, normalM, worldGeoNormal, runtimeLightUV);

   vec3 surfaceLighting = mix(lightingColor.rgb, albedoUnlit, waterSurfaceMask * 0.35);
   albedo.rgb = mix(surfaceLighting, albedoUnlit, isPortal);

   vec3 ambientRgb = ambient.rgb;
   float dayBright = max(sin(timeAngle * 6.28318530718), 0.0);

   #ifdef ENABLE_SHADOWS
      float sunStrength = getSunStrength() * dayBright;
      float shadowFactor = 1.0 - sunStrength;
      float translucentShadow = mix(0.85, 0.55, waterSurfaceMask);
      ambientRgb *= 1.0 - shadowFactor * 0.6 * translucentShadow;

      float blueness = shadowFactor * SHADOW_BLUENESS * translucentShadow;
      ambientRgb.g *= 1.0 + 0.3333 * blueness;
      ambientRgb.b *= 1.0 + blueness;

      float sunBrightness = max(0.0, SUN_BRIGHTNESS - 0.5 * pow3(luma(albedoUnlit)));
      ambientRgb += (sunBrightness * sunStrength) * sunColor;
   #endif

   vec3 litMul = mix(ambientRgb, vec3(1.0), isPortal);
   albedo.rgb *= litMul;

   vec3 torchContrib = getTorchColor(ambientRgb);
   float torchBoost = mix(1.10, 0.95, waterSurfaceMask) * (1.0 - isPortal);
   albedo.rgb += albedoUnlit * torchContrib * torchBoost;

   vec3 effectiveFog;
   if (isEyeInWater > 0) {
      effectiveFog = getSubmergedFogColor(isEyeInWater, fogColor);
   } else {
      float dither = bayer4(gl_FragCoord.xy * 0.5);
      vec2 screenUV = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
      vec4 clipPos = vec4(screenUV * 2.0 - 1.0, 1.0, 1.0);
      vec4 viewRayH = gbufferProjectionInverse * clipPos;
      vec3 viewRay = normalize(viewRayH.xyz / viewRayH.w);
      float VoU = clamp(dot(viewRay, upVec), 0.0, 1.0);
      float VoL = clamp(dot(viewRay, sunVec), 0.0, 1.0);
      float rainAmtFog = max(rainStrength, rainFactor);
      float dayBright = max(sin(timeAngle * 6.28318530718), 0.0);
      float lowSun = 1.0 - dayBright;
      float sunDirDamp = rainAmtFog * mix(0.42, 0.82, lowSun);
      float VoLfog = mix(VoL, VoL * 0.22, sunDirDamp);
      effectiveFog = getSky(VoU, VoLfog, dither);
      vec3 rainSkyOvercast = mix(skyColor, fogColor, 0.45);
      rainSkyOvercast = mix(rainSkyOvercast, vec3(luma(rainSkyOvercast)), 0.35);
      effectiveFog = mix(effectiveFog, rainSkyOvercast, rainAmtFog * 0.58);

      float waterFogMix = clamp(fogMix + rainAmtFog * smoothstep(0.35, 0.85, fogMix) * 0.18, 0.0, 1.0);
      float edgeOpacity = smoothstep(0.58, 1.0, waterFogMix);
      albedo.a = clamp(albedo.a + edgeOpacity * 0.42, 0.0, 1.0);
      float fogMixForSurface = waterFogMix;
      albedo.rgb = mix(albedo.rgb, effectiveFog, fogMixForSurface);

      if (isPortal > 0.5) {
         float portalLum = luma(albedo.rgb);
         float nEm = mix(0.06, 0.14, smoothstep(0.08, 0.70, 1.0 - portalLum));
         float emissive = nEm * isNetherPortal * (1.0 - fogMixForSurface * 0.85);
         albedo.rgb += albedo.rgb * emissive;
         albedo.a = max(albedo.a, 0.78);
      }

      /* DRAWBUFFERS:067 */
      fragColor0 = albedo;
      fragColor1 = normal;
      fragColor2 = vec4(waterSurfaceMask, waterSurfaceMask, 0.0, 1.0);
      return;
   }

   float fogMixFinal = fogMix;
   albedo.rgb = mix(albedo.rgb, effectiveFog, fogMixFinal);
   if (isPortal > 0.5) {
      float portalLum = luma(albedo.rgb);
      float nEm = mix(0.06, 0.14, smoothstep(0.08, 0.70, 1.0 - portalLum));
      float emissive = nEm * isNetherPortal * (1.0 - fogMixFinal * 0.85);
      albedo.rgb += albedo.rgb * emissive;
      albedo.a = max(albedo.a, 0.78);
   }

   /* DRAWBUFFERS:067 */
   fragColor0 = albedo;
   fragColor1 = normal;
   fragColor2 = vec4(waterSurfaceMask, waterSurfaceMask, 0.0, 1.0);
}
