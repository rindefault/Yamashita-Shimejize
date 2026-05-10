uniform vec3 cameraPosition;
uniform vec3 chunkOffset;

varying vec2 texUV;
varying float alpha;
varying float shadowVertY;

#include "/common/getShadowDistortion.glsl"

void main() {
   vec3 shadowPos = gl_Vertex.xyz + chunkOffset;
   gl_Position = gl_ProjectionMatrix * gl_ModelViewMatrix * vec4(shadowPos, 1.0);
   gl_Position.xyz = getShadowDistortion(gl_Position.xyz);

   texUV = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
   alpha = gl_Color.a;
   shadowVertY = shadowPos.y + cameraPosition.y;
}
