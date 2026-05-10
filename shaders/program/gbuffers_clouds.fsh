#define gbuffers_clouds

#include "/shader.h"

uniform vec3 fogColor;
uniform vec3 skyColor;
uniform float fogEnd;
uniform float far;
uniform float rainStrength;
uniform float rainFactor;
uniform int isEyeInWater;

varying float fogMix;
varying vec4  color;
varying vec3  worldPos;

#include "/common/math.glsl"

vec3 getRainOvercastTarget() {
   vec3 overcastSky = mix(skyColor, fogColor, 0.45);
   return mix(overcastSky, vec3(luma(overcastSky)), 0.35);
}

float getRainCloudDistanceFog(vec3 cloudPos) {
   float hDist = length(cloudPos.xz);
   float rayUp = clamp(cloudPos.y / max(length(cloudPos), 0.001), 0.0, 1.0);
   float horizonMask = 1.0 - smoothstep(0.05, 0.28, rayUp);
   float cloudFogRange = clamp(max(fogEnd, far) * 6.0, 768.0, 2048.0);
   float effectiveRange = cloudFogRange * mix(1.0, 0.82, horizonMask);
   float normalizedDist = clamp(hDist / max(effectiveRange, 1.0), 0.0, 2.0);
   float opticalDepth = pow(normalizedDist, mix(1.85, 1.15, horizonMask))
                      * mix(0.85, 1.75, horizonMask);
   return 1.0 - exp(-opticalDepth);
}

float getRainCloudDissolve(float cloudFog) {
   return pow(max(1.0 - cloudFog, 0.0), 0.65);
}

float getRainCloudDitheredAlpha(float baseAlpha, float cloudFog) {
   float dissolve = getRainCloudDissolve(cloudFog);
   float edgeNoise = (bayer4(gl_FragCoord.xy * 0.5) - 0.5) * 0.18;
   float edgeBlend = smoothstep(0.22, 0.92, cloudFog);
   return baseAlpha * clamp(dissolve + edgeNoise * edgeBlend, 0.0, 1.0);
}

void main() {
   #if defined(THE_NETHER) || defined(THE_END) || defined(NETHER) || defined(END)
      discard;
   #elif ENHANCED_CLOUDS > 0
      discard;
   #else
      if (isEyeInWater != 0) {
         discard;
      }

      float baseAlpha = 0.8 * color.a;
      vec3 dryCloudRgb = mix(color.rgb, fogColor, 0.4);
      float dryCloudFog = clamp(fogMix, 0.0, 1.0);
      float dryCloudAlpha = mix(baseAlpha, 0.0, dryCloudFog);

      float rainAmtFog = max(rainStrength, rainFactor);
      float rainFade = smoothstep(0.01, 0.12, rainAmtFog);
      vec3 cloudRgb = dryCloudRgb;
      float cloudAlpha = dryCloudAlpha;

      if (rainFade > 0.0) {
         float cloudFog = getRainCloudDistanceFog(worldPos);
         vec3 rainFogTarget = getRainOvercastTarget();
         float faceLuma = max(luma(color.rgb), 0.001);
         vec3 faceTint = clamp(color.rgb / faceLuma, 0.0, 1.25);
         float rainBaseLuma = mix(faceLuma, luma(rainFogTarget), 0.24);
         vec3 flattenedCloudRgb = clamp(faceTint * rainBaseLuma, 0.0, 1.0);

         float rainReliefKill = rainAmtFog * smoothstep(0.24, 0.86, cloudFog);
         vec3 rainCloudRgb = mix(color.rgb, flattenedCloudRgb, rainReliefKill * 0.78);
         float rainFogMix = clamp(cloudFog * 0.58, 0.0, 1.0);
         rainCloudRgb = mix(rainCloudRgb, rainFogTarget, rainFogMix);

         cloudRgb = mix(dryCloudRgb, rainCloudRgb, rainFade);
         cloudAlpha = mix(dryCloudAlpha, getRainCloudDitheredAlpha(baseAlpha, cloudFog), rainFade);
      }

      vec4 cloudColor = vec4(cloudRgb, cloudAlpha);

      /* DRAWBUFFERS:03 */
      gl_FragData[0] = cloudColor;
      gl_FragData[1] = vec4(1.0, cloudColor.a, 0.0, 1.0);
   #endif
}
