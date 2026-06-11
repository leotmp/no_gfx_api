
import "../../shared.slang";

struct VertexData
{
    float3* positions;
    float4x4 model_to_world;
    float4x4 world_to_view;
    float4x4 view_to_proj;
}

struct VertexOutput
{
    float4 pos : SV_Position;
    float3 world_pos : TEXCOORD0;
}

[shader("vertex")]
VertexOutput vertexMain(uint vert_id : SV_VertexID, GraphicsPipelineData<VertexData> data)
{
    float4 clip_pos = float4(data.vert.positions[vert_id].xyz, 1.0);
    float4 world_pos = mul(data.vert.model_to_world, clip_pos);
    clip_pos = mul(data.vert.world_to_view, world_pos);
    clip_pos = mul(data.vert.view_to_proj, clip_pos);
    clip_pos.y = -clip_pos.y;

    VertexOutput vert_out;
    vert_out.pos = clip_pos;
    vert_out.world_pos = world_pos.xyz;
    return vert_out;
}

struct FragmentData
{
    uint cloud_texture;
    uint cloud_sampler;
    float3 camera_pos;
}

bool intersectAABB(float3 ro, float3 rd, float3 bmin, float3 bmax,
                   out float t0, out float t1)
{
    float3 inv = 1.0 / rd;

    float3 tbot = (bmin - ro) * inv;
    float3 ttop = (bmax - ro) * inv;

    float3 tmin = min(ttop, tbot);
    float3 tmax = max(ttop, tbot);

    t0 = max(max(tmin.x, tmin.y), tmin.z);
    t1 = min(min(tmax.x, tmax.y), tmax.z);

    return t1 > max(t0, 0.0);
}

[shader("fragment")]
float4 fragmentMain(VertexOutput input, GraphicsPipelineData<void, FragmentData> data) : SV_Target
{
    float3 ray_origin = input.world_pos;

    // approximate ray direction (camera to pixel)
    float3 ray_dir = normalize(input.world_pos - data.frag.camera_pos);

    // volume bounds in model space (cube centered at origin)
    float3 bmin = float3(-0.5, -0.5, -0.5);
    float3 bmax = float3( 0.5,  0.5,  0.5);

    float t0, t1;

    if (!intersectAABB(ray_origin, ray_dir, bmin, bmax, t0, t1))
    {
        return float4(0,0,0,1);
    }

    // move inside volume
    t0 = max(t0, 0.0);

    const int STEPS = 64;
    float step_size = (t1 - t0) / STEPS;

    float3 col = float3(0.2);
    float alpha = 0.0;

    float t = t0;

    // NOTE: Not physically accurate volume rendering,
    // it's just for the sake of the example.
    for (int i = 0; i < STEPS; i++)
    {
        float3 p = ray_origin + ray_dir * t;

        // Transform to [0, 1]
        float3 uvw = p + 0.5;

        // Sample density
        float density = getTexture3D(data.frag.cloud_texture)
            .SampleLevel(getSampler(data.frag.cloud_sampler), uvw, 0).r;

        // Absorption
        float d = density * step_size * 2.0;

        // Compositing
        float a = (1.0 - alpha) * d;
        alpha += a;

        if (alpha > 0.95)
            break;

        t += step_size;
    }

    return float4(col, alpha);
}
