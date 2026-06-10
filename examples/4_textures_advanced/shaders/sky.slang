
import "../../shared.slang";

struct VertexData
{
    float3* positions;
    float4x4 world_to_view;
    float4x4 view_to_proj;
}

struct VertexOutput
{
    float4 pos : SV_Position;
    float3 dir : TEXCOORD0;
}

[shader("vertex")]
VertexOutput vertexMain(uint vert_id : SV_VertexID, GraphicsPipelineData<VertexData> data)
{
    float4 clip_pos = float4(data.vert.positions[vert_id].xyz, 1.0);
    clip_pos = float4(mul(float3x3(data.vert.world_to_view), clip_pos.xyz), 1.0);
    clip_pos = mul(data.vert.view_to_proj, clip_pos);
    clip_pos.y = -clip_pos.y;

    VertexOutput vert_out;
    vert_out.pos = clip_pos;
    vert_out.dir = normalize(data.vert.positions[vert_id].xyz);
    return vert_out;
}

struct FragmentData
{
    uint sky_texture;
    uint sky_sampler;
}

[shader("fragment")]
float4 fragmentMain(VertexOutput input, GraphicsPipelineData<void, FragmentData> data) : SV_Target
{
    float3 frag_dir = normalize(input.dir);
    float3 sky_color = getTextureCube(data.frag.sky_texture).Sample(getSampler(data.frag.sky_sampler), frag_dir).rgb;
    return float4(sky_color, 1.0);
}
