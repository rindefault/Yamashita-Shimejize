#version 120

varying vec2 texcoord;
varying vec2 lightPos;
varying vec4 color;

uniform vec3 sunPosition;
uniform mat4 gbufferProjection;

void main() {
  texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
  gl_Position = ftransform();
  color = vec4(1.0);

  vec4 tpos = vec4(sunPosition,1.0)*gbufferProjection;
  tpos = vec4(tpos.xyz/tpos.w,1.0);
  vec2 pos1 = tpos.xy/tpos.z;
  lightPos = pos1*0.5+0.5;
}
