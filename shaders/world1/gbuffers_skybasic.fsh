#version 120

#define THE_END

#define gbuffers_skybasic

uniform int isEyeInWater;
uniform vec3 fogColor;

varying vec4 color;

void main() {
   float fog = (isEyeInWater > 0)
             ? 1.0 - exp(-gl_FogFragCoord * gl_Fog.density)
             : clamp((gl_FogFragCoord - gl_Fog.start) * gl_Fog.scale, 0.0, 1.0);
   float endVeil = smoothstep(gl_Fog.end * 0.18, gl_Fog.end * 0.80, gl_FogFragCoord);
   fog = clamp(max(fog, endVeil * 0.82), 0.0, 1.0);

   // Keep the End fog curve, but bias the baseline much darker than the
   // Overworld-oriented post chain would normally leave it.
   vec3 endFog = max(fogColor * vec3(0.30, 0.22, 0.40), vec3(0.010, 0.004, 0.015));
   vec3 endSky = max(endFog * 0.10, vec3(0.003, 0.001, 0.005));

   gl_FragData[0] = vec4(mix(endSky, endFog, fog), color.a);
}
