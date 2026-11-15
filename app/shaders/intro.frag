#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;
uniform float uTime;
uniform float uImpact;
uniform float uFlood;

out vec4 fragColor;

const float TAU = 6.2831853;
const vec3 LIME = vec3(0.71, 1.0, 0.24);
const vec3 GREEN = vec3(0.18, 0.84, 0.29);
const vec3 TEAL = vec3(0.05, 0.72, 0.62);

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

// Sparks riding the spiral: a grid in log-polar space, so they stretch and speed
// up as they fall toward the middle.
float sparks(vec2 p, float time, float density, float seed) {
  float r = length(p) + 0.0001;
  float logR = log(r);
  float a = atan(p.y, p.x) + logR * 1.15 + time * 0.55;
  vec2 grid = vec2(a / TAU * density, logR * density * 0.34 + time * 1.5);
  vec2 cell = floor(grid);
  vec2 f = fract(grid) - 0.5;
  cell.x = mod(cell.x, density);
  float h = hash(cell + seed);
  if (h < 0.62) return 0.0;
  vec2 jitter = vec2(hash(cell + seed + 1.3), hash(cell + seed + 2.7)) - 0.5;
  vec2 d = f - jitter * 0.55;
  d.y *= 0.42;
  float size = 0.035 + 0.07 * hash(cell + seed + 4.1);
  float twinkle = 0.55 + 0.45 * sin(time * 9.0 + h * 40.0);
  return smoothstep(size, 0.0, length(d)) * twinkle;
}

// Long glowing filaments spiraling inward.
float filaments(vec2 p, float time) {
  float r = length(p) + 0.0001;
  float a = atan(p.y, p.x);
  float s = a * 5.0 + log(r) * 9.5 + time * 4.2;
  float line = pow(0.5 + 0.5 * sin(s), 14.0);
  // Whole-number wave counts join up perfectly all the way around the circle.
  float L = log(r);
  float breakup = 0.5 + 0.28 * sin(3.0 * a + 2.3 * L - time * 1.7) + 0.22 * sin(7.0 * a - 3.1 * L + time * 2.3);
  return line * smoothstep(0.25, 0.75, breakup);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  vec3 iconGreen = mix(LIME, GREEN, clamp((uv.x + uv.y) * 0.5, 0.0, 1.0));
  if (uFlood >= 1.0) {
    fragColor = vec4(iconGreen, 1.0);
    return;
  }
  float unit = min(uSize.x, uSize.y);
  vec2 p = (frag - vec2(0.5, 0.46) * uSize) / unit;
  float t = uTime;
  float impact = uImpact;
  float after = max(t - impact, 0.0);
  float before = clamp(t / impact, 0.0, 1.0);

  // The whole field gets sucked into the middle just before impact.
  float collapse = smoothstep(0.72, 1.0, before);
  collapse = collapse * collapse * collapse;
  vec2 q = p * (1.0 + 26.0 * collapse);

  // Time runs faster and faster as it spins up.
  float spin = before * before * 3.4 + t * 0.35;
  float r = length(p);
  float qr = length(q) + 0.0001;

  float fieldIn = smoothstep(0.0, 0.45, t);
  float fieldOut = 1.0 - smoothstep(0.0, 0.3, after);
  float field = fieldIn * fieldOut;

  vec3 color = vec3(0.012, 0.018, 0.022);

  if (field > 0.001) {
    float edge = smoothstep(0.02, 0.2, qr);
    float fade = exp(-qr * 1.25);
    float lines = filaments(q, spin) * edge * fade * 1.5;
    float dots = sparks(q, spin, 34.0, 1.0) + 0.8 * sparks(q * 1.35, spin * 1.2, 52.0, 7.0);
    vec3 tint = mix(LIME, TEAL, smoothstep(0.05, 0.75, qr));
    color += tint * lines * (0.35 + 1.2 * before) * field;
    color += mix(vec3(1.0), tint, 0.45) * dots * fade * (0.6 + 1.6 * before) * field;
    // Hazy light building up in the core.
    float haze = exp(-qr * (9.0 - 5.0 * before)) * (0.2 + 1.5 * before * before);
    color += mix(TEAL, LIME, before) * haze * field;
  }

  // The last point of light right before the blast.
  float pinch = smoothstep(0.86, 1.0, before) * step(t, impact);
  color += vec3(1.0, 1.0, 0.92) * exp(-r * 38.0) * pinch * 3.0;

  if (t >= impact) {
    // White flash.
    color += vec3(0.92, 1.0, 0.82) * exp(-after * 11.0) * 1.15;

    // Shockwave ring, with colors split slightly like a lens under stress.
    float radius = 1.75 * (1.0 - exp(-after * 2.5));
    float width = 0.016 + after * 0.05;
    float strength = exp(-after * 2.6);
    float ringR = exp(-pow((r - radius * 1.012) / width, 2.0));
    float ringG = exp(-pow((r - radius) / width, 2.0));
    float ringB = exp(-pow((r - radius * 0.988) / width, 2.0));
    color += vec3(ringR * 0.75, ringG, ringB * 0.7) * strength * 1.5;
    float inner = exp(-pow((r - radius * 0.64) / (width * 2.2), 2.0));
    color += GREEN * inner * strength * 0.65;

    // Light rays thrown out of the blast.
    vec2 around = p / (r + 0.0001);
    float rays = noise(around * 7.0 + vec2(3.0, after * 1.1)) * noise(around * 17.0 + vec2(11.0, 2.0));
    rays = pow(rays, 2.0) * 4.5;
    color += mix(LIME, vec3(1.0), 0.25) * rays * exp(-r * 2.2) * exp(-after * 2.8);

    // Embers flung outward, and the calm glow left behind the logo.
    vec2 ember = p * (1.0 / (0.25 + after * 0.9));
    float flung = sparks(ember, 2.0 + after * 0.15, 40.0, 13.0);
    color += LIME * flung * exp(-after * 1.5) * smoothstep(0.1, 0.5, r) * 1.4;
    float aura = exp(-r * 3.1) * (0.2 + 0.06 * sin(after * 5.0));
    color += GREEN * aura * smoothstep(0.0, 0.5, after);
  }

  // Soft film grain keeps the dark gradients clean.
  color += (hash(frag + fract(t) * 91.0) - 0.5) * 0.012;

  color = color / (1.0 + max(color - 1.0, 0.0));
  color = clamp(color, 0.0, 1.0);

  // A wave of the icon's green floods out from the logo, with a bright leading edge.
  if (uFlood > 0.0) {
    float edge = uFlood * 1.5;
    float inside = smoothstep(edge, edge - 0.015, r);
    color += mix(LIME, vec3(1.0), 0.5) * exp(-abs(r - edge) * 34.0) * (1.0 - inside);
    color = mix(clamp(color, 0.0, 1.0), iconGreen, inside);
  }

  fragColor = vec4(color, 1.0);
}
