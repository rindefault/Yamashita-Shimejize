#ifndef PASS_CLASSES_GLSL
#define PASS_CLASSES_GLSL

const int PASS_TERRAIN = 0;
const int PASS_TEXTURED = 1;

bool isTerrainPass(int passType) {
	return passType == PASS_TERRAIN;
}

bool isTexturedPass(int passType) {
	return passType == PASS_TEXTURED;
}

#endif
