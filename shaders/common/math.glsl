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

float dither(vec2 position, float brightness) {
  int x = int(mod(position.x, 2.0));
  int y = int(mod(position.y, 2.0));
  int index = x + y * 2;
  float limit = 0.0;

  if (x < 8) {
		if (index == 0) limit = 0.12;
		if (index == 1) limit = 0.75;
		if (index == 2) limit = 1.00;
		if (index == 3) limit = 0.50;
  }

  return brightness < limit ? 0.6 : 1.0;
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