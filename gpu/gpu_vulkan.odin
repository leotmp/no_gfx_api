
package gpu

import "core:slice"
import "core:log"
import "base:runtime"
import vmem "core:mem/virtual"
import "core:mem"
import "core:sync"
import rbt "core:container/rbtree"
import "core:dynlib"

import vk "vendor:vulkan"
import "vma"

Max_Textures :: 65535

@(private="file")
Graphics_Shader_Push_Constants :: struct #packed {
    vert_data: rawptr,
    frag_data: rawptr,
    indirect_data: rawptr,
}

@(private="file")
Compute_Shader_Push_Constants :: struct #packed {
    compute_data: rawptr,
}

@(private="file")
GPU_Alloc_Meta :: struct #all_or_none
{
    buf_handle: vk.Buffer,
    allocation: vma.Allocation,
    device_address: vk.DeviceAddress,
    align: u32,
    buf_size: vk.DeviceSize,
    alloc_type: Allocation_Type,
}

@(private="file")
Alloc_Range :: struct
{
    ptr: u64,
    size: u32,
}

@(private="file")
Timeline :: struct
{
    sem: vk.Semaphore,
    val: u64,
    recording: bool,
}

@(private="file")
Context :: struct
{
    instance: vk.Instance,
    debug_messenger: vk.DebugUtilsMessengerEXT,
    surface: vk.SurfaceKHR,
    phys_device: vk.PhysicalDevice,
    device: vk.Device,
    vma_allocator: vma.Allocator,

    // Allocations
    gpu_allocs: [dynamic]GPU_Alloc_Meta,
    // TODO: freelist of gpu allocs
    cpu_ptr_to_alloc: map[rawptr]u32,  // Each entry has an index to its corresponding GPU allocation
    gpu_ptr_to_alloc: map[rawptr]u32,  // From base GPU allocation pointer to metadata
    alloc_tree: rbt.Tree(Alloc_Range, u32),

    // Common resources
    textures_desc_layout: vk.DescriptorSetLayout,
    textures_rw_desc_layout: vk.DescriptorSetLayout,
    samplers_desc_layout: vk.DescriptorSetLayout,
    data_desc_layout: vk.DescriptorSetLayout,
    indirect_data_desc_layout: vk.DescriptorSetLayout,
    common_pipeline_layout_graphics: vk.PipelineLayout,
    common_pipeline_layout_compute: vk.PipelineLayout,

    // Resource pools
    queues: [len(Queue_Type) + 1]Queue_Info,  // Reserve slot 0 for invalid queue.
    textures: Pool(Texture_Info),
    samplers: [dynamic]Sampler_Info,  // Samplers are interned but have permanent lifetime

    // Swapchain
    swapchain: Swapchain,
    swapchain_image_idx: u32,
    frames_in_flight: u32,

    // Descriptor sizes
    texture_desc_size: u32,
    texture_rw_desc_size: u32,
    sampler_desc_size: u32,

    // Shader metadata
    current_workgroup_size: map[Shader][3]u32,  // Maps shader to [x, y, z] work group size
    cmd_buf_compute_shader: map[Command_Buffer]Shader,  // Tracks current compute shader per command buffer

    lock: sync.Benaphore, // Ensures thread-safe access to ctx and VK operations
    tls_contexts: [dynamic]^Thread_Local_Context,
}

@(private="file")
Thread_Local_Context :: struct
{
    cmd_pools: [Queue_Type]vk.CommandPool,
    cmd_bufs: [Queue_Type][10]vk.CommandBuffer,
    cmd_bufs_timelines: [Queue_Type][10]Timeline,
}

@(private="file")
Key :: struct
{
    idx: u64
}
#assert(size_of(Key) == 8)

@(private="file")
Texture_Info :: struct
{
    handle: vk.Image,
    views: [dynamic]Image_View_Info
}

@(private="file")
Image_View_Info :: struct
{
    info: vk.ImageViewCreateInfo,
    view: vk.ImageView,
}

@(private="file")
Sampler_Info :: struct
{
    info: vk.SamplerCreateInfo,
    sampler: vk.Sampler,
}

@(private="file")
Queue_Info :: struct
{
    handle: vk.Queue,
    family_idx: u32,
    queue_idx: u32,
    queue_type: Queue_Type,
}

// Initialization

@(private="file")
ctx: Context

@(private="file")
// Allow multiple init/cleanup pairs in tests.
init_ref_count: i32

@(private="file")
// Vulkan global proc addresses only need loading once per process.
vk_globals_loaded: bool

@(private="file") @(thread_local)
tls_ctx: ^Thread_Local_Context

@(private="file")
vk_logger: log.Logger

