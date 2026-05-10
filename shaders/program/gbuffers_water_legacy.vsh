#define gbuffers_water_legacy
#define IS_TERRAIN
#define YS_LEGACY_VERTEX_PATH

#include "/shader.h"

attribute vec4 mc_Entity;

uniform int fogShape;
uniform int isEyeInWater;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform float fogEnd;
uniform float fogStart;
uniform float far;
uniform float rainStrength;
uniform float timeAngle;
uniform int worldTime;

varying vec2 texUV;
varying vec2 lightUV;
varying vec3 worldPos;
varying vec3 viewPos;
varying vec4 color;
varying vec4 normal;
varying vec3 shadingNormal;
varying float fogMix;
varying float isWater;
varying float isNetherPortal;
varying float torchStrength;
varying vec3 upVec;
varying vec3 sunVec;

#ifdef ENABLE_SHADOWS
uniform vec3 shadowLightPosition;

varying vec3 sunColor;
varying float diffuse;
#endif

#include "/common/math.glsl"
#include "/common/getFogMix.vsh"
#include "/common/getWorldPosition.vsh"
#include "/common/getTorchStrength.vsh"
#include "/common/material_ids.glsl"
#include "/common/vertex_lighting.vsh"

#ifdef ENABLE_SHADOWS
float getWaterDiffuse(float skyLight) {
	vec3 shapeNormal = gl_Normal;
	bool isThin = mc_Entity.x == 10031.0 || mc_Entity.x == 10032.0
	           || mc_Entity.x == 10059.0 || mc_Entity.x == 10060.0
	           || mc_Entity.x == 10061.0
	           || mc_Entity.x == 10175.0 || mc_Entity.x == 10176.0
	           || (abs(shapeNormal.y) < 0.01 && abs(abs(shapeNormal.x) - abs(shapeNormal.z)) < 0.01);
	float directionalDiffuse = clamp(2.5 * dot(normalize(shadingNormal),
	                                            normalize(shadowLightPosition)), -0.3333, 1.0);

	return (isEyeInWater == 0 ? 1.0 : 0.5)
	     * (1.0 - fogMix)
	     * (1.0 - rainStrength)
	     * rescale(skyLight, 0.3137, 0.6235)
	     * (isThin ? 0.75 : directionalDiffuse);
}

#include "/common/getSunColor.vsh"
#endif

void main() {
	vec4 modelViewPos = gl_ModelViewMatrix * gl_Vertex;
	gl_Position = ftransform();

	color = gl_Color;
	texUV = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
	lightUV = (gl_TextureMatrix[1] * gl_MultiTexCoord1).st;
	shadingNormal = normalize(gl_NormalMatrix * gl_Normal);
	normal = vec4(0.5 + 0.5 * gl_Normal, 1.0);
	isWater = float(isWaterBlock(mc_Entity.x));
	isNetherPortal = float(isNetherPortalBlock(mc_Entity.x));

	torchStrength = getTorchStrength(lightUV.s);
	worldPos = getWorldPosition();
	fogMix = getFogMix(worldPos);
	viewPos = modelViewPos.xyz;

	getSunAndUpVectors(timeAngle, sunVec, upVec);

	#ifdef ENABLE_SHADOWS
		diffuse = getWaterDiffuse(lightUV.t);
		sunColor = getSunColor();
	#endif
}
