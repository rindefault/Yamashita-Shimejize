#ifndef YS_RAIN_PARTICLE_SPLASH_GLSL
#define YS_RAIN_PARTICLE_SPLASH_GLSL

bool isLikelyParticleAtlas() {
#if __VERSION__ < 130
   #if defined(IS_GBUFFERS_TEXTURED) || defined(IS_GBUFFERS_TEXTURED_LIT)
      // GLSL 120 has no textureSize(), and the legacy textured path mixes
      // world border plus particle fallbacks through textured/textured_lit.
      // The actual rain/splash detection below is already a very narrow
      // blue-range check that matches the vanilla splash sprites, while
      // vanilla forcefield.png is grayscale, so let the per-pixel tests do
      // the filtering here.
      return true;
   #else
      return false;
   #endif
#else
   #if MC_VERSION >= 12000
      const float atlasCheck = 1100.0;
   #else
      const float atlasCheck = 900.0;
   #endif
   ivec2 atlasSize = ivec2(textureSize(texture, 0));
   return float(atlasSize.x) < atlasCheck;
#endif
}

float getWaterSplashLikeParticleMask(vec3 particleColor, float particleAlpha) {
   if (!isLikelyParticleAtlas()) return 0.0;

   vec3 c = clamp(particleColor, 0.0, 1.0);

   return
      step(1.15 * (c.r + c.g), c.b) *
      step(c.r * 1.25, c.g) *
      (1.0 - step(0.425, c.g)) *
      step(0.75, c.b) *
      smoothstep(0.02, 0.95, particleAlpha);
}

float getPhysicsRainLikeParticleMask(vec3 particleColor, float particleAlpha) {
   if (!isLikelyParticleAtlas()) return 0.0;

   vec3 c = clamp(particleColor, 0.0, 1.0);

   return
      step(0.70, c.b) *
      (1.0 - step(0.28, c.r)) *
      (1.0 - step(0.425, c.g)) *
      step(c.r * 1.40, c.g) *
      smoothstep(0.02, 0.95, particleAlpha);
}

vec3 getRainSplashParticleColor(float shade) {
   float splashGray = mix(0.12, 0.30, shade);
   return vec3(splashGray) * vec3(0.94, 0.98, 1.06);
}

float getVanillaRainSplashCoverage(float shade) {
   return clamp(mix(0.24, 0.62, WEATHER_OPACITY) * mix(0.90, 1.06, shade), 0.0, 0.92);
}

#endif
