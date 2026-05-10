#define final

#include "/shader.h"

uniform mat4 gbufferModelView;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;

uniform sampler2D colortex0;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex6;
uniform sampler2D colortex7;

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform float wetness;
uniform float near;
uniform float far;
uniform float centerDepthSmooth;

varying vec2 texUV;

#include "/common/math.glsl"
#include "/common/depth_utils.glsl"
#include "/common/effect_metadata.glsl"
#include "/common/transformations.fsh"
#include "/common/getReflectionColor.fsh"

#define fragColor gl_FragData[0]

vec4 sampleFinalTexture(sampler2D tex, vec2 uv) {
#if __VERSION__ < 130
	return texture2D(tex, uv);
#else
	return texture(tex, uv);
#endif
}

vec4 sampleFinalScreenNearest(sampler2D tex, vec2 uv) {
	vec2 texSize = vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));
	vec2 clampedUV = clamp(uv, vec2(0.0), vec2(1.0) - 0.5 / texSize);
	vec2 snappedUV = (floor(clampedUV * texSize) + 0.5) / texSize;
	return sampleFinalTexture(tex, snappedUV);
}

vec4 sampleFinalEffectDataNearest(vec2 uv) {
	return sampleFinalScreenNearest(colortex2, uv);
}

float sampleFinalEffectMetadataNearest(vec2 uv) {
	return sampleFinalEffectDataNearest(uv).a;
}

vec2 getSkyFeatureOffset(int index) {
	if (index == 0) return vec2(6.0, 0.0);
	if (index == 1) return vec2(-6.0, 0.0);
	if (index == 2) return vec2(0.0, 6.0);
	if (index == 3) return vec2(0.0, -6.0);
	if (index == 4) return vec2(4.0, 4.0);
	if (index == 5) return vec2(-4.0, 4.0);
	if (index == 6) return vec2(4.0, -4.0);
	return vec2(-4.0, -4.0);
}

vec2 getDofTapOffset(int index) {
	if (index == 0) return vec2(0.55, 0.0);
	if (index == 1) return vec2(-0.55, 0.0);
	if (index == 2) return vec2(0.0, 0.55);
	if (index == 3) return vec2(0.0, -0.55);
	if (index == 4) return vec2(0.55, 0.55);
	if (index == 5) return vec2(-0.55, 0.55);
	if (index == 6) return vec2(0.55, -0.55);
	if (index == 7) return vec2(-0.55, -0.55);
	if (index == 8) return vec2(1.05, 0.0);
	if (index == 9) return vec2(-1.05, 0.0);
	if (index == 10) return vec2(0.0, 1.05);
	return vec2(0.0, -1.05);
}

float getDofTapWeight(int index) {
	if (index < 4) return 0.11;
	if (index < 8) return 0.075;
	return 0.045;
}

float getHandMask(vec2 uv) {
	return getDepthHandMask(depthtex1, uv);
}

vec3 getPuddleWaterTint(vec3 baseColor) {
	float waterBright = clamp(WATER_BRIGHTNESS, 0.0, 1.0);
	float waterOpacity = clamp(WATER_A, 0.0, 1.0);
	float waterBlue = mix(1.0, 1.55, clamp(WATER_B - 1.0, 0.0, 1.0));

	vec3 tint = mix(FOG_COLOR, SKY_COLOR, 0.38);
	tint = mix(tint, vec3(0.10, 0.16, 0.24 * waterBlue), 0.34);
	tint *= mix(0.52, 0.92, waterBright);

	return mix(baseColor, tint, waterOpacity * 0.42);
}

