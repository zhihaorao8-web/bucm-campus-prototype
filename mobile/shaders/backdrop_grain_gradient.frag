#include <flutter/runtime_effect.glsl>

// Single-pass domain-warped gradient with film grain, adapted from uibrik
// GrainGradient (free component).
// Includes 3D simplex noise by Ian McEwan / Ashima Arts / Stefan Gustavson (MIT)
// and "Hash without Sine" by David Hoskins (MIT).

uniform vec2 u_size;
uniform float u_time;
uniform float u_scale;
uniform float u_warp;
uniform float u_sheen;
uniform float u_angle;
uniform float u_sweep;
uniform float u_vignette;
uniform float u_grain;
uniform vec3 u_c0;
uniform vec3 u_c1;
uniform vec3 u_c2;
uniform vec3 u_c3;
uniform vec3 u_c4;

out vec4 frag_color;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 mod289(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 permute(vec4 x) { return mod289(((x * 34.0) + 1.0) * x); }
vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(vec3 v) {
  const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
  const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);
  vec3 i = floor(v + dot(v, C.yyy));
  vec3 x0 = v - i + dot(i, C.xxx);
  vec3 g = step(x0.yzx, x0.xyz);
  vec3 l = 1.0 - g;
  vec3 i1 = min(g.xyz, l.zxy);
  vec3 i2 = max(g.xyz, l.zxy);
  vec3 x1 = x0 - i1 + C.xxx;
  vec3 x2 = x0 - i2 + C.yyy;
  vec3 x3 = x0 - D.yyy;
  i = mod289(i);
  vec4 p = permute(permute(permute(
    i.z + vec4(0.0, i1.z, i2.z, 1.0))
    + i.y + vec4(0.0, i1.y, i2.y, 1.0))
    + i.x + vec4(0.0, i1.x, i2.x, 1.0));
  float n_ = 0.142857142857;
  vec3 ns = n_ * D.wyz - D.xzx;
  vec4 j = p - 49.0 * floor(p * ns.z * ns.z);
  vec4 x_ = floor(j * ns.z);
  vec4 y_ = floor(j - 7.0 * x_);
  vec4 x = x_ * ns.x + ns.yyyy;
  vec4 y = y_ * ns.x + ns.yyyy;
  vec4 h = 1.0 - abs(x) - abs(y);
  vec4 b0 = vec4(x.xy, y.xy);
  vec4 b1 = vec4(x.zw, y.zw);
  vec4 s0 = floor(b0) * 2.0 + 1.0;
  vec4 s1 = floor(b1) * 2.0 + 1.0;
  vec4 sh = -step(h, vec4(0.0));
  vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
  vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
  vec3 p0 = vec3(a0.xy, h.x);
  vec3 p1 = vec3(a0.zw, h.y);
  vec3 p2 = vec3(a1.xy, h.z);
  vec3 p3 = vec3(a1.zw, h.w);
  vec4 norm = taylorInvSqrt(vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
  p0 *= norm.x;
  p1 *= norm.y;
  p2 *= norm.z;
  p3 *= norm.w;
  vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
  m = m * m;
  return 42.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

float fbm(vec3 p) {
  float sum = 0.0;
  float amp = 0.5;
  for (int i = 0; i < 3; i++) {
    sum += amp * snoise(p);
    p = p * 1.9 + vec3(1.7, 9.2, 0.3);
    amp *= 0.4;
  }
  return sum;
}

vec3 stop5(int i) {
  if (i <= 0) return u_c0;
  if (i == 1) return u_c1;
  if (i == 2) return u_c2;
  if (i == 3) return u_c3;
  return u_c4;
}

vec3 paletteRamp5(float x) {
  float f = clamp(x, 0.0, 1.0) * 4.0;
  float fi = min(floor(f), 3.0);
  int i = int(fi);
  return mix(stop5(i), stop5(i + 1), smoothstep(0.0, 1.0, f - fi));
}

vec3 oklabToLinear(vec3 c) {
  float l = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
  float m = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
  float s = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
  l = l * l * l;
  m = m * m * m;
  s = s * s * s;
  return vec3(
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
  );
}

vec3 linearToSrgb(vec3 c) {
  c = clamp(c, 0.0, 1.0);
  return mix(
    c * 12.92,
    1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055,
    step(0.0031308, c)
  );
}

void main() {
  vec2 res = max(u_size, vec2(1.0));
  vec2 fc = FlutterFragCoord().xy;
  vec2 frag = vec2(fc.x, res.y - fc.y);
  float aspect = res.x / res.y;
  vec2 uv = frag / res;
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0) * (0.75 / max(u_scale, 0.05));
  float t = u_time * 0.06;

  vec2 q = vec2(fbm(vec3(p, t)), fbm(vec3(p + vec2(5.2, 1.3), t)));
  vec2 r = vec2(
    fbm(vec3(p + 0.8 * u_warp * q + vec2(1.7, 9.2), t * 1.3)),
    fbm(vec3(p + 0.8 * u_warp * q + vec2(8.3, 2.8), t * 1.3))
  );
  float f = fbm(vec3(p + 0.8 * u_warp * r, t * 0.8));

  float a = radians(u_angle);
  float sweep = dot(uv - 0.5, vec2(cos(a), sin(a)));
  vec3 lab = paletteRamp5(0.5 + f * 0.85 + sweep * u_sweep);
  lab.x += u_sheen * 0.08 * (smoothstep(0.05, 0.5, length(r)) - 0.4);
  lab.x *= 1.0 - 0.36 * u_vignette * dot(uv - 0.5, uv - 0.5);

  vec3 srgb = linearToSrgb(oklabToLinear(lab));
  srgb += (hash12(floor(fc)) - 0.5) * u_grain;
  srgb += (hash12(fc + 17.0) - 0.5) * (1.5 / 255.0);
  frag_color = vec4(clamp(srgb, 0.0, 1.0), 1.0);
}
