#define gbuffers_skybasic

#include "/shader.h"

uniform vec3 cameraPosition;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;

uniform sampler2D texture;
uniform sampler2D noisetex;

uniform int   worldDay;
uniform int   worldTime;
uniform int   bedrockLevel;
uniform int   frameCounter;
uniform float frameTimeCounter;

uniform float viewWidth, viewHeight;
uniform float rainStrength, rainFactor, timeAngle;
uniform int   isEyeInWater;
uniform vec3  fogColor, skyColor;
uniform float isCold;

varying vec4  glColor;
varying float alpha;
varying vec3  upVec;
varying vec3  sunVec;
varying vec2  texUV;

#include "/common/math.glsl"
#define time float(worldTime)
#include "/common/getAurora.fsh"
#undef time
#include "/common/getSkyAndFogColors.fsh"
#include "/common/getSubmergedFogColor.glsl"

// Colors
vec3 nightSkyColor = vec3(0.02, 0.007, 0.002);
vec3 nightFogColor = vec3(0.005, 0.002, 0.002);

vec3 rainSkyColor = vec3(0.5, 0.52, 0.55);
vec3 rainFogColor = vec3(0.4, 0.43, 0.5);

void main() {
    float fog = 0.0; // aurora already has horizonFade; no gl_Fog in core profile
    float dither = bayer4(gl_FragCoord.xy / 2.0);
    
    // Viewpos
		vec2 screenUV = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
		vec4 clipPos = vec4(screenUV * 2.0 - 1.0, 1.0, 1.0);
		vec4 viewPos = gbufferProjectionInverse * clipPos;
		viewPos /= viewPos.w;

    float VoU = clamp(dot(normalize(viewPos.rgb), upVec), 0.0, 1.0);
    float VoL = clamp(dot(normalize(viewPos.rgb), sunVec), 0.0, 1.0);

    // Final color with perfect band transitions
    vec4 finalColor = glColor;

    if (isEyeInWater != 0) {
      finalColor.rgb = getSubmergedFogColor(isEyeInWater, fogColor);

		  /* DRAWBUFFERS:0 */
      gl_FragData[0] = vec4(finalColor.rgb, 1.0);
      return;
    }

    // Fog & sky colors
    finalColor.rgb = getSky(VoU, VoL, dither);

		// Stars
		finalColor.rgb += getStars(viewPos.xyz);
    
    // Aurora
    #if ENABLE_AURORA > 0
			
			vec3 aurora = floor(getAurora(viewPos.xyz, dither) * 4.0 + dither) / 4.0;
			finalColor.rgb += aurora * (1.0 - fog);

    #endif

		/* DRAWBUFFERS:0 */
    gl_FragData[0] = vec4(finalColor.rgb, alpha);
}
