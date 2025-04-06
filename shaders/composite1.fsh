#version 330 compatibility

#include "shader.h"
#include "common/math.glsl"

uniform float viewWidth, viewHeight, aspectRatio;

uniform vec3 cameraPosition, previousCameraPosition;

uniform mat4 gbufferPreviousProjection, gbufferProjectionInverse;
uniform mat4 gbufferModelView, gbufferPreviousModelView, gbufferModelViewInverse;

uniform sampler2D colortex0;
uniform sampler2D depthtex1;

in vec2 texcoord;

vec3 motionBlur(vec3 color, float z, float dither) {
	
	float hand = float(z < 0.56);

	if (hand < 0.5) {
		float mbwg = 0.0;
		vec2 doublePixel = 2.0 / vec2(viewWidth, viewHeight);
		vec3 mblur = vec3(0.0);
		
		vec4 currentPosition = vec4(texcoord, z, 1.0) * 2.0 - 1.0;
		
		vec4 viewPos = gbufferProjectionInverse * currentPosition;
		viewPos = gbufferModelViewInverse * viewPos;
		viewPos /= viewPos.w;
		
		vec3 cameraOffset = cameraPosition - previousCameraPosition;
		
		vec4 previousPosition = viewPos + vec4(cameraOffset, 0.0);
		previousPosition = gbufferPreviousModelView * previousPosition;
		previousPosition = gbufferPreviousProjection * previousPosition;
		previousPosition /= previousPosition.w;

		vec2 velocity = (currentPosition - previousPosition).xy;
		velocity = velocity / (1.0 + length(velocity)) * 1.6 * 0.02;
		
		vec2 coord = texcoord.st - velocity * dither;

		for (int i = 0; i < 5; i++, coord += velocity) {
			vec2 sampleCoord = clamp(coord, doublePixel, 1.0 - doublePixel);
			float mask = float(texture2D(depthtex1, sampleCoord).r > 0.56);
			mblur += texture2DLod(colortex0, sampleCoord, 0.0).rgb * mask;
			mbwg += mask;
		}
		mblur /= max(mbwg, 1.0);

		return mblur;
	}

	else return color;
}

void main() {
  vec3 color = texture2DLod(colortex0, texcoord, 0.0).rgb;
	
	float z = texture2D(depthtex1, texcoord.st).x;
	float dither = bayer4(gl_FragCoord.xy / 2) * 16;

	color = motionBlur(color, z, dither);
	
	/*DRAWBUFFERS:0*/
	gl_FragData[0] = vec4(color, 1.0);
}