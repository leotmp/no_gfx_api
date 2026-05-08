// Standard no_gfx_api bindings, you can copy this into your project

module shared;

[[vk::binding(0, 0)]] public Texture2D textureHeap[];
[[vk::binding(0, 1)]] public RWTexture2D<float4> textureHeapRW[];
[[vk::binding(0, 2)]] public SamplerState samplerHeap[];
[[vk::binding(0, 3)]] RaytracingAccelerationStructure bvhHeap[];

// Push constant blocks - different structures for graphics vs compute shaders
public struct __PushConstants_Graphics
{
    public uint64_t vertData;
    public uint64_t fragData;
    public uint64_t indirectData;
};

public struct __PushConstants_Compute
{
    public uint64_t computeData;
};

[[vk::push_constant]] __PushConstants_Graphics __push_graphics;
[[vk::push_constant]] __PushConstants_Compute __push_compute;

// Standard Vulkan indirect draw command structure
public struct DrawIndexedIndirectCommand
{
    uint indexCount;
    uint instanceCount;
    uint firstIndex;
    int  vertexOffset;
    uint firstInstance;
};

struct __DrawCommand<TUserData>
{
    DrawIndexedIndirectCommand cmd;
    TUserData data;
};

in int draw_id : SV_DrawIndex;

public struct GraphicsPipelineData<TVertexData = void, TFragmentData = void, TDrawData = void> {
    public property vert : TVertexData* {
        [ForceInline]
        get { return (TVertexData*)__push_graphics.vertData; }
    }

    public property frag : TFragmentData* {
        [ForceInline]
        get { return (TFragmentData*)__push_graphics.fragData; }
    }

    public property drawData : TDrawData {
        [ForceInline]
        get {
            __DrawCommand<TDrawData>* buffer = (__DrawCommand<TDrawData>*)__push_graphics.indirectData;
            return buffer[draw_id].data;
        }
    }

    public property drawCmd : DrawIndexedIndirectCommand {
        [ForceInline]
        get {
            __DrawCommand<TDrawData>* buffer = (__DrawCommand<TDrawData>*)__push_graphics.indirectData;
            return buffer[draw_id].cmd;
        }
    }
}

public struct ComputePipelineData<TData = void> {
    public property data : TData* {
        [ForceInline]
        get { return (TData*)__push_compute.computeData; }
    }
}

// Sampling helpers
public float4 sampleTexture(uint textureIndex, uint samplerIndex, float2 uv)
{
    return textureHeap[NonUniformResourceIndex(textureIndex)]
        .Sample(samplerHeap[NonUniformResourceIndex(samplerIndex)], uv);
}

public float4 sampleTextureLevel(uint textureIndex, uint samplerIndex, float2 uv, float lod)
{
    return textureHeap[NonUniformResourceIndex(textureIndex)]
        .SampleLevel(samplerHeap[NonUniformResourceIndex(samplerIndex)], uv, lod);
}

public float4 sampleTextureGrad(uint textureIndex, uint samplerIndex, float2 uv, float2 ddx, float2 ddy)
{
    return textureHeap[NonUniformResourceIndex(textureIndex)]
        .SampleGrad(samplerHeap[NonUniformResourceIndex(samplerIndex)], uv, ddx, ddy);
}

public float4 loadTexture(uint textureIndex, int2 coord, int mipLevel)
{
    return textureHeap[NonUniformResourceIndex(textureIndex)].Load(int3(coord, mipLevel));
}

public float4 loadTextureRW(uint textureIndex, int2 coord, int mipLevel)
{
    return textureHeapRW[NonUniformResourceIndex(textureIndex)][coord];
}

public uint2 getTextureDimensions(uint textureIndex, uint samplerIndex, int lod)
{
    uint width;
    uint height;
    uint mip_levels;
    textureHeap[NonUniformResourceIndex(textureIndex)]
        .GetDimensions(lod, width, height, mip_levels);
    return uint2(width, height);
}

public uint2 getTextureDimensionsRW(uint textureIndex)
{
    uint width;
    uint height;
    textureHeapRW[NonUniformResourceIndex(textureIndex)]
        .GetDimensions(width, height);
    return uint2(width, height);
}

// Image store helper for writing to RWTexture2D
public void imageStore(uint textureIndex, int2 coord, float4 color)
{
    textureHeapRW[NonUniformResourceIndex(textureIndex)][coord] = color;
}

public RaytracingAccelerationStructure getBVH(uint bvhIndex)
{
    return bvhHeap[NonUniformResourceIndex(bvhIndex)];
}