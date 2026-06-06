
import "../../shared.slang";

struct VertexData
{
    float3* positions;
    float4x4 model_to_world;
    float4x4 model_to_world_normal;
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
    clip_pos = mul(data.vert.model_to_world, clip_pos);
    clip_pos = mul(data.vert.world_to_view, clip_pos);
    clip_pos = mul(data.vert.view_to_proj, clip_pos);
    clip_pos.y = -clip_pos.y;

    VertexOutput vert_out;
    vert_out.pos = clip_pos;
    vert_out.dir = normalize(data.vert.positions[vert_id].xyz);
    return vert_out;
}

[shader("fragment")]
float4 fragmentMain(VertexOutput input) : SV_Target
{
    float3 frag_dir = normalize(input.dir);
    return float4(frag_dir, 1.0);
}
