#ifndef DEPTH_UTILS_GLSL
#define DEPTH_UTILS_GLSL

float linearizeDepthValue(float depth, float nearPlane, float farPlane) {
	float z = depth * 2.0 - 1.0;
	return (2.0 * nearPlane * farPlane) / max(farPlane + nearPlane - z * (farPlane - nearPlane), 0.0001);
}

float sampleDepthTextureValue(sampler2D depthTexture, vec2 uv) {
#if __VERSION__ < 130
	return texture2D(depthTexture, uv).r;
#else
	return texture(depthTexture, uv).r;
#endif
}

float getDepthHandMask(sampler2D depthTexture, vec2 uv) {
	return 1.0 - step(0.56, sampleDepthTextureValue(depthTexture, uv));
}

#endif
