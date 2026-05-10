#ifndef EFFECT_METADATA_GLSL
#define EFFECT_METADATA_GLSL

const float EFFECT_METADATA_PUDDLE_SCALE = 0.48;
const float EFFECT_METADATA_FOREGROUND_MARKER = 0.82;
const float EFFECT_METADATA_HAND_MARKER = 1.0;
const float EFFECT_METADATA_FOREGROUND_THRESHOLD = 0.75;
const float EFFECT_METADATA_HAND_THRESHOLD = 0.95;

ivec2 getEffectMetadataTexel(sampler2D effectTexture, vec2 uv) {
#if __VERSION__ < 130
	return ivec2(0);
#else
	ivec2 texSize = ivec2(textureSize(effectTexture, 0));
	vec2 clampedUV = clamp(uv, vec2(0.0), vec2(1.0) - 0.5 / vec2(texSize));
	return clamp(ivec2(floor(clampedUV * vec2(texSize))), ivec2(0), texSize - ivec2(1));
#endif
}

vec4 sampleEffectData(sampler2D effectTexture, vec2 uv) {
#if __VERSION__ < 130
	return texture2D(effectTexture, uv);
#else
	return texture(effectTexture, uv);
#endif
}

vec4 sampleEffectDataNearest(sampler2D effectTexture, vec2 uv) {
#if __VERSION__ < 130
	return sampleEffectData(effectTexture, uv);
#else
	return texelFetch(effectTexture, getEffectMetadataTexel(effectTexture, uv), 0);
#endif
}

float sampleEffectMetadata(sampler2D effectTexture, vec2 uv) {
	return sampleEffectData(effectTexture, uv).a;
}

float sampleEffectMetadataNearest(sampler2D effectTexture, vec2 uv) {
	return sampleEffectDataNearest(effectTexture, uv).a;
}

float encodeEffectMetadata(float puddleMask, float foregroundMarker, float handMarker) {
	float packedPuddleMask = clamp(puddleMask, 0.0, 1.0) * EFFECT_METADATA_PUDDLE_SCALE;
	float packedForeground = clamp(foregroundMarker, 0.0, 1.0) * EFFECT_METADATA_FOREGROUND_MARKER;
	float packedHand = clamp(handMarker, 0.0, 1.0) * EFFECT_METADATA_HAND_MARKER;
	return max(packedPuddleMask, max(packedForeground, packedHand));
}

float decodeEffectForegroundMask(float packedAlpha) {
	return step(EFFECT_METADATA_FOREGROUND_THRESHOLD, packedAlpha);
}

float decodeEffectHandMask(float packedAlpha) {
	return step(EFFECT_METADATA_HAND_THRESHOLD, packedAlpha);
}

float decodeEffectPuddleMask(float packedAlpha) {
	return clamp(packedAlpha / EFFECT_METADATA_PUDDLE_SCALE, 0.0, 1.0) * (1.0 - decodeEffectForegroundMask(packedAlpha));
}

float sampleEffectForegroundMask(sampler2D effectTexture, vec2 uv) {
	return decodeEffectForegroundMask(sampleEffectMetadata(effectTexture, uv));
}

float sampleEffectForegroundMaskNearest(sampler2D effectTexture, vec2 uv) {
	return decodeEffectForegroundMask(sampleEffectMetadataNearest(effectTexture, uv));
}

float sampleEffectHandMask(sampler2D effectTexture, vec2 uv) {
	return decodeEffectHandMask(sampleEffectMetadata(effectTexture, uv));
}

float sampleEffectHandMaskNearest(sampler2D effectTexture, vec2 uv) {
	return decodeEffectHandMask(sampleEffectMetadataNearest(effectTexture, uv));
}

#endif
