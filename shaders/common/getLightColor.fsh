float vsBrightness = clamp(screenBrightness, 0.0, 1.0);
float SdotU = dot(sunVec, upVec);
float sunVisibility = clamp(SdotU + 0.0625, 0.0, 0.125) / 0.125;
float sunVisibility2 = sunVisibility * sunVisibility;

float shadowTimeVar1 = abs(sunVisibility - 0.5) * 1.9;
float shadowTimeVar2 = shadowTimeVar1 * shadowTimeVar1;
float shadowTime = shadowTimeVar2 * shadowTimeVar2;

vec3 lightVec = sunVec * ((timeAngle < 0.5325 || timeAngle > 0.9675) ? 1.0 : -1.0);

#include "/common/pass_classes.glsl"

#if defined OVERWORLD
  #ifndef COMPOSITE
      vec3 noonClearLightColor = vec3(0.7, 0.55, 0.4) * 1.9; //ground and cloud color
  #else
      vec3 noonClearLightColor = vec3(0.4, 0.7, 1.4); //light shaft color
  #endif
  vec3 noonClearAmbientColor = pow(skyColor, vec3(0.65)) * 0.85;

  #ifndef COMPOSITE
      vec3 sunsetClearLightColor = pow(vec3(0.64, 0.45, 0.3), vec3(1.5 + invNoonFactor)) * 5.0; //ground and cloud color
  #else
      vec3 sunsetClearLightColor = pow(vec3(0.62, 0.39, 0.24), vec3(1.5 + invNoonFactor)) * 6.8; //light shaft color
  #endif
  vec3 sunsetClearAmbientColor   = noonClearAmbientColor * vec3(1.21, 0.92, 0.76) * 0.95;

  #if !defined COMPOSITE && !defined DEFERRED1
      vec3 nightClearLightColor = vec3(0.15, 0.14, 0.20) * (0.4 + vsBrightness * 0.4); //ground color
  #elif defined DEFERRED1
      vec3 nightClearLightColor = vec3(0.11, 0.14, 0.20); //cloud color
  #else
      vec3 nightClearLightColor = vec3(0.07, 0.12, 0.27); //light shaft color
  #endif
  vec3 nightClearAmbientColor   = vec3(0.09, 0.12, 0.17) * (1.55 + vsBrightness * 0.77);

  #ifdef SPECIAL_BIOME_WEATHER
    vec3 drlcSnowM = inSnowy * vec3(-0.06, 0.0, 0.04);
    vec3 drlcDryM = inDry * vec3(0.0, -0.03, -0.05);
  #else
    vec3 drlcSnowM = vec3(0.0), drlcDryM = vec3(0.0);
  #endif
  #if RAIN_STYLE == 2
    vec3 drlcRainMP = vec3(-0.03, 0.0, 0.02);
    #ifdef SPECIAL_BIOME_WEATHER
      vec3 drlcRainM = inRainy * drlcRainMP;
    #else
      vec3 drlcRainM = drlcRainMP;
    #endif
  #else
    vec3 drlcRainM = vec3(0.0);
  #endif

  vec3 dayRainLightColor   = vec3(0.21, 0.16, 0.13) * 0.85 + noonFactor * vec3(0.0, 0.02, 0.06)
                          + rainFactor * (drlcRainM + drlcSnowM + drlcDryM);
  vec3 dayRainAmbientColor = vec3(0.2, 0.2, 0.25) * (1.8 + 0.5 * vsBrightness);

  vec3 nightRainLightColor   = vec3(0.03, 0.035, 0.05) * (0.5 + 0.5 * vsBrightness);
  vec3 nightRainAmbientColor = vec3(0.16, 0.20, 0.3) * (0.75 + 0.6 * vsBrightness);

  #ifndef COMPOSITE
    float noonFactorDM = noonFactor; //ground and cloud factor
  #else
    float noonFactorDM = noonFactor * noonFactor; //light shaft factor
  #endif
  vec3 dayLightColor   = mix(sunsetClearLightColor, noonClearLightColor, noonFactorDM);
  vec3 dayAmbientColor = mix(sunsetClearAmbientColor, noonClearAmbientColor, noonFactorDM);

  vec3 clearLightColor   = mix(nightClearLightColor, dayLightColor, sunVisibility2);
  vec3 clearAmbientColor = mix(nightClearAmbientColor, dayAmbientColor, sunVisibility2);

  vec3 rainLightColor   = mix(nightRainLightColor, dayRainLightColor, sunVisibility2) * 2.5;
  vec3 rainAmbientColor = mix(nightRainAmbientColor, dayRainAmbientColor, sunVisibility2);

  vec3 lightColor   = mix(clearLightColor, rainLightColor, rainFactor);
  vec3 ambientColor = mix(clearAmbientColor, rainAmbientColor, rainFactor);

  // Lightning
  void doLighting(inout vec4 color, inout vec3 shadowMult, vec3 normalM,
				vec3 worldGeoNormal, vec2 lightmap) {

    vec3 lightColorM = lightColor;
    // Shadows
    #if defined OVERWORLD || defined END
      float NdotL = dot(normalM, lightVec);
      #ifdef GBUFFERS_WATER
        NdotL = mix(NdotL, 1.0, 1.0 - color.a);
      #endif
      float NdotLmax0 = max0(NdotL);
      float NdotLM = NdotLmax0 * 0.9999;

      #ifdef GBUFFERS_TEXTURED
        NdotLM = 1.0;
      #else
          float horizonPhase = 1.0 - smoothstep(0.15, 0.65, abs(SdotU));
          float twilightBoost = horizonPhase
                              * smoothstep(0.08, 0.98, sunVisibility)
                              * (1.0 - 0.50 * rainFactor);
          float sideFaceStrength = mix(0.68, 2.10, twilightBoost);
          NdotLM = max0(NdotL + 0.2) * sideFaceStrength;
          #ifdef END
            NdotLM = sqrt3(NdotLM);
          #endif

      #endif
      // Dynamic entities/items: keep directional term stable in core profile.
      if (isTexturedPass(passType)) {
        NdotLM = 1.0;
      }
        shadowMult *= max(NdotLM * shadowTime, 0.7);
    #endif

    // Scene lighting with subtle warm/cool split on side faces.
    vec3 sceneLighting = lightColorM * shadowMult;
    if (!isTexturedPass(passType)) {
      vec2 lightXZ = lightVec.xz;
      vec2 geoXZ = worldGeoNormal.xz;
      float lightXZLen2 = dot(lightXZ, lightXZ);
      float geoXZLen2 = dot(geoXZ, geoXZ);
      if (lightXZLen2 > 0.000001 && geoXZLen2 > 0.000001) {
      vec2 nXZ = geoXZ * inversesqrt(geoXZLen2);
      vec2 lXZ = lightXZ * inversesqrt(lightXZLen2);
      float sideMask = clamp(1.0 - abs(worldGeoNormal.y), 0.0, 1.0);
      float styleMask = sideMask * smoothstep(0.08, 0.98, sunVisibility) * (1.0 - 0.50 * rainFactor);
      float towardSun = max(dot(nXZ, lXZ), 0.0);
      float awaySun = max(dot(nXZ, -lXZ), 0.0);
      vec3 warmTint = vec3(1.18, 1.05, 0.90);
      vec3 coolTint = vec3(0.90, 0.98, 1.10);
      vec3 tint = mix(vec3(1.0), warmTint, 0.45 * styleMask * towardSun);
      tint = mix(tint, coolTint, 0.28 * styleMask * awaySun);
      sceneLighting *= tint;
      }
    }

    // Mix Colors
    vec3 finalDiffuse = abs(sceneLighting);

    // Apply Lighting
    color.rgb = color.rgb * finalDiffuse;
    float darkMul = pow2(1.0 - darknessLightFactor);
    color.rgb *= darkMul;

  }

#else
  // Fallback for dimensions that do not use the full Overworld light model.
  // Keeps compilation valid for Nether/End and preserves readable contrast.
  void doLighting(inout vec4 color, inout vec3 shadowMult, vec3 normalM,
				vec3 worldGeoNormal, vec2 lightmap) {
    float lmBlock = clamp(lightmap.x, 0.0, 1.0);
    float lmSky = clamp(lightmap.y, 0.0, 1.0);
    float lm = max(lmBlock, lmSky);
    float baseAmbient = mix(0.38, 1.0, lm);
    float darkMul = pow2(1.0 - darknessLightFactor);
    color.rgb *= baseAmbient * darkMul;
  }
#endif
