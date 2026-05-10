#define gbuffers_line

uniform sampler2D texture;

varying vec2 texUV;
varying vec4 glColor;

void main() {
    gl_FragData[0] = texture2D(texture, texUV) * glColor;
}
