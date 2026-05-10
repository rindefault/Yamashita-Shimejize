#define gbuffers_beaconbeam_legacy
varying vec2 texUV;
varying vec4 color;
varying float viewDist;

void main() {
   gl_Position = ftransform();

   texUV = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
   color = gl_Color;
   viewDist = length((gl_ModelViewMatrix * gl_Vertex).xyz);
}
