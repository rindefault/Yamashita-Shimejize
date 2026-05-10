#define gbuffers_skybasic

#include "/shader.h"

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

uniform float timeAngle;

uniform int renderStage;

varying float alpha;
varying vec4 glColor;
varying vec3 upVec;
varying vec3 sunVec;
varying vec2 texUV;

#ifndef MC_RENDER_STAGE_MOON
#define MC_RENDER_STAGE_MOON 1
#endif

void main() {
   vec3 position = (gl_ModelViewMatrix * gl_Vertex).xyz;
   position = (gbufferModelViewInverse * vec4(position, 1.0)).xyz;
   gl_Position = gl_ProjectionMatrix * gbufferModelView * vec4(position, 1.0);

   texUV = gl_MultiTexCoord0.xy;

   const vec2 sunRotationData = vec2(cos(sunPathRotation * 0.01745329251994), -sin(sunPathRotation * 0.01745329251994));
   float ang = fract(timeAngle - 0.25);
   ang = (ang + (cos(ang * 3.14159265358979) * -0.5 + 0.5 - ang) / 3.0) * 6.28318530717959;

   sunVec = normalize((gbufferModelView * vec4(vec3(-sin(ang), cos(ang) * sunRotationData) * 2000.0, 1.0)).xyz);
   upVec = normalize(gbufferModelView[1].xyz);

   glColor = gl_Color;

   alpha = 1.0;

   #if MC_VERSION >= 11605
      if (renderStage == MC_RENDER_STAGE_STARS) {
         alpha = 0.0;
      }
      #else
      if (gl_Color.r == gl_Color.g && gl_Color.g == gl_Color.b && gl_Color.r > 0.0) {
         alpha = 0.0;
      }
	#endif

   // Keep legacy sunset-gradient suppression disabled in core migration path.
   // On some Iris versions/stages this condition can match sun/moon passes and
   // hide the sun disk entirely.
}
