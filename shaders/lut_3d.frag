#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uLutSize;      // e.g. 17.0 or 33.0
uniform float uIntensity;    // 0.0 to 1.0
uniform sampler2D uPhotoTex;
uniform sampler2D uLutTex;   // Horizontal strip of 2D slices: width = N*N, height = N

out vec4 fragColor;

vec3 sampleLutSlice(vec3 rgb, float sliceIndex, float n) {
  float sliceWidth = n * n;
  // Map r and g from [0, 1] to pixel centers [0.5, n - 0.5]
  float u = (sliceIndex * n + (0.5 + rgb.r * (n - 1.0))) / sliceWidth;
  float v = (0.5 + rgb.g * (n - 1.0)) / n;
  return texture(uLutTex, vec2(u, v)).rgb;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 origColor = texture(uPhotoTex, uv);
  vec3 rgb = clamp(origColor.rgb, 0.0, 1.0);

  float n = uLutSize;
  float blueSlice = rgb.b * (n - 1.0);
  float sliceLow = floor(blueSlice);
  float sliceHigh = min(sliceLow + 1.0, n - 1.0);
  float sliceFrac = blueSlice - sliceLow;

  vec3 colorLow = sampleLutSlice(rgb, sliceLow, n);
  vec3 colorHigh = sampleLutSlice(rgb, sliceHigh, n);
  vec3 lutRgb = mix(colorLow, colorHigh, sliceFrac);

  vec3 finalRgb = mix(origColor.rgb, lutRgb, clamp(uIntensity, 0.0, 1.0));
  fragColor = vec4(finalRgb, origColor.a);
}

