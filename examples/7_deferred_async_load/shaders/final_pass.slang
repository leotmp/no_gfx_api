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
    uint gbuffer_albedo;
    uint gbuffer_albedo_sampler;
    uint gbuffer_normal;
    uint gbuffer_normal_sampler;
    uint gbuffer_metallic_roughness;
    uint gbuffer_metallic_roughness_sampler;
    int selected_texture_type;
}

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD0, GraphicsPipelineData<void, FragmentData> data) : SV_Target
{
    // TODO: Implement the full PBR lighting pass for the deferred renderer.
    float4 result;
    if (data.frag.selected_texture_type == 0)
    {
        result = getTexture2D(data.frag.gbuffer_albedo).Sample(getSampler(data.frag.gbuffer_albedo_sampler), uv);
    }
    else if (data.frag.selected_texture_type == 1)
    {
        result = getTexture2D(data.frag.gbuffer_normal).Sample(getSampler(data.frag.gbuffer_normal_sampler), uv);
    }
    else
    {
        result = getTexture2D(data.frag.gbuffer_metallic_roughness).Sample(
            getSampler(data.frag.gbuffer_metallic_roughness_sampler), uv);
    }

    return result;
}
