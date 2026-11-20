#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;
precision highp int;

uniform vec2 uSize;
uniform float uLutSize;      // e.g. 17.0 or 33.0
uniform float uIntensity;    // 0.0 to 1.0
uniform sampler2D uPhotoTex;
uniform sampler2D uLutTex;   // Horizontal strip of 2D slices: width = N*N, height = N

out vec4 fragColor;

// Samples a single lattice node (x, y, z) from the horizontal strip 2D texture at exact pixel center
vec3 sampleLutNode(highp float x, highp float y, highp float z, highp float n) {
  highp float texX = (z * n + x + 0.5) / (n * n);
  highp float texY = (y + 0.5) / n;
  return texture(uLutTex, vec2(texX, texY)).rgb;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 origColor = texture(uPhotoTex, uv);
  highp vec3 rgb = clamp(origColor.rgb, 0.0, 1.0);

  highp float n = uLutSize;
  highp float maxCoord = n - 1.0;

  // Map normalized color [0.0..1.0] to continuous 3D coordinate space [0.0..N-1]
  highp float xCoord = rgb.r * maxCoord;
  highp float yCoord = rgb.g * maxCoord;
  highp float zCoord = rgb.b * maxCoord;

  // Bounding integer coordinates
  highp float x0 = floor(xCoord);
  highp float x1 = min(x0 + 1.0, maxCoord);
  highp float fx = xCoord - x0;

  highp float y0 = floor(yCoord);
  highp float y1 = min(y0 + 1.0, maxCoord);
  highp float fy = yCoord - y0;

  highp float z0 = floor(zCoord);
  highp float z1 = min(z0 + 1.0, maxCoord);
  highp float fz = zCoord - z0;

  // --- Slice Z0 Bilinear Interpolation (4 samples) ---
  highp vec3 c00_z0 = sampleLutNode(x0, y0, z0, n);
  highp vec3 c10_z0 = sampleLutNode(x1, y0, z0, n);
  highp vec3 c01_z0 = sampleLutNode(x0, y1, z0, n);
  highp vec3 c11_z0 = sampleLutNode(x1, y1, z0, n);

  highp vec3 c0_z0 = mix(c00_z0, c10_z0, fx);
  highp vec3 c1_z0 = mix(c01_z0, c11_z0, fx);
  highp vec3 colorZ0 = mix(c0_z0, c1_z0, fy);

  // --- Slice Z1 Bilinear Interpolation (4 samples) ---
  highp vec3 c00_z1 = sampleLutNode(x0, y0, z1, n);
  highp vec3 c10_z1 = sampleLutNode(x1, y0, z1, n);
  highp vec3 c01_z1 = sampleLutNode(x0, y1, z1, n);
  highp vec3 c11_z1 = sampleLutNode(x1, y1, z1, n);

  highp vec3 c0_z1 = mix(c00_z1, c10_z1, fx);
  highp vec3 c1_z1 = mix(c01_z1, c11_z1, fx);
  highp vec3 colorZ1 = mix(c0_z1, c1_z1, fy);

  // --- Final Trilinear Interpolation across Z axis ---
  highp vec3 lutRgb = mix(colorZ0, colorZ1, fz);

  highp vec3 finalRgb = mix(origColor.rgb, lutRgb, clamp(uIntensity, 0.0, 1.0));
  fragColor = vec4(finalRgb, origColor.a);
}
