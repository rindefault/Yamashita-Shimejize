#define gbuffers_spidereyes

varying vec2 texcoord;
varying vec4 glColor;

void main() {
  gl_Position = ftransform();

  texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
  glColor = gl_Color;
}
