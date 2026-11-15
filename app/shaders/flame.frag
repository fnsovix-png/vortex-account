#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;
uniform float uTime;
uniform vec3 uCore;
uniform vec3 uMid;
uniform vec3 uOuter;

out vec4 fragColor;

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
             mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
  float value = 0.0;
  float amplitude = 0.5;
  for (int i = 0; i < 4; i++) {
    value += amplitude * noise(p);
    p = p * 2.03 + vec2(1.7, 9.2);
    amplitude *= 0.5;
  }
  return value;
}

// One tongue of fire. Returns heat: above 0 is inside the flame.
float tongue(vec2 p, float t, float seed, float height, float width) {
  float y = clamp(p.y / height, 0.0, 1.0);
  float turbulence = fbm(vec2(p.x * 1.6 + seed, p.y * 2.0 - t * 1.75)) - 0.5;
  float sway = sin(t * 1.9 + p.y * 2.8 + seed) * 0.045 + sin(t * 4.3 + p.y * 5.4 + seed * 2.0) * 0.02;
  float x = p.x + (turbulence * 0.78 + sway) * smoothstep(0.08, 0.9, y);
  // Full and round low down, narrowing to a licking point at the top.
  float belly = pow(sin(3.14159 * pow(y, 0.56)), 0.82);
  float w = width * belly + 0.0001;
  float heat = 1.0 - abs(x) / w;
  float erosion = (1.0 - fbm(vec2(x * 2.6 + seed, p.y * 3.4 - t * 2.4))) * pow(y, 1.5) * 0.62;
  return heat - erosion;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 p = vec2((uv.x - 0.5) * 2.0, (1.0 - uv.y) * 1.08 - 0.03);
  float t = uTime;

  float breathe = 0.93 + 0.07 * sin(t * 1.6) + 0.03 * sin(t * 3.7);
  float body = tongue(p, t, 0.0, 0.95 * breathe, 0.52);
  float left = tongue(p + vec2(0.26, 0.0), t * 1.13, 3.1, 0.62 * breathe, 0.27);
  float right = tongue(p - vec2(0.28, 0.0), t * 1.21, 7.3, 0.5 * breathe, 0.24);
  float heat = max(body, max(left, right));

  // The hot heart sits low and flickers on its own.
  float inner = tongue(p, t * 1.25, 11.0, 0.42 * breathe, 0.24);

  vec3 color = mix(uOuter, uMid, smoothstep(0.04, 0.42, heat));
  color = mix(color, uCore, smoothstep(0.02, 0.5, inner));
  float alpha = smoothstep(0.0, 0.07, heat);

  // Soft light around the fire that always fades out before the widget's edge.
  float distance_out = length(vec2(p.x, (p.y - 0.32) * 1.1));
  float glow = (1.0 - smoothstep(0.0, 0.82, distance_out));
  glow = glow * glow * 0.3;
  color = mix(uOuter, color, alpha);
  float total = clamp(alpha + glow * (1.0 - alpha), 0.0, 1.0);

  // Embers drifting up from the flame.
  for (int i = 0; i < 6; i++) {
    float index = float(i);
    float speed = 0.34 + hash(vec2(index, 2.0)) * 0.3;
    float life = fract(t * speed + hash(vec2(index, 5.0)));
    vec2 ember = vec2((hash(vec2(index, 9.0)) - 0.5) * 0.8 + sin(t * 2.0 + index * 2.4) * 0.07 * life, 0.26 + life * 0.76);
    float size = (0.02 + hash(vec2(index, 13.0)) * 0.018) * (1.0 - life * 0.7);
    float spark = smoothstep(size, 0.0, length(p - ember)) * (1.0 - life) * smoothstep(0.0, 0.12, life);
    color = mix(color, uCore, spark);
    total = max(total, spark);
  }

  fragColor = vec4(color * total, total);
}
