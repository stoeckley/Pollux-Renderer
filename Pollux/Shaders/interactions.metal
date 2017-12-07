//
//  interactions.metal
//  Pollux
//
//  Created by Youssef Kamal Victor on 11/22/17.
//  Copyright © 2017 Youssef Victor. All rights reserved.
//

#include "interactions_header.metal"

using namespace metal;


void shadeAndScatter(device Ray& ray,
                     thread Intersection& isect,
                     thread Material &m,
                     thread Loki& rng,
                     thread float& pdf) {
    switch (m.bsdf) {
        case -1:
            // Light Shade and 'absorb' ray by terminating
            ray.color *= (m.color * m.emittance);
            ray.idx_bounces[2] = 0;
            break;
        case 0:
            SnS_diffuse(ray, isect, m, rng, pdf);
            break;
        case 1:
            SnS_reflect(ray, isect, m, rng, pdf);
            break;
        case 2:
            SnS_refract(ray, isect, m, rng, pdf);
            break;
        default:
            break;
    }
}

float3 sample_li(constant Geom& light,
                 constant Material& m,
                 constant float3& ref,
                 thread Loki& rng,
                 thread float3 *wi,
                 thread float* pdf_li) {
    return float3(0);
}

float3 getEnvironmentColor(texture2d<float, access::sample> environment,
                           device Ray& ray) {
    constexpr sampler textureSampler(coord::normalized,
                                     address::repeat,
                                     min_filter::linear,
                                     mag_filter::linear,
                                     mip_filter::linear);
    float x = ray.direction.x, y = ray.direction.y, z = ray.direction.z;
    float u = atan2(x, z) / (2 * PI) + 0.5f;
    float v = y * 0.5f + 0.5f;
    
    v = 1-v;
    float4 color = environment.sample(textureSampler, float2(u, v));
    return color.xyz;
}


