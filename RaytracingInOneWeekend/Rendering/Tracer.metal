#include "ShaderTypes.h"

#include <metal_stdlib>

using namespace metal;
using namespace raytracing;

constant int SAMPLES = 1;
constant int MAX_BOUNCES = 10;

constant unsigned int primes[] = {
      2,   3,   5,   7,  11,  13,  17,
     19,  23,  29,  31,  37,  41,  43,
     47,  53,  59,  61,  67,  71,  73,
     79,  83,  89,  97, 101, 103, 107,
    109, 113, 127, 131, 137, 139, 149,
    151, 157, 163, 167, 173, 179, 181,
    191, 193, 197, 199, 211, 223, 227,
    229, 233, 239, 241, 251, 257, 263,
    269, 271, 277, 281, 283, 293
};

float halton(unsigned int i, unsigned int d) {
    unsigned int b = primes[d];

    float f = 1.0f;
    float r = 0.0f;

    while (i > 0) {
        f = f / b;
        r = r + f * (i % b);
        i = i / b;
    }

    return r;
}

struct Intersection {
    bool accept     [[accept_intersection]];
    float distance  [[distance]];
};

struct Payload {
    float3 normal;
    float3 pos;
    bool frontFace;
};

void setFaceNormal(ray_data Payload& payload, float3 rayDirection, float3 outwardNormal) {
    payload.frontFace = dot(rayDirection, outwardNormal) < 0;
    payload.normal = payload.frontFace ? outwardNormal : -outwardNormal;
}

[[intersection(bounding_box)]]
Intersection sphereIntersection(float3 origin             [[ origin ]],
                                float3 direction          [[ direction ]],
                                float minDistance         [[ min_distance ]],
                                float maxDistance         [[ max_distance ]],
                                const device Sphere* data [[ primitive_data ]],
                                ray_data Payload& payload [[ payload ]]) {
    Intersection intersection;
    Sphere sphere = *data;

    const auto oc = sphere.center - origin;
    const auto a = length_squared(direction);
    const auto h = dot(direction, oc);
    const auto c = length_squared(oc) - sphere.radius * sphere.radius;
    const auto discriminant = h * h - a * c;

    intersection.accept = false;

    if (discriminant < 0.0f) {
        return intersection;
    }

    const auto distance = (h - sqrt(discriminant)) / a;

    if (distance < minDistance || distance > maxDistance) {
        return intersection;
    }

    intersection.accept = true;
    intersection.distance = (h - sqrt(discriminant)) / a;
    payload.pos = origin + direction * intersection.distance;
    setFaceNormal(payload, direction, (payload.pos - sphere.center) / sphere.radius);

    return intersection;
}

// https://karthikkaranth.me/blog/generating-random-points-in-a-sphere/
float3 sampleOnUnitSphere(float2 uv) {
    const auto theta = uv.x * 2.0 * M_PI_F;
    const auto phi = acos(2.0 * uv.y - 1.0);
    const auto r = 1;
    const auto sinTheta = sin(theta);
    const auto cosTheta = cos(theta);
    const auto sinPhi = sin(phi);
    const auto cosPhi = cos(phi);

    const auto x = r * sinPhi * cosTheta;
    const auto y = r * sinPhi * sinTheta;
    const auto z = r * cosPhi;

    return float3(x, y, z);
}

__attribute__((always_inline))
inline bool nearZero(float3 v) {
    return any(fabs(v) < 1e-8);
}

inline float reflectance(float cosine, float refractionIndex) {
    auto r0 = (1.0 - refractionIndex) / (1.0 + refractionIndex);
    r0 *= r0;
    return r0 + (1.0 - r0) * pow((1.0 - cosine), 5.0);
}

