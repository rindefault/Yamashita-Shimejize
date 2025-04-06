#define MAX_RAYS 16
#define MAX_REFINEMENTS 4
#define RAY_MULT 2.0
#define REFINEMENT_MULT 0.1

uniform float viewWidth, viewHeight, aspectRatio;
uniform vec3 cameraPosition;

vec2 ditherUV(vec2 uv) {
	float pixelSize = 2;
	vec2 pixelUV = floor(uv * vec2(viewWidth, viewHeight) / pixelSize); // Pixelate UVs
	float ditherValue = bayer4(pixelUV);
	return floor(uv * vec2(viewWidth, viewHeight) / pixelSize) * pixelSize / vec2(viewWidth, viewHeight) + (ditherValue - 0.5) * pixelSize / vec2(viewWidth, viewHeight); //dithered and pixelated uv.
}

float getReflectionVignette(vec2 uv) {
  uv.y = 1.0 - uv.y;
  uv.x *= 1.0 - uv.x;
  uv.y *= uv.y;
  return 1.0 - pow(1.0 - uv.x, 10.0*uv.y);
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

		float sampleDepth = texture2D(depthtex0, ditheredUV).x;
		vec3 samplePos = uv2screen(ditheredUV, sampleDepth);
		float dist = abs(curPos.z - samplePos.z);
		float len = squaredLength(reflection);

		if (dist*dist < 2.0*len * exp(0.03*len) && !(texture2D(colortex7, ditheredUV).x > 0.99)) {
			j++;

			if (j >= MAX_REFINEMENTS && sampleDepth + 0.001 >= depth) {
				// Sample color with pixelated UV, but use original UV for vignette
				vec3 reflectedColor = texture2D(colortex0, ditheredUV).rgb;
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