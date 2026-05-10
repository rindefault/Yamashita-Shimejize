#define gbuffers_textured_lit

#include "/shader.h"

in vec4 mc_Entity;

uniform vec3 cameraPosition;
uniform sampler2D texture;

uniform float fogEnd;
uniform float fogStart;
uniform float far;
uniform float timeAngle;
uniform float rainStrength;
uniform int fogShape;
uniform int isEyeInWater;
uniform int worldTime;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;
uniform mat3 normalMatrix;
uniform sampler2D lightmap;
uniform vec2 lightmapSize;

in vec4 vaPosition;
in vec4 vaColor;
in vec4 vaUV0;
in uvec2 vaUV2;
in vec3 vaNormal;

out vec2 lmcoord;
out vec3 normal;
out vec3 upVec;
out vec3 sunVec;

flat out int time;
flat out int passType;
flat out int materialId;

out float fogMix;
out float isLava;
out vec2 lightUV;
out vec2 texUV;
out vec3 worldPos;
out vec4 color;
out float foliageWindMask;
out float hotSourceMask;
out float hotGlowSourceMask;

#ifdef GLOWING_ORES
out float isOre;
#endif

#ifdef HIGHLIGHT_WAXED
uniform int heldItemId;
uniform int heldItemId2;
#endif

#include "/common/math.glsl"
#include "/common/getFogMix.vsh"
#include "/common/getWorldPosition.vsh"
#include "/common/vertex_lighting.vsh"

#ifdef ENABLE_SHADOWS
uniform vec3 shadowLightPosition;

out vec3 sunColor;
out float diffuse;

#include "/common/getDiffuse.vsh"
#include "/common/getSunColor.vsh"
#endif

void main() {
   gl_Position = projectionMatrix * modelViewMatrix * vec4(vaPosition.xyz, 1.0);

   time = worldTime;
   passType = 1;
   materialId = int(mc_Entity.x + 0.5);

   vec2 decodedLightUV = getDecodedLightmapUV(vec2(vaUV2));
   lmcoord = getNormalizedLmcoord(decodedLightUV);
   texUV = vaUV0.xy;
   normal = normalize(normalMatrix * vaNormal);
   color = vaColor;
   lightUV = decodedLightUV;
   foliageWindMask = 0.0;

   isLava = float(mc_Entity.x == 10068.0);
   vec2 hotMasks = getHotSourceMasks(mc_Entity.x);
   hotSourceMask = hotMasks.x;
   hotGlowSourceMask = hotMasks.y;
   getSunAndUpVectors(timeAngle, sunVec, upVec);

   if (isLava > 0.9) {
      color.rgb = mix(vec3(0.8, 0.5, 0.3), vec3(1.0), rescale(color.rgb, vec3(0.54), vec3(0.9)));
   }

   #ifdef GLOWING_ORES
      isOre = 0.0;
   #endif

   worldPos = getWorldPosition();
   fogMix = getFogMix(worldPos);

   #ifdef ENABLE_SHADOWS
      diffuse = getDiffuse(lightUV.t);
      sunColor = getSunColor();
   #endif
}
