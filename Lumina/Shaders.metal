//
//  Shaders.metal
//  Lumina
//
//  Created by Juyoung Kim on 1/2/26.
//

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 textureCoordinate;
};

// 1. Helper: Pseudo-Random Number Generator
// Returns a random number between 0.0 and 1.0 based on a coordinate seed
float random(float2 uv, float time) {
    // The "dot product" mixes the X and Y coordinates thoroughly
    // The "sin" makes it wave, and "fract" keeps just the decimal part
    return fract(sin(dot(uv + time, float2(12.9898, 78.233))) * 43758.5453);
}

float3x3 makeRotationMatrix(float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float3x3(float3(c, -s, 0), float3(s, c, 0), float3(0, 0, 1));
}

vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
                              constant float &rotationAngle [[buffer(1)]],
                              constant float2 &scale [[buffer(2)]]) {
    
    float4 positions[4] = {
        float4(-1.0, -1.0, 0.0, 1.0), float4( 1.0, -1.0, 0.0, 1.0),
        float4(-1.0,  1.0, 0.0, 1.0), float4( 1.0,  1.0, 0.0, 1.0),
    };

    float2 texCoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0),
    };
    
    VertexOut out;
    
    float4 pos = positions[vertexID];
    pos.x *= scale.x;
    pos.y *= scale.y;
    out.position = pos;
    
    float3 texCoord3 = float3(texCoords[vertexID].x - 0.5, texCoords[vertexID].y - 0.5, 1.0);
    texCoord3 = makeRotationMatrix(rotationAngle) * texCoord3;
    out.textureCoordinate = float2(texCoord3.x + 0.5, texCoord3.y + 0.5);
    
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               texture2d<float> cameraTexture [[texture(0)]],
                               constant float &saturation [[buffer(0)]],    // Existing
                               constant float &grainStrength [[buffer(1)]], // NEW
                               constant float &time [[buffer(2)]]) {        // NEW
    
    constexpr sampler textureSampler (mag_filter::linear, min_filter::linear);
    float4 color = cameraTexture.sample(textureSampler, in.textureCoordinate);
    
    // --- 1. Saturation ---
    float3 grayWeights = float3(0.299, 0.587, 0.114);
    float grayValue = dot(color.rgb, grayWeights);
    float3 grayColor = float3(grayValue, grayValue, grayValue);
    float3 finalColor = mix(grayColor, color.rgb, saturation);
    
    // --- 2. Grain ---
    // Generate noise based on pixel position (in.textureCoordinate) AND time
    float noise = random(in.textureCoordinate, time);
    
    // "noise" is 0.0 to 1.0. We shift it to be -0.5 to 0.5 so it darkens AND brightens.
    float grain = (noise - 0.5) * grainStrength;
    
    // Apply grain
    finalColor += grain;
    
    return float4(finalColor, 1.0);
}