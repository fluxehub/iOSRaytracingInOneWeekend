#include "ShaderTypes.h"

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[ position ]];
    float2 uv;
};

// Coordinates of a quad (two triangles)
constant float2 quadCoords[] = {
    float2(-1.0, -1.0),
    float2(-1.0,  1.0),
    float2( 1.0,  1.0),
    float2(-1.0, -1.0),
    float2( 1.0,  1.0),
    float2( 1.0, -1.0)
};

vertex VertexOut drawQuad(unsigned int vid [[ vertex_id ]]) {
    VertexOut out;
    out.position = float4(quadCoords[vid], 0.0, 1.0);
    out.uv = out.position.xy * 0.5f + 0.5f;

    return out;
}

float3 narkowiczACES(float3 color) {
    constexpr auto a = 2.51f;
    constexpr auto b = 0.03f;
    constexpr auto c = 2.43f;
    constexpr auto d = 0.59f;
    constexpr auto e = 0.14f;
    return saturate((color * (a * color + b)) / (color * (c * color + d) + e));
}

inline float3 gammaCorrect(float3 color) {
    constexpr auto exponent = 1 / 2.2;
    return pow(color, exponent);
}

fragment float4 drawTexture(VertexOut in [[ stage_in ]], texture2d<float> texture [[ texture(0) ]]) {
    constexpr sampler textureSampler(min_filter::nearest, mag_filter::nearest, mip_filter::none);
    const auto color = narkowiczACES(texture.sample(textureSampler, in.uv).xyz * 0.6f);
    return float4(gammaCorrect(color), 1.0);
}
