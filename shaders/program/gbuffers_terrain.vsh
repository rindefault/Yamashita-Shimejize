#define gbuffers_terrain
#define IS_TERRAIN

#include "/shader.h"

in vec4 mc_Entity;

uniform vec3 cameraPosition;
uniform sampler2D texture;

uniform float     fogEnd;
uniform float     fogStart;
uniform float     far;
uniform float     timeAngle;
uniform float     rainStrength;
uniform int       fogShape;
uniform int       isEyeInWater;
uniform int       worldTime;
uniform mat4      gbufferModelView, gbufferModelViewInverse, gbufferProjection;
uniform vec3      chunkOffset;
uniform sampler2D lightmap;
uniform vec2      lightmapSize;

in vec4 vaPosition;
in vec4 vaColor;
in vec4 vaUV0;
in uvec2 vaUV2;
in vec3 vaNormal;
in vec4 mc_midTexCoord;

out vec2 lmcoord;
out vec3 normal;
out vec3 upVec, sunVec;
out vec2 signMidCoordPos;
flat out vec2 absMidCoordPos;
flat out vec2 midCoord;

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
#include "/common/material_ids.glsl"
#include "/common/vertex_lighting.vsh"

#ifdef ENABLE_SHADOWS
   uniform vec3 shadowLightPosition;

   out vec3 sunColor;
   out float diffuse;

   #include "/common/getDiffuse.vsh"
   #include "/common/getSunColor.vsh"
#endif

void main() {
   vec3 terrainPos = vaPosition.xyz + chunkOffset;

   gl_Position = gbufferProjection * gbufferModelView * vec4(terrainPos, 1.0);

   time = worldTime;
   passType = 0;
   materialId = int(mc_Entity.x + 0.5);

   vec2 decodedLightUV = getDecodedLightmapUV(vec2(vaUV2));
   lmcoord = getNormalizedLmcoord(decodedLightUV);

   normal = normalize(mat3(gbufferModelView) * vaNormal);

   color   = vaColor;
   texUV   = vaUV0.xy;
   midCoord = mc_midTexCoord.xy;
   vec2 texMinMidCoord = texUV - midCoord;
   signMidCoordPos = sign(texMinMidCoord);
   absMidCoordPos = abs(texMinMidCoord);
   lightUV = decodedLightUV;
   foliageWindMask = float(isFoliageWindBlock(mc_Entity.x));

   isLava  = float(mc_Entity.x == 10068.0);
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
