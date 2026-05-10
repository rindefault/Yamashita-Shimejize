#define gbuffers_line

uniform float viewWidth, viewHeight;

varying vec2 texUV;
varying vec4 glColor;

void main() {
    const float VIEW_SHRINK = 1.0 - (1.0 / 256.0);
    const float LINE_WIDTH  = 3.0;

    vec2 resolution = vec2(viewWidth, viewHeight);

    vec4 startView = gl_ModelViewMatrix * gl_Vertex;
    vec4 endView   = gl_ModelViewMatrix * vec4(gl_Vertex.xyz + gl_Normal.xyz, 1.0);

    vec4 startClip = gl_ProjectionMatrix * vec4(VIEW_SHRINK * startView.xyz, startView.w);
    vec4 endClip   = gl_ProjectionMatrix * vec4(VIEW_SHRINK * endView.xyz,   endView.w);

    vec2 clipDelta  = (endClip.xy / endClip.w - startClip.xy / startClip.w) * resolution;
    float deltaLen  = length(clipDelta);
    vec2 lineDir    = (deltaLen > 0.0) ? (clipDelta / deltaLen) : vec2(1.0, 0.0);
    vec2 lineOffset = vec2(-lineDir.y, lineDir.x) * LINE_WIDTH / resolution;

    if (lineOffset.x < 0.0) lineOffset *= -1.0;
    gl_Position = startClip;
    gl_Position.xy += ((gl_VertexID % 2 == 0) ? lineOffset : -lineOffset) * startClip.w;

    glColor = gl_Color;
    texUV   = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
}