kernel void trace(uint2                                     threadId                    [[ thread_position_in_grid ]],
                  const texture2d<unsigned int>             randomTexture               [[ texture(0) ]],
                  const texture2d<float>                    previousTexture             [[ texture(1) ]],
                  const texture2d<float, access::write>     outputTexture               [[ texture(2) ]],
                  constant Uniforms&                        uniforms                    [[ buffer(0) ]],
                  primitive_acceleration_structure          accelerationStructure       [[ buffer(1) ]],
                  intersection_function_table<>             intersectionFunctionTable   [[ buffer(2) ]]) {
    ray ray;
    const auto pixel = (float2) threadId;
    auto averageColor = float3(0.0f, 0.0f, 0.0f);

    const auto randomValue = randomTexture.read(threadId).x;

    for (int sample = 0; sample < SAMPLES; sample++) {
        auto color = float3(0.0f, 0.0f, 0.0f);

        const auto haltonIndex = randomValue + uniforms.frame * SAMPLES + sample;

        const auto offset = float3(halton(haltonIndex, 0) - 0.5f,
                                   halton(haltonIndex, 1) - 0.5f,
                                   0.0f);

        const auto pixelCenter = uniforms.pixel00Loc
                                + ((pixel.x + offset.x) * uniforms.pixelDeltaU)
                                + ((pixel.y + offset.y) * uniforms.pixelDeltaV);

        const auto randomOnDisc = sampleOnUnitSphere(float2(halton(haltonIndex, 2),
                                                            halton(haltonIndex, 3))).xy;

        const auto defocusDiscSample = uniforms.cameraCenter + (randomOnDisc.x * uniforms.defocusDiscU) + (randomOnDisc.y * uniforms.defocusDiscV);

        ray.origin = defocusDiscSample;
        ray.direction = pixelCenter - ray.origin;
        ray.min_distance = 1e-3;
        ray.max_distance = INFINITY;

        intersector<> rayIntersector;
        intersector<>::result_type intersection;
        Payload payload;

        auto light = float3(1.0f, 1.0f, 1.0f);

        bool absorbed = false;

        for (int bounce = 0; bounce <= MAX_BOUNCES; bounce++) {
            if (bounce == MAX_BOUNCES || absorbed) {
                color = float3(0.0f, 0.0f, 0.0f);
            }

            intersection = rayIntersector.intersect(ray, accelerationStructure, intersectionFunctionTable, payload);

            if (intersection.type == intersection_type::none) {
                const auto unitDirection = normalize(ray.direction);
                const auto a = 0.5 * (unitDirection.y + 1.0);
                color = mix(float3(1, 1, 1), float3(0.5, 0.7, 1.0), a) * light;
                break;
            }

            const auto sphere = *(const device Sphere*) intersection.primitive_data;
            switch (sphere.materialType) {
                case LAMBERTIAN: {
                    light *= sphere.material.lambertian.color;
                    const auto sampleUv = float2(halton(haltonIndex, bounce + 4),
                                                 halton(haltonIndex, bounce + 5));
                    auto scatterDirection = payload.normal + sampleOnUnitSphere(sampleUv);
                    if (nearZero(scatterDirection)) {
                        scatterDirection = payload.normal;
                    }

                    ray.origin = payload.pos;
                    ray.direction = scatterDirection;
                    break;
                }
                case METAL: {
                    auto reflected = reflect(ray.direction, payload.normal);
                    const auto sampleUv = float2(halton(haltonIndex, bounce + 4),
                                                 halton(haltonIndex, bounce + 5));

                    reflected = normalize(reflected) + (sphere.material.metal.fuzz * sampleOnUnitSphere(sampleUv));

                    if (dot(reflected, payload.normal) <= 0) {
                        absorbed = true;
                        break;
                    }

                    light *= sphere.material.metal.albedo;

                    ray.origin = payload.pos;
                    ray.direction = reflected;
                    break;
                }
                case GLASS: {
                    const auto refractionIndex = sphere.material.glass.indexOfRefraction;
                    const auto ri = payload.frontFace ? (1.0 / refractionIndex) : refractionIndex;

                    const auto normalizedDirection = normalize(ray.direction);
                    const auto cosTheta = fmin(dot(-normalizedDirection, payload.normal), 1.0);
                    const auto sinTheta = sqrt(1.0 - cosTheta * cosTheta);

                    const auto cannotRefract = ri * sinTheta > 1.0;

                    ray.origin = payload.pos;
                    if (cannotRefract || reflectance(cosTheta, ri) > halton(haltonIndex, bounce + 6)) {
                        ray.direction = reflect(normalizedDirection, payload.normal);
                    } else {
                        ray.direction = refract(normalizedDirection, payload.normal, ri);
                    }

                    break;
                }
            }
        }

        averageColor += color;
    }

    averageColor /= SAMPLES;

    if (uniforms.frame > 0) {
        auto previous = previousTexture.read(threadId).xyz;
        previous *= uniforms.frame;

        averageColor += previous;
        averageColor /= uniforms.frame + 1;
    }

    outputTexture.write(float4(averageColor, 1.0f), threadId);
}
