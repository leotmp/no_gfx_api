
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
    uint texture_a;
    uint texture_b;
    uint s;
    float fade;
}

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD0, GraphicsPipelineData<void, FragmentData> data) : SV_Target
{
    float4 tex_a = getTexture2D(data.frag.texture_a).Sample(getSampler(data.frag.s), uv);
    float4 tex_b = getTexture2D(data.frag.texture_b).Sample(getSampler(data.frag.s), uv);
    return lerp(tex_a, tex_b, data.frag.fade);
}
