import "../../shared.slang";

struct SceneMesh
{
    float4* pos;
    float4* normal;
    uint* indices;
}

struct SceneInstance
{
    uint mesh_idx;
}

struct Scene
{
    SceneInstance* instances;
    SceneMesh* meshes;
}

struct ComputeData
{
    uint output_texture_id;
    uint tlas_id;
    Scene scene;
    uint accum_counter;
    column_major float4x4 camera_to_world;
}

struct Ray
{
    float3 ori;
    float3 dir;
}

struct HitInfo
{
    bool hit;
    float t;
    float3 normal;
}

struct RayResult
{
    uint kind;
    float t;
    uint instance_idx;
    uint primitive_idx;
    float2 barycentrics;
    bool front_face;
    column_major float4x4 object_to_world;
    column_major float4x4 world_to_object;
}

static const float pi = 3.1415;
static uint RNG_STATE;

float4x4 mat4_from_mat3x4(float3x4 m)
{
    return float4x4(
        float4(m[0][0], m[0][1], m[0][2], m[0][3]),
        float4(m[1][0], m[1][1], m[1][2], m[1][3]),
        float4(m[2][0], m[2][1], m[2][2], m[2][3]),
        float4(0.0, 0.0, 0.0, 1.0));
}

RayResult rayquery_result(RayQuery<RAY_FLAG_NONE> rq)
{
    RayResult res;
    res.kind = rq.CommittedStatus();
    res.t = rq.CommittedRayT();
    res.instance_idx = rq.CommittedInstanceIndex();
    res.primitive_idx = rq.CommittedPrimitiveIndex();
    res.front_face = rq.CommittedTriangleFrontFace();
    res.object_to_world = mat4_from_mat3x4(rq.CommittedObjectToWorld3x4());
    res.world_to_object = mat4_from_mat3x4(rq.CommittedWorldToObject3x4());
    res.barycentrics = rq.CommittedTriangleBarycentrics();
    return res;
}

[shader("compute")]
[numthreads(8, 8, 1)]
void computeMain(uint3 global_invocation_id : SV_DispatchThreadID, uniform ComputePipelineData<ComputeData> pipeline_data)
{
    ComputeData* data = pipeline_data.data;

    float2 resolution = float2(getTextureDimensionsRW(data->output_texture_id));

    float2 uv = float2(global_invocation_id.xy) / resolution;
    float2 coord = 2.0 * uv - 1.0;
    coord = coord * tan((90.0 * pi / 180.0) / 2.0);
    coord.y = coord.y * resolution.y / resolution.x;

    float3 world_camera_pos = mul(float4(0.0, 0.0, 0.0, 1.0), transpose(data->camera_to_world)).xyz;
    float3 camera_lookat = normalize(float3(coord, 1.0));
    float3 world_camera_lookat = normalize(mul(float4(camera_lookat, 0.0), transpose(data->camera_to_world)).xyz);

    Ray camera_ray;
    camera_ray.ori = world_camera_pos;
    camera_ray.dir = world_camera_lookat;

    init_rng(uint(global_invocation_id.y * uint(resolution.x) + global_invocation_id.x), data->accum_counter);
    float3 color = pathtrace(camera_ray, data->tlas_id, data->scene);

    if (float(global_invocation_id.x) < resolution.x && float(global_invocation_id.y) < resolution.y)
    {
        if (data->accum_counter > 1)
        {
            float weight = 1.0 / float(data->accum_counter);
            float3 prev_color = loadTextureRW(data->output_texture_id, int2(global_invocation_id.xy), 0).xyz;
            color = prev_color * (1.0 - weight) + color * weight;
            color = max(color, float3(0.0, 0.0, 0.0));
        }

        imageStore(data->output_texture_id, int2(global_invocation_id.xy), float4(color, 1.0));
    }
}

float3 pathtrace(Ray start_ray, uint tlas_id, Scene scene)
{
    float3 radiance = float3(0.0, 0.0, 0.0);
    float3 weight = float3(1.0, 1.0, 1.0);
    Ray ray = start_ray;
    float3 albedo_color = float3(0.9, 0.9, 0.9);

    int max_bounces = 5;
    for (int bounce = 0; bounce <= max_bounces; bounce++)
    {
        HitInfo hit = ray_scene_intersection(ray, tlas_id, scene);
        if (!hit.hit)
        {
            float2 coords = float2(atan2(ray.dir.x, ray.dir.z) / (2.0 * pi), acos(clamp(ray.dir.y, -1.0, 1.0)) / pi);
            float3 emission = lerp(float3(0.8, 0.7, 0.1), float3(0.1, 0.2, 0.8), float3(coords.y)) * 5.0;
            radiance += emission * weight;
            break;
        }

        float3 outgoing = -ray.dir;
        float2 rnd = random_vec2();
        float3 incoming = sample_matte(albedo_color, hit.normal, outgoing, rnd);
        if (all(incoming == float3(0.0, 0.0, 0.0))) { break; }

        float prob = sample_matte_pdf(albedo_color, hit.normal, outgoing, incoming);
        weight = weight * eval_matte(albedo_color, hit.normal, outgoing, incoming) / prob;

        ray.ori = ray.ori + ray.dir * hit.t;
        ray.dir = incoming;

        if (all(weight == float3(0.0, 0.0, 0.0)) || !is_finite(weight)) { break; }

        if (bounce > 3)
        {
            float survive_prob = min(0.99, max(weight.x, max(weight.y, weight.z)));
            if (random_f32() >= survive_prob) { break; }
            weight = weight / survive_prob;
        }
    }

    return radiance;
}

