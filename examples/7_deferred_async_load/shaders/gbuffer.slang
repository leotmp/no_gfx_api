import "../../shared.slang";

struct Data
{
    float4* positions;
    float4* normals;
    float2* uvs;
    float4x4 model_to_world;
    float4x4 model_to_world_normal;
    float4x4 world_to_view;
    float4x4 view_to_proj;
}

struct VertexOutput
{
    float4 pos : SV_Position;
    float4 normal : TEXCOORD0;
    float2 uv : TEXCOORD1;
    float4 world_pos : TEXCOORD2;
}

[shader("vertex")]
VertexOutput vertexMain(uint vert_id : SV_VertexID, GraphicsPipelineData<Data> data)
{
    Data* vert_data = data.vert;
    float4 clip_pos = float4(vert_data->positions[vert_id].xyz, 1.0);
    float4 world_pos = mul(vert_data->model_to_world, clip_pos);
    clip_pos = mul(vert_data->world_to_view, world_pos);
    clip_pos = mul(vert_data->view_to_proj, clip_pos);
    clip_pos.y = -clip_pos.y;

    float4 world_normal = mul(vert_data->model_to_world_normal, vert_data->normals[vert_id]);

    VertexOutput vert_out;
    vert_out.pos = clip_pos;
    vert_out.normal = world_normal;
    vert_out.uv = vert_data->uvs[vert_id];
    vert_out.world_pos = world_pos;
    return vert_out;
}

struct FragmentData
{
    uint base_color_map;
    uint base_color_map_sampler;
    uint metallic_roughness_map;
    uint metallic_roughness_map_sampler;
    uint normal_map;
    uint normal_map_sampler;
}

struct GBufferOutput
{
    float4 albedo : SV_Target0;
    float4 normal : SV_Target1;
    float4 metallic_roughness : SV_Target2;
}

[shader("fragment")]
GBufferOutput fragmentMain(
    float4 normal_vert : TEXCOORD0,
    float2 uv : TEXCOORD1,
    float4 world_pos : TEXCOORD2,
    GraphicsPipelineData<void, FragmentData> data)
{
    GBufferOutput gbuffer_out;
    float4 base_color = getTexture2D(data.frag.base_color_map).Sample(getSampler(data.frag.base_color_map_sampler), uv);
    if(base_color.a < 0.1) discard;

    float4 normal_map_sample = getTexture2D(data.frag.normal_map).Sample(getSampler(data.frag.normal_map_sampler), uv);

    // TODO: Use normal_map_sample with tangent/bitangent when available.
    float3 world_normal = normalize(normal_vert.xyz);
    float4 packed_normal = float4(world_normal * 0.5 + 0.5, 1.0);

    float4 metallic_roughness_sample = getTexture2D(data.frag.metallic_roughness_map).Sample(
        getSampler(data.frag.metallic_roughness_map_sampler), uv);

    gbuffer_out.albedo = base_color;
    gbuffer_out.normal = packed_normal;
    gbuffer_out.metallic_roughness = metallic_roughness_sample;
    return gbuffer_out;
}
