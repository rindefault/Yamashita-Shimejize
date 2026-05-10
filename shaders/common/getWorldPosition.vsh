vec3 getWorldPosition() {
#ifdef IS_TERRAIN
   #ifdef YS_LEGACY_VERTEX_PATH
   return (gbufferModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz;
   #else
   return mat3(gbufferModelViewInverse)
        * (gbufferModelView * vec4(vaPosition.xyz + chunkOffset, 1.0)).xyz
        + gbufferModelViewInverse[3].xyz;
   #endif
#elif defined(IS_GBUFFERS_TEXTURED) || defined(YS_LEGACY_VERTEX_PATH)
   return (gbufferModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz;
#else
   return mat3(gbufferModelViewInverse)
        * (modelViewMatrix * vec4(vaPosition.xyz, 1.0)).xyz
        + gbufferModelViewInverse[3].xyz;
#endif
}
