#include "/common/getShadowDistortion.glsl"
#include "/common/pass_classes.glsl"

vec3 getShadowLookupPos(vec3 pos, float pixelScale) {
   if (pixelScale > 0.0) {
      vec3 shadowPos = pos + cameraPosition;
      shadowPos = shadowPos * pixelScale;
      shadowPos = floor(shadowPos + 0.01) + 0.5;
      return shadowPos / pixelScale - cameraPosition;
   }

   return pos;
}

float getShadowVisibilityAtLookupPos(vec3 shadowPos) {
   float posDistance = squaredLength(shadowPos);
   vec4 shadowView = shadowModelView * vec4(shadowPos, 1.0);
   vec4 shadowClip = shadowProjection * shadowView;

   shadowClip.xyz = getShadowDistortion(shadowClip.xyz);

   vec3 shadowUV = nvec3(shadowClip) * 0.5 + 0.5;

   if (posDistance < SHADOW_MAX_DIST_SQUARED &&
      shadowUV.z < 1.0 &&
      shadowUV.s > 0.0 && shadowUV.s < 1.0 &&
      shadowUV.t > 0.0 && shadowUV.t < 1.0)
   {
      float shadowFade = 1.0 - posDistance * INV_SHADOW_MAX_DIST_SQUARED;
#if __VERSION__ < 130
      float shadowDepth = texture2D(shadowtex1, shadowUV.st).x;
#else
      float shadowDepth = texture(shadowtex1, shadowUV.st).x;
#endif

      return 1.0 - shadowFade * clamp(3.0 * (shadowDepth - shadowUV.z) / shadowProjection[2].z, 0.0, 1.0);
   }

   return 1.0;
}

float getShadowVisibilityAt(vec3 pos) {
   #if SHADOW_PIXEL > 0
      return getShadowVisibilityAtLookupPos(getShadowLookupPos(pos, float(SHADOW_PIXEL)));
   #else
      return getShadowVisibilityAtLookupPos(pos);
   #endif
}

float getSunStrength() {
   if (isTexturedPass(passType)) {
      return diffuse;
   }

   float shadowVisibility = getShadowVisibilityAt(worldPos);
   return diffuse * shadowVisibility;
}
