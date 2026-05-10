uniform ivec2 atlasSize;

vec2 screen2uv(vec3 screen) {
   return (0.5*nvec3(gbufferProjection * vec4(screen, 1.0)) + 0.5).st;
}

vec3 screen2space(vec2 coord, float depth) {
	vec4 pos = gbufferProjectionInverse * (vec4(coord, depth, 1.0) * 2.0 - 1.0);
	return pos.xyz/pos.w;
}

float cdist(vec2 coord) {
	return clamp(1.0 - max(abs(coord.s-0.5),abs(coord.t-0.5))*2.0, 0.0, 1.0);
}

vec2 ComputeTexelOffset(vec2 uv, vec4 texelSize) {
   // 1. Calculate how much the texture UV coords need to shift to be at the center of the nearest texel.
   vec2 uvCenter = (floor(uv * texelSize.zw) + 0.5) * texelSize.xy;
   vec2 dUV = uvCenter - uv;

   // 2. Calculate how much the texture coords vary over fragment space.
   //     This essentially defines a 2x2 matrix that gets texture space (UV) deltas from fragment space (ST) deltas.
   vec2 dUVdS = dFdx(uv);
   vec2 dUVdT = dFdy(uv);

   if (abs(dUVdS) + abs(dUVdT) == vec2(0.0)) return vec2(0.0);

   // 3. Invert the texture delta from fragment delta matrix. Where the magic happens.
   mat2x2 dSTdUV = mat2x2(dUVdT[1], -dUVdT[0], -dUVdS[1], dUVdS[0]) * (1.0 / (dUVdS[0] * dUVdT[1] - dUVdT[0] * dUVdS[1]));

   // 4. Convert the texture delta to fragment delta.
   vec2 dST = dUV * dSTdUV;
   return dST;
}

vec2 ComputeTexelOffset(sampler2D tex, vec2 uv) {
#if __VERSION__ < 130
   vec2 texSize = vec2(max(atlasSize, ivec2(1)));
   if (texSize.x <= 1.0 || texSize.y <= 1.0) return vec2(0.0);
   vec4 texelSize = vec4(1.0 / texSize.xy, texSize.xy);
   return ComputeTexelOffset(uv, texelSize);
#else
   vec2 texSize = vec2(ivec2(textureSize(tex, 0)));
   vec4 texelSize = vec4(1.0 / texSize.xy, texSize.xy);

   return ComputeTexelOffset(uv, texelSize);
#endif
}

vec4 TexelSnap(vec4 value, vec2 texelOffset) {
   if (texelOffset == vec2(0.0)) return value;
   vec4 dx = dFdx(value);
   vec4 dy = dFdy(value);

   vec4 valueOffset = dx * texelOffset.x + dy * texelOffset.y;
   valueOffset = clamp(valueOffset, -1.0, 1.0);

   return value + valueOffset;
}

vec3 TexelSnap(vec3 value, vec2 texelOffset) {
   if (texelOffset == vec2(0.0)) return value;
   vec3 dx = dFdx(value);
   vec3 dy = dFdy(value);

   vec3 valueOffset = dx * texelOffset.x + dy * texelOffset.y;
   valueOffset = clamp(valueOffset, -1.0, 1.0);

   return value + valueOffset;
}

vec2 TexelSnap(vec2 value, vec2 texelOffset) {
   if (texelOffset == vec2(0.0)) return value;
   vec2 dx = dFdx(value);
   vec2 dy = dFdy(value);

   vec2 valueOffset = dx * texelOffset.x + dy * texelOffset.y;
   valueOffset = clamp(valueOffset, -1.0, 1.0);

   return value + valueOffset;
}

float TexelSnap(float value, vec2 texelOffset) {
   if (texelOffset == vec2(0.0)) return value;
   float dx = dFdx(value);
   float dy = dFdy(value);

   float valueOffset = dx * texelOffset.x + dy * texelOffset.y;
   valueOffset = clamp(valueOffset, -1.0, 1.0);

   return value + valueOffset;
}

vec3 view2player(vec3 pos) {
   return mat3(gbufferModelViewInverse) * pos + gbufferModelViewInverse[3].xyz;
}

vec3 screen2view(vec3 pos) {
   vec4 iProjDiag = vec4(gbufferProjectionInverse[0].x,
                         gbufferProjectionInverse[1].y,
                         gbufferProjectionInverse[2].zw);
   vec3 p3 = pos * 2.0 - 1.0;
   vec4 viewPos = iProjDiag * p3.xyzz + gbufferProjectionInverse[3];
   return viewPos.xyz / viewPos.w;
}

vec3 uv2screen(vec2 uv, float depth) {
   return nvec3(gbufferProjectionInverse * vec4(2.0*vec3(uv, depth) - 1.0, 1.0));
}

vec3 world2screen(vec3 world) {
   return mat3(gbufferModelView) * world;
}
