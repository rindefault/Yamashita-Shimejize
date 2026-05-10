#define gbuffers_terrain_legacy
#define IS_TERRAIN
#define YS_LEGACY_VERTEX_PATH

#include "/shader.h"

attribute vec4 mc_Entity;

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
uniform sampler2D lightmap;
uniform vec2 lightmapSize;

varying vec2 lmcoord;
varying vec3 normal;
varying vec3 upVec;
varying vec3 sunVec;
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

#include "/common/math.glsl"
#include "/common/getFogMix.vsh"
#include "/common/getWorldPosition.vsh"
#include "/common/material_ids.glsl"
#include "/common/vertex_lighting.vsh"

#ifdef ENABLE_SHADOWS
uniform vec3 shadowLightPosition;

varying vec3 sunColor;
varying float diffuse;

#include "/common/getDiffuse.vsh"
#include "/common/getSunColor.vsh"
#endif

void main() {
   gl_Position = ftransform();

   lightUV = (gl_TextureMatrix[1] * gl_MultiTexCoord1).st;
   lmcoord = getNormalizedLmcoord(lightUV);
   texUV = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
   normal = normalize(gl_NormalMatrix * gl_Normal);
   color = gl_Color;
   foliageWindMask = float(isFoliageWindBlock(mc_Entity.x));

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
