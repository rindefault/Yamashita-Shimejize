#define gbuffers_weather

#include "/shader.h"

uniform sampler2D texture;
uniform float timeBrightness;

varying vec2 texUV;
varying vec2 lightUV;
varying vec4 color;

void main() {
   vec4 albedo = texture2D(texture, texUV) * color;

   // Neutral gray rain that follows actual scene brightness:
   // dark in shadow/night, lighter in torch/day light.
   float day = clamp(timeBrightness, 0.0, 1.0);
   float lum = dot(albedo.rgb, vec3(0.299, 0.587, 0.114));
   // Local block light (torches etc.) from lightmap coords.
   float blockL = clamp(lightUV.s * 1.18, 0.0, 1.0);
   float skyL = clamp(lightUV.t, 0.0, 1.0);
   float lightInfluence = max(lum, max(blockL, day * skyL));
   float shade = smoothstep(0.06, 0.88, lightInfluence);
   shade = shade * shade * (3.0 - 2.0 * shade);
   float grayLevel = mix(0.18, 0.50, shade);
   // Saturation must be zero: force fully neutral grayscale.
   albedo.rgb = vec3(grayLevel);
   // Minimal floor to keep streaks visible, but stay dark at night.
   albedo.rgb = max(albedo.rgb, vec3(0.05) * albedo.a);

   // Keep streaks translucent at all times and avoid opaque "blue bars".
   albedo.a *= WEATHER_OPACITY;
   albedo.a *= mix(0.88, 1.0, day);

   gl_FragColor = albedo;
}
