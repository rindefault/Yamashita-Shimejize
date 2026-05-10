vec2 getFoliageWindUV(vec2 baseUV) {
   #if PIXEL_FOLIAGE_WIND <= 0
      return baseUV;
   #else
      if (foliageWindMask <= 0.5) return baseUV;

      float rawSkyExposure = clamp(float(eyeBrightness.y) / 240.0, 0.0, 1.0);
      float smoothSkyExposure = clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0);
      float windOutdoorMask = smoothstep(0.72, 0.93, mix(smoothSkyExposure, rawSkyExposure, 0.18));
      if (windOutdoorMask <= 0.01) return baseUV;

      ivec2 atlasSizeI = ivec2(int(max(float(atlasSize.x), 1.0)), int(max(float(atlasSize.y), 1.0)));
      vec2 atlasSizeF = vec2(float(atlasSizeI.x), float(atlasSizeI.y));
      vec2 atlasTexel = 1.0 / atlasSizeF;
      vec2 safeUV = clamp(baseUV, atlasTexel * 0.5, vec2(1.0) - atlasTexel * 0.5);

      float windPixelScale = max(1.0, float(FOLIAGE_WIND_RES) * 0.125);
      vec2 coarseCoord = floor((safeUV * atlasSizeF) / windPixelScale);

      float t = frameTimeCounter * 0.84;
      float rowWave = sin(coarseCoord.y * 0.16 + t);
      float colWave = sin(coarseCoord.x * 0.14 - t * 0.82);
      float swirl = sin((coarseCoord.x + coarseCoord.y) * 0.09 + t * 0.55);

      float qx = floor((rowWave * 0.75 + swirl * 0.25) * windOutdoorMask * 1.8 + 0.5);
      float qy = floor((colWave * 0.75 - swirl * 0.25) * windOutdoorMask * 1.8 + 0.5);

      ivec2 shiftDir = ivec2(
         int(sign(qx) * step(1.0, abs(qx))),
         int(sign(qy) * step(1.0, abs(qy)))
      );

      ivec2 baseTexel = ivec2(floor(safeUV * atlasSizeF));

      const int windTile = FOLIAGE_WIND_RES;
      int localX = int(mod(float(baseTexel.x), float(windTile)));
      int localY = int(mod(float(baseTexel.y), float(windTile)));
      if ((shiftDir.x > 0 && localX >= windTile - 1) || (shiftDir.x < 0 && localX <= 0)) shiftDir.x = 0;
      if ((shiftDir.y > 0 && localY >= windTile - 1) || (shiftDir.y < 0 && localY <= 0)) shiftDir.y = 0;

      ivec2 shiftedTexel = baseTexel + shiftDir;
      shiftedTexel.x = clamp(shiftedTexel.x, 0, atlasSizeI.x - 1);
      shiftedTexel.y = clamp(shiftedTexel.y, 0, atlasSizeI.y - 1);

      return (vec2(float(shiftedTexel.x), float(shiftedTexel.y)) + 0.5) * atlasTexel;
   #endif
}
