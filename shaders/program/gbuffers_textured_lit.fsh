#define gbuffers_textured_lit

#include "/shader.h"

uniform vec3 cameraPosition;
uniform sampler2D lightmap;

uniform int entityId;
uniform sampler2D texture;
uniform vec3 fogColor;
uniform vec4 entityColor;

uniform float viewHeight;
uniform float viewWidth;

out float torchStrength;
in vec2 lmcoord;

varying float fogMix;
varying float isLava;
varying vec2 lightUV;
varying vec2 texUV;
varying vec3 worldPos;
varying vec4 ambient;
varying vec4 color;

#ifdef GLOWING_ORES
   varying float isOre;
#endif

#ifdef HAND_DYNAMIC_LIGHTING
   uniform int heldBlockLightValue;
#endif

#include "/common/math.glsl"
#include "/common/transformations.fsh"
#include "/common/getTorchStrength.vsh"
#include "/common/getTorchColor.fsh"

#ifdef ENABLE_SHADOWS
   uniform mat4 shadowModelView;
   uniform mat4 shadowProjection;
   uniform mat4 gbufferProjectionInverse;
   uniform sampler2D shadowtex1;

   varying vec3 sunColor;
   varying float diffuse;

   #include "/common/getSunStrength.fsh"
#endif

void main() {
   vec4 albedo  = texture2D(texture, texUV);
   vec4 ambient = ambient;

   #ifdef GLOWING_ORES

      ambient.rgb = mix(
         ambient.rgb,
         vec3(1.0, 0.9, 0.9),
         isOre * 0.3333*squaredLength(rescale(albedo.rgb, vec3(0.59), vec3(1.0)))
      );

   #endif

   albedo *= color;

   #ifdef ENABLE_SHADOWS

      float sunStrength = max(0.75*isLava, getSunStrength());
      float blueness = (1.0 - sunStrength) * SHADOW_BLUENESS;

      ambient.rgb *= 1.0 - SHADOW_DARKNESS;
      ambient.g *= 1.0 + 0.3333*blueness;
      ambient.b *= 1.0 + blueness;

      float sunBrightness = max(0.0, SUN_BRIGHTNESS - 0.5*pow3(luma(albedo.rgb)));

      ambient.rgb *= 1.0 + (sunBrightness * sunStrength) * sunColor;

   #endif

   // render thunder
   albedo.a = entityId == 11000.0 ? 0.15 : albedo.a;

   // render ao
   vec2 pixelationOffset = ComputeTexelOffset(texture, texUV);

   float ambientOcclusion = TexelSnap(color.a, pixelationOffset);

   // render pixelated blocklight
   vec2 lightmap = clamp(TexelSnap(lightUV, pixelationOffset), 0.0, 1.0);

   torchStrength = getTorchStrength(lightmap.s);

   ambient.rgb += getTorchColor(ambient.rgb);
   
   // render entity color changes (e.g taking damage)
   albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a);

   albedo *= ambient;

   albedo.rgb *= ambientOcclusion;
   albedo.rgb = mix(albedo.rgb, fogColor, fogMix);

   gl_FragData[0] = albedo;
}