"""Independent full-float reference for the admitted URP 17.5 direct-light subset.

This is not a complete URP renderer: metallic=0, smoothness=0, no clearcoat,
no specular-off keyword. Inputs are linear RGB and unit world-space vectors.
"""
from __future__ import annotations
from math import cos, isfinite, pi, radians, sin, sqrt

FLT_MIN = 1.175494351e-38
DIELECTRIC = 0.04
DIFFUSE = 1.0 - DIELECTRIC
SOURCE_COMMIT = 'c930feab9f105738328d183bb3c32758d8da0ac3'


def dot(a, b):
    return sum(x * y for x, y in zip(a, b, strict=True))


def saturate(value):
    return min(1.0, max(0.0, value))


def safe_normalize(vector):
    """HLSL float3 SafeNormalize, including its zero/tiny-vector behavior."""
    scale = 1.0 / sqrt(max(FLT_MIN, dot(vector, vector)))
    return tuple(x * scale for x in vector)


def direction(degrees):
    return (sin(radians(degrees)), 0.0, cos(radians(degrees)))


def specular(light, view):
    halfway = safe_normalize(tuple(a + b for a, b in zip(light, view, strict=True)))
    light_half = saturate(dot(light, halfway))
    return DIELECTRIC / (6.0 * max(0.1, light_half * light_half) * 1.00001 ** 2)


def source_direct(albedo, normal, light, view, light_color=(1.0, 1.0, 1.0), attenuation=1.0):
    """URP InitializeBRDFData + DirectBRDF + LightingPhysicallyBased subset."""
    cosine = saturate(dot(normal, light))
    highlight = specular(light, view)
    return tuple((DIFFUSE * channel + highlight) * color * attenuation * cosine
                 for channel, color in zip(albedo, light_color, strict=True))


def godot_custom_direct(albedo, normal, light, view, light_color=(1.0, 1.0, 1.0), attenuation=1.0):
    """Godot nonphysical LIGHT_COLOR includes pi, post-light diffuse uses ALBEDO."""
    cosine = saturate(dot(normal, light))
    diffuse_accumulator = tuple(c * pi * attenuation * cosine * (DIFFUSE / pi) for c in light_color)
    specular_accumulator = tuple(c * pi * attenuation * cosine * (specular(light, view) / pi) for c in light_color)
    return tuple(a * d + s for a, d, s in zip(albedo, diffuse_accumulator, specular_accumulator, strict=True))


def srgb_to_linear(value):
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def finite_rgb(rgb):
    return len(rgb) == 3 and all(isfinite(x) for x in rgb)
