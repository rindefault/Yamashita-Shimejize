#define gbuffers_skytextured

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

varying vec2 texUV;
varying vec4 glColor;

void main() {
  vec3 position = (gl_ModelViewMatrix * gl_Vertex).xyz;
  position = (gbufferModelViewInverse * vec4(position, 1.0)).xyz;
  gl_Position = gl_ProjectionMatrix * gbufferModelView * vec4(position, 1.0);
  texUV = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

  glColor = gl_Color;
}