HitInfo ray_scene_intersection(Ray ray, uint tlas_id, Scene scene)
{
    static const uint Ray_Flags_Opaque = 1;
    static const uint Ray_Flags_Terminate_On_First_Hit = 4;
    static const uint Ray_Flags_Skip_Closest_Hit_Shader = 8;
    static const uint Ray_Result_Kind_Miss = 0;
    static const uint Ray_Result_Kind_Hit_Mesh = 1;
    static const uint Ray_Result_Kind_Hit_AABB = 2;

    HitInfo hit_info;

    uint ray_flags = Ray_Flags_Opaque;
    uint cull_mask = 0xFF;

    RayDesc ray_desc;
    ray_desc.Origin = ray.ori;
    ray_desc.Direction = ray.dir;
    ray_desc.TMin = 0.001;
    ray_desc.TMax = 1000000000.0;

    RayQuery<RAY_FLAG_NONE> rq;
    rq.TraceRayInline(getBVH(tlas_id), ray_flags, cull_mask, ray_desc);

    rq.Proceed();

    RayResult hit = rayquery_result(rq);
    if (hit.kind != Ray_Result_Kind_Hit_Mesh)
    {
        hit_info.hit = false;
        return hit_info;
    }

    SceneInstance instance = scene.instances[hit.instance_idx];
    SceneMesh mesh = scene.meshes[instance.mesh_idx];
    uint base_idx = hit.primitive_idx * 3;

    float w = 1.0 - hit.barycentrics.x - hit.barycentrics.y;
    float4 n0 = mesh.normal[mesh.indices[base_idx + 0]];
    float4 n1 = mesh.normal[mesh.indices[base_idx + 1]];
    float4 n2 = mesh.normal[mesh.indices[base_idx + 2]];
    float4 normal = normalize(n0 * w + n1 * hit.barycentrics.x + n2 * hit.barycentrics.y);
    if (hit.front_face) normal *= -1.0;
    float4 world_normal = normalize(mul(float4(normal.xyz, 0.0), hit.world_to_object));

    hit_info.hit = true;
    hit_info.t = hit.t;
    hit_info.normal = world_normal.xyz;
    return hit_info;
}

uint hash_u32(uint seed)
{
    uint x = seed;
    x = x ^ (x >> 17);
    x = x * 0xed5ad4bb;
    x = x ^ (x >> 11);
    x = x * 0xac4c1b51;
    x = x ^ (x >> 15);
    x = x * 0x31848bab;
    x = x ^ (x >> 14);
    return x;
}

void init_rng(uint global_id, uint accum_counter)
{
    RNG_STATE = hash_u32((global_id * 19349663) ^ (accum_counter * 83492791));
}

uint random_u32()
{
    RNG_STATE = RNG_STATE * 747796405 + 2891336453;
    uint result = ((RNG_STATE >> ((RNG_STATE >> 28) + 4)) ^ RNG_STATE) * 277803737;
    result = (result >> 22) ^ result;
    return result;
}

float random_f32()
{
    RNG_STATE = RNG_STATE * 747796405 + 2891336453;
    uint result = ((RNG_STATE >> ((RNG_STATE >> 28) + 4)) ^ RNG_STATE) * 277803737;
    result = (result >> 22) ^ result;
    return float(result) / 4294967295.0;
}

float2 random_vec2()
{
    float rnd0 = random_f32();
    float rnd1 = random_f32();
    return float2(rnd0, rnd1);
}

float copysignf(float mag, float sgn)
{
    return sgn < 0.0 ? -mag : mag;
}

float4x4 basis_fromz(float3 v)
{
    float3 z = normalize(v);
    float sign = copysignf(1.0, z.z);
    float a = -1.0 / (sign + z.z);
    float b = z.x * z.y * a;
    float3 x = float3(1.0 + sign * z.x * z.x * a, sign * b, -sign * z.x);
    float3 y = float3(b, sign + z.y * z.y * a, -z.y);
    return float4x4(float4(x, 0.0), float4(y, 0.0), float4(z, 0.0), float4(0.0, 0.0, 0.0, 0.0));
}

float3 sample_hemisphere_cos(float3 normal, float2 ruv)
{
    float z = sqrt(ruv.y);
    float r = sqrt(1.0 - z * z);
    float phi = 2.0 * pi * ruv.x;
    float3 local_direction = float3(r * cos(phi), r * sin(phi), z);
    return normalize(mul(float4(local_direction, 0.0), basis_fromz(normal)).xyz);
}

float sample_hemisphere_cos_pdf(float3 normal, float3 direction)
{
    float cosw = dot(normal, direction);
    return cosw <= 0.0 ? 0.0 : cosw / pi;
}

float3 sample_matte(float3 color, float3 normal, float3 outgoing, float2 rn)
{
    return sample_hemisphere_cos(normal, rn);
}

float3 eval_matte(float3 color, float3 normal, float3 outgoing, float3 incoming)
{
    return color / pi * abs(dot(normal, incoming));
}

float sample_matte_pdf(float3 color, float3 normal, float3 outgoing, float3 incoming)
{
    return sample_hemisphere_cos_pdf(normal, incoming);
}

bool is_finite(float3 v)
{
    bool is_x_finite = (asint(v.x) & 0x7F800000) != 0x7F800000;
    bool is_y_finite = (asint(v.y) & 0x7F800000) != 0x7F800000;
    bool is_z_finite = (asint(v.z) & 0x7F800000) != 0x7F800000;
    return is_x_finite && is_y_finite && is_z_finite;
}
