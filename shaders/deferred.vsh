#version 120

varying vec2 texcoord;

void main() {
  texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
  gl_Position = ftransform();
}