float getPuddleFogFade(vec3 fragPos) {
	#if !defined ENABLE_FOG
		return 1.0;
	#elif defined OVERWORLD
		float len = length(fragPos);
		float baseFog = clamp(OVERWORLD_FOG_MAX, 0.0, 1.0);
		float transitionFog = clamp(1.0 - OVERWORLD_FOG_MIN, 0.0, 1.0);
		float farPlane = max(far, 1.0);

		baseFog = min(baseFog, 1.0 - rainStrength * 0.35);

		float fogBase = rescale(len, 0.9 * baseFog * farPlane, farPlane);
		float softBandStart = mix(0.92, 0.48, transitionFog) * farPlane;
		float transitionHaze = rescale(len, softBandStart, farPlane) * (0.06 + 0.42 * transitionFog);
		float distanceHaze = (0.0008 + 0.0014 * transitionFog) * max(0.0, len - 96.0);
		distanceHaze *= mix(1.0, 0.90, rainStrength);
		float edgeMask = smoothstep(0.90 * farPlane, farPlane, len);
		float edgeBoost = edgeMask * (0.22 + 0.22 * transitionFog);
		float rainFarMask = smoothstep(0.55 * farPlane, farPlane, len);
		float rainBoost = rainStrength * rainFarMask * (0.12 + 0.16 * transitionFog);
		float fogMix = min(1.0, fogBase + transitionHaze + distanceHaze + edgeBoost + rainBoost);
		return 1.0 - fogMix;
	#else
		return 1.0;
	#endif
}

float getColorSaturation(vec3 color) {
	float maxC = max(max(color.r, color.g), color.b);
	float minC = min(min(color.r, color.g), color.b);
	return (maxC - minC) / max(maxC, 0.0001);
}

float getCloudCoverageMask(vec2 uv) {
	return clamp(sampleFinalTexture(colortex3, uv).g, 0.0, 1.0);
}

float getCloudPresenceMask(vec2 uv) {
	return step(0.001, getCloudCoverageMask(uv));
}

float getCloudAlphaMask(vec2 uv) {
	return smoothstep(0.01, 0.10, getCloudCoverageMask(uv));
}

float getSkyPixelMask(vec2 uv) {
	float skyDepth = step(0.9999, sampleFinalTexture(depthtex0, uv).x);
	return max(skyDepth, getCloudPresenceMask(uv));
}

float getSkyColorFeature(vec3 color) {
	float sat = getColorSaturation(color);
	float lum = luma(color);
	return smoothstep(0.18, 0.34, sat)
		* smoothstep(0.05, 0.16, lum)
		* (1.0 - smoothstep(0.48, 0.68, lum));
}

float getSkyFeatureMask(vec2 uv, vec3 centerColor) {
	float cloudFeature = max(getCloudAlphaMask(uv), getCloudPresenceMask(uv) * 0.72);
	float colorFeature = getSkyColorFeature(centerColor);
	if (cloudFeature > 0.96) return 1.0;
	if (colorFeature <= 0.0) return cloudFeature;

	vec2 pixel = 1.0 / vec2(viewWidth, viewHeight);

	float detail = 0.0;
	float coloredNeighbors = 0.0;
	float neighborLum = 0.0;
	float weightSum = 0.0;

	for (int i = 0; i < 8; i++) {
		vec2 sampleUV = clamp(uv + getSkyFeatureOffset(i) * pixel, vec2(0.0), vec2(1.0));
		float skyMask = getSkyPixelMask(sampleUV);
		if (skyMask < 0.5) continue;

		vec3 sampleColor = sampleFinalTexture(colortex0, sampleUV).rgb;
		detail += length(sampleColor - centerColor);
		coloredNeighbors += getSkyColorFeature(sampleColor);
		neighborLum += luma(sampleColor);
		weightSum += 1.0;
	}

	if (weightSum <= 0.0) return cloudFeature;

	detail /= weightSum;
	coloredNeighbors /= weightSum;
	neighborLum /= weightSum;

	float centerLum = luma(centerColor);
	float isolatedHighlight = smoothstep(0.10, 0.24, centerLum - neighborLum)
		* smoothstep(0.18, 0.42, centerLum)
		* (1.0 - smoothstep(0.02, 0.16, cloudFeature));
	if (isolatedHighlight > 0.0) return cloudFeature;

	float detailFeature = smoothstep(0.025, 0.12, detail);
	float broadColorFeature = colorFeature
		* detailFeature
		* smoothstep(0.10, 0.32, coloredNeighbors);

	return clamp(max(cloudFeature, broadColorFeature), 0.0, 1.0);
}

vec2 snapDofUV(vec2 uv, float pixelSize) {
	vec2 res = vec2(viewWidth, viewHeight);
	vec2 cell = floor(clamp(uv, vec2(0.0), vec2(1.0)) * res / pixelSize);
	return (cell * pixelSize + pixelSize * 0.5) / res;
}

