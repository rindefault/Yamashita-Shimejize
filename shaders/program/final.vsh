varying vec2 texUV;

void main() {
   texUV = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
   gl_Position = ftransform();
}
