#define gbuffers_clouds

#include "/shader.h"

uniform vec3 fogColor;
uniform float rainStrength;
uniform int isEyeInWater;

varying float fogMix;
varying vec4  color;

#include "/common/math.glsl"

void main() {
   #if defined(THE_NETHER) || defined(THE_END) || defined(NETHER) || defined(END)
      discard;
   #elif ENHANCED_CLOUDS > 0
      discard;
   #else
      if (isEyeInWater != 0) {
         discard;
      }

      float cloudFog = clamp(fogMix, 0.0, 1.0);
      float rainFogBoost = rainStrength * smoothstep(0.40, 0.88, cloudFog) * 0.16;
      cloudFog = clamp(cloudFog + rainFogBoost, 0.0, 1.0);

      float rainReliefKill = rainStrength * smoothstep(0.26, 0.84, cloudFog) * 0.70;
      vec3 cloudRgb = mix(color.rgb, vec3(luma(color.rgb)), rainReliefKill * 0.84);
      cloudRgb = mix(cloudRgb, fogColor, 0.4);

      vec4 cloudColor = vec4(cloudRgb, mix(0.8 * color.a, 0.0, cloudFog));

      /* DRAWBUFFERS:03 */
      gl_FragData[0] = cloudColor;
      gl_FragData[1] = vec4(1.0, cloudColor.a, 0.0, 1.0);
   #endif
}
