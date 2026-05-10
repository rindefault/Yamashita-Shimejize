vec3 getSubmergedFogColor(int eyeMedium, vec3 baseFogColor) {
   if (eyeMedium == 2) {
      // Some drivers/runtime paths feed an overly bright or neutral fogColor
      // while submerged in lava. Keep vanilla-provided warm fog when it exists,
      // but fall back to a stable lava tint when it does not.
      float baseLum = clamp(luma(baseFogColor), 0.0, 1.0);
      float warmMask =
         smoothstep(0.14, 0.92, baseFogColor.r - baseFogColor.b) *
         smoothstep(0.04, 0.70, baseFogColor.g) *
         smoothstep(0.02, 0.85, baseLum);

      vec3 lavaFog = mix(vec3(0.82, 0.20, 0.02), vec3(1.00, 0.42, 0.08), 0.52 + 0.24 * baseLum);
      return mix(lavaFog, baseFogColor, warmMask);
   }

   if (eyeMedium == 3) {
      return mix(baseFogColor, vec3(0.90, 0.94, 0.98), 0.08);
   }

   return baseFogColor;
}
