#define gbuffers_water
#define IS_TERRAIN

#include "/shader.h"

in vec4 mc_Entity;

uniform int fogShape;
uniform int isEyeInWater;
uniform mat4 gbufferModelView, gbufferModelViewInverse, gbufferProjection;
uniform vec3 chunkOffset;
uniform float fogEnd;
uniform float fogStart;
uniform float far;
uniform float rainStrength;
uniform float timeAngle;
uniform int worldTime;
uniform sampler2D lightmap;

in vec4 vaPosition;
in vec4 vaColor;
in vec4 vaUV0;
in uvec2 vaUV2;
in vec3 vaNormal;

out vec2 texUV;
out vec2 lightUV;
out vec3 worldPos;
out vec4 color;
out vec4 normal;
out vec3 shadingNormal;
out vec4 ambient;
out float fogMix;
out float isWater;
out float isNetherPortal;
out float torchStrength;
out vec3  viewPos;
out vec3  upVec, sunVec;

#ifdef ENABLE_SHADOWS
uniform vec3 shadowLightPosition;

out vec3 sunColor;
out float diffuse;
#endif

#include "/common/math.glsl"
#include "/common/getFogMix.vsh"
#include "/common/getWorldPosition.vsh"
#include "/common/getTorchStrength.vsh"
#include "/common/material_ids.glsl"
#include "/common/vertex_lighting.vsh"

#ifdef ENABLE_SHADOWS
float getWaterDiffuse(float skyLight) {
	vec3 shapeNormal = vaNormal;
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
	vec4 localPos = vec4(vaPosition.xyz + chunkOffset, 1.0);
	vec4 modelViewPos = gbufferModelView * localPos;
	gl_Position = gbufferProjection * modelViewPos;

	color = vaColor;
	texUV = vaUV0.xy;

	lightUV = getDecodedLightmapUV(vec2(vaUV2));
	shadingNormal = normalize(mat3(gbufferModelView) * vaNormal);
	normal  = vec4(0.5 + 0.5 * vaNormal, 1.0);
	ambient = texture(lightmap, vec2(AMBIENT_UV.s, lightUV.t));
	isWater = float(isWaterBlock(mc_Entity.x));
	isNetherPortal = float(isNetherPortalBlock(mc_Entity.x));

	torchStrength = getTorchStrength(lightUV.s);
	worldPos = getWorldPosition();
	fogMix    = getFogMix(worldPos);
	viewPos   = modelViewPos.xyz;

	// Sun/up vectors in view space — same computation as gbuffers_textured_lit.vsh
	getSunAndUpVectors(timeAngle, sunVec, upVec);

	#ifdef ENABLE_SHADOWS
		diffuse = getWaterDiffuse(lightUV.t);
		sunColor = getSunColor();
	#endif
}
