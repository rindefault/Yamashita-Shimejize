#version 330 compatibility

out vec2 texcoord;
out vec2 lightPos;
out vec4 color;

uniform vec3 sunPosition;
uniform mat4 gbufferProjection;

void main() {
  gl_Position = ftransform();
  texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
  color = gl_Color;

  vec4 tpos = vec4(sunPosition,1.0)*gbufferProjection;
  tpos = vec4(tpos.xyz/tpos.w,1.0);
  vec2 pos1 = tpos.xy/tpos.z;
  lightPos = pos1*0.5+0.5;
}