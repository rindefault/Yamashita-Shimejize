#ifndef VERTEX_LIGHTING_VSH
#define VERTEX_LIGHTING_VSH

vec2 getDecodedLightmapUV(vec2 packedLightUV) {
	return packedLightUV / 256.0;
}

vec2 getLightmapUV(ivec2 packedLightUV) {
	return getDecodedLightmapUV(vec2(packedLightUV));
}

#if __VERSION__ >= 130
vec2 getLightmapUV(uvec2 packedLightUV) {
	return getDecodedLightmapUV(vec2(packedLightUV));
}
#endif

vec2 getNormalizedLmcoord(vec2 lightUV) {
	return clamp((lightUV - 0.03125) * 1.06667, 0.0, 1.0);
}

vec2 getNormalizedLmcoord(ivec2 packedLightUV) {
	return getNormalizedLmcoord(getLightmapUV(packedLightUV));
}

#if __VERSION__ >= 130
vec2 getNormalizedLmcoord(uvec2 packedLightUV) {
	return getNormalizedLmcoord(getLightmapUV(packedLightUV));
}
#endif

vec2 getHotSourceMasks(float blockId) {
	float isLava = float(blockId == 10068.0);
	float isFireHot = float(blockId == 10090.0);
	float isTorchHot = float(blockId == 10089.0);
	float isLanternHot = float(blockId == 10091.0);
	float hotSourceMask = clamp(isLava + isFireHot + isTorchHot * 0.55, 0.0, 1.0);
	float hotGlowSourceMask = clamp(hotSourceMask + isLanternHot * 0.95, 0.0, 1.0);
	return vec2(hotSourceMask, hotGlowSourceMask);
}

void getSunAndUpVectors(float localTimeAngle, out vec3 localSunVec, out vec3 localUpVec) {
	const vec2 sunRotationData = vec2(cos(sunPathRotation * 0.01745329251994), -sin(sunPathRotation * 0.01745329251994));
	float ang = fract(localTimeAngle - 0.25);
	ang = (ang + (cos(ang * 3.14159265358979) * -0.5 + 0.5 - ang) / 3.0) * 6.28318530717959;

	localSunVec = normalize((gbufferModelView * vec4(vec3(-sin(ang), cos(ang) * sunRotationData) * 2000.0, 1.0)).xyz);
	localUpVec = normalize(gbufferModelView[1].xyz);
}

#endif
