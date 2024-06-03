#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

#ifndef __METAL_VERSION__
#include <metal/metal.h>
typedef MTLPackedFloat3 packed_float3;
#endif

typedef struct LambertianMaterial {
    packed_float3 color;
} LambertianMaterial;

typedef struct MetalMaterial {
    packed_float3 albedo;
    float fuzz;
} MetalMaterial;

typedef struct GlassMaterial {
    float indexOfRefraction;
} GlassMaterial;

typedef union Material {
    LambertianMaterial lambertian;
    MetalMaterial metal;
    GlassMaterial glass;
} Material;

typedef enum MaterialType {
    LAMBERTIAN,
    METAL,
    GLASS
} MaterialType;

struct Uniforms {
    simd_float3 pixel00Loc;
    simd_float3 pixelDeltaU;
    simd_float3 pixelDeltaV;
    simd_float3 defocusDiscU;
    simd_float3 defocusDiscV;
    simd_float3 cameraCenter;
    float width;
    float height;
    unsigned int frame;
};

struct Sphere {
    packed_float3 center;
    float radius;
    MaterialType materialType;
    Material material;
};

#endif /* ShaderTypes_h */
