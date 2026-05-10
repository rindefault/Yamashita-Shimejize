#version 120

#include "shader.h"

uniform sampler2D colortex0;
uniform sampler2D colortex1; // pre-extracted bloom source from composite2
uniform sampler2D colortex2;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform float viewWidth, viewHeight;
uniform float near, far;

varying vec2 texcoord;
varying float twinkleFactor;
#include "/common/math.glsl"
#include "/common/depth_utils.glsl"
#include "/common/effect_metadata.glsl"

float getBloomWeight(int i) {
    if (i == 0) return 0.10855;
    if (i == 1) return 0.13135;
    if (i == 2) return 0.10406;
    if (i == 3) return 0.07216;
    if (i == 4) return 0.04380;
    if (i == 5) return 0.02328;
    if (i == 6) return 0.01083;
    if (i == 7) return 0.00441;
    return 0.00157;
}

float getHandMask(vec2 uv) {
    return getDepthHandMask(depthtex1, uv);
}

float getForegroundHandMask(vec2 uv) {
    return sampleEffectHandMask(colortex2, uv);
}

float getBloomDepthWeight(float centerDepth, float centerLinearDepth, vec2 sampleCoord) {
    if (centerDepth >= 0.9999) return 1.0;

    float sampleDepth = texture2D(depthtex0, sampleCoord).r;
    if (sampleDepth >= 0.9999) return 0.0;

    float sampleLinearDepth = linearizeDepthValue(sampleDepth, near, far);
    float depthTolerance = mix(1.6, 14.0, smoothstep(10.0, 96.0, centerLinearDepth));
    return 1.0 - smoothstep(depthTolerance, depthTolerance * 2.4, abs(sampleLinearDepth - centerLinearDepth));
}

vec3 extractBloomTap(vec2 sampleCoord, float centerDepth, float centerLinearDepth) {
    float depthWeight = getBloomDepthWeight(centerDepth, centerLinearDepth, sampleCoord);
    if (depthWeight <= 0.0) return vec3(0.0);
    return texture2D(colortex1, sampleCoord).rgb * depthWeight;
}

vec3 applyBlur(vec2 coord, vec2 direction) {
    float centerDepth = texture2D(depthtex0, coord).r;
    float centerLinearDepth = centerDepth < 0.9999 ? linearizeDepthValue(centerDepth, near, far) : 0.0;
    vec2 texelSize = 1.0 / vec2(viewWidth, viewHeight);
    vec2 sampleStep = direction * texelSize;
    vec3 result = vec3(0.0);

    result += extractBloomTap(coord, centerDepth, centerLinearDepth) * getBloomWeight(0);
    for (int i = 1; i < 9; ++i) {
        float fi = float(i);
        vec2 off = sampleStep * fi;
        float weight = getBloomWeight(i);
        result += extractBloomTap(coord + off, centerDepth, centerLinearDepth) * weight;
        result += extractBloomTap(coord - off, centerDepth, centerLinearDepth) * weight;
    }

    // Reduced from 3.0 to 2.0 вЂ” prevents overly aggressive bloom accumulation
    // across large uniform surfaces (wide desert, plain biomes).
    return result * 2.0;
}

void main() {
    vec3 color = texture2D(colortex0, texcoord).rgb;

    #if ENABLE_BLOOM > 0
      if (max(getHandMask(texcoord), getForegroundHandMask(texcoord)) < 0.5) {

        vec3 bloom = vec3(0.0);
        
        // Apply blur passes
        bloom += applyBlur(texcoord, vec2(4.0, 4.0));
        bloom += applyBlur(texcoord, vec2(4.0, -4.0));
        
        // Apply dithering
        float dither = bayer4(gl_FragCoord.xy / 2.0);
        bloom = floor(bloom * 2.0 + dither) / 2.0;
        
        // Apply stepped twinkle
        bloom *= twinkleFactor;
        
        color += bloom;
      }

    #endif
    
    gl_FragColor = vec4(color, 1.0);
    /*DRAWBUFFERS:0*/
}

