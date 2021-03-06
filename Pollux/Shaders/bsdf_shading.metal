//
//  bsdf_shading.metal
//  Pollux
//
//  Created by Youssef Kamal Victor on 11/22/17.
//  Copyright © 2017 Youssef Victor. All rights reserved.
//


#include "bsdf_shading_header.metal"

using namespace metal;


void SnS_diffuse(thread Ray& ray,
                 thread Intersection& isect,
                 thread Material &m,
                 thread Loki& rng,
                 thread float& pdf) {
    
    const float3 n  = isect.normal;
    const float3 wo = -ray.direction;
    
    // Material's color divided `R` which in this case is InvPi
    float3 f = m.color * InvPi;
    
    //This is lambert factor for light attenuation
    float lambert_factor = fabs(dot(n, wo));
    
    //PDF Calculation
    float dotWo = dot(n, wo);
    float cosTheta = fabs(dotWo) * InvPi;
    pdf = cosTheta;
    
    if (abs(pdf) < ZeroEpsilon) {
        ray.idx_bounces[2] = 0;
        return;
    }
    
    float3 integral = (f * lambert_factor)
                            / pdf;
    ray.color *= integral;
    
    //Scatter the Ray
    ray.origin = isect.point + n*EPSILON;
    ray.direction = cosRandomDirection(n, rng);
    ray.idx_bounces[2]--;
}

void  SnS_reflect(thread Ray& ray,
                  thread Intersection& isect,
                  thread Material &m,
                  thread Loki& rng,
                  thread float& pdf) {

    ray.origin = isect.point + isect.normal * EPSILON;
    ray.color *= m.color;
    ray.direction = reflect(ray.direction, isect.normal);
    ray.idx_bounces[2]--;
    pdf = 1;
}

void SnS_refract(thread Ray& ray,
                 thread Intersection& isect,
                 thread Material &m,
                 thread Loki& rng,
                 thread float& pdf) {
    //Figure out which n is incident and which is transmitted
    const bool    entering = isect.outside;
    const float        eta = entering ? 1.0 / m.index_of_refraction : m.index_of_refraction;
    
    float3 refracted = normalize(refract(ray.direction, isect.normal, eta));
    
    if (abs(refracted.x) < ZeroEpsilon &&
        abs(refracted.y) < ZeroEpsilon &&
        abs(refracted.z) < ZeroEpsilon) {
        ray.color = float3(0);
    } else {
        ray.color *= m.color;
    }

    ray.origin = isect.point - isect.normal * 0.1;
    ray.direction = refracted;
    ray.idx_bounces[2]--;
    pdf = 1.f;
}

void SnS_microfacetBTDF(thread Ray& ray,
                        thread Intersection& isect,
                        thread Material &m,
                        thread Loki& rng,
                        thread float& pdf) {
    
//    const float3 wo = -ray.direction;
    
//    if (wo.z == 0) {
//        ray.color = float3(0.f);
//    }
//
//    float3 wh = distribution->Sample_wh(wo, xi);
//
//    const float eta = entering ? 1.0 / m.index_of_refraction : m.index_of_refraction;
//
//    const float3 wi = normalize(refract(wo, wh, eta))
//
//    if (abs(wi.x) < ZeroEpsilon &&
//        abs(wi.y) < ZeroEpsilon &&
//        abs(wi.z) < ZeroEpsilon) {
//        ray.color = float3(0);
//    }
    
    /*************************
     **** PDF Calculation ****
     *************************/
//    if (dot(wo, wi) < 0) {
//        *pdf = 0;
//        return;
//    }
    
//    const float dotWo = dot(n, wo);
//    const float cosTheta = fabs(dotWo) * InvPi;
    
//    const bool   entering = isect.outside;
//    const float  eta = entering ? 1.0 / m.index_of_refraction : m.index_of_refraction;
//    const float3 wh = normalize(wo + (wi * eta));
//
//    const float bottomTerm = dot(wo, wh) + (eta * dot(wi, wh));
//    const float dwh_dwi = abs((eta * eta * dot(wi, wh))
//                           / (bottomTerm * bottomTerm));
    
//    *pdf = distribution->Pdf(wo, wh) * dwh_dwi;
    
    
    /***************************
     **** Color Calculation ****
     ***************************/
    
    
    
    
    /***************************
     ******  Ray Updating ******
     ***************************/
//    ray.origin = isect.point - isect.normal * 0.1;
//    ray.direction = wi;
//    ray.idx_bounces[2]--;
}


/**************************
 **************************
 ***** HELPER METHODS *****
 **************************
 **************************/

float3 cosRandomDirection(const float3 normal,
                          thread Loki& rng) {
    float up = sqrt(rng.rand()); // cos(theta)
    float over = sqrt(1 - up * up); // sin(theta)
    float around = rng.rand() * TWO_PI;
    
    // Find a direction that is not the normal based off of whether or not the
    // normal's components are all equal to sqrt(1/3) or whether or not at
    // least one component is less than sqrt(1/3). Taken from CUDA Pathtracer.
    // Originally learned from Peter Kutz.
    
    float3 directionNotNormal;
    if (abs(normal.x) < SQRT_OF_ONE_THIRD) {
        directionNotNormal = float3(1, 0, 0);
    }
    else if (abs(normal.y) < SQRT_OF_ONE_THIRD) {
        directionNotNormal = float3(0, 1, 0);
    }
    else {
        directionNotNormal = float3(0, 0, 1);
    }
    
    // Use not-normal direction to generate two perpendicular directions
    float3 perpendicularDirection1 =
    normalize(cross(normal, directionNotNormal));
    float3 perpendicularDirection2 =
    normalize(cross(normal, perpendicularDirection1));
    
    return up * normal
    + cos(around) * over * perpendicularDirection1
    + sin(around) * over * perpendicularDirection2;
}
