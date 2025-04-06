#version 330 compatibility

#include "shader.h"
#include "common/math.glsl"

uniform vec2 viewSize;
uniform sampler2D colortex0;

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
  vec4 texColor = texture(colortex0, texcoord);

  float distortStrength = 0.01;
  
  vec2 center = vec2(0.5, 0.5);
  float dist = distance(texcoord, center);

  // Enable 3d-anaglyph
  #if ENABLE_ANAGLYPH > 0

    // Adjust strength based on distance
    float adjustedStrength = distortStrength * dist;

    // Anaglyph effect
    vec2 offset = vec2(adjustedStrength * 0.100, 0.0); // Adjust offset for separation

    vec4 leftColor = texture(colortex0, texcoord - offset);
    vec4 rightColor = texture(colortex0, texcoord + offset);

    texColor = vec4(rightColor.r, leftColor.g, leftColor.b, color.a);
    
  #endif

  color.rgb = (floor(texColor.rgb * POSTERIZE_STRENGTH) / POSTERIZE_STRENGTH);
}