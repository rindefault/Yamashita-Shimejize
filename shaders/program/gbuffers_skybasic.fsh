#define gbuffers_skybasic

uniform int isEyeInWater;
uniform vec3 fogColor;

varying vec4 color;

#include "/common/math.glsl"

void main() {
    float fog = (isEyeInWater > 0)
                ? 1.0 - exp(-gl_FogFragCoord * gl_Fog.density)
                : clamp((gl_FogFragCoord - gl_Fog.start) * gl_Fog.scale, 0.0, 1.0);

    vec4 finalColor = mix(color, vec4(fogColor, color.a), fog);

    gl_FragData[0] = finalColor;
    gl_FragData[1] = vec4(0.0);
}