float getDofFocusDepth() {
	if (centerDepthSmooth > 0.0 && centerDepthSmooth < 0.9999) {
		return centerDepthSmooth;
	}

	float centerDepth = sampleFinalTexture(depthtex0, vec2(0.5)).x;
	if (centerDepth > 0.0 && centerDepth < 0.9999) {
		return centerDepth;
	}

	return 0.9995;
}

const int DOF_TAP_COUNT = 12;

float getDofAmount() {
	return clamp(DOF_STRENGTH, 0.0, 1.0);
}

float getDofMacroFactor() {
	float dofAmount = getDofAmount();
	return dofAmount * dofAmount * (3.0 - 2.0 * dofAmount);
}

float getSingleFocusDofStrength(float depth, float focusDepth) {
	float dofAmount = getDofAmount();
	float depthDiff = abs(depth - focusDepth);
	float cocScale = mix(8.0, 34.0, dofAmount);
	float cocBias = mix(0.0006, 0.0001, dofAmount);
	float cocCurve = mix(0.12, 0.06, dofAmount);
	float coc = max(depthDiff * cocScale - cocBias, 0.0);
	coc = coc / sqrt(coc * coc + cocCurve);
	coc *= mix(0.42, 1.18, dofAmount);
	return clamp(pow(coc, mix(1.20, 0.90, dofAmount)), 0.0, 1.0);
}

vec4 sampleDofTap(vec2 uv, float pixelSize, float centerLinearDepth, float blurStrength) {
	vec2 snappedUV = snapDofUV(uv, pixelSize);
	float samplePackedEffectMask = sampleFinalEffectMetadataNearest(snappedUV);
	float sampleForegroundHandMask = decodeEffectHandMask(samplePackedEffectMask);
	if (max(getHandMask(snappedUV), sampleForegroundHandMask) > 0.5) return vec4(0.0);

	vec3 tapColor = sampleFinalTexture(colortex0, snappedUV).rgb;
	float tapDepth = sampleFinalTexture(depthtex0, snappedUV).x;
	if (tapDepth >= 0.9999) {
		float skyWeight = smoothstep(0.24, 0.86, blurStrength) * 0.40;
		return vec4(tapColor, skyWeight);
	}

	float tapLinearDepth = linearizeDepthValue(tapDepth, near, far);
	float depthTolerance = mix(3.2, 20.0, blurStrength);
	depthTolerance *= mix(1.0, 1.85, smoothstep(10.0, 96.0, centerLinearDepth));
	float depthWeight = 1.0 - smoothstep(depthTolerance, depthTolerance * 2.5, abs(tapLinearDepth - centerLinearDepth));
	if (depthWeight <= 0.0) return vec4(0.0);

	return vec4(tapColor, depthWeight);
}

vec4 sampleSkyDofTap(vec2 uv, float pixelSize, vec3 centerColor) {
	vec2 snappedUV = snapDofUV(uv, pixelSize);
	float skyMask = getSkyPixelMask(snappedUV);
	if (skyMask < 0.5) return vec4(0.0);

	vec3 sampleColor = sampleFinalTexture(colortex0, snappedUV).rgb;
	float cloudWeight = max(getCloudAlphaMask(snappedUV), getCloudPresenceMask(snappedUV) * 0.72);
	float featureWeight = max(cloudWeight, getSkyColorFeature(sampleColor) * 0.85);
	float similarity = 1.0 - smoothstep(0.10, 0.55, length(sampleColor - centerColor));
	float tapWeight = mix(0.28, 1.0, max(featureWeight, similarity * 0.45));
	return vec4(sampleColor, tapWeight);
}

