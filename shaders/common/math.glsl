float random(vec2 pos) {
	return fract(sin(dot(pos, vec2(18.9898, 28.633))) * 4378.5453);
}

float random(vec3 pos) {
	return fract(sin(dot(pos, vec3(12.9898, 78.233, 45.164))) * 43758.5453);
}

float luma(vec3 color) {
	return dot(vec3(0.299, 0.587, 0.114), color);
}

float luma(vec4 color) {
  return dot(color.rgb, vec3(0.299, 0.587, 0.114));
}

float rescale(float x, float a, float b) {
	return clamp((x - a) / (b - a), 0.0, 1.0);
}

vec3 rescale(vec3 x, vec3 a, vec3 b) {
	return clamp((x - a) / (b - a), vec3(0.0), vec3(1.0));
}

float squaredLength(vec3 v) {
	return dot(v, v);
}

float bandify(float value, float bands) {
	return floor(bands*value) / (bands - 1.0);
}

vec3 nvec3(vec4 pos) {
	return pos.xyz / pos.w;
}

vec3 contrast(vec3 color, float contrast) {
	return contrast * (color.rgb - 0.5) + 0.5;
}

float invpow2(float x) {
	return 1.0 - x*x;
}

float smoothe(float x) {
	return x*x*(3.0 - 2.0*x);
}

float pow2(float x) {
	return x*x;
}

float pow3(float x) {
	return x*x*x;
}

vec2 pow2(vec2 x) {
    return x * x;
}
vec3 pow2(vec3 x) {
    return x * x;
}
vec4 pow2(vec4 x) {
    return x * x;
}
int min1(int x) {
    return min(x, 1);
}
float min1(float x) {
    return min(x, 1.0);
}

float pow1_5(float x) { // Faster pow(x, 1.5) approximation (that isn't accurate at all) if x is between 0 and 1
    return x - x * pow2(1.0 - x); // Thanks to SixthSurge
}
vec2 pow1_5(vec2 x) {
    return x - x * pow2(1.0 - x);
}
vec3 pow1_5(vec3 x) {
    return x - x * pow2(1.0 - x);
}
vec4 pow1_5(vec4 x) {
    return x - x * pow2(1.0 - x);
}

float sqrt1(float x) {
    return sqrt(max(x, 0.0));
}
vec2 sqrt1(vec2 x) {
    return sqrt(max(x, vec2(0.0)));
}
vec3 sqrt1(vec3 x) {
    return sqrt(max(x, vec3(0.0)));
}
vec4 sqrt1(vec4 x) {
    return sqrt(max(x, vec4(0.0)));
}

float sqrt2(float x) {
    x = 1.0 - x;
    x *= x;
    x *= x;
    return 1.0 - x;
}
vec2 sqrt2(vec2 x) {
    x = 1.0 - x;
    x *= x;
    x *= x;
    return 1.0 - x;
}
vec3 sqrt2(vec3 x) {
    x = 1.0 - x;
    x *= x;
    x *= x;
    return 1.0 - x;
}
vec4 sqrt2(vec4 x) {
    x = 1.0 - x;
    x *= x;
    x *= x;
    return 1.0 - x;
}

float sqrt3(float x) {
    return pow(max(x, 0.0), 0.3333333333333333);
}
vec2 sqrt3(vec2 x) {
    return pow(max(x, vec2(0.0)), vec2(0.3333333333333333));
}
vec3 sqrt3(vec3 x) {
    return pow(max(x, vec3(0.0)), vec3(0.3333333333333333));
}
vec4 sqrt3(vec4 x) {
    return pow(max(x, vec4(0.0)), vec4(0.3333333333333333));
}

//Dithering from Jodie
float bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x * 0.5 + a.y * a.y * 0.75);
}

float bayer4(vec2 a) {
	return bayer2(a * 0.5) * 0.25 + bayer2(a);
}

float bayer8(vec2 a) {
	return bayer4(a * 0.5) * 0.25 + bayer2(a);
}

float smoothstep1(float x) {
    return x * x * (3.0 - 2.0 * x);
}
vec2 smoothstep1(vec2 x) {
    return x * x * (3.0 - 2.0 * x);
}
vec3 smoothstep1(vec3 x) {
    return x * x * (3.0 - 2.0 * x);
}
vec4 smoothstep1(vec4 x) {
    return x * x * (3.0 - 2.0 * x);
}

int max0(int x) {
    return max(x, 0);
}
float max0(float x) {
    return max(x, 0.0);
}
