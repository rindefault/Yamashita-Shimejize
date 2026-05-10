#define gbuffers_beaconbeam_legacy

#include "/shader.h"

uniform sampler2D texture;
uniform vec3 fogColor;
uniform float fogStart;
uniform float fogEnd;

varying vec2 texUV;
varying vec4 color;
varying float viewDist;

#define fragColor0 gl_FragData[0]
#define hotMaskOut gl_FragData[1]
#define infoOut gl_FragData[2]

void main() {
   vec4 beam = texture2D(texture, texUV) * color;

   if (beam.a < 0.001) {
      discard;
   }

   #ifdef ENABLE_FOG
      float fogRange = max(fogEnd - fogStart, 0.0001);
      float beamFog = clamp((viewDist - fogStart) / fogRange, 0.0, 1.0);
      beam.rgb = mix(beam.rgb, fogColor, beamFog);
   #endif

   if (beam.a < 0.5) {
      beam.a *= 0.85;
   }

   /* DRAWBUFFERS:027 */
   fragColor0 = beam;
   hotMaskOut = vec4(0.0, 0.0, 0.0, 0.82);
   infoOut = vec4(0.0);
}