vec4 getPuddleReflectionColor(vec2 uv, float depth, vec3 normal, vec3 fragPos) {
	float baseLinearDepth = linearizeDepthValue(depth, near, far);
	float biasFade = smoothstep(8.0, 80.0, baseLinearDepth);
	float originBias = mix(0.0015, 0.008, biasFade);
	float planeRejectThreshold = mix(0.008, 0.030, biasFade);
	float puddlePlaneY = view2player(fragPos).y;

	vec3 reflection = normalize(reflect(fragPos, normal));
	vec3 origin = fragPos + normal * originBias;
	vec3 curPos = origin + reflection;
	vec3 oldPos = origin;
	int refineCount = 0;

	for (int _ = 0; _ < MAX_RAYS; _++) {
		vec2 curUV = screen2uv(curPos);

		if (curUV.s < 0.0 || curUV.s > 1.0 || curUV.t < 0.0 || curUV.t > 1.0)
			break;

		vec2 ditheredUV = ditherUV(curUV);
		float sampleDepth = 1.0;
		bool sampleHit = false;
		vec3 samplePos = sampleReflectionScenePos(ditheredUV, sampleDepth, sampleHit);
		if (sampleHit) {
			float sampleWorldY = view2player(samplePos).y;
			if (sampleWorldY <= puddlePlaneY + planeRejectThreshold) {
				reflection *= RAY_MULT;
				oldPos = curPos;
				curPos += reflection;
				continue;
			}
		}

		float dist = abs(curPos.z - samplePos.z);
		float len = squaredLength(reflection);

		if (dist * dist < 2.0 * len * exp(0.03 * len) && !isWaterInfoPixel(ditheredUV)) {
			refineCount++;

			if (refineCount >= MAX_REFINEMENTS && isReflectionDepthAcceptable(sampleDepth, samplePos, depth, fragPos)) {
				vec2 reflectionUV = clamp(curUV + getReflectionWaveOffset(curUV, 0.0), vec2(0.0), vec2(1.0));
				vec2 reflectionPixelUV = pixelateUV(reflectionUV);
				vec3 reflectedColor = sampleFinalTexture(colortex0, reflectionPixelUV).rgb;
				float vignette = getReflectionVignette(curUV);
				return vec4(reflectedColor, vignette);
			}

			curPos = oldPos;
			reflection *= REFINEMENT_MULT;
		}

		reflection *= RAY_MULT;
		oldPos = curPos;
		curPos += reflection;
	}

	return vec4(0.0);
}

vec3 applySkyFeatureDof(vec3 currentColor, vec2 uv, float focusDepth) {
	float skyMask = getSkyPixelMask(uv);
	if (skyMask < 0.5) return currentColor;

	float featureMask = getSkyFeatureMask(uv, currentColor);

	float dofAmount = getDofAmount();
	float macro = getDofMacroFactor();
	float baseStrength = getSingleFocusDofStrength(0.99995, focusDepth);
	float layerStrength = mix(0.82, 1.0, featureMask);
	float strength = baseStrength * layerStrength;
	strength *= mix(0.55, 1.22, dofAmount);
	if (strength < 0.025) return currentColor;

	vec2 pixel = 1.0 / vec2(viewWidth, viewHeight);
	float pixelSize = 4.0;
	float radiusPx = mix(1.0, mix(5.0, 10.0, macro), pow(strength, mix(1.04, 0.78, macro)));

	vec3 blur = currentColor * mix(0.30, 0.16, macro);
	float weightSum = mix(0.30, 0.16, macro);

	vec4 tap;
	float tapWeight;

	tap = sampleSkyDofTap(uv + vec2( pixel.x * radiusPx, 0.0), pixelSize, currentColor);
	tapWeight = 0.13 * tap.a;
	blur += tap.rgb * tapWeight;
	weightSum += tapWeight;

	tap = sampleSkyDofTap(uv + vec2(-pixel.x * radiusPx, 0.0), pixelSize, currentColor);
	tapWeight = 0.13 * tap.a;
	blur += tap.rgb * tapWeight;
	weightSum += tapWeight;

	tap = sampleSkyDofTap(uv + vec2(0.0,  pixel.y * radiusPx), pixelSize, currentColor);
	tapWeight = 0.13 * tap.a;
	blur += tap.rgb * tapWeight;
	weightSum += tapWeight;

	tap = sampleSkyDofTap(uv + vec2(0.0, -pixel.y * radiusPx), pixelSize, currentColor);
	tapWeight = 0.13 * tap.a;
	blur += tap.rgb * tapWeight;
	weightSum += tapWeight;

	tap = sampleSkyDofTap(uv + vec2( pixel.x * radiusPx,  pixel.y * radiusPx), pixelSize, currentColor);
	tapWeight = 0.06 * tap.a;
	blur += tap.rgb * tapWeight;
	weightSum += tapWeight;

	tap = sampleSkyDofTap(uv + vec2(-pixel.x * radiusPx,  pixel.y * radiusPx), pixelSize, currentColor);
	tapWeight = 0.06 * tap.a;
	blur += tap.rgb * tapWeight;
	weightSum += tapWeight;

	tap = sampleSkyDofTap(uv + vec2( pixel.x * radiusPx, -pixel.y * radiusPx), pixelSize, currentColor);
	tapWeight = 0.06 * tap.a;
	blur += tap.rgb * tapWeight;
	weightSum += tapWeight;

	tap = sampleSkyDofTap(uv + vec2(-pixel.x * radiusPx, -pixel.y * radiusPx), pixelSize, currentColor);
	tapWeight = 0.06 * tap.a;
	blur += tap.rgb * tapWeight;
	weightSum += tapWeight;

	if (weightSum <= 0.32) return currentColor;
	blur /= weightSum;

	float dofDither = bayer4(gl_FragCoord.xy / 2.0);
	float strengthQ = floor(clamp(strength, 0.0, 1.0) * 5.0 + dofDither) / 5.0;
	float blurLevels = max(float(POSTERIZE_STRENGTH) * 0.5, 12.0);
	blur = floor(blur * blurLevels + dofDither) / blurLevels;

	float skyMix = clamp(strengthQ * mix(0.34, 0.84, dofAmount), 0.0, mix(0.32, 0.80, dofAmount));
	return mix(currentColor, blur, skyMix);
}

