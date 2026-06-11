
import "../../shared.slang";

struct Vertex
{
    float3 pos;
}

struct VertexData
{
    Vertex* verts;
}

// PerDrawData extends DrawIndexedIndirectCommand with user data fields
// The struct layout matches the Odin struct that uses `using cmd: gpu.Draw_Indexed_Indirect_Command`
struct PerDrawData
{
    float3 color;
    float3 pos;
    float size;
}

struct VertexOutput
{
    float4 pos : SV_Position;
    float4 color : TEXCOORD0;
}

[shader("vertex")]
VertexOutput vertexMain(uint vert_id : SV_VertexID, GraphicsPipelineData<VertexData, void, PerDrawData> data)
{
    VertexOutput vert_out;

    // vertices are shared between all draws so we use `data.vert` to access them
    // Scale vertices by size and translate by position
    vert_out.pos = float4(data.vert.verts[vert_id].pos * data.drawData.size + data.drawData.pos, 1.0);

    // color is per-draw so we use `data.drawData` to access it
    vert_out.color = float4(data.drawData.color, 1.0);

    return vert_out;
}

[shader("fragment")]
float4 fragmentMain(float4 color : TEXCOORD0) : SV_Target
{
    return color;
}
