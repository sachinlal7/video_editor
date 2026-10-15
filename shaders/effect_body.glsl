// Shared SDR, encoded RGB shader body. Generated GLSL and Metal wrappers supply
// SAMPLE (clamped input), LUT (trilinear cube), uv, pixel, p[8], time and kind.
vec3 original = SAMPLE(uv).rgb;
vec3 c = original;
if (kind == 1) {
  c = c * pow(2.0, p[5]) + vec3(p[0]);
  c = (c - vec3(0.5)) * p[1] + vec3(0.5);
  c = mix(vec3(dot(c, vec3(0.2126, 0.7152, 0.0722))), c, p[2]);
  c += vec3(p[3] * 0.1 + p[4] * 0.05, -p[4] * 0.1, -p[3] * 0.1 + p[4] * 0.05);
} else if (kind == 2) {
  c = vec3(dot(c, vec3(0.2126, 0.7152, 0.0722)));
} else if (kind == 3) {
  c *= 1.0 - p[0] * smoothstep(0.2, 0.72, length(uv - vec2(0.5)));
} else if (kind == 4) {
  vec2 cell = floor(uv / pixel);
  float noise = fract(sin(dot(cell + floor(time * 24.0), vec2(12.9898, 78.233))) * 43758.5453);
  c += vec3((noise - 0.5) * p[0]);
} else if (kind == 5 || kind == 6 || kind == 7) {
  float radius = kind == 5 ? p[0] : (kind == 6 ? p[1] : 1.0);
  vec3 blurred = vec3(0.0);
  for (int y = -1; y <= 1; y++) {
    for (int x = -1; x <= 1; x++) {
      float weight = (x == 0 ? 2.0 : 1.0) * (y == 0 ? 2.0 : 1.0) / 16.0;
      vec3 tap = SAMPLE(uv + vec2(float(x), float(y)) * pixel * radius).rgb;
      blurred += (kind == 6 ? max(tap - vec3(0.6), vec3(0.0)) : tap) * weight;
    }
  }
  c = kind == 5 ? blurred : (kind == 6 ? c + blurred * p[0] : c + (c - blurred) * p[0]);
} else if (kind == 8) {
  c.r = SAMPLE(uv + vec2(pixel.x * p[0], 0.0)).r;
  c.b = SAMPLE(uv - vec2(pixel.x * p[0], 0.0)).b;
} else if (kind == 9) {
  vec2 d = uv - vec2(0.5);
  c = SAMPLE(vec2(0.5) + d * (1.0 + p[0] * dot(d, d) * 4.0)).rgb;
} else if (kind == 10) {
  float band = floor(uv.y * 24.0);
  float offset = sin(band * 7.0 + floor(time * p[1] * 8.0)) * p[0];
  c = SAMPLE(uv + vec2(offset, 0.0)).rgb;
} else if (kind == 11) {
  float center = 0.2 + 0.2 * sin(time * p[1] * 2.0);
  float leak = exp(-abs(uv.x - center) * 6.0) * p[0];
  c = vec3(1.0) - (vec3(1.0) - c) * (vec3(1.0) - vec3(leak, leak * 0.3, leak * 0.05));
} else if (kind == 12) {
  c *= 1.0 + p[0] * sin(time * p[1] * 6.28318530718);
} else if (kind == 13) {
  c = LUT(clamp(c, vec3(0.0), vec3(1.0)));
}
return vec4(mix(original, clamp(c, vec3(0.0), vec3(1.0)), intensity), 1.0);
