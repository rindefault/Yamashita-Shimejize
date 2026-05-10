#version 120

varying vec2 texcoord;
varying float twinkleFactor;

uniform float frameTimeCounter;

float getTwinkleFactor() {
  float speed = 1.0;
  float steps = 3.0;
  float pingpong = abs(fract(frameTimeCounter * speed * 0.5) * 2.0 - 1.0);
  float stepped = floor(pingpong * steps) / (steps - 1.0);
  return mix(0.1, 0.2, stepped);
}

void main() {
  texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
  twinkleFactor = getTwinkleFactor();
  gl_Position = ftransform();
}
