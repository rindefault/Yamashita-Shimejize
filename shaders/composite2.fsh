#version 330 compatibility

#include "shader.h"
#include "/common/math.glsl"

uniform float viewWidth, viewHeight, aspectRatio;

uniform vec3 cameraPosition, previousCameraPosition, shadowLightPosition;

uniform mat4 gbufferPreviousProjection, gbufferProjectionInverse;
uniform mat4 gbufferModelView, gbufferPreviousModelView, gbufferModelViewInverse;

uniform sampler2D texture;
uniform sampler2D colortex0;
uniform sampler2D depthtex0;

uniform float near;
uniform float far;
uniform int   isEyeInWater;

in vec4 color;
in vec2 texcoord;
in vec2 lightPos;

vec3 screen2space(vec2 coord, float depth) {
	vec4 pos = gbufferProjectionInverse * (vec4(coord, depth, 1.0) * 2.0 - 1.0);
	return pos.xyz/pos.w;
}

float cdist(vec2 coord) {
	return clamp(1.0 - max(abs(coord.s-0.5),abs(coord.t-0.5))*2.0, 0.0, 1.0);
}

float getNoise(vec2 pos) {
  float noise = fract(sin(dot(pos, vec2(18.9898f,28.633f))) * 4378.5453f);
	return noise;
}

vec3 calcRays(vec3 color) {
  float land = 1.0-near/far/far;
  float raysIntensity = 0.25;
  
  // Pixelation parameters for rays only
  float rayPixelSize = 512.0;
  vec2 rayTexcoord = floor(texcoord * rayPixelSize) / rayPixelSize;
  
  vec2 deltatexcoord = vec2(lightPos - texcoord) * 0.04; // Use original texcoord for direction
  vec2 noisetc = rayTexcoord + deltatexcoord*getNoise(rayTexcoord);
  
  // Pixelated ray sampling
  float gr = 1.0;
  for (int i = 0; i < 20; i++) {
    vec2 sampleCoord = floor(noisetc * rayPixelSize) / rayPixelSize;
    float depth0 = texture2D(depthtex0, sampleCoord).x;
    noisetc += deltatexcoord;
    gr += dot(step(land, depth0), 1.0)*cdist(noisetc);
  }
  gr /= 20.0;

  // Regular lighting calculation (unchanged)
  vec3 gfragpos0 = screen2space(texcoord.xy, texture2D(depthtex0, texcoord.xy).x);
  float lightFactor = clamp(dot(normalize(gfragpos0.xyz), normalize(shadowLightPosition.xyz)), 0.0, 1.0);
  
  // Apply dithering and quantization only to rays
  float rayDither = bayer4(gl_FragCoord.xy / 2.0);
  float pixelatedRays = (gr + 1.0) * raysIntensity;
  pixelatedRays += rayDither * 0.1;
  pixelatedRays = floor(pixelatedRays * 8.0) / 8.0;
  
  // Combine original color with pixelated rays
  vec3 raysEffect = color * pixelatedRays * (1.0 - isEyeInWater);
  return (color + raysEffect) / 1.2; // Additive blending for rays
}

void main() {
  vec4 tex = texture2D(texture, texcoord.xy) * color;

  #if ENABLE_GODRAYS > 0

    tex.rgb = calcRays(tex.rgb);

  #endif

  gl_FragData[0] = tex;
  gl_FragData[1] = vec4(0.0);
}