float getDiffuse(float skyLight) {
#if defined(IS_GBUFFERS_TEXTURED) || defined(YS_LEGACY_VERTEX_PATH)
  vec3 shapeNormal = gl_Normal;
#else
  vec3 shapeNormal = vaNormal;
#endif
  bool isThin = mc_Entity.x == 10031.0 || mc_Entity.x == 10032.0
             || mc_Entity.x == 10059.0 || mc_Entity.x == 10060.0
             || mc_Entity.x == 10061.0
             || mc_Entity.x == 10175.0 || mc_Entity.x == 10176.0
             || (abs(shapeNormal.y) < 0.01 && abs(abs(shapeNormal.x) - abs(shapeNormal.z)) < 0.01);
  float directionalDiffuse = clamp(2.5 * dot(normalize(normal),
                                              normalize(shadowLightPosition)), -0.3333, 1.0);

        //  reduce under water
  return (isEyeInWater == 0 ? 1.0 : 0.5)
        //  reduce with fog
          * (1.0 - fogMix)
        //  reduce with rain strength
          * (1.0 - rainStrength)
        //  reduce with sky light
          * rescale(skyLight, 0.3137, 0.6235)
        //  thin objects keep constant diffuse
#ifdef IS_TERRAIN
          * (isThin ? 0.75 : directionalDiffuse);
#else
          * (isThin ? 0.75 : directionalDiffuse);
#endif
}
