float getWaterTextureStrength(float random) {
#if defined(IS_GBUFFERS_TEXTURED) || defined(YS_LEGACY_VERTEX_PATH)
	vec3 shapeNormal = gl_Normal;
#else
	vec3 shapeNormal = vaNormal;
#endif
	// if the water is moving show all texture
	return !(abs(shapeNormal.x) < 0.01 && abs(shapeNormal.z) < 0.01) ? 1.0
		#if WATER_MIN_TEXTURE >= 0

			: 2.0*max(random - 0.5, 0.05*WATER_MIN_TEXTURE);

		#else

			: 0.0;

		#endif
}