vec3 applySkySilhouetteDof(vec3 currentColor, vec2 uv, float focusDepth) {
	float dofAmount = getDofAmount();
	float macro = getDofMacroFactor();
	vec2 pixel = 1.0 / vec2(viewWidth, viewHeight);
	float pixelSize = 4.0;
	float edgeRadiusPx = mix(4.0, 8.0, macro);

	vec3 blur = currentColor * mix(0.34, 0.18, macro);
	float weightSum = mix(0.34, 0.18, macro);
	float edgeStrength = 0.0;

	for (int i = 0; i < DOF_TAP_COUNT; i++) {
		vec2 tapOffset = getDofTapOffset(i);
		vec2 sampleUV = uv + vec2(pixel.x * edgeRadiusPx * tapOffset.x,
		                          pixel.y * edgeRadiusPx * tapOffset.y);
		vec2 snappedUV = snapDofUV(sampleUV, pixelSize);
		float samplePackedEffectMask = sampleFinalEffectMetadataNearest(snappedUV);
		float sampleForegroundHandMask = decodeEffectHandMask(samplePackedEffectMask);
		if (max(getHandMask(snappedUV), sampleForegroundHandMask) > 0.5) continue;

		float sampleDepth = sampleFinalTexture(depthtex0, snappedUV).x;
		if (sampleDepth >= 0.9999) continue;

		float sampleStrength = getSingleFocusDofStrength(sampleDepth, focusDepth);
		if (sampleStrength < 0.015) continue;

		float tapWeight = getDofTapWeight(i) * sampleStrength;
		blur += sampleFinalTexture(colortex0, snappedUV).rgb * tapWeight;
		weightSum += tapWeight;
		edgeStrength = max(edgeStrength, sampleStrength);
	}

	if (weightSum <= 0.18 || edgeStrength < 0.015) return currentColor;
	blur /= weightSum;

	float dofDither = bayer4(gl_FragCoord.xy / 2.0);
	float blurLevels = max(float(POSTERIZE_STRENGTH) * 0.5, 12.0);
	blur = floor(blur * blurLevels + dofDither) / blurLevels;

	float edgeMix = smoothstep(0.04, 0.90, edgeStrength);
	return mix(currentColor, blur, clamp(edgeMix * mix(0.20, 0.64, dofAmount), 0.0, mix(0.24, 0.62, dofAmount)));
}

