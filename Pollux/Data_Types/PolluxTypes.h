//
//  PolluxTypes.h
//  Pollux
//
//  Created by Youssef Kamal Victor on 11/8/17.
//  Copyright © 2017 Youssef Victor. All rights reserved.
//

#ifndef PolluxTypes_h
#define PolluxTypes_h

#import "simd/simd.h"

#define MAX_FILENAME_LENGTH 50

#define DEPTH 8.f
#define FOV   45.f
#define MAX_GEOMS 10


enum GeomType {
    SPHERE,
    CUBE,
    PLANE
    // TODO: - MESH?
};

enum PipelineStage {
    GENERATE_RAYS,
    COMPUTE_INTERSECTIONS,
    SHADE,
    COMPACT_RAYS,
    FINAL_GATHER,
};

typedef struct {
    enum GeomType type;
    int materialid;
    vector_float3 translation;
    vector_float3 rotation;
    vector_float3 scale;
    matrix_float4x4 transform;
    matrix_float4x4 inverseTransform;
    matrix_float4x4 invTranspose;
} Geom;

typedef struct {
    unsigned int count;
    Geom data[MAX_GEOMS];
} GeomData;

typedef struct {
    vector_float3 color;

    float         specular_exponent;
    vector_float3 specular_color;

    float hasReflective;
    
    vector_float3 emittance;
    float hasRefractive;
    float index_of_refraction;
    short bsdf;
    
    float hasSubsurface;
    float scatteringDistance;
    float absorptionAtDistance;
} Material;

typedef struct {
    // Ray Info
    vector_float3 origin;
    vector_float3 direction;
    vector_float3 color;
    vector_float3 throughput;
    int inMedium;
    
    // Ray's Pixel Index x, y, and Remaining Bounces
    vector_uint3 idx_bounces;
    unsigned int specularBounce;
} Ray;

typedef struct {
    // Stores  WIDTH, HEIGHT, FOV, DEPTH (4 floats)
    vector_float4 data;
    
    // Camera's Position (duh)
    vector_float3 pos;
    // Stores the target the camera is looking at
    vector_float3 lookAt;
    // Direction Camera is looking in
    vector_float3 view;
    // The camera's right vector
    vector_float3 right;
    // The camera's up vector
    vector_float3 up;
    // Lens Information (lensRadius, focalDistance) for DOF
    vector_float2 lensData;
} Camera;

// Use with a corresponding PathSegment to do:
// 1) color contribution computation
// 2) BSDF evaluation: generate a new ray
typedef struct {
    vector_float3 normal;
    float t;
    
    vector_float3 point;
    int materialId;
    
    int outside;
} Intersection;

#endif /* PolluxTypes_h */
