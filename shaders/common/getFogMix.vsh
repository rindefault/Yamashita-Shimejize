float getFogMix(vec3 worldPos) {
#if MC_VERSION >= 11300 && defined ENABLE_FOG
   float len = fogShape == 1 ? max(length(worldPos.xz), abs(worldPos.y)) : length(worldPos);

   #if defined gbuffers_clouds

      // Always use horizontal (XZ) distance for clouds.
      // The vertical offset to cloud level (~128 blocks above the player) makes
      // the 3D distance huge even for nearby clouds, causing them to be fully
      // fogged and creating a hard circular cutout at the edge of the fog band.
      // Keep the fade much farther out than normal terrain fog so vanilla clouds
      // dissolve softly instead of dying near the camera.
      float hLen = length(worldPos.xz);
      float posHeight = clamp(worldPos.y / max(length(worldPos), 0.001), 0.0, 1.0);
      float horizonMask = 1.0 - smoothstep(0.05, 0.28, posHeight);
      float cloudFogRange = clamp(max(far, 1.0) * 3.5, 640.0, 1920.0);
      float effectiveRange = cloudFogRange * mix(1.0, 0.84, horizonMask);
      float normalizedDist = clamp(hLen / max(effectiveRange, 1.0), 0.0, 2.0);
      float opticalDepth = pow(normalizedDist, mix(1.90, 1.20, horizonMask))
                         * mix(0.82, 1.45, horizonMask);
      return 1.0 - exp(-opticalDepth);

   #elif defined OVERWORLD

      // When the camera is inside water, lava, or powder snow, use the
      // medium-provided fog range directly. The custom far-plane fog logic
      // below is only meant for open-air overworld atmosphere and makes
      // submerged vision almost perfectly clear.
      if (isEyeInWater != 0) {
         return rescale(len, fogStart, fogEnd);
      }

      // Keep sliders independent:
      // - OVERWORLD_FOG_* (main fog): base fog wall distance
      // - TRANSITION_FOG (named OVERWORLD_FOG_MIN in this pack): persistent soft haze
      float baseFog = clamp(OVERWORLD_FOG_MAX, 0.0, 1.0);          // 0=foggy, 1=clear
      float transitionFog = clamp(1.0 - OVERWORLD_FOG_MIN, 0.0, 1.0); // 0=off, 1=max

      // Mild rain influence only, to avoid rain "white veil".
      baseFog = min(baseFog, 1.0 - rainStrength * 0.35);

      float farPlane = max(far, 1.0);

      // Main fog wall (controls chunk-edge masking strength).
      float fogBase = rescale(len, 0.9 * baseFog * farPlane, farPlane);

      // Always-on soft transition haze, similar to Miniature feel.
      float softBandStart = mix(0.92, 0.48, transitionFog) * farPlane;
      float transitionHaze = rescale(len, softBandStart, farPlane) * (0.06 + 0.42 * transitionFog);

      // Extra very soft long-distance veil to remove hard render boundary.
      float distanceHaze = (0.0008 + 0.0014 * transitionFog) * max(0.0, len - 96.0);
      distanceHaze *= mix(1.0, 0.90, rainStrength);

      // Extra fade right at render edge to fully hide chunk silhouettes.
      float edgeMask = smoothstep(0.90 * farPlane, farPlane, len);
      float edgeBoost = edgeMask * (0.22 + 0.22 * transitionFog);

      // Rain should hide far landscape more aggressively, but only at distance.
      float rainFarMask = smoothstep(0.55 * farPlane, farPlane, len);
      float rainBoost = rainStrength * rainFarMask * (0.12 + 0.16 * transitionFog);

      return min(1.0, fogBase + transitionHaze + distanceHaze + edgeBoost + rainBoost);

   #elif defined THE_END

      if (isEyeInWater != 0) {
         return rescale(len, fogStart, fogEnd);
      }

      float farPlane = max(far, 1.0);
      float vanillaFog = rescale(len, fogStart, fogEnd);

      // The End needs a persistent distance veil even when the runtime reports
      // a very weak fog range, otherwise the sky and terrain separate visually.
      float bodyFog = rescale(len, 0.26 * farPlane, 0.82 * farPlane) * 0.76;
      float haze = rescale(len, 0.12 * farPlane, 0.56 * farPlane) * 0.18;
      float edgeFog = smoothstep(0.78 * farPlane, farPlane, len) * 0.16;

      return min(1.0, max(vanillaFog, bodyFog + haze + edgeFog));

   #elif defined THE_NETHER

      return rescale(len, fogStart, fogEnd * (isEyeInWater == 0 ? NETHER_FOG : 1.0));

   #else

      return rescale(len, fogStart, fogEnd);

   #endif
#else

   return 0.0;

#endif
}
