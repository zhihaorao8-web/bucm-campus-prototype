#include <flutter/runtime_effect.glsl>

// Edge field adapted from bilalgursen/liquid-glass (MIT), engine.ts.
// The engine supplies the first vec2 and sampler, in physical texture pixels.
uniform vec2 u_size;
uniform vec2 u_logicalSize;
uniform float u_radius;
uniform float u_depth;
uniform float u_refraction;
uniform sampler2D u_input;
out vec4 frag_color;

float field(vec2 p) {
  vec2 halfSize = u_logicalSize * 0.5;
  float radius = min(u_radius, min(halfSize.x, halfSize.y));
  vec2 q = abs(p) - halfSize + radius;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / u_size;
  vec2 p = (uv - 0.5) * u_logicalSize;
  float d = field(p);
  vec2 normal = vec2(field(p + vec2(0.5, 0.0)) - field(p - vec2(0.5, 0.0)),
                     field(p + vec2(0.0, 0.5)) - field(p - vec2(0.0, 0.5)));
  normal /= max(length(normal), 0.0001);
  float bend = pow(clamp(1.0 + d / u_depth, 0.0, 1.0), 1.6);
  uv -= normal * bend * u_refraction / u_logicalSize;
  uv = clamp(uv, vec2(0.0), vec2(1.0));
  // Flutter 3.47.9's composed backdrop snapshot is already oriented for
  // FlutterFragCoord on GLES. An extra flip inverts the sampled background.
  frag_color = texture(u_input, uv);
}
