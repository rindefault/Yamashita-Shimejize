#define gbuffers_clouds

#include "/shader.h"

uniform float fogEnd;
uniform float fogStart;
uniform float far;
uniform int fogShape;
uniform mat4 gbufferModelViewInverse;
varying float fogMix;
varying vec4  color;

#include "/common/math.glsl"
#include "/common/getFogMix.vsh"

void main() {
   gl_Position = ftransform();

   color = gl_Color;
   vec3 worldPos = mat3(gbufferModelViewInverse)
                 * (gl_ModelViewMatrix * gl_Vertex).xyz
                 + gbufferModelViewInverse[3].xyz;
   fogMix = getFogMix(worldPos);
}
