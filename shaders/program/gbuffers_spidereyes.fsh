#define gbuffers_spidereyes

uniform sampler2D texture;

varying vec2 texcoord;
varying vec4 glColor;

#include "/common/math.glsl"

void main() {
  vec4 color = texture2D(texture, texcoord) * glColor;

  color.rgb *= 1.0 - 0.6 * pow2(pow2(min1(luma(color.rgb) * 1.2)));

  /* DRAWBUFFERS:0 */
  gl_FragColor = color;
}
