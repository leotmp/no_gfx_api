
import "../../shared.slang";

// Shader "Clearly a bug" by Glow on https://www.shadertoy.com/view/33cGDj

struct ComputeData
{
    uint output_texture_id;
    float time;
}

// Helper to construct 2x2 matrix from vec4 (GLSL mat2(vec4) equivalent)
// mat2(vec4(a,b,c,d)) creates matrix [a c; b d] (column-major)
// So vec4 represents: first column (a,b), second column (c,d)
float4 mat2_from_vec4(float4 v)
{
    // Return as [a, b, c, d] for easy access
    return v;
}

// Apply 2x2 matrix to vec2
// m = [a c; b d] (column-major), v = [x; y]
// result = [a*x + c*y; b*x + d*y]
float2 mat2_mul(float4 m, float2 v)
{
    // m.x = a, m.y = b, m.z = c, m.w = d
    // Matrix is [a c; b d]
    // Result = [a*x + c*y; b*x + d*y]
    return float2(m.x * v.x + m.z * v.y, m.y * v.x + m.w * v.y);
}

// Raymarching calculation for a single pixel
// Uses raymarching to render 3D fractal patterns
float4 raymarch(ComputeData* data, uint3 global_invocation_id)
{
    // C is the pixel coordinate (0 to resolution)
    float2 C = global_invocation_id.xy;

    float d;
    float z = frac(dot(C, sin(C))) - 0.5;
    float4 o = float4(0.0, 0.0, 0.0, 0.0);
    float4 p;
    float2 r = float2(0.0);
    getTexture2DRW(data->output_texture_id).GetDimensions(r.x, r.y);
    float4 O;

    // Loop: ++i < 77 means i goes from 1 to 76 (76 iterations)
    // z += .6*d happens at the end of each iteration
    for (float i = 1.0; i < 77.0; i = i + 1.0)
    {
        // Convert 2D pixel to 3D ray direction
        // Note: original uses .1*iTime not .1*i!
        p = float4(z * normalize(float3(C - 0.5 * r, r.y)), 0.1 * data.time);

        // Move through 3D space over time
        p = float4(p.x, p.y, p.z + data.time, p.w);

        // Save position for lighting calculations
        O = p;

        // Apply rotation matrices to create fractal patterns
        // p.xy *= mat2(cos(...)) means multiply p.xy by the rotation matrix
        float4 rot1 = mat2_from_vec4(cos(2.0 + O.z + float4(0.0, 11.0, 33.0, 0.0)));
        float2 p_xy = mat2_mul(rot1, float2(p.x, p.y));
        p = float4(p_xy.x, p_xy.y, p.z, p.w);

        // This was originally a bug in the matrix calculation
        // The incorrect transformation created an unexpectedly interesting pattern
        float4 rot2 = mat2_from_vec4(cos(O + float4(0.0, 11.0, 33.0, 0.0)));
        p_xy = mat2_mul(rot2, float2(p.x, p.y));
        p = float4(p_xy.x, p_xy.y, p.z, p.w);

        // Calculate color based on position and space distortion
        // The sin() creates a nice looking palette, division by dot() creates falloff
        float4 numerator = 1.0 + sin(0.5 * O.z + length(p - O) + float4(0.0, 4.0, 3.0, 6.0));
        float denominator = 0.5 + 2.0 * dot(O.xy, O.xy);
        O = numerator / denominator;

        // Domain repetition, repeats the single line and the 2 planes infinitely
        p = abs(frac(p) - 0.5);

        // Calculate distance to nearest surface
        // This combines a cylinder (length(p.xy)-.125) with 2 planesbox (min(p.x,p.y))
        d = abs(min(length(p.xy) - 0.125, min(p.x, p.y) + 0.001)) + 0.001;

        // Add lighting contribution (brighter when closer to surfaces)
        o = o + O.w / d * O;

        // Step forward (larger steps when far from surfaces)
        // This happens in the for loop increment in the original
        z = z + 0.6 * d;
    }

    // tanh() compresses the accumulated brightness to 0-1 range
    // (Like HDR tone mapping in photography)
    return tanh(o / 20000.0);
}

[shader("compute")]
[numthreads(8, 8, 1)]
void computeMain(uint3 global_invocation_id : SV_DispatchThreadID, uniform ComputePipelineData<ComputeData> pipeline_data)
{
    ComputeData* data = pipeline_data.data;

    float2 resolution = float2(0.0);
    getTexture2DRW(data->output_texture_id).GetDimensions(resolution.x, resolution.y);

    // Out of bounds check: only execute if thread is within resolution
    if (global_invocation_id.x < resolution.x)
    {
        if (global_invocation_id.y < resolution.y)
        {
            float4 color = raymarch(data, global_invocation_id);
            getTexture2DRW(data.output_texture_id)[int2(global_invocation_id.xy)] = color;
        }
    }
}
