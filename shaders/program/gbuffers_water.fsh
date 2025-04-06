#define gbuffers_water

#include "/shader.h"

uniform vec3 fogColor;
uniform sampler2D texture;

varying vec2 texUV;
varying vec2 lightUV;
varying vec3 worldPos;
varying vec4 color;
varying vec4 normal;
varying vec4 ambient;
varying float fogMix;
varying float isWater;
varying float waterTexStrength;
varying float torchStrength;

#ifdef HAND_DYNAMIC_LIGHTING
   uniform int heldBlockLightValue;
#endif

#include "/common/math.glsl"

void main() {
   vec4 albedo  = texture2D(texture, texUV);
   vec4 ambient = ambient;
   vec4 color   = color;

   albedo *= color * ambient;

   albedo.rgb = mix(albedo.rgb, fogColor, fogMix);

   /* DRAWBUFFERS:067 */
   gl_FragData[0] = albedo;
   gl_FragData[1] = normal;
   gl_FragData[2] = vec4(1.0, isWater, 0.0, 1.0);
}