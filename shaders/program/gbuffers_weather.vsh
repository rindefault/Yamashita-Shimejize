#define gbuffers_weather

varying vec2 texUV;
varying vec2 lightUV;
varying vec4 color;

void main() {
   gl_Position = ftransform();

   color = gl_Color;
   texUV = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
   lightUV = (gl_TextureMatrix[1] * gl_MultiTexCoord1).st;
}