vec3 applyWorldDof(vec3 currentColor, vec2 uv, float depth, float focusDepth, float waterSurfaceMask, float waterReflectionMask) {
	float linearDepth = linearizeDepthValue(depth, near, far);
	float strength = getSingleFocusDofStrength(depth, focusDepth);
	float dofAmount = getDofAmount();
	if (waterSurfaceMask > 0.5) {
		float reflectiveMask = waterSurfaceMask * smoothstep(0.03, 0.20, waterReflectionMask);
		float waterBlurFloor = mix(0.0, mix(0.08, 0.18, dofAmount), reflectiveMask);
		strength = max(strength, waterBlurFloor);
		strength = mix(strength, pow(clamp(strength, 0.0, 1.0), 0.74), reflectiveMask * 0.9);
	}
	if (strength < 0.005) return currentColor;

	float macro = getDofMacroFactor();
	vec2 pixel = 1.0 / vec2(viewWidth, viewHeight);
	float pixelSize = 4.0;
	float radiusMin = mix(0.8, 1.8, macro);
	float radiusMax = mix(5.5, 18.0, macro);
	float radiusPx = mix(radiusMin, radiusMax, pow(strength, mix(1.02, 0.70, macro)));

	vec3 blur = currentColor * mix(0.24, 0.06, macro);
	float weightSum = mix(0.24, 0.06, macro);

	for (int i = 0; i < DOF_TAP_COUNT; i++) {
		vec2 tapOffset = getDofTapOffset(i);
		vec2 sampleUV = uv + vec2(pixel.x * radiusPx * tapOffset.x,
		                          pixel.y * radiusPx * tapOffset.y);
		vec4 tap = sampleDofTap(sampleUV, pixelSize, linearDepth, strength);
		float tapWeight = getDofTapWeight(i) * tap.a;
		blur += tap.rgb * tapWeight;
		weightSum += tapWeight;
	}

	if (weightSum <= 0.10) return currentColor;
	blur /= weightSum;

	if (waterSurfaceMask > 0.5) {
		float currentLuma = max(luma(currentColor), 0.0001);
		float blurLuma = max(luma(blur), 0.0001);
		vec3 lumaMatchedBlur = blur * (currentLuma / blurLuma);
		float preserveMix = waterSurfaceMask * smoothstep(0.05, 0.85, strength) * mix(0.94, 0.99, smoothstep(0.03, 0.20, waterReflectionMask));
		blur = mix(blur, lumaMatchedBlur, preserveMix);
	}

	float dofDither = bayer4(gl_FragCoord.xy / 2.0);
	float blurLevels = max(float(POSTERIZE_STRENGTH) * 0.5, 12.0);
	blur = floor(blur * blurLevels + dofDither) / blurLevels;

	float dofMix = smoothstep(0.005, 0.92, strength);
	float waterDampen = mix(1.0, 0.90, waterSurfaceMask * smoothstep(0.05, 0.90, strength));
	waterDampen = mix(waterDampen, waterDampen * 0.72, smoothstep(0.03, 0.20, waterReflectionMask) * waterSurfaceMask);
	float dofMixScale = mix(0.32, 0.96, dofAmount) * waterDampen;
	float dofMixMax = mix(0.36, 0.94, dofAmount) * waterDampen;
	return mix(currentColor, blur, clamp(dofMix * dofMixScale, 0.0, dofMixMax));
}

vec3 applyPixelDof(vec3 currentColor, vec2 uv, float depth, float effectBlockMask, float waterSurfaceMask, float waterReflectionMask) {
	#if ENABLE_PIXEL_DOF == 0
		return currentColor;
	#else
		if (effectBlockMask > 0.5) return currentColor;
		float dofAmount = getDofAmount();
		if (dofAmount <= 0.001) return currentColor;
		float focusDepth = getDofFocusDepth();
	float skyMask = getSkyPixelMask(uv);

		if (depth >= 0.9999 || skyMask > 0.001) {
			vec3 skyColor = applySkyFeatureDof(currentColor, uv, focusDepth);
			return applySkySilhouetteDof(skyColor, uv, focusDepth);
		}

		return applyWorldDof(currentColor, uv, depth, focusDepth, waterSurfaceMask, waterReflectionMask);
	#endif
}

