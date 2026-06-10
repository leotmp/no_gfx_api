import "../../shared.slang";

struct Vertex
{
    float3 pos;
    float2 uv;
}

struct VertexData
{
    Vertex* verts;
}

struct VertexOutput
{
    float4 pos : SV_Position;
    float2 uv : TEXCOORD0;
}

[shader("vertex")]
VertexOutput vertexMain(uint vert_id : SV_VertexID, GraphicsPipelineData<VertexData> data)
{
    VertexOutput vert_out;
    vert_out.pos = float4(data.vert.verts[vert_id].pos.xyz, 1.0);
    vert_out.uv = data.vert.verts[vert_id].uv;
    return vert_out;
}

struct FragmentData
{
    uint texture_id;
    uint sampler_id;
}

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD0, GraphicsPipelineData<void, FragmentData> data) : SV_Target
{
    float4 linear = getTexture2D(data.frag.texture_id).Sample(getSampler(data.frag.sampler_id), uv);
    return linear_to_srgb(hdr_to_ldr(max(linear, float4(0.0, 0.0, 0.0, 0.0))));
}

float4 linear_to_srgb(float4 color)
{
    float3 cutoff = float3(
        color.x < 0.0031308 ? 1.0 : 0.0,
        color.y < 0.0031308 ? 1.0 : 0.0,
        color.z < 0.0031308 ? 1.0 : 0.0);
    float3 higher = 1.055 * pow(color.xyz, 1.0 / 2.4) - 0.055;
    float3 lower = color.xyz * 12.92;

    return float4(lerp(higher, lower, cutoff), color.w);
}

float3 filmic(float3 x)
{
    float3 X = max(float3(0.0, 0.0, 0.0), x - 0.004);
    float3 result = (X * (6.2 * X + 0.5)) / (X * (6.2 * X + 1.7) + 0.06);
    return pow(result, 2.2);
}

float4 hdr_to_ldr(float4 color)
{
    return float4(filmic(color.xyz), color.w);
}
