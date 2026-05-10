#define gbuffers_weather

varying vec2 texUV;
varying vec2 lightUV;
varying vec4 color;
varying float weatherDistXZ;
varying float weatherRelativeY;

uniform mat4 gbufferModelViewInverse;

void main() {
   gl_Position = ftransform();

   color = gl_Color;
   texUV = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
   lightUV = (gl_TextureMatrix[1] * gl_MultiTexCoord1).st;
   vec3 viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
   vec3 cameraPos = gbufferModelViewInverse[3].xyz;
   vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos + cameraPos;
   weatherDistXZ = length(worldPos.xz - cameraPos.xz);
   weatherRelativeY = worldPos.y - cameraPos.y;
}