void main() {
	vec4 color = sampleFinalTexture(colortex0, texUV);
	vec4 info  = sampleFinalTexture(colortex7, texUV);

	float depth = sampleFinalTexture(depthtex0, texUV).x;
	vec4 effectData = sampleFinalEffectDataNearest(texUV);
	float packedEffectMask = effectData.a;
	float handMask = getHandMask(texUV);
	float puddleMaskRaw = decodeEffectPuddleMask(packedEffectMask);
	float effectBlockMask = handMask;
	float waterSurfaceMask = step(0.99, info.y);
	float waterReflectionMask = 0.0;
	float puddleMask = 0.0;

	#if ENABLE_PUDDLES > 0
		puddleMask = puddleMaskRaw * smoothstep(0.05, 0.24, max(rainStrength, wetness));
		puddleMask *= 1.0 - effectBlockMask;
	#endif

	if (isSceneInfoWater(info)) {
		// the normal doesn't come premultiplied by the normal matrix to
		// avoid the modelview transformations when view bobbing is on
		// which causes severe artifacts when moving
		vec3 prenormal = sampleFinalTexture(colortex6, texUV).xyz*2.0 - 1.0;

		#if WATER_WAVE_SIZE > 0

			if (info.y > 0.99 && abs(prenormal.y) > 0.8) {
				prenormal.xz *= 0.01 * WATER_WAVE_SIZE;
			}

		#endif

		float dither = bayer2(texUV / 4);

		vec3 normal          = world2screen(prenormal);
		vec3 fragPos         = uv2screen(texUV, depth);
		vec4 reflectionColor = getReflectionColor(depth, normal, fragPos, dither);
		float fresnel        = 1.0 - dot(normal, -normalize(fragPos));
		float reflFade = 1.0;
		if (info.y > 0.99) {
			// Only damp far reflection in rain; keep dry-weather reflections intact.
			float farSky = smoothstep(0.78, 0.995, depth);
			float rainFade = smoothstep(0.02, 0.18, rainStrength);
			reflFade *= 1.0 - farSky * 0.38 * rainFade;
		}
		float rainReflBoost = mix(1.0, 1.32, rainStrength);
		waterReflectionMask = clamp(reflectionColor.a * fresnel * REFLECTIONS * reflFade, 0.0, 1.0);

		color.rgb = mix(
			color.rgb,
			reflectionColor.rgb,
			reflectionColor.a * fresnel * 0.1*REFLECTIONS * (1.0 - color.rgb) * reflFade * rainReflBoost
		);

	}

	#if ENABLE_PUDDLES > 0
		if (puddleMask > 0.12 && effectBlockMask < 0.5 && depth < 0.9999 && info.x <= 0.99) {
			vec3 puddleNormal = normalize(world2screen(vec3(0.0, 1.0, 0.0)));
			vec3 fragPos = uv2screen(texUV, depth);
			float puddleFogFade = getPuddleFogFade(fragPos);
			vec4 puddleReflection = getPuddleReflectionColor(texUV, depth, puddleNormal, fragPos);
			float fresnel = 1.0 - clamp(dot(puddleNormal, -normalize(fragPos)), 0.0, 1.0);
			float rimMask = smoothstep(0.04, 0.95, fresnel);
			float flatViewMask = 1.0 - rimMask;
			float bodyMask = smoothstep(0.10, 0.34, puddleMask);
			float wetDarken = (bodyMask * 0.034 + puddleMask * mix(0.010, 0.026, rimMask)) * puddleFogFade;
			float ssrAlpha = clamp(puddleReflection.a, 0.0, 1.0);
			float ssrSoft = smoothstep(0.02, 0.22, ssrAlpha);
			vec3 puddleTint = getPuddleWaterTint(color.rgb);
			float tintAmount = puddleMask *
				(0.08 + 0.16 * bodyMask + 0.14 * flatViewMask) *
				clamp(WATER_A, 0.0, 1.0) *
				(1.0 - 0.25 * ssrSoft) *
				puddleFogFade;
			float reflectAmount = ssrAlpha *
				(bodyMask * 0.05 + puddleMask * (0.03 + 0.15 * rimMask)) *
				clamp(0.72 * REFLECTIONS, 0.0, 1.0) *
				puddleFogFade;
			vec3 puddleSurface = mix(puddleTint, puddleReflection.rgb, ssrSoft);
			color.rgb *= 1.0 - wetDarken;
			color.rgb = mix(color.rgb, puddleTint, clamp(tintAmount, 0.0, 0.44));
			color.rgb = mix(color.rgb, puddleSurface, clamp(reflectAmount, 0.0, 0.70));
		}
	#endif

	color.rgb = applyPixelDof(color.rgb, texUV, depth, effectBlockMask, waterSurfaceMask, waterReflectionMask);
	fragColor = color;
}
