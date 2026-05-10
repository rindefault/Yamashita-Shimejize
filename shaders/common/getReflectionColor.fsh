#define MAX_RAYS 16
#define MAX_REFINEMENTS 4
#define RAY_MULT 2.0
#define REFINEMENT_MULT 0.1

#ifndef YS_REFLECTION_COMMON_UNIFORMS
#define YS_REFLECTION_COMMON_UNIFORMS
uniform float viewWidth, viewHeight, aspectRatio;
uniform float frameTimeCounter;
uniform float rainStrength;
uniform vec3 cameraPosition;
#endif

vec4 sampleReflectionTexture(sampler2D tex, vec2 uv) {
#if __VERSION__ < 130
	return texture2D(tex, uv);
#else
	return texture(tex, uv);
#endif
}

vec4 sampleSceneInfo(vec2 uv) {
	return sampleReflectionTexture(colortex7, uv);
}

vec3 uv2screenWithProjection(vec2 uv, float depth, mat4 projectionInverse) {
	return nvec3(projectionInverse * vec4(2.0 * vec3(uv, depth) - 1.0, 1.0));
}

vec3 sampleReflectionScenePos(vec2 uv, out float sampleDepth, out bool sceneHit) {
	float vanillaDepth = sampleReflectionTexture(depthtex0, uv).x;
	sceneHit = vanillaDepth < 0.9999;
	sampleDepth = vanillaDepth;

	return uv2screen(uv, vanillaDepth);
}

bool isReflectionDepthAcceptable(float sampleDepth, vec3 samplePos, float currentDepth, vec3 currentPos) {
	return sampleDepth + 0.001 >= currentDepth;
}

bool isSceneInfoWater(vec4 info) {
	return info.x > 0.99;
}

bool isWaterInfoPixel(vec2 uv) {
	return isSceneInfoWater(sampleSceneInfo(uv));
}

vec2 ditherUV(vec2 uv) {
	float pixelSize = 2;
	vec2 pixelUV = floor(uv * vec2(viewWidth, viewHeight) / pixelSize); // Pixelate UVs
	float ditherValue = bayer4(pixelUV);
	return floor(uv * vec2(viewWidth, viewHeight) / pixelSize) * pixelSize / vec2(viewWidth, viewHeight) + (ditherValue - 0.5) * pixelSize / vec2(viewWidth, viewHeight); //dithered and pixelated uv.
}

vec2 pixelateUV(vec2 uv) {
	float pixelSize = 2.0;
	return floor(uv * vec2(viewWidth, viewHeight) / pixelSize) * pixelSize / vec2(viewWidth, viewHeight);
}

vec2 getReflectionWaveOffset(vec2 uv, float dither) {
	vec2 pixel = vec2(1.0 / viewWidth, 1.0 / viewHeight);
	float waveRate = mix(14.0, 26.0, rainStrength);
	float time = floor(frameTimeCounter * waveRate) / waveRate;
	float storm = rainStrength;
	float row = floor(uv.y * viewHeight * 0.5);
	float rowPhase = fract(row * 0.381966);

	// Pixel-ripple: each row shifts in whole-pixel steps (no subpixel movement).
	float waveA = sin(row * 0.42 + time * 2.2 + rowPhase * 6.28318530718);
	float waveB = sin(row * 0.97 - time * 1.6 + rowPhase * 4.1);
	float horizontalWave = 0.7 * waveA + 0.3 * waveB;

	// Rain storm swell: wider (lower-frequency) wave layer on top of ripple.
	float swellA = sin(row * 0.085 + time * 0.95);
	float swellB = sin(row * 0.048 - time * 0.62 + rowPhase * 1.7);
	float stormSwell = 0.65 * swellA + 0.35 * swellB;
	horizontalWave = mix(horizontalWave, horizontalWave * 0.50 + stormSwell * 1.05, storm);

	// Gust bursts: short pulses that create storm-like "jerky" kicks.
	float burstT = floor(frameTimeCounter * mix(3.0, 7.0, storm)) / mix(3.0, 7.0, storm);
	float burstWave = sin(row * 0.11 + burstT * 5.4 + rowPhase * 9.0);
	float burstGate = smoothstep(0.35, 0.92, abs(sin(burstT * 1.8 + rowPhase * 12.0)));
	horizontalWave += burstWave * burstGate * storm * 0.55;

	// Micro-jitter in heavy rain, quantized so it stays pixel-ish.
	float jitterSeed = fract(sin(row * 17.13 + floor(frameTimeCounter * 18.0) * 0.37) * 43758.5453);
	float jitter = (jitterSeed - 0.5) * 2.0;
	horizontalWave += jitter * storm * 0.28;

	float wavePixels = mix(4.0, 8.0, rainStrength);
	// Quantized jump intensity: stronger jumps in storm without becoming chaotic.
	float jumpLevels = mix(10.0, 6.0, storm);
	float quantWave = floor(horizontalWave * jumpLevels + 0.5) / jumpLevels;
	float waveShiftPixels = floor(quantWave * wavePixels + 0.5);
	return vec2(waveShiftPixels * pixel.x, 0.0);
}

float getReflectionVignette(vec2 uv) {
  uv.y = 1.0 - uv.y;
  uv.x *= 1.0 - uv.x;
  uv.y *= uv.y;
  return 1.0 - pow(1.0 - uv.x, 20.0*uv.y);
}

vec4 getReflectionColor(float depth, vec3 normal, vec3 fragPos, float dither) {
	vec3 reflection = normalize(reflect(fragPos, normal));
	vec3 curPos = fragPos + reflection;
	vec3 oldPos = fragPos;

	int j = 0;

	for (int _ = 0; _ < MAX_RAYS; _++) {
		vec2 curUV = screen2uv(curPos);

		if (curUV.s < 0.0 || curUV.s > 1.0 || curUV.t < 0.0 || curUV.t > 1.0)
			break;

		// Dither the UV coordinates
		vec2 ditheredUV = ditherUV(curUV);

		float sampleDepth = 1.0;
		bool sampleHit = false;
		vec3 samplePos = sampleReflectionScenePos(ditheredUV, sampleDepth, sampleHit);
		float dist = abs(curPos.z - samplePos.z);
		float len = squaredLength(reflection);

		if (dist*dist < 2.0*len * exp(0.03*len) && !isWaterInfoPixel(ditheredUV)) {
			j++;

			if (j >= MAX_REFINEMENTS && isReflectionDepthAcceptable(sampleDepth, samplePos, depth, fragPos)) {
				// Animate only reflection sampling, then re-apply pixel+dither snapping.
				vec2 reflectionUV = clamp(curUV + getReflectionWaveOffset(curUV, dither), vec2(0.0), vec2(1.0));
				vec2 reflectionPixelUV = pixelateUV(reflectionUV);
				vec3 reflectedColor = sampleReflectionTexture(colortex0, reflectionPixelUV).rgb;
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
