// Colors
vec3 auroraLowCol = vec3(7.0, 2.1, 8.0);
vec3 auroraHighCol = vec3(8.0, 12.0, 6.0);

vec4 sampleAuroraNoiseTex(vec2 uv) {
  #if __VERSION__ < 130
    return texture2D(noisetex, uv);
  #else
    return texture(noisetex, uv);
  #endif
}

float isNightTime() {
  float nightDuration = 23000.0 - 11000.0;
  float t = clamp((time - 11000.0) / nightDuration, 0.0, 1.0);
  
  // Bell curve peaking at 0.4 when t=0.3 (16000)
  return 0.8 * sin(t * 3.14159) * 1.1; // 1.1 scales peak to exactly 0.4
}

// Every ten days if it's cold and blah
float visibility = isNightTime() * isCold * ((mod(worldDay, 8.0) == 0.0) ? 1.0 : 0.0);

vec3 getAurora(vec3 viewPos, float dither) {

  // Get view pos height
  float posHeight = dot(normalize(viewPos), upVec);

  if (posHeight > 0.0 && visibility > 0) {

      vec3 aurora = vec3(0.0);

      // World pos position
      vec3 wpos = mat3(gbufferModelViewInverse) * viewPos;
           wpos.xz /= wpos.y;

      vec2 cameraPositionM = cameraPosition.xz * 0.075;

      int sampleCount = 10;
      int sampleCountP = sampleCount + 2;

      float ditherM = dither + 1.0;
      float auroraAnimate = frameTimeCounter * 0.001;
      
      for (int i = 0; i < sampleCount; i++) {
        float current = pow2((i + ditherM) / sampleCountP);

        vec2 planePos = wpos.xz * (1.2 + current) * 11.0 + cameraPositionM;
        planePos = floor(planePos) * 0.0007;

        float noise = sampleAuroraNoiseTex(planePos).b;
              noise = pow2(pow2(pow2(pow2(1.0 - 2.0 * abs(noise - 0.5)))));

        noise *= pow1_5(sampleAuroraNoiseTex(planePos * 100.0 + auroraAnimate).b);

        float currentM = 1.0 - current;
        aurora += noise * currentM * mix(auroraLowCol, auroraHighCol, pow2(currentM));
      }

      aurora *= 0.8;

      // Atmospheric perspective: fade aurora near the horizon.
      // At low elevation (posHeight ≈ 0), the plane projection makes wpos.xz
      // enormous → ultra-high frequency noise → visual chaos ("soup").
      // Smoothstep from 0 at horizon to 1 at ~20° elevation eliminates this.
      float horizonFade = smoothstep(0.02, 0.20, posHeight);

      return aurora * visibility / sampleCount * horizonFade;
  }

  else return vec3(0.0);
}

float getNoise(vec2 pos) {
	return fract(sin(dot(pos, vec2(12.9898, 4.1414))) * 43758.5453);
}

vec3 getStars(vec3 viewPos) {
	vec3 wpos = vec3(gbufferModelViewInverse * vec4(viewPos * 100.0, 1.0));
	vec3 planeCoord = wpos / (wpos.y + length(wpos.xz));
	vec2 wind = vec2(frameTimeCounter, 0.0);
	vec2 coord = planeCoord.xz * 0.4 + cameraPosition.xz * 0.0001 + wind * 0.00125;
	coord = floor(coord * 1024.0) / 1024.0;
	
	float VoU = clamp(dot(normalize(viewPos), upVec), 0.0, 1.0);
	float multiplier = sqrt(sqrt(VoU)) * 5.0 * (1.0 - rainStrength) * 1.0;
	
	float star = 1.0;
  
	if (VoU > 0.0) {
		star *= getNoise(coord.xy);
		star *= getNoise(coord.xy + 0.10);
		star *= getNoise(coord.xy + 0.23);
	}
	star = clamp(star - 0.7825, 0.0, 1.0) * multiplier;
  vec3 finalStars = star * pow(vec3(1.5, 1.3, 1.0), vec3(2.3));// * isNightTime();
  
  // Blur
	return finalStars * isNightTime();
}