_init :: proc()
{
    if init_ref_count > 0 {
        init_ref_count += 1
        return
    }
    init_ref_count = 1

    init_scratch_arenas()

    scratch, _ := acquire_scratch()

    // Load vulkan function pointers
    if !vk_globals_loaded {
        vk.load_proc_addresses_global(cast(rawptr) get_instance_proc_address)
        vk_globals_loaded = true
    }

    vk_logger = context.logger

    // Create instance
    {
        when ODIN_DEBUG
        {
            layers := []cstring {
                "VK_LAYER_KHRONOS_validation",
            }
        }
        else
        {
            layers := []cstring {}
        }

        required_extensions := make([dynamic]cstring, allocator = scratch)
        append(&required_extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
        append(&required_extensions, vk.KHR_SURFACE_EXTENSION_NAME)

        optional_extensions := make([dynamic]cstring, allocator = scratch)
        append(&optional_extensions, "VK_KHR_win32_surface")
        append(&optional_extensions, "VK_KHR_wayland_surface")
        append(&optional_extensions, "VK_KHR_xlib_surface")

        for opt in optional_extensions {
            if supports_instance_extension(opt) {
                append(&required_extensions, opt)
            }
        }

        debug_messenger_ci := vk.DebugUtilsMessengerCreateInfoEXT {
            sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
            messageSeverity = { .WARNING, .ERROR },
            messageType = { .VALIDATION, .PERFORMANCE },
            pfnUserCallback = vk_debug_callback
        }


        when ODIN_DEBUG
        {
            validation_features := []vk.ValidationFeatureEnableEXT {
                // .GPU_ASSISTED,
                // .GPU_ASSISTED_RESERVE_BINDING_SLOT,
                .SYNCHRONIZATION_VALIDATION,
            }
        }
        else
        {
            validation_features := []vk.ValidationFeatureEnableEXT {}
        }

        next: rawptr
        next = &debug_messenger_ci
        next = &vk.ValidationFeaturesEXT {
            sType = .VALIDATION_FEATURES_EXT,
            pNext = next,
            enabledValidationFeatureCount = u32(len(validation_features)),
            pEnabledValidationFeatures = raw_data(validation_features),
        }

        vk_check(vk.CreateInstance(&{
            sType = .INSTANCE_CREATE_INFO,
            pApplicationInfo = &{
                sType = .APPLICATION_INFO,
                apiVersion = vk.API_VERSION_1_3,
            },
            enabledLayerCount = u32(len(layers)),
            ppEnabledLayerNames = raw_data(layers),
            enabledExtensionCount = u32(len(required_extensions)),
            ppEnabledExtensionNames = raw_data(required_extensions),
            pNext = next,
        }, nil, &ctx.instance))

        vk.load_proc_addresses_instance(ctx.instance)
        assert(vk.DestroyInstance != nil, "Failed to load Vulkan instance API")

        vk_check(vk.CreateDebugUtilsMessengerEXT(ctx.instance, &debug_messenger_ci, nil, &ctx.debug_messenger))
    }

    // Physical device
    phys_device_count: u32
    vk_check(vk.EnumeratePhysicalDevices(ctx.instance, &phys_device_count, nil))
    if phys_device_count == 0 do fatal_error("Did not find any GPUs!")
    phys_devices := make([]vk.PhysicalDevice, phys_device_count, allocator = scratch)
    vk_check(vk.EnumeratePhysicalDevices(ctx.instance, &phys_device_count, raw_data(phys_devices)))

    found := false
    best_score: u32
    device_loop: for candidate, i in phys_devices
    {
        score: u32

        properties := vk.PhysicalDeviceProperties2 { sType = .PHYSICAL_DEVICE_PROPERTIES_2 }
        features := vk.PhysicalDeviceFeatures2 { sType = .PHYSICAL_DEVICE_FEATURES_2 }
        vk.GetPhysicalDeviceProperties2(candidate, &properties);
        vk.GetPhysicalDeviceFeatures2(candidate, &features);

        #partial switch properties.properties.deviceType
        {
            case .DISCRETE_GPU:   score += 1000
            case .VIRTUAL_GPU:    score += 100
            case .INTEGRATED_GPU: score += 10
            case: {}
        }

        if best_score < score
        {
            best_score = score
            ctx.phys_device = candidate
            found = true
        }
    }

    if !found do fatal_error("Could not find suitable GPU.")

    // Check descriptor sizes
    props := vk.PhysicalDeviceDescriptorBufferPropertiesEXT {
        sType = .PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_PROPERTIES_EXT
    };
    props2 := vk.PhysicalDeviceProperties2 {
        sType = .PHYSICAL_DEVICE_PROPERTIES_2,
        pNext = &props
    };
    vk.GetPhysicalDeviceProperties2(ctx.phys_device, &props2)
    ensure(props.storageImageDescriptorSize <= 32, "Unexpected storage image descriptor size.")
    ensure(props.sampledImageDescriptorSize <= 32, "Unexpected sampled texture descriptor size.")
    ensure(props.samplerDescriptorSize <= 16, "Unexpected sampler descriptor size.")
    ctx.texture_desc_size = u32(props.sampledImageDescriptorSize)
    ctx.texture_rw_desc_size = u32(props.storageImageDescriptorSize)
    ctx.sampler_desc_size = u32(props.samplerDescriptorSize)

    // Queues create info
    queue_create_infos: [dynamic]vk.DeviceQueueCreateInfo
    defer delete(queue_create_infos)
    {
        queue_families: [3]u32  // Main, Compute, Transfer
        queue_indices: [3]u32
        queue_count: [3]u32 = { 1, 1, 1 }
        is_subsumed: [3]bool
        queue_families[0] = find_queue_family(true, true, true)
        queue_families[1] = find_queue_family(graphics = false, compute = true, transfer = true)
        queue_families[2] = find_queue_family(graphics = false, compute = false, transfer = true)
        for i := 1; i < len(queue_families); i += 1
        {
            for j := 0; j < i; j += 1
            {
                if queue_families[i] == queue_families[j]
                {
                    assert(!is_subsumed[j])
                    queue_indices[i] = queue_indices[j] + 1
                    is_subsumed[i] = true
                    queue_count[j] += 1
                    break
                }
            }
        }

        max_queue_count := max(queue_count[0], queue_count[1], queue_count[2])
        queue_priorities := make([]f32, max_queue_count, allocator = scratch)  // Filled in with zeros

        for i in 0..<len(queue_families)
        {
            if is_subsumed[i] do continue

            append(&queue_create_infos, vk.DeviceQueueCreateInfo {
                sType = .DEVICE_QUEUE_CREATE_INFO,
                queueFamilyIndex = queue_families[i],
                queueCount = queue_count[i],
                pQueuePriorities = raw_data(queue_priorities)
            })
        }

        for i in 0..<3 {
            ctx.queues[i+1] = { handle = nil, family_idx = queue_families[i], queue_idx = queue_indices[i], queue_type = cast(Queue_Type) i }
        }
    }

    // Device
    device_extensions := []cstring {
        vk.KHR_SWAPCHAIN_EXTENSION_NAME,
        vk.EXT_SHADER_OBJECT_EXTENSION_NAME,
        vk.EXT_DESCRIPTOR_BUFFER_EXTENSION_NAME,
        vk.KHR_DRAW_INDIRECT_COUNT_EXTENSION_NAME,
    }

    next: rawptr
    next = &vk.PhysicalDeviceVulkan12Features {
        sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        pNext = next,
        runtimeDescriptorArray = true,
        shaderSampledImageArrayNonUniformIndexing = true,
        timelineSemaphore = true,
        bufferDeviceAddress = true,
        drawIndirectCount = true,
        scalarBlockLayout = true,
    }
    next = &vk.PhysicalDeviceVulkan11Features {
        sType = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
        pNext = next,
        shaderDrawParameters = true,
    }
    next = &vk.PhysicalDeviceVulkan13Features {
        sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        pNext = next,
        dynamicRendering = true,
        synchronization2 = true,
    }
    next = &vk.PhysicalDeviceDescriptorBufferFeaturesEXT {
        sType = .PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_FEATURES_EXT,
        pNext = next,
        descriptorBuffer = true,
    }
    next = &vk.PhysicalDeviceShaderObjectFeaturesEXT {
        sType = .PHYSICAL_DEVICE_SHADER_OBJECT_FEATURES_EXT,
        pNext = next,
        shaderObject = true,
    }
    next = &vk.PhysicalDeviceDepthClipEnableFeaturesEXT {
        sType = .PHYSICAL_DEVICE_DEPTH_CLIP_ENABLE_FEATURES_EXT,
        pNext = next,
        depthClipEnable = true,
    }
    next = &vk.PhysicalDeviceFeatures2 {
        sType = .PHYSICAL_DEVICE_FEATURES_2,
        pNext = next,
        features = {
            shaderInt64 = true,
            vertexPipelineStoresAndAtomics = true,
        }
    }

    device_ci := vk.DeviceCreateInfo {
        sType = .DEVICE_CREATE_INFO,
        pNext = next,
        queueCreateInfoCount = u32(len(queue_create_infos)),
        pQueueCreateInfos = raw_data(queue_create_infos),
        enabledExtensionCount = u32(len(device_extensions)),
        ppEnabledExtensionNames = raw_data(device_extensions),
    }
    vk_check(vk.CreateDevice(ctx.phys_device, &device_ci, nil, &ctx.device))

    vk.load_proc_addresses_device(ctx.device)
    if vk.BeginCommandBuffer == nil do fatal_error("Failed to load Vulkan device API")

    // Common resources
    {
        {
            layout_ci := vk.DescriptorSetLayoutCreateInfo {
                sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
                flags = { .DESCRIPTOR_BUFFER_EXT },
                bindingCount = 1,
                pBindings = &vk.DescriptorSetLayoutBinding {
                    binding = 0,
                    descriptorType = .SAMPLED_IMAGE,
                    descriptorCount = Max_Textures,
                    stageFlags = { .VERTEX, .FRAGMENT, .COMPUTE },
                },
            }
            vk_check(vk.CreateDescriptorSetLayout(ctx.device, &layout_ci, nil, &ctx.textures_desc_layout))
        }
        {
            layout_ci := vk.DescriptorSetLayoutCreateInfo {
                sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
                flags = { .DESCRIPTOR_BUFFER_EXT },
                bindingCount = 1,
                pBindings = &vk.DescriptorSetLayoutBinding {
                    binding = 0,
                    descriptorType = .STORAGE_IMAGE,
                    descriptorCount = Max_Textures,
                    stageFlags = { .VERTEX, .FRAGMENT, .COMPUTE },
                },
            }
            vk_check(vk.CreateDescriptorSetLayout(ctx.device, &layout_ci, nil, &ctx.textures_rw_desc_layout))
        }
        {
            layout_ci := vk.DescriptorSetLayoutCreateInfo {
                sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
                flags = { .DESCRIPTOR_BUFFER_EXT },
                bindingCount = 1,
                pBindings = &vk.DescriptorSetLayoutBinding {
                    binding = 0,
                    descriptorType = .SAMPLER,
                    descriptorCount = Max_Textures,
                    stageFlags = { .VERTEX, .FRAGMENT, .COMPUTE },
                },
            }
            vk_check(vk.CreateDescriptorSetLayout(ctx.device, &layout_ci, nil, &ctx.samplers_desc_layout))
        }
        {
            layout_ci := vk.DescriptorSetLayoutCreateInfo {
                sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
                flags = { .DESCRIPTOR_BUFFER_EXT },
                bindingCount = 1,
                pBindings = &vk.DescriptorSetLayoutBinding {
                    binding = 0,
                    descriptorType = .STORAGE_BUFFER,
                    descriptorCount = 1,
                    stageFlags = { .VERTEX, .FRAGMENT, .COMPUTE },
                },
            }
            vk_check(vk.CreateDescriptorSetLayout(ctx.device, &layout_ci, nil, &ctx.data_desc_layout))
        }
        {
            layout_ci := vk.DescriptorSetLayoutCreateInfo {
                sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
                flags = { .DESCRIPTOR_BUFFER_EXT },
                bindingCount = 1,
                pBindings = &vk.DescriptorSetLayoutBinding {
                    binding = 0,
                    descriptorType = .STORAGE_BUFFER,
                    descriptorCount = 1,
                    stageFlags = { .VERTEX, .FRAGMENT, .COMPUTE },
                },
            }
            vk_check(vk.CreateDescriptorSetLayout(ctx.device, &layout_ci, nil, &ctx.indirect_data_desc_layout))
        }

        desc_layouts := []vk.DescriptorSetLayout {
            ctx.textures_desc_layout,
            ctx.textures_rw_desc_layout,
            ctx.samplers_desc_layout,
            ctx.data_desc_layout,
            ctx.indirect_data_desc_layout,
        }

        // Graphics pipeline layout
        {
            push_constant_ranges := []vk.PushConstantRange {
                {
                    stageFlags = { .VERTEX, .FRAGMENT },
                    size = size_of(Graphics_Shader_Push_Constants),
                }
            }
            pipeline_layout_ci := vk.PipelineLayoutCreateInfo {
                sType = .PIPELINE_LAYOUT_CREATE_INFO,
                pushConstantRangeCount = u32(len(push_constant_ranges)),
                pPushConstantRanges = raw_data(push_constant_ranges),
                setLayoutCount = u32(len(desc_layouts)),
                pSetLayouts = raw_data(desc_layouts),
            }
            vk_check(vk.CreatePipelineLayout(ctx.device, &pipeline_layout_ci, nil, &ctx.common_pipeline_layout_graphics))
        }

        // Compute pipeline layout
        {
            push_constant_ranges := []vk.PushConstantRange {
                {
                    stageFlags = { .COMPUTE },
                    size = size_of(Compute_Shader_Push_Constants),
                }
            }
            pipeline_layout_ci := vk.PipelineLayoutCreateInfo {
                sType = .PIPELINE_LAYOUT_CREATE_INFO,
                pushConstantRangeCount = u32(len(push_constant_ranges)),
                pPushConstantRanges = raw_data(push_constant_ranges),
                setLayoutCount = u32(len(desc_layouts)),
                pSetLayouts = raw_data(desc_layouts),
            }
            vk_check(vk.CreatePipelineLayout(ctx.device, &pipeline_layout_ci, nil, &ctx.common_pipeline_layout_compute))
        }
    }

    // Resource pools
    // NOTE: Reserve slot 0 for all resources as key 0 is invalid.
    pool_append(&ctx.textures, Texture_Info {})

    // Tree init
    rbt.init_cmp(&ctx.alloc_tree, proc(range_a: Alloc_Range, range_b: Alloc_Range) -> rbt.Ordering {
        // NOTE: When searching, Alloc_Range { ptr, 0 } is used.
        diff_ba := int(range_b.ptr) - int(range_a.ptr)
        diff_ab := int(range_a.ptr) - int(range_b.ptr)
        if diff_ba >= 0 && diff_ba < int(range_a.size) {
            return .Equal
        } else if diff_ab >= 0 && diff_ab < int(range_b.size) {
            return .Equal
        } else if range_a.ptr < range_b.ptr {
            return .Less
        } else {
            return .Greater
        }
    })

    // VMA allocator
    vma_vulkan_procs := vma.create_vulkan_functions()
    ok_vma := vma.create_allocator({
        flags = { .Buffer_Device_Address },
        instance = ctx.instance,
        vulkan_api_version = 1003000,  // 1.3
        physical_device = ctx.phys_device,
        device = ctx.device,
        vulkan_functions = &vma_vulkan_procs,
    }, &ctx.vma_allocator)
    assert(ok_vma == .SUCCESS)

    // From GLFW: https://github.com/glfw/glfw
    get_instance_proc_address :: proc "c"(p: rawptr, name: cstring) -> rawptr
    {
        context = runtime.default_context()

        vk_dll_path: string
        when ODIN_OS == .Windows {
            vk_dll_path = "vulkan-1.dll"
        } else when ODIN_OS == .OpenBSD || ODIN_OS == .NetBSD {
            vk_dll_path = "libvulkan.so"
        } else when ODIN_OS == .Linux {
            vk_dll_path = "libvulkan.so.1"
        } else do #panic("OS not supported!")

        @(static) vk_dll: dynlib.Library
        if vk_dll == nil
        {
            did_load: bool
            vk_dll, did_load = dynlib.load_library(vk_dll_path, allocator = context.allocator)
            vk.GetInstanceProcAddr = auto_cast dynlib.symbol_address(vk_dll, "vkGetInstanceProcAddr", allocator = context.allocator)
            assert(did_load)
        }

        // NOTE: Vulkan 1.0 and 1.1 vkGetInstanceProcAddr cannot return itself
        if name == "vkGetInstanceProcAddr" do return auto_cast vk.GetInstanceProcAddr

        addr := vk.GetInstanceProcAddr(auto_cast p, name);
        if addr == nil {
            addr = auto_cast dynlib.symbol_address(vk_dll, string(name), allocator = context.allocator)
        }
        return auto_cast addr
    }

    supports_instance_extension :: proc(name: cstring) -> bool
    {
        count: u32;
        vk_check(vk.EnumerateInstanceExtensionProperties(nil, &count, nil))

        available_extensions := make([]vk.ExtensionProperties, count)
        defer delete(available_extensions)
        vk_check(vk.EnumerateInstanceExtensionProperties(nil, &count, raw_data(available_extensions)))

        for &available in available_extensions {
            if name == cstring(&available.extensionName[0]) do return true
        }

        return false
    }
}

@(private="file")
tls_init :: proc()
{
    // Only initialize if not already initialized
    if tls_ctx != nil do return

    tls_ctx = new(Thread_Local_Context)
    
    
    for type in Queue_Type
    {
        queue := get_queue(type)
        cmd_pool_ci := vk.CommandPoolCreateInfo {
            sType = .COMMAND_POOL_CREATE_INFO,
            queueFamilyIndex = get_resource(queue, &ctx.queues).family_idx,
            flags = { .TRANSIENT, .RESET_COMMAND_BUFFER }
        }
        vk_check(vk.CreateCommandPool(ctx.device, &cmd_pool_ci, nil, &tls_ctx.cmd_pools[type]))
    }

    for type in Queue_Type
    {
        cmd_buf_ai := vk.CommandBufferAllocateInfo {
            sType = .COMMAND_BUFFER_ALLOCATE_INFO,
            commandPool = tls_ctx.cmd_pools[type],
            level = .PRIMARY,
            commandBufferCount = len(tls_ctx.cmd_bufs[type]),
        }
        vk_check(vk.AllocateCommandBuffers(ctx.device, &cmd_buf_ai, &tls_ctx.cmd_bufs[type][0]))

    }

    for type in Queue_Type
    {
        for &timeline in tls_ctx.cmd_bufs_timelines[type]
        {
            next_sem: rawptr
            next_sem = &vk.SemaphoreTypeCreateInfo {
                sType = .SEMAPHORE_TYPE_CREATE_INFO,
                pNext = next_sem,
                semaphoreType = .TIMELINE,
                initialValue = 0,
            }
            sem_ci := vk.SemaphoreCreateInfo {
                sType = .SEMAPHORE_CREATE_INFO,
                pNext = next_sem
            }
            vk_check(vk.CreateSemaphore(ctx.device, &sem_ci, nil, &timeline.sem))
        }
    }

    if sync.guard(&ctx.lock) do append(&ctx.tls_contexts, tls_ctx)
}

_cleanup :: proc()
{
    if init_ref_count <= 0 {
        return
    }
    init_ref_count -= 1
    if init_ref_count > 0 {
        return
    }

    sync.guard(&ctx.lock)

    // Cleanup all TLS contexts
    for tls_context in ctx.tls_contexts {
        if tls_context != nil {
            for type in Queue_Type {
                vk.DestroyCommandPool(ctx.device, tls_context.cmd_pools[type], nil)
            }
            for type in Queue_Type {
                for timeline in tls_context.cmd_bufs_timelines[type] {
                    vk.DestroySemaphore(ctx.device, timeline.sem, nil)
                }
            }
            free(tls_context)
        }
    }
    delete(ctx.tls_contexts)
    ctx.tls_contexts = {}
    // Ensure TLS contexts are rebuilt after cleanup.
    tls_ctx = nil

    for &sampler in ctx.samplers {
        vk.DestroySampler(ctx.device, sampler.sampler, nil)
    }
    delete(ctx.samplers)
    ctx.samplers = {}

    delete(ctx.current_workgroup_size)
    ctx.current_workgroup_size = {}
    delete(ctx.cmd_buf_compute_shader)
    ctx.cmd_buf_compute_shader = {}

    destroy_swapchain(&ctx.swapchain)
    pool_destroy(&ctx.textures)

    vk.DestroyDescriptorSetLayout(ctx.device, ctx.textures_desc_layout, nil)
    vk.DestroyDescriptorSetLayout(ctx.device, ctx.textures_rw_desc_layout, nil)
    vk.DestroyDescriptorSetLayout(ctx.device, ctx.samplers_desc_layout, nil)
    vk.DestroyDescriptorSetLayout(ctx.device, ctx.data_desc_layout, nil)
    vk.DestroyDescriptorSetLayout(ctx.device, ctx.indirect_data_desc_layout, nil)
    vk.DestroyPipelineLayout(ctx.device, ctx.common_pipeline_layout_graphics, nil)
    vk.DestroyPipelineLayout(ctx.device, ctx.common_pipeline_layout_compute, nil)

    // Ensure any outstanding allocations are released before tearing down VMA.
    for &meta in ctx.gpu_allocs {
        if meta.buf_handle != {} {
            vma.destroy_buffer(ctx.vma_allocator, meta.buf_handle, meta.allocation)
        }
    }
    delete(ctx.gpu_allocs)
    ctx.gpu_allocs = {}
    delete(ctx.cpu_ptr_to_alloc)
    ctx.cpu_ptr_to_alloc = {}
    delete(ctx.gpu_ptr_to_alloc)
    ctx.gpu_ptr_to_alloc = {}
    ctx.alloc_tree = {}

    vma.destroy_allocator(ctx.vma_allocator)

    vk.DestroyDevice(ctx.device, nil)
}

_wait_idle :: proc()
{
    sync.guard(&ctx.lock)
    vk.DeviceWaitIdle(ctx.device)
}

_swapchain_init :: proc(surface: vk.SurfaceKHR, init_size: [2]u32, frames_in_flight: u32)
{
    if sync.guard(&ctx.lock) {
        ctx.frames_in_flight = frames_in_flight
        ctx.surface = surface
    }

    // NOTE: surface_caps.currentExtent could be max(u32)!!!
    surface_caps: vk.SurfaceCapabilitiesKHR
    vk_check(vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(ctx.phys_device, ctx.surface, &surface_caps))
    extent := surface_caps.currentExtent
    if extent.width == max(u32) || extent.height == max(u32) {
        extent.width = init_size[0]
        extent.height = init_size[1]
    }
    assert(extent.width != max(u32) && extent.height != max(u32))

    ctx.swapchain = create_swapchain(max(extent.width, 1), max(extent.height, 1), ctx.frames_in_flight)
}

_swapchain_resize :: proc(size: [2]u32)
{
    queue_wait_idle(get_queue(.Main))
    recreate_swapchain(size)
}

@(private="file")
recreate_swapchain :: proc(size: [2]u32)
{
    sync.guard(&ctx.lock)
    destroy_swapchain(&ctx.swapchain)

    // NOTE: surface_caps.currentExtent could be max(u32)!!!
    surface_caps: vk.SurfaceCapabilitiesKHR
    vk_check(vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(ctx.phys_device, ctx.surface, &surface_caps))
    extent := surface_caps.currentExtent
    if extent.width == max(u32) || extent.height == max(u32) {
        extent.width = size[0]
        extent.height = size[1]
    }
    assert(extent.width != max(u32) && extent.height != max(u32))

    ctx.swapchain = create_swapchain(max(extent.width, 1), max(extent.height, 1), ctx.frames_in_flight)
}

_swapchain_acquire_next :: proc() -> Texture
{
    fence_ci := vk.FenceCreateInfo { sType = .FENCE_CREATE_INFO }
    fence: vk.Fence
    vk_check(vk.CreateFence(ctx.device, &fence_ci, nil, &fence))
    defer vk.DestroyFence(ctx.device, fence, nil)

    if sync.guard(&ctx.lock) {
        res := vk.AcquireNextImageKHR(ctx.device, ctx.swapchain.handle, max(u64), {}, fence, &ctx.swapchain_image_idx)
        if res == .SUBOPTIMAL_KHR do log.warn("Suboptimal swapchain acquire!")
        if res != .SUCCESS && res != .SUBOPTIMAL_KHR {
            vk_check(res)
        }
    }

    vk_check(vk.WaitForFences(ctx.device, 1, &fence, true, max(u64)))

    // Transition layout from swapchain
    {
        cmd_buf := vk_acquire_cmd_buf(get_queue(.Main))

        cmd_buf_bi := vk.CommandBufferBeginInfo {
            sType = .COMMAND_BUFFER_BEGIN_INFO,
            flags = { .ONE_TIME_SUBMIT },
        }
        vk_check(vk.BeginCommandBuffer(cmd_buf, &cmd_buf_bi))

        transition := vk.ImageMemoryBarrier2 {
            sType = .IMAGE_MEMORY_BARRIER_2,
            image = ctx.swapchain.images[ctx.swapchain_image_idx],
            subresourceRange = {
                aspectMask = { .COLOR },
                levelCount = 1,
                layerCount = 1,
            },
            oldLayout = .UNDEFINED,
            newLayout = .GENERAL,
            srcStageMask = { .ALL_COMMANDS },
            srcAccessMask = { .MEMORY_WRITE },
            dstStageMask = { .COLOR_ATTACHMENT_OUTPUT },
            dstAccessMask = { .MEMORY_READ, .MEMORY_WRITE },
        }
        vk.CmdPipelineBarrier2(cmd_buf, &vk.DependencyInfo {
            sType = .DEPENDENCY_INFO,
            imageMemoryBarrierCount = 1,
            pImageMemoryBarriers = &transition,
        })

        vk_check(vk.EndCommandBuffer(cmd_buf))

        vk_submit_cmd_buf(get_queue(.Main), cmd_buf)
    }

    return Texture {
        dimensions = { ctx.swapchain.width, ctx.swapchain.height, 1 },
        format = .BGRA8_Unorm,
        handle = transmute(Texture_Handle) ctx.swapchain.texture_keys[ctx.swapchain_image_idx],
    }
}

_swapchain_present :: proc(queue: Queue, sem_wait: Semaphore, wait_value: u64)
{
    vk_queue := get_resource(queue, &ctx.queues).handle
    vk_sem_wait := transmute(vk.Semaphore) sem_wait

    present_semaphore := ctx.swapchain.present_semaphores[ctx.swapchain_image_idx]

    // NOTE: Workaround for the fact that swapchain presentation
    // only supports binary semaphores.
    // wait on sem_wait on wait_value and signal ctx.binary_sem
    {
        // Switch to optimal layout for presentation (this is mandatory)
        cmd_buf: vk.CommandBuffer
        {
            cmd_buf = vk_acquire_cmd_buf(queue)

            cmd_buf_bi := vk.CommandBufferBeginInfo {
                sType = .COMMAND_BUFFER_BEGIN_INFO,
                flags = { .ONE_TIME_SUBMIT },
            }
            vk_check(vk.BeginCommandBuffer(cmd_buf, &cmd_buf_bi))

            transition := vk.ImageMemoryBarrier2 {
                sType = .IMAGE_MEMORY_BARRIER_2,
                image = ctx.swapchain.images[ctx.swapchain_image_idx],
                subresourceRange = {
                    aspectMask = { .COLOR },
                    levelCount = 1,
                    layerCount = 1,
                },
                oldLayout = .GENERAL,
                newLayout = .PRESENT_SRC_KHR,
                srcStageMask = { .ALL_COMMANDS },
                srcAccessMask = { .MEMORY_WRITE },
                dstStageMask = { .COLOR_ATTACHMENT_OUTPUT },
                dstAccessMask = { .MEMORY_READ },
            }
            vk.CmdPipelineBarrier2(cmd_buf, &vk.DependencyInfo {
                sType = .DEPENDENCY_INFO,
                imageMemoryBarrierCount = 1,
                pImageMemoryBarriers = &transition,
            })

            vk_check(vk.EndCommandBuffer(cmd_buf))
        }

        timeline := vk_get_cmd_buf_timeline(queue, cmd_buf)
        timeline.val += 1

        wait_stage_flags := vk.PipelineStageFlags { .COLOR_ATTACHMENT_OUTPUT }
        next: rawptr
        next = &vk.TimelineSemaphoreSubmitInfo {
            sType = .TIMELINE_SEMAPHORE_SUBMIT_INFO,
            pNext = next,
            waitSemaphoreValueCount = 1,
            pWaitSemaphoreValues = raw_data([]u64 {
                wait_value,
            }),
            signalSemaphoreValueCount = 2,
            pSignalSemaphoreValues = raw_data([]u64 {
                {},
                timeline.val,
            })
        }
        submit_info := vk.SubmitInfo {
            sType = .SUBMIT_INFO,
            pNext = next,
            commandBufferCount = 1,
            pCommandBuffers = &cmd_buf,
            waitSemaphoreCount = 1,
            pWaitSemaphores = raw_data([]vk.Semaphore {
                vk_sem_wait,
            }),
            pWaitDstStageMask = raw_data([]vk.PipelineStageFlags {
                wait_stage_flags,
            }),
            signalSemaphoreCount = 2,
            pSignalSemaphores = raw_data([]vk.Semaphore {
                present_semaphore,
                timeline.sem,
            }),
        }

        if sync.guard(&ctx.lock) do vk_check(vk.QueueSubmit(vk_queue, 1, &submit_info, {}))

        timeline.recording = false
    }

    sync.guard(&ctx.lock)
    res := vk.QueuePresentKHR(vk_queue, &{
        sType = .PRESENT_INFO_KHR,
        swapchainCount = 1,
        waitSemaphoreCount = 1,
        pWaitSemaphores = &present_semaphore,
        pSwapchains = &ctx.swapchain.handle,
        pImageIndices = &ctx.swapchain_image_idx,
    })
    if res == .SUBOPTIMAL_KHR do log.warn("Suboptimal swapchain acquire!")
    if res != .SUCCESS && res != .SUBOPTIMAL_KHR {
        vk_check(res)
    }
}

// Memory

_mem_alloc :: proc(bytes: u64, align: u64 = 1, mem_type := Memory.Default, alloc_type := Allocation_Type.Default) -> rawptr
{
    vma_usage: vma.Memory_Usage
    properties: vk.MemoryPropertyFlags
    switch mem_type
    {
        case .Default:
        {
            properties = { .HOST_VISIBLE, .HOST_COHERENT }
            vma_usage = .Cpu_To_Gpu
        }
        case .GPU:
        {
            properties = { .DEVICE_LOCAL }
            vma_usage = .Gpu_Only
        }
        case .Readback:
        {
            properties = { .HOST_VISIBLE, .HOST_CACHED, .HOST_COHERENT }
            vma_usage = .Gpu_To_Cpu
        }
    }

    buf_usage: vk.BufferUsageFlags
    switch alloc_type
    {
        case .Default:
        {
            buf_usage = { .SHADER_DEVICE_ADDRESS, .STORAGE_BUFFER, .TRANSFER_SRC, .TRANSFER_DST, .INDIRECT_BUFFER }
            if mem_type == .GPU {
                buf_usage += { .INDEX_BUFFER }
            }
        }
        case .Descriptors:
        {
            buf_usage = { .RESOURCE_DESCRIPTOR_BUFFER_EXT, .SHADER_DEVICE_ADDRESS, .TRANSFER_SRC, .TRANSFER_DST }
        }
    }

    buf_ci := vk.BufferCreateInfo {
        sType = .BUFFER_CREATE_INFO,
        size = cast(vk.DeviceSize) bytes,
        usage = buf_usage,
        sharingMode = .EXCLUSIVE,
    }

    buf: vk.Buffer
    vk_check(vk.CreateBuffer(ctx.device, &buf_ci, nil, &buf))

    mem_requirements: vk.MemoryRequirements
    vk.GetBufferMemoryRequirements(ctx.device, buf, &mem_requirements)

    mem_requirements.alignment = vk.DeviceSize(max(u64(mem_requirements.alignment), align))

    alloc_ci := vma.Allocation_Create_Info {
        flags = vma.Allocation_Create_Flags { .Mapped } if mem_type != .GPU else {},
        usage = vma_usage,
        required_flags = properties,
    }
    alloc: vma.Allocation
    alloc_info: vma.Allocation_Info
    vk_check(vma.allocate_memory(ctx.vma_allocator, mem_requirements, alloc_ci, &alloc, &alloc_info))

    vk_check(vma.bind_buffer_memory(ctx.vma_allocator, alloc, buf))

    info := vk.BufferDeviceAddressInfo {
        sType = .BUFFER_DEVICE_ADDRESS_INFO,
        buffer = buf
    }
    addr := vk.GetBufferDeviceAddress(ctx.device, &info)
    addr_ptr := cast(rawptr) cast(uintptr) addr

    sync.guard(&ctx.lock)
    append(&ctx.gpu_allocs, GPU_Alloc_Meta {
        allocation = alloc,
        buf_handle = buf,
        device_address = addr,
        align = u32(align),
        buf_size = cast(vk.DeviceSize) bytes,
        alloc_type = alloc_type,
    })
    gpu_alloc_idx := u32(len(ctx.gpu_allocs)) - 1
    ctx.gpu_ptr_to_alloc[addr_ptr] = gpu_alloc_idx
    rbt.find_or_insert(&ctx.alloc_tree, Alloc_Range { u64(addr), u32(bytes) }, gpu_alloc_idx)

    if mem_type != .GPU
    {
        ptr := alloc_info.mapped_data
        ctx.cpu_ptr_to_alloc[ptr] = gpu_alloc_idx
        return ptr
    }

    return rawptr(uintptr(addr))
}

_mem_free :: proc(ptr: rawptr, loc := #caller_location)
{
    sync.guard(&ctx.lock)
    cpu_alloc, cpu_found := ctx.cpu_ptr_to_alloc[ptr]
    gpu_alloc, gpu_found := ctx.gpu_ptr_to_alloc[ptr]
    if !cpu_found && !gpu_found
    {
        log.error("Attempting to free a pointer which is not allocated.", location = loc)
        return
    }

    if cpu_found
    {
        meta := &ctx.gpu_allocs[cpu_alloc]
        rbt.remove_key(&ctx.alloc_tree, Alloc_Range { u64(meta.device_address), u32(meta.buf_size) })
        vma.destroy_buffer(ctx.vma_allocator, meta.buf_handle, meta.allocation)
        meta^ = {}
        delete_key(&ctx.cpu_ptr_to_alloc, ptr)
    }
    else if gpu_found
    {
        meta := &ctx.gpu_allocs[gpu_alloc]
        rbt.remove_key(&ctx.alloc_tree, Alloc_Range { u64(meta.device_address), u32(meta.buf_size) })
        vma.destroy_buffer(ctx.vma_allocator, meta.buf_handle, meta.allocation)
        meta^ = {}
        delete_key(&ctx.gpu_ptr_to_alloc, ptr)
    }
}

_host_to_device_ptr :: proc(ptr: rawptr) -> rawptr
{
    // We could do a tree search here but that would be more expensive

    meta_idx, found := ctx.cpu_ptr_to_alloc[ptr]
    if !found
    {
        log.error("Attempting to get the device pointer of a host pointer which is not allocated. Note: The pointer passed to this function must be a base allocation pointer.")
        return {}
    }

    meta := ctx.gpu_allocs[meta_idx]
    return rawptr(uintptr(meta.device_address))
}

// Textures
_texture_create :: proc(desc: Texture_Desc, storage: rawptr, queue: Queue = nil, signal_sem: Semaphore = {}, signal_value: u64 = 0) -> Texture
{
    vk_signal_sem := transmute(vk.Semaphore) signal_sem

    queue_to_use := queue
    if queue == nil {
        queue_to_use = get_queue(.Main)
    }

    alloc_idx, ok_s := search_alloc_from_gpu_ptr(storage)
    if !ok_s
    {
        log.error("Address does not reside in allocated GPU memory.")
        return {}
    }
    alloc := ctx.gpu_allocs[alloc_idx]

    image: vk.Image
    offset := uintptr(storage) - uintptr(alloc.device_address)
    vk_check(vma.create_aliasing_image2(ctx.vma_allocator, alloc.allocation, vk.DeviceSize(offset), {
        sType = .IMAGE_CREATE_INFO,
        imageType = to_vk_texture_type(desc.type),
        format = to_vk_texture_format(desc.format),
        extent = vk.Extent3D { desc.dimensions.x, desc.dimensions.y, desc.dimensions.z },
        mipLevels = desc.mip_count,
        arrayLayers = desc.layer_count,
        samples = to_vk_sample_count(desc.sample_count),
        usage = to_vk_texture_usage(desc.usage) + { .TRANSFER_DST },
        initialLayout = .UNDEFINED,
    }, &image))

    plane_aspect: vk.ImageAspectFlags = { .DEPTH } if desc.format == .D32_Float else { .COLOR }

    // Transition layout from UNDEFINED to GENERAL
    {
        cmd_buf := vk_acquire_cmd_buf(queue_to_use)

        cmd_buf_bi := vk.CommandBufferBeginInfo {
            sType = .COMMAND_BUFFER_BEGIN_INFO,
            flags = { .ONE_TIME_SUBMIT },
        }
        vk_check(vk.BeginCommandBuffer(cmd_buf, &cmd_buf_bi))

        transition := vk.ImageMemoryBarrier2 {
            sType = .IMAGE_MEMORY_BARRIER_2,
            image = image,
            subresourceRange = {
                aspectMask = plane_aspect,
                levelCount = 1,
                layerCount = 1,
            },
            oldLayout = .UNDEFINED,
            newLayout = .GENERAL,
            srcStageMask = { .ALL_COMMANDS },
            srcAccessMask = { .MEMORY_WRITE },
            dstStageMask = { .ALL_COMMANDS },
            dstAccessMask = { .MEMORY_READ, .MEMORY_WRITE },
        }
        vk.CmdPipelineBarrier2(cmd_buf, &vk.DependencyInfo {
            sType = .DEPENDENCY_INFO,
            imageMemoryBarrierCount = 1,
            pImageMemoryBarriers = &transition,
        })

        vk_check(vk.EndCommandBuffer(cmd_buf))
        vk_submit_cmd_buf(queue_to_use, cmd_buf, vk_signal_sem, signal_value)
    }

    tex_info := Texture_Info { image, {} }
    sync.guard(&ctx.lock)
    return {
        dimensions = desc.dimensions,
        format = desc.format,
        handle = transmute(Texture_Handle) u64(pool_append(&ctx.textures, tex_info))
    }
}

_texture_destroy :: proc(texture: ^Texture)
{
    tex_key := transmute(Key) texture.handle
    sync.guard(&ctx.lock)
    tex_info := get_resource(texture.handle, ctx.textures)
    vk_image := tex_info.handle

    for view in tex_info.views {
        vk.DestroyImageView(ctx.device, view.view, nil)
    }
    delete(tex_info.views)
    tex_info.views = {}

    vk.DestroyImage(ctx.device, vk_image, nil)
    pool_free_idx(&ctx.textures, u32(tex_key.idx))
    texture^ = {}
}

_texture_size_and_align :: proc(desc: Texture_Desc) -> (size: u64, align: u64)
{
    image_ci := vk.ImageCreateInfo {
        sType = .IMAGE_CREATE_INFO,
        imageType = to_vk_texture_type(desc.type),
        format = to_vk_texture_format(desc.format),
        extent = vk.Extent3D { desc.dimensions.x, desc.dimensions.y, desc.dimensions.z },
        mipLevels = desc.mip_count,
        arrayLayers = desc.layer_count,
        samples = to_vk_sample_count(desc.sample_count),
        usage = to_vk_texture_usage(desc.usage),
        initialLayout = .UNDEFINED,
    }

    plane_aspect: vk.ImageAspectFlags = { .DEPTH } if desc.format == .D32_Float else { .COLOR }

    info := vk.DeviceImageMemoryRequirements {
        sType = .DEVICE_IMAGE_MEMORY_REQUIREMENTS,
        pCreateInfo = &image_ci,
        planeAspect = plane_aspect,
    }

    mem_requirements_2 := vk.MemoryRequirements2 { sType = .MEMORY_REQUIREMENTS_2 }
    vk.GetDeviceImageMemoryRequirements(ctx.device, &info, &mem_requirements_2)

    mem_requirements := mem_requirements_2.memoryRequirements
    return u64(mem_requirements.size), u64(mem_requirements.alignment)
}

@(private="file")
get_or_add_image_view :: proc(texture: Texture_Handle, info: vk.ImageViewCreateInfo) -> vk.ImageView
{
    sync.guard(&ctx.lock)
    tex_info := get_resource(texture, ctx.textures)

    for view in tex_info.views
    {
        if view.info == info {
            return view.view
        }
    }

    image_view: vk.ImageView
    view_ci := info
    vk_check(vk.CreateImageView(ctx.device, &view_ci, nil, &image_view))
    append(&tex_info.views, Image_View_Info { info, image_view })
    return image_view
}

_texture_view_descriptor :: proc(texture: Texture, view_desc: Texture_View_Desc) -> Texture_Descriptor
{
    tex_info := get_resource(texture.handle, ctx.textures)
    vk_image := tex_info.handle

    format := view_desc.format
    if format == .Default {
        format = texture.format
    }

    plane_aspect: vk.ImageAspectFlags = { .DEPTH } if format == .D32_Float else { .COLOR }

    image_view_ci := vk.ImageViewCreateInfo {
        sType = .IMAGE_VIEW_CREATE_INFO,
        image = vk_image,
        viewType = to_vk_texture_view_type(view_desc.type),
        format = to_vk_texture_format(format),
        subresourceRange = {
            aspectMask = plane_aspect,
            levelCount = 1,
            layerCount = 1,
        }
    }
    view := get_or_add_image_view(texture.handle, image_view_ci)

    desc: Texture_Descriptor
    info := vk.DescriptorGetInfoEXT {
        sType = .DESCRIPTOR_GET_INFO_EXT,
        type = .SAMPLED_IMAGE,
        data = { pSampledImage = &{ imageView = view, imageLayout = .GENERAL } }
    }
    vk.GetDescriptorEXT(ctx.device, &info, int(ctx.texture_desc_size), &desc)
    return desc
}

_texture_rw_view_descriptor :: proc(texture: Texture, view_desc: Texture_View_Desc) -> Texture_Descriptor
{
    tex_info := get_resource(texture.handle, ctx.textures)
    vk_image := tex_info.handle

    format := view_desc.format
    if format == .Default {
        format = texture.format
    }

    plane_aspect: vk.ImageAspectFlags = { .DEPTH } if format == .D32_Float else { .COLOR }

    image_view_ci := vk.ImageViewCreateInfo {
        sType = .IMAGE_VIEW_CREATE_INFO,
        image = vk_image,
        viewType = to_vk_texture_view_type(view_desc.type),
        format = to_vk_texture_format(format),
        subresourceRange = {
            aspectMask = plane_aspect,
            levelCount = 1,
            layerCount = 1,
        }
    }
    view := get_or_add_image_view(texture.handle, image_view_ci)

    desc: Texture_Descriptor
    info := vk.DescriptorGetInfoEXT {
        sType = .DESCRIPTOR_GET_INFO_EXT,
        type = .STORAGE_IMAGE,
        data = { pStorageImage = &{ imageView = view, imageLayout = .GENERAL } }
    }
    vk.GetDescriptorEXT(ctx.device, &info, int(ctx.texture_rw_desc_size), &desc)
    return desc
}

_sampler_descriptor :: proc(sampler_desc: Sampler_Desc) -> Sampler_Descriptor
{
    sampler_ci := vk.SamplerCreateInfo {
        sType = .SAMPLER_CREATE_INFO,
        magFilter = to_vk_filter(sampler_desc.mag_filter),
        minFilter = to_vk_filter(sampler_desc.min_filter),
        mipmapMode = to_vk_mipmap_filter(sampler_desc.mip_filter),
        addressModeU = to_vk_address_mode(sampler_desc.address_mode_u),
        addressModeV = to_vk_address_mode(sampler_desc.address_mode_v),
        addressModeW = to_vk_address_mode(sampler_desc.address_mode_w),
    }
    sampler := get_or_add_sampler(sampler_ci)

    desc: Sampler_Descriptor
    info := vk.DescriptorGetInfoEXT {
        sType = .DESCRIPTOR_GET_INFO_EXT,
        type = .SAMPLER,
        data = { pSampledImage = &{ sampler = sampler, imageView = {}, imageLayout = .GENERAL } }
    }
    vk.GetDescriptorEXT(ctx.device, &info, int(ctx.sampler_desc_size), &desc)
    return desc

    get_or_add_sampler :: proc(info: vk.SamplerCreateInfo) -> vk.Sampler
    {
        sync.guard(&ctx.lock)
        for sampler in ctx.samplers
        {
            if sampler.info == info {
                return sampler.sampler
            }
        }

        sampler: vk.Sampler
        sampler_ci := info
        vk_check(vk.CreateSampler(ctx.device, &sampler_ci, nil, &sampler))
        append(&ctx.samplers, Sampler_Info { info, sampler })
        return sampler
    }
}

_get_texture_view_descriptor_size :: proc() -> u32
{
    return ctx.texture_desc_size
}

_get_texture_rw_view_descriptor_size :: proc() -> u32
{
    return ctx.texture_rw_desc_size
}

_get_sampler_descriptor_size :: proc() -> u32
{
    return ctx.sampler_desc_size
}

// Shaders
@(private="file")
_shader_create_internal :: proc(code: []u32, is_compute: bool, vk_stage: vk.ShaderStageFlags, group_size_x: u32 = 1, group_size_y: u32 = 1, group_size_z: u32 = 1) -> Shader
{
    push_constant_ranges: []vk.PushConstantRange
    if is_compute {
        push_constant_ranges = []vk.PushConstantRange {
            {
                stageFlags = { .COMPUTE },
                size = size_of(Compute_Shader_Push_Constants),
            }
        }
    } else {
        push_constant_ranges = []vk.PushConstantRange {
            {
                stageFlags = { .VERTEX, .FRAGMENT },
                size = size_of(Graphics_Shader_Push_Constants),
            }
        }
    }

    desc_layouts := []vk.DescriptorSetLayout {
        ctx.textures_desc_layout,
        ctx.textures_rw_desc_layout,
        ctx.samplers_desc_layout,
        ctx.data_desc_layout,
        ctx.indirect_data_desc_layout,
    }

    // Setup specialization constants for compute shader workgroup size
    spec_map_entries: [3]vk.SpecializationMapEntry
    spec_data: [3]u32
    spec_info: vk.SpecializationInfo
    spec_info_ptr: ^vk.SpecializationInfo = nil
    spec_count: u32 = 0

    if is_compute
    {
        {
            spec_map_entries[spec_count] = vk.SpecializationMapEntry {
                constantID = 13370, // Random big ids to avoid conflicts with user defined constants
                offset = u32(spec_count * size_of(u32)),
                size = size_of(u32),
            }
            spec_data[spec_count] = group_size_x
            spec_count += 1
        }

        {
            spec_map_entries[spec_count] = vk.SpecializationMapEntry {
                constantID = 13371, // Random big ids to avoid conflicts with user defined constants
                offset = u32(spec_count * size_of(u32)),
                size = size_of(u32),
            }
            spec_data[spec_count] = group_size_y
            spec_count += 1
        }

        {
            spec_map_entries[spec_count] = vk.SpecializationMapEntry {
                constantID = 13372, // Random big ids to avoid conflicts with user defined constants
                offset = u32(spec_count * size_of(u32)),
                size = size_of(u32),
            }
            spec_data[spec_count] = group_size_z
            spec_count += 1
        }
    }

    if spec_count > 0
    {
        spec_info = vk.SpecializationInfo {
            mapEntryCount = spec_count,
            pMapEntries = raw_data(spec_map_entries[:spec_count]),
            dataSize = int(spec_count * size_of(u32)),
            pData = raw_data(spec_data[:spec_count]),
        }
        spec_info_ptr = &spec_info
    }

    next_stage: vk.ShaderStageFlags
    if is_compute {
        next_stage = {}
    } else if vk_stage == { .VERTEX } {
        next_stage = { .FRAGMENT }
    } else {
        next_stage = {}
    }

    shader_cis := vk.ShaderCreateInfoEXT {
        sType = .SHADER_CREATE_INFO_EXT,
        codeType = .SPIRV,
        codeSize = len(code) * size_of(code[0]),
        pCode = raw_data(code),
        pName = "main",
        stage = vk_stage,
        nextStage = next_stage,
        pushConstantRangeCount = u32(len(push_constant_ranges)),
        pPushConstantRanges = raw_data(push_constant_ranges),
        setLayoutCount = u32(len(desc_layouts)),
        pSetLayouts = raw_data(desc_layouts),
        pSpecializationInfo = spec_info_ptr,
    }

    shader: vk.ShaderEXT
    vk_check(vk.CreateShadersEXT(ctx.device, 1, &shader_cis, nil, &shader))
    shader_handle := transmute(Shader) shader

    // Store work group size for compute shaders
    if is_compute
    {
        sync.guard(&ctx.lock)
        ctx.current_workgroup_size[shader_handle] = { group_size_x, group_size_y, group_size_z }
    }

    return shader_handle
}

_shader_create :: proc(code: []u32, type: Shader_Type_Graphics) -> Shader
{
    vk_stage := to_vk_shader_stage(type)
    return _shader_create_internal(code, false, vk_stage)
}

_shader_create_compute :: proc(code: []u32, group_size_x: u32, group_size_y: u32 = 1, group_size_z: u32 = 1) -> Shader
{
    return _shader_create_internal(code, true, { .COMPUTE }, group_size_x, group_size_y, group_size_z)
}

_shader_destroy :: proc(shader: ^Shader)
{
    vk_shader := transmute(vk.ShaderEXT) (shader^)
    vk.DestroyShaderEXT(ctx.device, vk_shader, nil)

    sync.guard(&ctx.lock)
    // Remove from workgroup size map
    delete_key(&ctx.current_workgroup_size, shader^)

    // Remove from any command buffer tracking
    for cmd_buf, compute_shader in ctx.cmd_buf_compute_shader
    {
        if compute_shader == shader^
        {
            delete_key(&ctx.cmd_buf_compute_shader, cmd_buf)
        }
    }

    shader^ = {}
}

// Semaphores
_semaphore_create :: proc(init_value: u64 = 0) -> Semaphore
{
    next: rawptr
    next = &vk.SemaphoreTypeCreateInfo {
        sType = .SEMAPHORE_TYPE_CREATE_INFO,
        pNext = next,
        semaphoreType = .TIMELINE,
        initialValue = init_value,
    }
    sem_ci := vk.SemaphoreCreateInfo {
        sType = .SEMAPHORE_CREATE_INFO,
        pNext = next
    }
    sem: vk.Semaphore
    vk_check(vk.CreateSemaphore(ctx.device, &sem_ci, nil, &sem))

    return cast(Semaphore) uintptr(sem)
}

_semaphore_wait :: proc(sem: Semaphore, wait_value: u64)
{
    sems := []vk.Semaphore { auto_cast uintptr(sem) }
    values := []u64 { wait_value }
    assert(len(sems) == len(values))
    vk.WaitSemaphores(ctx.device, &{
        sType = .SEMAPHORE_WAIT_INFO,
        semaphoreCount = u32(len(sems)),
        pSemaphores = raw_data(sems),
        pValues = raw_data(values),
    }, timeout = max(u64))
}

_semaphore_destroy :: proc(sem: ^Semaphore)
{
    vk_sem := transmute(vk.Semaphore) (sem^)
    vk.DestroySemaphore(ctx.device, vk_sem, nil)
    sem^ = {}
}

// Command buffer

_get_queue :: proc(queue_type: Queue_Type) -> Queue
{
    sync.guard(&ctx.lock)

    queue_info := &ctx.queues[cast(u32) queue_type + 1]
    if queue_info.handle == nil
    {
        queue: vk.Queue
        vk.GetDeviceQueue(ctx.device, queue_info.family_idx, queue_info.queue_idx, &queue)
        queue_info.handle = queue
    }

    return transmute(Queue) Key { idx = cast(u64) queue_type + 1 }
}

_queue_wait_idle :: proc(queue: Queue)
{
    sync.guard(&ctx.lock)
    vk.QueueWaitIdle(get_resource(queue, &ctx.queues).handle)
}

_commands_begin :: proc(queue: Queue) -> Command_Buffer
{
    cmd_buf := vk_acquire_cmd_buf(queue)

    cmd_buf_bi := vk.CommandBufferBeginInfo {
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = { .ONE_TIME_SUBMIT },
    }
    vk_check(vk.BeginCommandBuffer(cmd_buf, &cmd_buf_bi))

    return cast(Command_Buffer) cmd_buf
}

_queue_submit :: proc(queue: Queue, cmd_bufs: []Command_Buffer, signal_sem: Semaphore = {}, signal_value: u64 = 0)
{
    queue_info := get_resource(queue, &ctx.queues)
    vk_queue := queue_info.handle
    vk_signal_sem := transmute(vk.Semaphore) signal_sem

    for cmd_buf in cmd_bufs
    {
        vk_cmd_buf := cast(vk.CommandBuffer) cmd_buf
        vk_check(vk.EndCommandBuffer(vk_cmd_buf))

        vk_submit_cmd_buf(queue, vk_cmd_buf, vk_signal_sem, signal_value)

        // Clear compute shader tracking for this command buffer
        sync.guard(&ctx.lock)
        delete_key(&ctx.cmd_buf_compute_shader, cmd_buf)
    }
}

// Commands

_cmd_mem_copy :: proc(cmd_buf: Command_Buffer, src, dst: rawptr, #any_int bytes: i64)
{
    vk_cmd_buf := cast(vk.CommandBuffer) cmd_buf

    src_buf, src_offset, ok_s := compute_buf_offset_from_gpu_ptr(src)
    dst_buf, dst_offset, ok_d := compute_buf_offset_from_gpu_ptr(dst)
    if !ok_s || !ok_d
    {
        log.error("Alloc not found.")
        return
    }

    copy_regions := []vk.BufferCopy {
        {
            srcOffset = vk.DeviceSize(src_offset),
            dstOffset = vk.DeviceSize(dst_offset),
            size = vk.DeviceSize(bytes),
        }
    }
    vk.CmdCopyBuffer(vk_cmd_buf, src_buf, dst_buf, u32(len(copy_regions)), raw_data(copy_regions))
}

// TODO: dst is ignored atm.
_cmd_copy_to_texture :: proc(cmd_buf: Command_Buffer, texture: Texture, src, dst: rawptr)
{
    vk_cmd_buf := cast(vk.CommandBuffer) cmd_buf
    tex_info := get_resource(texture.handle, ctx.textures)
    vk_image := tex_info.handle

    src_buf, src_offset, ok_s := compute_buf_offset_from_gpu_ptr(src)
    if !ok_s {
        log.error("Alloc not found.")
        return
    }

    plane_aspect: vk.ImageAspectFlags = { .DEPTH } if texture.format == .D32_Float else { .COLOR }

    vk.CmdCopyBufferToImage(vk_cmd_buf, src_buf, vk_image, .GENERAL, 1, &vk.BufferImageCopy {
        bufferOffset = vk.DeviceSize(src_offset),
        bufferRowLength = texture.dimensions.x,
        bufferImageHeight = texture.dimensions.y,
        imageSubresource = {
            aspectMask = plane_aspect,
            mipLevel = 0,
            baseArrayLayer = 0,
            layerCount = 1,
        },
        imageOffset = {},
        imageExtent = { texture.dimensions.x, texture.dimensions.y, texture.dimensions.z }
    })
}

_cmd_set_texture_heap :: proc(cmd_buf: Command_Buffer, textures, textures_rw, samplers: rawptr)
{
    vk_cmd_buf := cast(vk.CommandBuffer) cmd_buf

    if textures == nil && textures_rw == nil && samplers == nil do return

    // Check pointers. Drivers are currently not very good at recovering from situations
    // like this (e.g. on my setup, the whole desktop freezes for 10 seconds) so we try
    // to catch these at the API level if possible.
    {
        if textures != nil
        {
            alloc, ok_s := search_alloc_from_gpu_ptr(textures)
            if !ok_s {
                log.error("Alloc not found.")
                return
            }
            if ctx.gpu_allocs[alloc].alloc_type != .Descriptors {
                log.error("Attempted to use cmd_set_texture_heap with memory that wasn't allocated with alloc_type = .Descriptors!")
                return
            }
        }
        if textures_rw != nil
        {
            alloc, ok_s := search_alloc_from_gpu_ptr(textures_rw)
            if !ok_s {
                log.error("Alloc not found.")
                return
            }
            if ctx.gpu_allocs[alloc].alloc_type != .Descriptors {
                log.error("Attempted to use cmd_set_texture_heap with memory that wasn't allocated with alloc_type = .Descriptors!")
                return
            }
        }
        if samplers != nil
        {
            alloc, ok_s := search_alloc_from_gpu_ptr(samplers)
            if !ok_s {
                log.error("Alloc not found.")
                return
            }
            if ctx.gpu_allocs[alloc].alloc_type != .Descriptors {
                log.error("Attempted to use cmd_set_texture_heap with memory that wasn't allocated with alloc_type = .Descriptors!")
                return
            }
        }
    }

    infos: [3]vk.DescriptorBufferBindingInfoEXT
    // Fill in infos with the subset of valid pointers
    cursor := u32(0)
    if textures != nil
    {
        infos[cursor] = {
            sType = .DESCRIPTOR_BUFFER_BINDING_INFO_EXT,
            address = transmute(vk.DeviceAddress) textures,
            usage = { .RESOURCE_DESCRIPTOR_BUFFER_EXT, .SHADER_DEVICE_ADDRESS, .STORAGE_BUFFER, .TRANSFER_SRC },
        }
        cursor += 1
    }
    if textures_rw != nil
    {
        infos[cursor] = {
            sType = .DESCRIPTOR_BUFFER_BINDING_INFO_EXT,
            address = transmute(vk.DeviceAddress) textures_rw,
            usage = { .RESOURCE_DESCRIPTOR_BUFFER_EXT, .SHADER_DEVICE_ADDRESS, .STORAGE_BUFFER, .TRANSFER_SRC },
        }
        cursor += 1
    }
    if samplers != nil
    {
        infos[cursor] = {
            sType = .DESCRIPTOR_BUFFER_BINDING_INFO_EXT,
            address = transmute(vk.DeviceAddress) samplers,
            usage = { .RESOURCE_DESCRIPTOR_BUFFER_EXT, .SHADER_DEVICE_ADDRESS, .STORAGE_BUFFER, .TRANSFER_SRC },
        }
        cursor += 1
    }

    vk.CmdBindDescriptorBuffersEXT(vk_cmd_buf, cursor, &infos[0])

    buffer_offsets := []vk.DeviceSize { 0, 0, 0 }
    cursor = 0
    if textures != nil {
        vk.CmdSetDescriptorBufferOffsetsEXT(vk_cmd_buf, .GRAPHICS, ctx.common_pipeline_layout_graphics, 0, 1, &cursor, &buffer_offsets[0])
        vk.CmdSetDescriptorBufferOffsetsEXT(vk_cmd_buf, .COMPUTE, ctx.common_pipeline_layout_compute, 0, 1, &cursor, &buffer_offsets[0])
        cursor += 1
    }
    if textures_rw != nil {
        vk.CmdSetDescriptorBufferOffsetsEXT(vk_cmd_buf, .GRAPHICS, ctx.common_pipeline_layout_graphics, 1, 1, &cursor, &buffer_offsets[1])
        vk.CmdSetDescriptorBufferOffsetsEXT(vk_cmd_buf, .COMPUTE, ctx.common_pipeline_layout_compute, 1, 1, &cursor, &buffer_offsets[1])
        cursor += 1
    }
    if samplers != nil {
        vk.CmdSetDescriptorBufferOffsetsEXT(vk_cmd_buf, .GRAPHICS, ctx.common_pipeline_layout_graphics, 2, 1, &cursor, &buffer_offsets[2])
        vk.CmdSetDescriptorBufferOffsetsEXT(vk_cmd_buf, .COMPUTE, ctx.common_pipeline_layout_compute, 2, 1, &cursor, &buffer_offsets[2])
        cursor += 1
    }
}

_cmd_barrier :: proc(cmd_buf: Command_Buffer, before: Stage, after: Stage, hazards: Hazard_Flags = {})
{
    vk_cmd_buf := cast(vk.CommandBuffer) cmd_buf

    vk_before := to_vk_stage(before)
    vk_after  := to_vk_stage(after)

    // Determine access masks based on hazards
    src_access: vk.AccessFlags
    dst_access: vk.AccessFlags

    if .Draw_Arguments in hazards
    {
        // When compute shader writes draw arguments, ensure they're visible to indirect draw commands
        // Source: compute shader writes
        src_access += { .SHADER_WRITE }
        // Destination: indirect command read (for draw/dispatch indirect)
        dst_access += { .INDIRECT_COMMAND_READ }
    }

    if .Descriptors in hazards
    {
        // When descriptors are updated, ensure visibility
        src_access += { .SHADER_WRITE }
        dst_access += { .SHADER_READ }
    }

    if .Depth_Stencil in hazards
    {
        // Depth/stencil attachment synchronization
        src_access += { .DEPTH_STENCIL_ATTACHMENT_WRITE }
        dst_access += { .DEPTH_STENCIL_ATTACHMENT_READ, .DEPTH_STENCIL_ATTACHMENT_WRITE }
    }

    // If no specific hazards, use generic memory barrier
    if card(hazards) == 0
    {
        src_access = { .MEMORY_WRITE }
        dst_access = { .MEMORY_READ }
    }

    barrier := vk.MemoryBarrier {
        sType = .MEMORY_BARRIER,
        srcAccessMask = src_access,
        dstAccessMask = dst_access,
    }
    vk.CmdPipelineBarrier(vk_cmd_buf, vk_before, vk_after, {}, 1, &barrier, 0, nil, 0, nil)
}

_cmd_signal_after :: proc() {}
_cmd_wait_before :: proc() {}

_cmd_set_shaders :: proc(cmd_buf: Command_Buffer, vert_shader: Shader, frag_shader: Shader)
{
    vk_cmd_buf := cast(vk.CommandBuffer) cmd_buf
    vk_vert_shader := transmute(vk.ShaderEXT) vert_shader
    vk_frag_shader := transmute(vk.ShaderEXT) frag_shader

    shader_stages := []vk.ShaderStageFlags { { .VERTEX }, { .FRAGMENT } }
    to_bind := []vk.ShaderEXT { vk_vert_shader, vk_frag_shader }
    assert(len(shader_stages) == len(to_bind))
    vk.CmdBindShadersEXT(vk_cmd_buf, u32(len(shader_stages)), raw_data(shader_stages), raw_data(to_bind))
}

_cmd_set_depth_state :: proc(cmd_buf: Command_Buffer, state: Depth_State)
{
    vk_cmd_buf := cast(vk.CommandBuffer) cmd_buf

    vk.CmdSetDepthCompareOp(vk_cmd_buf, to_vk_compare_op(state.compare))
    vk.CmdSetDepthTestEnable(vk_cmd_buf, .Read in state.mode)
    vk.CmdSetDepthWriteEnable(vk_cmd_buf, .Write in state.mode)
    vk.CmdSetDepthBiasEnable(vk_cmd_buf, false)
    vk.CmdSetDepthClipEnableEXT(vk_cmd_buf, true)
    vk.CmdSetStencilTestEnable(vk_cmd_buf, false)
}

_cmd_set_blend_state :: proc(cmd_buf: Command_Buffer, state: Blend_State)
{
    vk_cmd_buf := cast(vk.CommandBuffer) cmd_buf

    enable_b32 := b32(state.enable)
    vk.CmdSetColorBlendEnableEXT(vk_cmd_buf, 0, 1, &enable_b32)

    vk.CmdSetColorBlendEquationEXT(vk_cmd_buf, 0, 1, &vk.ColorBlendEquationEXT {
        srcColorBlendFactor = {},
        dstColorBlendFactor = {},
        colorBlendOp        = {},
        srcAlphaBlendFactor = {},
        dstAlphaBlendFactor = {},
        alphaBlendOp        = {},
    })

    color_write_mask := transmute(vk.ColorComponentFlags) cast(u32) state.color_write_mask
    vk.CmdSetColorWriteMaskEXT(vk_cmd_buf, 0, 1, &color_write_mask)
}

_cmd_set_compute_shader :: proc(cmd_buf: Command_Buffer, compute_shader: Shader)
{
    vk_cmd_buf := cast(vk.CommandBuffer) cmd_buf
    vk_compute_shader := transmute(vk.ShaderEXT) compute_shader

    shader_stages := []vk.ShaderStageFlags { { .COMPUTE } }
    to_bind := []vk.ShaderEXT { vk_compute_shader }
    assert(len(shader_stages) == len(to_bind))
    vk.CmdBindShadersEXT(vk_cmd_buf, u32(len(shader_stages)), raw_data(shader_stages), raw_data(to_bind))

    sync.guard(&ctx.lock)
    ctx.cmd_buf_compute_shader[cmd_buf] = compute_shader
}

_cmd_dispatch :: proc(cmd_buf: Command_Buffer, compute_data: rawptr, num_groups_x: u32, num_groups_y: u32 = 1, num_groups_z: u32 = 1)
{
    vk_cmd_buf := cast(vk.CommandBuffer) cmd_buf

    compute_shader, has_shader := ctx.cmd_buf_compute_shader[cmd_buf]
    if !has_shader
    {
        log.error("cmd_dispatch called without a compute shader set. Call cmd_set_compute_shader first.")
        return
    }

    push_constants := Compute_Shader_Push_Constants {
        compute_data = compute_data,
    }

    vk.CmdPushConstants(vk_cmd_buf, ctx.common_pipeline_layout_compute, { .COMPUTE }, 0, size_of(Compute_Shader_Push_Constants), &push_constants)

    vk.CmdDispatch(vk_cmd_buf, num_groups_x, num_groups_y, num_groups_z)
}

_cmd_dispatch_indirect :: proc(cmd_buf: Command_Buffer, compute_data: rawptr, arguments: rawptr)
{
    vk_cmd_buf := cast(vk.CommandBuffer) cmd_buf

    compute_shader, has_shader := ctx.cmd_buf_compute_shader[cmd_buf]
    if !has_shader
    {
        log.error("cmd_dispatch_indirect called without a compute shader set. Call cmd_set_compute_shader first.")
        return
    }

    arguments_buf, arguments_offset, ok_a := compute_buf_offset_from_gpu_ptr(arguments)
    if !ok_a
    {
        log.error("Arguments alloc not found for indirect dispatch")
        return
    }

    push_constants := Compute_Shader_Push_Constants {
        compute_data = compute_data,
    }

    vk.CmdPushConstants(vk_cmd_buf, ctx.common_pipeline_layout_compute, { .COMPUTE }, 0, size_of(Compute_Shader_Push_Constants), &push_constants)

    vk.CmdDispatchIndirect(vk_cmd_buf, arguments_buf, vk.DeviceSize(arguments_offset))
}

_cmd_begin_render_pass :: proc(cmd_buf: Command_Buffer, desc: Render_Pass_Desc)
{
    vk_cmd_buf := cast(vk.CommandBuffer) cmd_buf

    scratch, _ := acquire_scratch()

    vk_color_attachments := make([]vk.RenderingAttachmentInfo, len(desc.color_attachments), allocator = scratch)
    for &vk_attach, i in vk_color_attachments {
        vk_attach = to_vk_render_attachment(desc.color_attachments[i])
    }

    vk_depth_attachment: vk.RenderingAttachmentInfo
    vk_depth_attachment_ptr: ^vk.RenderingAttachmentInfo
    if desc.depth_attachment != nil
    {
        vk_depth_attachment = to_vk_render_attachment(desc.depth_attachment.?)
        vk_depth_attachment_ptr = &vk_depth_attachment
    }

    width := desc.render_area_size.x
    if width == {} {
        width = desc.color_attachments[0].texture.dimensions.x
    }
    height := desc.render_area_size.y
    if height == {} {
        height = desc.color_attachments[0].texture.dimensions.y
    }
    layer_count := desc.layer_count
    if layer_count == 0 {
        layer_count = 1
    }

    rendering_info := vk.RenderingInfo {
        sType = .RENDERING_INFO,
        renderArea = {
            offset = { desc.render_area_offset.x, desc.render_area_offset.y },
            extent = { width, height }
        },
        layerCount = layer_count,
        colorAttachmentCount = u32(len(vk_color_attachments)),
        pColorAttachments = raw_data(vk_color_attachments),
        pDepthAttachment = vk_depth_attachment_ptr,
    }
    vk.CmdBeginRendering(vk_cmd_buf, &rendering_info)

    // Blend state
    vk.CmdSetStencilTestEnable(vk_cmd_buf, false)
    color_attachment_count := u32(len(vk_color_attachments))
    if color_attachment_count > 0 {
        // Set blend enable for all attachments
        blend_enables := make([]b32, color_attachment_count, allocator = scratch)
        for i in 0 ..< color_attachment_count {
            blend_enables[i] = false
        }
        vk.CmdSetColorBlendEnableEXT(vk_cmd_buf, 0, color_attachment_count, raw_data(blend_enables))
        
        // Set color write mask for all attachments
        color_mask := vk.ColorComponentFlags { .R, .G, .B, .A }
        color_masks := make([]vk.ColorComponentFlags, color_attachment_count, allocator = scratch)
        for i in 0 ..< color_attachment_count {
            color_masks[i] = color_mask
        }
        vk.CmdSetColorWriteMaskEXT(vk_cmd_buf, 0, color_attachment_count, raw_data(color_masks))
    }

    // Depth state
    vk.CmdSetDepthCompareOp(vk_cmd_buf, .LESS)
    vk.CmdSetDepthTestEnable(vk_cmd_buf, false)
    vk.CmdSetDepthWriteEnable(vk_cmd_buf, false)
    vk.CmdSetDepthBiasEnable(vk_cmd_buf, false)
    vk.CmdSetDepthClipEnableEXT(vk_cmd_buf, true)

    // Viewport
    viewport := vk.Viewport {
        x = 0, y = 0,
        width = f32(width), height = f32(height),
        minDepth = 0.0, maxDepth = 1.0,
    }
    vk.CmdSetViewportWithCount(vk_cmd_buf, 1, &viewport)
    scissor := vk.Rect2D {
        offset = {
            x = 0, y = 0
        },
        extent = {
            width = width, height = height,
        }
    }
    vk.CmdSetScissorWithCount(vk_cmd_buf, 1, &scissor)
    vk.CmdSetRasterizerDiscardEnable(vk_cmd_buf, false)

    // Unused
    vk.CmdSetVertexInputEXT(vk_cmd_buf, 0, nil, 0, nil)
    vk.CmdSetRasterizationSamplesEXT(vk_cmd_buf, { ._1 })
    vk.CmdSetPrimitiveTopology(vk_cmd_buf, .TRIANGLE_LIST)
    vk.CmdSetPrimitiveRestartEnable(vk_cmd_buf, false)

    sample_mask := vk.SampleMask(1)
    vk.CmdSetSampleMaskEXT(vk_cmd_buf, { ._1 }, &sample_mask)
    vk.CmdSetAlphaToCoverageEnableEXT(vk_cmd_buf, false)
    vk.CmdSetPolygonModeEXT(vk_cmd_buf, .FILL)
    vk.CmdSetCullMode(vk_cmd_buf, { .BACK })
    vk.CmdSetFrontFace(vk_cmd_buf, .COUNTER_CLOCKWISE)
}

_cmd_end_render_pass :: proc(cmd_buf: Command_Buffer)
{
    vk_cmd_buf := cast(vk.CommandBuffer) cmd_buf
    vk.CmdEndRendering(vk_cmd_buf)
}

_cmd_draw_indexed_instanced :: proc(cmd_buf: Command_Buffer, vertex_data: rawptr, fragment_data: rawptr,
                                    indices: rawptr, index_count: u32, instance_count: u32 = 1)
{
    vk_cmd_buf := cast(vk.CommandBuffer) cmd_buf

    indices_buf, indices_offset, ok_i := compute_buf_offset_from_gpu_ptr(indices)
    if !ok_i
    {
        log.error("Indices alloc not found")
        return
    }

    push_constants := Graphics_Shader_Push_Constants {
        vert_data = vertex_data,
        frag_data = fragment_data,
        indirect_data = nil,
    }
    vk.CmdPushConstants(vk_cmd_buf, ctx.common_pipeline_layout_graphics, { .VERTEX, .FRAGMENT }, 0, size_of(Graphics_Shader_Push_Constants), &push_constants)

    vk.CmdBindIndexBuffer(vk_cmd_buf, indices_buf, vk.DeviceSize(indices_offset), .UINT32)
    vk.CmdDrawIndexed(vk_cmd_buf, index_count, instance_count, 0, 0, 0)
}

_cmd_draw_indexed_instanced_indirect :: proc(cmd_buf: Command_Buffer, vertex_data: rawptr, fragment_data: rawptr,
                                            indices: rawptr, indirect_arguments: rawptr)
{
    vk_cmd_buf := cast(vk.CommandBuffer) cmd_buf

    indices_buf, indices_offset, ok_i := compute_buf_offset_from_gpu_ptr(indices)
    if !ok_i
    {
        log.error("Indices alloc not found")
        return
    }

    arguments_buf, arguments_offset, ok_a := compute_buf_offset_from_gpu_ptr(indirect_arguments)
    if !ok_a
    {
        log.error("Arguments alloc not found")
        return
    }

    push_constants := Graphics_Shader_Push_Constants {
        vert_data = vertex_data,
        frag_data = fragment_data,
        indirect_data = indirect_arguments,
    }
    vk.CmdPushConstants(vk_cmd_buf, ctx.common_pipeline_layout_graphics, { .VERTEX, .FRAGMENT }, 0, size_of(Graphics_Shader_Push_Constants), &push_constants)

    vk.CmdBindIndexBuffer(vk_cmd_buf, indices_buf, vk.DeviceSize(indices_offset), .UINT32)
    vk.CmdDrawIndexedIndirect(vk_cmd_buf, arguments_buf, vk.DeviceSize(arguments_offset), 1, 0)
}

_cmd_draw_indexed_instanced_indirect_multi :: proc(cmd_buf: Command_Buffer, data_vertex: rawptr, data_pixel: rawptr,
                                                    indices: rawptr, indirect_arguments: rawptr, stride: u32, draw_count: rawptr)
{
    vk_cmd_buf := cast(vk.CommandBuffer) cmd_buf

    indices_buf, indices_offset, ok_i := compute_buf_offset_from_gpu_ptr(indices)
    if !ok_i
    {
        log.error("Indices alloc not found")
        return
    }

    arguments_buf, arguments_offset, ok_a := compute_buf_offset_from_gpu_ptr(indirect_arguments)
    if !ok_a
    {
        log.error("Arguments alloc not found")
        return
    }

    draw_count_buf, draw_count_offset, ok_dc := compute_buf_offset_from_gpu_ptr(draw_count)
    if !ok_dc
    {
        log.error("Draw count alloc not found")
        return
    }

    // data_vertex and data_pixel are shared data for vertex and fragment shaders
    // indirect_arguments points to the unified indirect data array containing both command and user data
    // The stride is the size of the combined struct { IndirectDrawCommand cmd; UserData data; }
    push_constants := Graphics_Shader_Push_Constants {
        vert_data = data_vertex,
        frag_data = data_pixel,
        indirect_data = indirect_arguments,
    }
    vk.CmdPushConstants(vk_cmd_buf, ctx.common_pipeline_layout_graphics, { .VERTEX, .FRAGMENT }, 0, size_of(Graphics_Shader_Push_Constants), &push_constants)

    vk.CmdBindIndexBuffer(vk_cmd_buf, indices_buf, vk.DeviceSize(indices_offset), .UINT32)

    max_draw_count: u32 = 0xFFFFFFFF
    buf_size, ok_size := get_buf_size_from_gpu_ptr(indirect_arguments)
    if ok_size && buf_size > vk.DeviceSize(arguments_offset)
    {
        available_size := buf_size - vk.DeviceSize(arguments_offset)
        max_draw_count = u32(available_size / vk.DeviceSize(stride))
    }

    vk.CmdDrawIndexedIndirectCount(vk_cmd_buf, arguments_buf, vk.DeviceSize(arguments_offset), draw_count_buf, vk.DeviceSize(draw_count_offset), max_draw_count, stride)
}

@(private="file")
vk_check :: proc(result: vk.Result, location := #caller_location)
{
    if result != .SUCCESS {
        fatal_error("Vulkan failure: %v", result, location = location)
    }
}

@(private="file")
vk_debug_callback :: proc "system" (severity: vk.DebugUtilsMessageSeverityFlagsEXT,
                                    types: vk.DebugUtilsMessageTypeFlagsEXT,
                                    callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT,
                                    user_data: rawptr) -> b32
{
    context = runtime.default_context()
    context.logger = vk_logger

    level: log.Level
    if .ERROR in severity        do level = .Error
    else if .WARNING in severity do level = .Warning
    else if .INFO in severity    do level = .Info
    else                         do level = .Debug
    log.log(level, callback_data.pMessage)
    if Hook_Debug_Log != nil {
        Hook_Debug_Log(level, callback_data.pMessage)
    }

    return false
}

@(private="file")
fatal_error :: proc(fmt: string, args: ..any, location := #caller_location)
{
    when ODIN_DEBUG {
        log.fatalf(fmt, ..args, location = location)
        runtime.panic("")
    } else {
        log.panicf(fmt, ..args, location = location)
    }
}

@(private="file")
align_up :: proc(x, align: u64) -> (aligned: u64)
{
    assert(0 == (align & (align - 1)), "must align to a power of two")
    return (x + (align - 1)) &~ (align - 1)
}

// Scratch arenas

@(private="file")
scratch_arenas: [4]vmem.Arena

@(private="file")
// Avoid reinitializing scratch arenas between tests.
scratch_arenas_initialized: bool

@(private="file")
init_scratch_arenas :: proc()
{
    if scratch_arenas_initialized {
        return
    }
    scratch_arenas_initialized = true

    for &scratch in scratch_arenas
    {
        error := vmem.arena_init_growing(&scratch)
        assert(error == nil)
    }
}

@(private="file")
@(deferred_out = release_scratch)
acquire_scratch :: proc(used_allocators: ..mem.Allocator) -> (mem.Allocator, vmem.Arena_Temp)
{
    available_arena: ^vmem.Arena
    if len(used_allocators) < 1
    {
        available_arena = &scratch_arenas[0]
    }
    else
    {
        for &scratch in scratch_arenas
        {
            for used_alloc in used_allocators
            {
                // NOTE: We assume that if the data points to the same exact address,
                // it's an arena allocator and it's the same arena
                if used_alloc.data != &scratch
                {
                    available_arena = &scratch
                    break
                }

                if available_arena != nil do break
            }
        }
    }

    assert(available_arena != nil, "Available scratch arena not found.")

    return vmem.arena_allocator(available_arena), vmem.arena_temp_begin(available_arena)
}

@(private="file")
release_scratch :: #force_inline proc(allocator: mem.Allocator, temp: vmem.Arena_Temp)
{
    vmem.arena_temp_end(temp)
}

@(private="file")
create_swapchain :: proc(width: u32, height: u32, frames_in_flight: u32) -> Swapchain
{
    scratch, _ := acquire_scratch()

    res: Swapchain

    surface_caps: vk.SurfaceCapabilitiesKHR
    vk_check(vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(ctx.phys_device, ctx.surface, &surface_caps))

    image_count := max(max(2, surface_caps.minImageCount), frames_in_flight)
    if surface_caps.maxImageCount != 0 do assert(image_count <= surface_caps.maxImageCount)

    surface_format_count: u32
    vk_check(vk.GetPhysicalDeviceSurfaceFormatsKHR(ctx.phys_device, ctx.surface, &surface_format_count, nil))
    surface_formats := make([]vk.SurfaceFormatKHR, surface_format_count, allocator = scratch)
    vk_check(vk.GetPhysicalDeviceSurfaceFormatsKHR(ctx.phys_device, ctx.surface, &surface_format_count, raw_data(surface_formats)))

    surface_format := surface_formats[0]
    for candidate in surface_formats
    {
        if candidate == { .B8G8R8A8_UNORM, .SRGB_NONLINEAR }
        {
            surface_format = candidate
            break
        }
    }

    present_mode_count: u32
    vk_check(vk.GetPhysicalDeviceSurfacePresentModesKHR(ctx.phys_device, ctx.surface, &present_mode_count, nil))
    present_modes := make([]vk.PresentModeKHR, present_mode_count, allocator = scratch)
    vk_check(vk.GetPhysicalDeviceSurfacePresentModesKHR(ctx.phys_device, ctx.surface, &present_mode_count, raw_data(present_modes)))

    present_mode := vk.PresentModeKHR.FIFO
    for candidate in present_modes {
        if candidate == .MAILBOX {
            present_mode = candidate
            break
        }
    }

    res.width = width
    res.height = height

    swapchain_ci := vk.SwapchainCreateInfoKHR {
        sType = .SWAPCHAIN_CREATE_INFO_KHR,
        surface = ctx.surface,
        minImageCount = image_count,
        imageFormat = surface_format.format,
        imageColorSpace = surface_format.colorSpace,
        imageExtent = { res.width, res.height },
        imageArrayLayers = 1,
        imageUsage = { .COLOR_ATTACHMENT },
        preTransform = surface_caps.currentTransform,
        compositeAlpha = { .OPAQUE },
        presentMode = present_mode,
        clipped = true,
    }
    vk_check(vk.CreateSwapchainKHR(ctx.device, &swapchain_ci, nil, &res.handle))

    vk_check(vk.GetSwapchainImagesKHR(ctx.device, res.handle, &image_count, nil))
    res.images = make([]vk.Image, image_count, context.allocator)
    res.texture_keys = make([]Key, image_count, context.allocator)
    vk_check(vk.GetSwapchainImagesKHR(ctx.device, res.handle, &image_count, raw_data(res.images)))

    res.image_views = make([]vk.ImageView, image_count, context.allocator)
    for image, i in res.images
    {
        image_view_ci := vk.ImageViewCreateInfo {
            sType = .IMAGE_VIEW_CREATE_INFO,
            image = image,
            viewType = .D2,
            format = surface_format.format,
            subresourceRange = {
                aspectMask = { .COLOR },
                levelCount = 1,
                layerCount = 1,
            },
        }
        vk_check(vk.CreateImageView(ctx.device, &image_view_ci, nil, &res.image_views[i]))

        tex_info := Texture_Info { handle = image }
        append(&tex_info.views, Image_View_Info { info = image_view_ci, view = res.image_views[i] })
        sync.guard(&ctx.lock)
        idx := pool_append(&ctx.textures, tex_info)
        res.texture_keys[i] = { idx = u64(idx) }
    }

    res.present_semaphores = make([]vk.Semaphore, image_count, context.allocator)

    semaphore_ci := vk.SemaphoreCreateInfo { sType = .SEMAPHORE_CREATE_INFO }
    for &semaphore in res.present_semaphores {
        vk_check(vk.CreateSemaphore(ctx.device, &semaphore_ci, nil, &semaphore))
    }

    return res
}

@(private="file")
destroy_swapchain :: proc(swapchain: ^Swapchain)
{
    delete(swapchain.images)
    for key in swapchain.texture_keys {
        tex_info := get_resource(key, ctx.textures)
        delete(tex_info.views)
        tex_info.views = {}
        pool_free_idx(&ctx.textures, u32(key.idx))
    }
    delete(swapchain.texture_keys)
    for semaphore in swapchain.present_semaphores {
        vk.DestroySemaphore(ctx.device, semaphore, nil)
    }
    delete(swapchain.present_semaphores)
    for image_view in swapchain.image_views {
        vk.DestroyImageView(ctx.device, image_view, nil)
    }
    delete(swapchain.image_views)
    vk.DestroySwapchainKHR(ctx.device, swapchain.handle, nil)

    swapchain^ = {}
}

@(private="file")
Swapchain :: struct
{
    handle: vk.SwapchainKHR,
    width, height: u32,
    images: []vk.Image,
    texture_keys: []Key,
    image_views: []vk.ImageView,
    present_semaphores: []vk.Semaphore,
}

// NOTE: This is slow but unfortunately needed for some things. Vulkan
// is still a "buffer object" centric API.
@(private="file")
search_alloc_from_gpu_ptr :: proc(ptr: rawptr) -> (res: u32, ok: bool)
{
    alloc_idx, found := rbt.find_value(&ctx.alloc_tree, Alloc_Range { u64(uintptr(ptr)), 0 })
    return alloc_idx, found
}

@(private="file")
compute_buf_offset_from_gpu_ptr :: proc(ptr: rawptr) -> (buf: vk.Buffer, offset: u32, ok: bool)
{
    alloc_idx, ok_s := search_alloc_from_gpu_ptr(ptr)
    if !ok_s do return {}, {}, false

    alloc := ctx.gpu_allocs[alloc_idx]

    buf = alloc.buf_handle
    offset = u32(uintptr(ptr) - uintptr(alloc.device_address))
    return buf, offset, true
}

@(private="file")
get_buf_size_from_gpu_ptr :: proc(ptr: rawptr) -> (size: vk.DeviceSize, ok: bool)
{
    alloc_idx, ok_s := search_alloc_from_gpu_ptr(ptr)
    if !ok_s do return 0, false

    // Get actual buffer size from metadata (not allocation size, which may be larger due to alignment)
    alloc := ctx.gpu_allocs[alloc_idx]
    return alloc.buf_size, true
}

// Command buffers
@(private="file")
vk_acquire_cmd_buf :: proc(queue: Queue) -> vk.CommandBuffer
{
    tls_init()
    queue_info := get_resource(queue, &ctx.queues)
    queue_type := queue_info.queue_type

    // Poll semaphores
    found_free := -1
    for _, i in tls_ctx.cmd_bufs[queue_type]
    {
        if tls_ctx.cmd_bufs_timelines[queue_type][i].recording do continue

        sem := tls_ctx.cmd_bufs_timelines[queue_type][i].sem
        des_val := tls_ctx.cmd_bufs_timelines[queue_type][i].val
        val: u64
        vk.GetSemaphoreCounterValue(ctx.device, sem, &val)
        if val >= des_val
        {
            found_free = i
            tls_ctx.cmd_bufs_timelines[queue_type][i].recording = true
            break
        }
    }

    ensure(found_free != -1)  // TODO

    return tls_ctx.cmd_bufs[queue_type][found_free]
}

@(private="file")
vk_submit_cmd_buf :: proc(queue: Queue, cmd_buf: vk.CommandBuffer, signal_sem: vk.Semaphore = {}, signal_value: u64 = 0)
{
    tls_init()
    queue_info := get_resource(queue, &ctx.queues)
    vk_queue := queue_info.handle
    queue_type := queue_info.queue_type

    // Find command buffer in array
    found_idx := -1
    for buf, i in tls_ctx.cmd_bufs[queue_type]
    {
        if buf == cmd_buf
        {
            found_idx = i
            break
        }
    }

    assert(found_idx != -1)

    tls_ctx.cmd_bufs_timelines[queue_type][found_idx].val += 1

    cmd_buf_sem := tls_ctx.cmd_bufs_timelines[queue_type][found_idx].sem
    cmd_buf_sem_value := tls_ctx.cmd_bufs_timelines[queue_type][found_idx].val

    signal_sems: []vk.Semaphore = { cmd_buf_sem, signal_sem } if signal_sem != {} else { cmd_buf_sem }
    signal_values: []u64 = { cmd_buf_sem_value, signal_value } if signal_sem != {} else { cmd_buf_sem_value }

    next: rawptr
    next = &vk.TimelineSemaphoreSubmitInfo {
        sType = .TIMELINE_SEMAPHORE_SUBMIT_INFO,
        pNext = next,
        signalSemaphoreValueCount = u32(len(signal_values)),
        pSignalSemaphoreValues = raw_data(signal_values)
    }
    to_submit := []vk.CommandBuffer { cmd_buf }
    submit_info := vk.SubmitInfo {
        sType = .SUBMIT_INFO,
        pNext = next,
        commandBufferCount = u32(len(to_submit)),
        pCommandBuffers = raw_data(to_submit),
        signalSemaphoreCount = u32(len(signal_sems)),
        pSignalSemaphores = raw_data(signal_sems)
    }
    
    if sync.guard(&ctx.lock) do vk_check(vk.QueueSubmit(vk_queue, 1, &submit_info, {}))

    tls_ctx.cmd_bufs_timelines[queue_type][found_idx].recording = false
}

@(private="file")
vk_get_cmd_buf_timeline :: proc(queue: Queue, cmd_buf: vk.CommandBuffer) -> ^Timeline
{
    tls_init()
    queue_info := get_resource(queue, &ctx.queues)
    queue_type := queue_info.queue_type

    // Find command buffer in array
    found_idx := -1
    for buf, i in tls_ctx.cmd_bufs[queue_type]
    {
        if buf == cmd_buf
        {
            found_idx = i
            break
        }
    }

    assert(found_idx != -1)
    return &tls_ctx.cmd_bufs_timelines[queue_type][found_idx]
}

// Enum conversion

@(private="file")
to_vk_shader_stage :: #force_inline proc(type: Shader_Type_Graphics) -> vk.ShaderStageFlags
{
    switch type
    {
        case .Vertex: return { .VERTEX }
        case .Fragment: return { .FRAGMENT }
    }
    return {}
}

@(private="file")
to_vk_stage :: #force_inline proc(stage: Stage) -> vk.PipelineStageFlags
{
    switch stage
    {
        case .Transfer: return { .TRANSFER }
        case .Compute: return { .COMPUTE_SHADER }
        case .Raster_Color_Out: return { .COLOR_ATTACHMENT_OUTPUT }
        case .Fragment_Shader: return { .FRAGMENT_SHADER }
        case .Vertex_Shader: return { .VERTEX_SHADER }
        case .All: return { .ALL_COMMANDS }
    }
    return {}
}

@(private="file")
to_vk_load_op :: #force_inline proc(load_op: Load_Op) -> vk.AttachmentLoadOp
{
    switch load_op
    {
        case .Clear: return .CLEAR
        case .Load: return .LOAD
        case .Dont_Care: return .DONT_CARE
    }
    return {}
}

@(private="file")
to_vk_store_op :: #force_inline proc(store_op: Store_Op) -> vk.AttachmentStoreOp
{
    switch store_op
    {
        case .Store: return .STORE
        case .Dont_Care: return .DONT_CARE
    }
    return {}
}

@(private="file")
to_vk_compare_op :: #force_inline proc(compare_op: Compare_Op) -> vk.CompareOp
{
    switch compare_op
    {
        case .Never: return .NEVER
        case .Less: return .LESS
        case .Equal: return .EQUAL
        case .Less_Equal: return .LESS_OR_EQUAL
        case .Greater: return .GREATER
        case .Not_Equal: return .NOT_EQUAL
        case .Greater_Equal: return .GREATER_OR_EQUAL
        case .Always: return .ALWAYS
    }
    return {}
}

@(private="file")
to_vk_render_attachment :: #force_inline proc(attach: Render_Attachment) -> vk.RenderingAttachmentInfo
{
    view_desc := attach.view
    texture := attach.texture
    tex_info := get_resource(texture.handle, ctx.textures)
    vk_image := tex_info.handle

    format := view_desc.format
    if format == .Default {
        format = attach.texture.format
    }

    plane_aspect: vk.ImageAspectFlags = { .DEPTH } if format == .D32_Float else { .COLOR }

    image_view_ci := vk.ImageViewCreateInfo {
        sType = .IMAGE_VIEW_CREATE_INFO,
        image = vk_image,
        viewType = to_vk_texture_view_type(view_desc.type),
        format = to_vk_texture_format(format),
        subresourceRange = {
            aspectMask = plane_aspect,
            levelCount = 1,
            layerCount = 1,
        }
    }
    view := get_or_add_image_view(texture.handle, image_view_ci)

    return {
        sType = .RENDERING_ATTACHMENT_INFO,
        imageView = view,
        imageLayout = .GENERAL,
        loadOp = to_vk_load_op(attach.load_op),
        storeOp = to_vk_store_op(attach.store_op),
        clearValue = { color = { float32 = attach.clear_color } }
    }
}

@(private="file")
to_vk_texture_type :: #force_inline proc(type: Texture_Type) -> vk.ImageType
{
    switch type
    {
        case .D2: return .D2
        case .D3: return .D3
        case .D1: return .D1
    }
    return {}
}

@(private="file")
to_vk_texture_view_type :: #force_inline proc(type: Texture_Type) -> vk.ImageViewType
{
    switch type
    {
        case .D2: return .D2
        case .D3: return .D3
        case .D1: return .D1
    }
    return {}
}

@(private="file")
to_vk_texture_format :: proc(format: Texture_Format) -> vk.Format
{
    switch format
    {
        case .Default: panic("Implementation bug!")
        case .RGBA8_Unorm: return .R8G8B8A8_UNORM
        case .BGRA8_Unorm: return .B8G8R8A8_UNORM
        case .D32_Float: return .D32_SFLOAT
    }
    return {}
}

@(private="file")
to_vk_sample_count :: proc(sample_count: u32) -> vk.SampleCountFlags
{
    switch sample_count
    {
        case 0: return { ._1 }
        case 1: return { ._1 }
        case 2: return { ._2 }
        case 4: return { ._4 }
        case 8: return { ._8 }
        case: panic("Unsupported sample count.")
    }
    return {}
}

@(private="file")
to_vk_texture_usage :: proc(usage: Usage_Flags) -> vk.ImageUsageFlags
{
    res: vk.ImageUsageFlags
    if .Sampled in usage do                  res += { .SAMPLED }
    if .Storage in usage do                  res += { .STORAGE }
    if .Color_Attachment in usage do         res += { .COLOR_ATTACHMENT }
    if .Depth_Stencil_Attachment in usage do res += { .DEPTH_STENCIL_ATTACHMENT }
    return res
}

@(private="file")
to_vk_filter :: proc(filter: Filter) -> vk.Filter
{
    switch filter
    {
        case .Linear: return .LINEAR
        case .Nearest: return .NEAREST
    }
    return {}
}

@(private="file")
to_vk_mipmap_filter :: proc(filter: Filter) -> vk.SamplerMipmapMode
{
    switch filter
    {
        case .Linear: return .LINEAR
        case .Nearest: return .NEAREST
    }
    return {}
}

@(private="file")
to_vk_address_mode :: proc(addr_mode: Address_Mode) -> vk.SamplerAddressMode
{
    switch addr_mode
    {
        case .Repeat: return .REPEAT
        case .Mirrored_Repeat: return .MIRRORED_REPEAT
        case .Clamp_To_Edge: return .CLAMP_TO_EDGE
    }
    return {}
}

@(private="file")
find_queue_family :: proc(graphics: bool, compute: bool, transfer: bool) -> u32
{
    {
        scratch, _ := acquire_scratch()

        family_count: u32
        vk.GetPhysicalDeviceQueueFamilyProperties(ctx.phys_device, &family_count, nil)
        family_properties := make([]vk.QueueFamilyProperties, family_count, allocator = scratch)
        vk.GetPhysicalDeviceQueueFamilyProperties(ctx.phys_device, &family_count, raw_data(family_properties))

        for props, i in family_properties
        {
            // NOTE: If a queue family supports graphics, it is required
            // to also support transfer, but it's NOT required
            // to report .TRANSFER in its queueFlags, as stated in
            // the Vulkan spec: https://docs.vulkan.org/spec/latest/chapters/devsandqueues.html
            // (Why?????????)
            supports_graphics := .GRAPHICS in props.queueFlags
            supports_compute  := .COMPUTE in props.queueFlags
            supports_transfer := .TRANSFER in props.queueFlags || supports_graphics || supports_compute

            if graphics != supports_graphics do continue
            if compute  != supports_compute  do continue
            if transfer != supports_transfer do continue

            return u32(i)
        }

        // Ideal queue family Not found. Be a little less strict now in your search.
        for props, i in family_properties
        {
            supports_graphics := .GRAPHICS in props.queueFlags
            supports_compute  := .COMPUTE in props.queueFlags
            supports_transfer := .TRANSFER in props.queueFlags || supports_graphics || supports_compute

            if graphics && !supports_graphics do continue
            if compute  && !supports_compute  do continue
            if transfer && !supports_transfer do continue

            return u32(i)
        }
    }

    panic("Queue family not found!")
}

@(private="file")
Pool :: struct($T: typeid)
{
    array: [dynamic]T,
    free_list: [dynamic]u32,
}

@(private="file")
pool_append :: proc(using pool: ^Pool($T), el: T) -> u32
{
    free_idx: u32
    if len(free_list) > 0 {
        free_idx = pop(&free_list)
    } else {
        append(&array, T {})
        free_idx = u32(len(array)) - 1
    }

    array[free_idx] = el
    return free_idx
}

@(private="file")
pool_free_idx :: proc(using pool: ^Pool($T), idx: u32)
{
    if idx == u32(len(array)) {
        pop(&array)
    } else {
        append(&free_list, idx)
    }
}

@(private="file")
pool_destroy :: proc(using pool: ^Pool($T))
{
    delete(array)
    delete(free_list)
    array = {}
    free_list = {}
}

@(private="file")
get_resource_from_pool :: proc(key: $T, pool: $T2/Pool($T3)) -> ^T3 where size_of(T) == 8
{
    key_ := transmute(Key) key
    return &pool.array[key_.idx]
}

@(private="file")
get_resource_from_slice :: proc(key: $T, array: $T2/[]$T3) -> ^T3 where size_of(T) == 8
{
    key_ := transmute(Key) key
    return &array[key_.idx]
}

@(private="file")
get_resource_from_array :: proc(key: $T, array: ^$T2/[$S]$T3) -> ^T3 where size_of(T) == 8
{
    key_ := transmute(Key) key
    return &array[key_.idx]
}

@(private="file")
get_resource :: proc
{
    get_resource_from_pool,
    get_resource_from_slice,
    get_resource_from_array,
}

// Interop

_get_vulkan_instance :: proc() -> vk.Instance
{
    return ctx.instance
}

_get_vulkan_physical_device :: proc() -> vk.PhysicalDevice
{
    return ctx.phys_device
}

_get_vulkan_device :: proc() -> vk.Device
{
    return ctx.device
}

_get_vulkan_queue :: proc(queue: Queue) -> vk.Queue
{
    return get_resource(queue, &ctx.queues).handle
}

_get_vulkan_queue_family :: proc(queue: Queue) -> u32
{
    return get_resource(queue, &ctx.queues).family_idx
}

_get_vulkan_command_buffer :: proc(cmd_buf: Command_Buffer) -> vk.CommandBuffer
{
    return cast(vk.CommandBuffer) cmd_buf
}

_get_swapchain_image_count :: proc() -> u32
{
    return u32(len(ctx.swapchain.images))
}
