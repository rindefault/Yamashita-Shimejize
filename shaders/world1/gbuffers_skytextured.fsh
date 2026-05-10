#version 120

#define THE_END

#include "/shader.h"

uniform sampler2D texture;
uniform float frameTimeCounter;

varying vec2 texUV;
varying vec4 color;
varying vec3 worldPos;

vec3 getBlockCenteredWorldPos(vec3 pos, vec2 blockCoord, vec2 blockOffset) {
   const float STAR_BLOCK = 4.0;
   vec2 blockCenter = (blockCoord + 0.5) * STAR_BLOCK + blockOffset;
   vec2 delta = blockCenter - gl_FragCoord.xy;

   return pos + dFdx(pos) * delta.x + dFdy(pos) * delta.y;
}

vec4 getMiniatureStarsAtPhase(vec3 pos, float phase) {
   float theta   = mod(atan(pos.y, pos.x), PI) - 0.5 * PI;
   float phi     = acos(clamp(pos.z / length(pos), -1.0, 1.0)) - 0.5 * PI;
   float slice   = ceil(atan(theta, phi) * END_STARS_AMOUNT);
   float offset  = cos(slice);
   float invDist = offset / (theta * theta + phi * phi);

   slice *= offset;

   return exp(fract(invDist + slice + phase) * -END_STARS_DRAG) / invDist;
}

vec4 getSupersampledMiniatureStars(vec3 pos, vec2 blockCoord, float phase) {
   float sub = mix(0.85, 1.35, clamp(END_STARS_SPEED * 4.0, 0.0, 1.0));

   vec4 center = clamp(getMiniatureStarsAtPhase(getBlockCenteredWorldPos(pos, blockCoord, vec2(0.0)), phase), vec4(0.0), vec4(1.0));
   vec4 diag0  = clamp(getMiniatureStarsAtPhase(getBlockCenteredWorldPos(pos, blockCoord, vec2(-sub, -sub)), phase), vec4(0.0), vec4(1.0));
   vec4 diag1  = clamp(getMiniatureStarsAtPhase(getBlockCenteredWorldPos(pos, blockCoord, vec2( sub, -sub)), phase), vec4(0.0), vec4(1.0));
   vec4 diag2  = clamp(getMiniatureStarsAtPhase(getBlockCenteredWorldPos(pos, blockCoord, vec2(-sub,  sub)), phase), vec4(0.0), vec4(1.0));
   vec4 diag3  = clamp(getMiniatureStarsAtPhase(getBlockCenteredWorldPos(pos, blockCoord, vec2( sub,  sub)), phase), vec4(0.0), vec4(1.0));

   vec4 avg = center * 0.40
            + diag0  * 0.15
            + diag1  * 0.15
            + diag2  * 0.15
            + diag3  * 0.15;

   return center + (avg - center) * 0.72;
}

vec4 getPixelizedMiniatureStarsAtPhase(vec3 pos, float phase) {
   const float STAR_BLOCK = 4.0;

   vec2 blockCoord = floor(gl_FragCoord.xy / STAR_BLOCK);
   vec2 blockFrac = fract(gl_FragCoord.xy / STAR_BLOCK);
   vec2 blend = smoothstep(vec2(0.18), vec2(0.82), blockFrac);

   vec4 stars00 = getSupersampledMiniatureStars(pos, blockCoord, phase);
   vec4 stars10 = getSupersampledMiniatureStars(pos, blockCoord + vec2(1.0, 0.0), phase);
   vec4 stars01 = getSupersampledMiniatureStars(pos, blockCoord + vec2(0.0, 1.0), phase);
   vec4 stars11 = getSupersampledMiniatureStars(pos, blockCoord + vec2(1.0, 1.0), phase);

   vec4 stars0 = mix(stars00, stars10, blend.x);
   vec4 stars1 = mix(stars01, stars11, blend.x);

   return mix(stars0, stars1, blend.y);
}

vec4 getMotionCompensatedMiniatureStars(vec3 pos) {
   float speed = clamp(END_STARS_SPEED * 6.0, 0.0, 1.0);
   float phase = frameTimeCounter * END_STARS_SPEED;
   float phaseAA = mix(0.0025, 0.0140, speed);
   float tailStrength = mix(0.18, 0.32, speed);

   vec4 center = getPixelizedMiniatureStarsAtPhase(pos, phase);
   vec4 prev   = getPixelizedMiniatureStarsAtPhase(pos, phase - phaseAA);
   vec4 tail   = max(prev - center, vec4(0.0));
   float centerMask = clamp(max(max(center.r, center.g), max(center.b, center.a)), 0.0, 1.0);

   return clamp(center + tail * tailStrength * (1.0 - centerMask), vec4(0.0), vec4(1.0));
}

void main() {
   vec4 albedo = texture2D(texture, texUV) * color;
   albedo.rgb *= vec3(0.16, 0.11, 0.20);

   vec4 stars = getMotionCompensatedMiniatureStars(worldPos);

   gl_FragData[0] = vec4(albedo.rgb, albedo.a) + stars * END_STARS_OPACITY;
}
