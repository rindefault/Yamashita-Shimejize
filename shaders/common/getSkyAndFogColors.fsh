
float noonFactor        = pow(max(sin(timeAngle*6.28318530718),0.0), 0.2);
float nightFactor       = max(sin(timeAngle*(-6.28318530718)),0.0);
float invNightFactor    = 1.0 - nightFactor;
float rainFactor2       = rainFactor * rainFactor;
float invRainFactor     = 1.0 - rainFactor;
float invRainFactorSqrt = 1.0 - rainFactor * rainFactor;
float invNoonFactor     = 1.0 - noonFactor;
float invNoonFactor2    = invNoonFactor * invNoonFactor;

vec3 skyColorSqrt = sqrt(SKY_COLOR);

vec3 nmscSnowM = vec3(0.0), nmscDryM = vec3(0.0), ndscSnowM = vec3(0.0), ndscDryM = vec3(0.0);

vec3 nmscRainM = vec3(0.0), ndscRainM = vec3(0.0);

vec3 nmscWeatherM = vec3(-0.1, -0.4, -0.6) + vec3(0.0, 0.06, 0.12) * noonFactor;
vec3 ndscWeatherM = vec3(-0.15, -0.3, -0.42) + vec3(0.0, 0.02, 0.08) * noonFactor;

vec3 noonUpSkyColor     = pow(skyColorSqrt, vec3(1.6));
vec3 noonMiddleSkyColor = skyColorSqrt * (FOG_COLOR + rainFactor * (nmscWeatherM + nmscRainM + nmscSnowM + nmscDryM))
                        + noonUpSkyColor * 0.6;
vec3 noonDownSkyColor   = skyColorSqrt * (vec3(0.9) + rainFactor * (ndscWeatherM + ndscRainM + ndscSnowM + ndscDryM))
                        + noonUpSkyColor * 0.25;

vec3 sunsetUpSkyColor     = skyColor * (vec3(0.8, 0.58, 0.58) + vec3(0.1, 0.2, 0.35) * rainFactor2);
vec3 sunsetMiddleSkyColor = skyColor * (vec3(1.8, 1.3, 1.2) + vec3(0.15, 0.25, -0.05) * rainFactor2);
vec3 sunsetDownSkyColorP  = vec3(1.2, 0.5, 0.3) - vec3(0.8, 0.3, 0.0) * rainFactor;
vec3 sunsetDownSkyColor   = sunsetDownSkyColorP * 0.5 + 0.25 * sunsetMiddleSkyColor;

vec3 dayUpSkyColor     = mix(noonUpSkyColor, sunsetUpSkyColor, invNoonFactor2);
vec3 dayMiddleSkyColor = mix(noonMiddleSkyColor, sunsetMiddleSkyColor, invNoonFactor2);
vec3 dayDownSkyColor   = mix(noonDownSkyColor, sunsetDownSkyColor, invNoonFactor2);

vec3 nightColFactor      = vec3(0.18, 0.11, 0.09) * (1.0 - 0.5 * rainFactor) + skyColor;
vec3 nightUpSkyColor     = pow(nightColFactor, vec3(0.90)) * 0.4;
vec3 nightMiddleSkyColor = sqrt(nightUpSkyColor) * 0.68;
vec3 nightDownSkyColor   = nightMiddleSkyColor * vec3(0.82, 0.82, 0.88);

vec3 getSkyFromVectors(float VdotU, float VdotS, float dither, vec3 sunVecLocal, vec3 upVecLocal) {

    float SdotU = dot(sunVecLocal, upVecLocal);
    float sunFactor = SdotU < 0.0 ? clamp(SdotU + 0.375, 0.0, 0.75) / 0.75 : clamp(SdotU + 0.03125, 0.0, 0.0625) / 0.0625;
    float sunVisibility = clamp(SdotU + 0.0625, 0.0, 0.125) / 0.125;
    float sunVisibility2 = sunVisibility * sunVisibility;

    float nightFactorSqrt2 = sqrt2(nightFactor);
    float nightFactorM = sqrt2(nightFactorSqrt2) * 0.4;
    float VdotSM1 = pow2(max(VdotS, 0.0));
    float VdotSM2 = pow2(VdotSM1);
    float VdotSM3 = pow2(pow2(max(-VdotS, 0.0)));
    float VdotSML = sunVisibility > 0.5 ? VdotS : -VdotS;

    float VdotUmax0 = max(VdotU, 0.0);
    float VdotUmax0M = 1.0 - pow2(VdotUmax0);

    // Prepare colors
    vec3 upColor = mix(nightUpSkyColor * (1.5 - 0.5 * nightFactorSqrt2 + nightFactorM * VdotSM3 * 1.5), dayUpSkyColor, sunFactor);
    vec3 middleColor = mix(nightMiddleSkyColor * (3.0 - 2.0 * nightFactorSqrt2), dayMiddleSkyColor * (1.0 + VdotSM2 * 0.3), sunFactor);
    vec3 downColor = mix(nightDownSkyColor, dayDownSkyColor, (sunFactor + sunVisibility) * 0.5);

    // Mix the colors
    // Set sky gradient
    float VdotUM1 = pow2(1.0 - VdotUmax0);
          VdotUM1 = pow(VdotUM1, 1.0 - VdotSM2 * 0.4);
          VdotUM1 = mix(VdotUM1, 1.0, rainFactor2 * 0.15);
    vec3 finalSky = mix(upColor, middleColor, VdotUM1);

    // Add sunset color
    float VdotUM2 = pow2(1.0 - abs(VdotU));
          VdotUM2 = VdotUM2 * VdotUM2 * (3.0 - 2.0 * VdotUM2);
          VdotUM2 *= (0.7 - nightFactorM + VdotSM1 * (0.3 + nightFactorM)) * invNoonFactor * sunFactor;
    finalSky = mix(finalSky, sunsetDownSkyColorP * (1.0 + VdotSM1 * 0.3), VdotUM2 * invRainFactor);

    // Dither
    finalSky += dither / 24;

    return finalSky;
}

vec3 getSky(float VdotU, float VdotS, float dither) {
    return getSkyFromVectors(VdotU, VdotS, dither, sunVec, upVec);
}
