#define gbuffers_block_legacy
#define YS_LEGACY_VERTEX_PATH

#include "/shader.h"

uniform vec3 cameraPosition;
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
varying vec3 eastVec;
varying float fogMix;
varying vec2 lightUV;
varying vec2 texUV;
varying vec3 worldPos;
varying vec4 color;
varying vec4 portalProj0;

#ifdef ENABLE_SHADOWS
uniform vec3 shadowLightPosition;

varying vec3 sunColor;
varying float diffuse;
#endif

#include "/common/math.glsl"
#include "/common/getFogMix.vsh"
#include "/common/getWorldPosition.vsh"
#include "/common/vertex_lighting.vsh"

#ifdef ENABLE_SHADOWS
float getBlockDiffuse(float skyLight) {
   float directionalDiffuse = clamp(2.5 * dot(normalize(normal), normalize(shadowLightPosition)), -0.3333, 1.0);

   return (isEyeInWater == 0 ? 1.0 : 0.5)
        * (1.0 - fogMix)
        * (1.0 - rainStrength)
        * rescale(skyLight, 0.3137, 0.6235)
        * directionalDiffuse;
}

#include "/common/getSunColor.vsh"
#endif

void main() {
   gl_Position = ftransform();
   portalProj0 = gl_Position * 0.5;
   portalProj0.xy = vec2(portalProj0.x + portalProj0.w, portalProj0.y + portalProj0.w);
   portalProj0.zw = gl_Position.zw;

   lightUV = (gl_TextureMatrix[1] * gl_MultiTexCoord1).st;
   lmcoord = getNormalizedLmcoord(lightUV);
   texUV = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
   normal = normalize(gl_NormalMatrix * gl_Normal);
   color = gl_Color;

   getSunAndUpVectors(timeAngle, sunVec, upVec);
   eastVec = normalize(gbufferModelView[0].xyz);

   worldPos = getWorldPosition();
   fogMix = getFogMix(worldPos);

   #ifdef ENABLE_SHADOWS
      diffuse = getBlockDiffuse(lightUV.t);
      sunColor = getSunColor();
   #endif
}
