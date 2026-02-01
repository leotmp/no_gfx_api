
package gpu

import "core:slice"
import "core:log"
import "base:runtime"
import vmem "core:mem/virtual"
import "core:mem"
import "core:sync"
import rbt "core:container/rbtree"
import "core:dynlib"
import "core:container/priority_queue"
import "core:strings"
import "core:math"

import vk "vendor:vulkan"
import "vma"

Max_Textures :: 65535
Max_BVHs :: 65535

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
}

@(private="file")
Context :: struct
{
    features: Features,
    instance: vk.Instance,
    debug_messenger: vk.DebugUtilsMessengerEXT,
    surface: vk.SurfaceKHR,
    phys_device: vk.PhysicalDevice,
    device: vk.Device,
    vma_allocator: vma.Allocator,
    physical_properties: Physical_Properties,

    // Allocations
    gpu_allocs: [dynamic]GPU_Alloc_Meta,
    // TODO: freelist of gpu allocs
    cpu_ptr_to_alloc: map[rawptr]u32,  // Each entry has an index to its corresponding GPU allocation
    gpu_ptr_to_alloc: map[rawptr]u32,  // From base GPU allocation pointer to metadata
    alloc_tree: rbt.Tree(Alloc_Range, u32),

    // Common resources
    desc_layouts: [dynamic]vk.DescriptorSetLayout,
    common_pipeline_layout_graphics: vk.PipelineLayout,
    common_pipeline_layout_compute: vk.PipelineLayout,

    // Resource pools
    queues: [Queue_Type]Queue_Info,
    textures: Pool(Texture_Info),
    samplers: [dynamic]Sampler_Info,  // Samplers are interned but have permanent lifetime
    bvhs: Pool(BVH_Info),
    shaders: Pool(Shader_Info),
    command_buffers: Pool(Command_Buffer_Info),
    semaphore_commands: Pool(Semaphore_Command),

    cmd_bufs_timelines: [Queue_Type]Timeline,

    // Swapchain
    swapchain: Swapchain,
    swapchain_image_idx: u32,
    frames_in_flight: u32,

    // Descriptor sizes
    texture_desc_size: u32,
    texture_rw_desc_size: u32,
    sampler_desc_size: u32,
    bvh_desc_size: u32,

    lock: sync.Atomic_Mutex, // Ensures thread-safe access to ctx and VK operations
    tls_contexts: [dynamic]^Thread_Local_Context,
}

@(private="file")
Free_Command_Buffer :: struct
{
    pool_handle: Command_Buffer,
    timeline_value: u64, // Duplicated information from Command_Buffer_Info to avoid locking during search
}

@(private="file")
Thread_Local_Context :: struct
{
    pools: [Queue_Type]vk.CommandPool,
    buffers: [Queue_Type][dynamic]Command_Buffer,
    free_buffers: [Queue_Type]priority_queue.Priority_Queue(Free_Command_Buffer),
}

@(private="file")
Physical_Properties :: struct
{
    bvh_props: vk.PhysicalDeviceAccelerationStructurePropertiesKHR,
    props2: vk.PhysicalDeviceProperties2,
}

@(private="file")
BVH_Info :: struct
{
    handle: vk.AccelerationStructureKHR,
    mem: rawptr,
    is_blas: bool,
    shapes: [dynamic]BVH_Shape_Desc,  // Only used if BLAS.
    blas_desc: BLAS_Desc,
    tlas_desc: TLAS_Desc,
}

@(private="file")
Key :: struct
{
    idx: u64
}
#assert(size_of(Key) == 8)

@(private="file")
Semaphore_Command_Handle :: distinct rawptr

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

@(private="file")
Semaphore_Command :: struct
{
    sem: vk.Semaphore,
    value: u64,
    next: Semaphore_Command_Handle,
}

@(private="file")
Shader_Info :: struct {
    handle: vk.ShaderEXT,
    command_buffers: map[Command_Buffer]Command_Buffer,
    current_workgroup_size: [3]u32,
    is_compute: bool,
}

@(private="file")
Command_Buffer_Info :: struct  {
    handle: vk.CommandBuffer,
    timeline_value: u64,
    thread_id: int,
    queue_type: Queue_Type,
    compute_shader: Maybe(Shader),
    recording: bool,
    pool_handle: Command_Buffer,
    wait_semaphores: Semaphore_Command_Handle,
    signal_semaphores: Semaphore_Command_Handle,
}

// Initialization

@(private="file")
ctx: Context

@(private="file")
vk_logger: log.Logger

_init :: proc()
{
    scratch, _ := acquire_scratch()

    // Load vulkan function pointers
    vk.load_proc_addresses_global(cast(rawptr) get_instance_proc_address)

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
    device_loop: for candidate in phys_devices
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

    raytracing_extensions := []cstring {
        vk.KHR_DEFERRED_HOST_OPERATIONS_EXTENSION_NAME,
        vk.KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME,
        vk.KHR_RAY_QUERY_EXTENSION_NAME,
    }

    // Query physical device feature availability
    {
        supports_raytracing := true

        count: u32
        vk.EnumerateDeviceExtensionProperties(ctx.phys_device, nil, &count, nil)
        extensions := make([]vk.ExtensionProperties, count)
        vk.EnumerateDeviceExtensionProperties(ctx.phys_device, nil, &count, raw_data(extensions))

        for required_ext in raytracing_extensions
        {
            found := false
            for &supported_ext in extensions
            {
                if cstring(&supported_ext.extensionName[0]) == required_ext {
                    found = true
                    continue
                }
            }

            if !found {
                supports_raytracing = false
                break
            }
        }

        ray_query_features := vk.PhysicalDeviceRayQueryFeaturesKHR {
            sType = .PHYSICAL_DEVICE_RAY_QUERY_FEATURES_KHR
        }
        accel_features := vk.PhysicalDeviceAccelerationStructureFeaturesKHR {
            sType = .PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_FEATURES_KHR,
            pNext = &ray_query_features,
        }
        features := vk.PhysicalDeviceFeatures2 {
            sType = .PHYSICAL_DEVICE_FEATURES_2,
            pNext = &accel_features
        }
        vk.GetPhysicalDeviceFeatures2(ctx.phys_device, &features)

        supports_raytracing = supports_raytracing && accel_features.accelerationStructure && ray_query_features.rayQuery

        if supports_raytracing do ctx.features += { .Raytracing }
    }

    // Get physical device properties
    accel_props := vk.PhysicalDeviceAccelerationStructurePropertiesKHR {
        sType = .PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_PROPERTIES_KHR
    }
    desc_buf_props := vk.PhysicalDeviceDescriptorBufferPropertiesEXT {
        sType = .PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_PROPERTIES_EXT,
        pNext = &accel_props,
    }
    props2 := vk.PhysicalDeviceProperties2 {
        sType = .PHYSICAL_DEVICE_PROPERTIES_2,
        pNext = &desc_buf_props,
    }
    vk.GetPhysicalDeviceProperties2(ctx.phys_device, &props2)
    ctx.physical_properties = {
        accel_props, props2
    }

    // Check descriptor sizes
    ensure(desc_buf_props.storageImageDescriptorSize <= 32, "Unexpected storage image descriptor size.")
    ensure(desc_buf_props.sampledImageDescriptorSize <= 32, "Unexpected sampled texture descriptor size.")
    ensure(desc_buf_props.samplerDescriptorSize <= 16, "Unexpected sampler descriptor size.")
    if .Raytracing in ctx.features {
        ensure(desc_buf_props.accelerationStructureDescriptorSize <= 32, "Unexpected BVH descriptor size.")
    }
    ctx.texture_desc_size = u32(desc_buf_props.sampledImageDescriptorSize)
    ctx.texture_rw_desc_size = u32(desc_buf_props.storageImageDescriptorSize)
    ctx.sampler_desc_size = u32(desc_buf_props.samplerDescriptorSize)
    ctx.bvh_desc_size = u32(desc_buf_props.accelerationStructureDescriptorSize)

    // Queues create info
    priority: f32 = 1.0
    queue_create_infos: [dynamic]vk.DeviceQueueCreateInfo = make([dynamic]vk.DeviceQueueCreateInfo, allocator = scratch)
    {
        families: [Queue_Type]u32
        families[.Main] = find_queue_family(graphics = true, compute = true, transfer = true)
        families[.Compute] = find_queue_family(graphics = false, compute = true, transfer = true)
        families[.Transfer] = find_queue_family(graphics = false, compute = false, transfer = true)

        main: for type, type_idx in Queue_Type {
            family := families[type]
            for prev_type, prev_type_idx in Queue_Type {
                if prev_type_idx >= type_idx do break
                if ctx.queues[prev_type].family_idx == family {
                    ctx.queues[type] = ctx.queues[prev_type]
                    ctx.queues[type].queue_type = type
                    continue main
                }
            }

            ctx.queues[type] = {
                queue_type = type,
                family_idx = family,
                queue_idx = 0,
            }

            append(&queue_create_infos, vk.DeviceQueueCreateInfo {
                sType = .DEVICE_QUEUE_CREATE_INFO,
                queueFamilyIndex = family,
                queueCount = 1,
                pQueuePriorities = &priority,
            })
        }
    }

    // Device
    {
        required_extensions := make([dynamic]cstring, allocator = scratch)
        append(&required_extensions, vk.KHR_SWAPCHAIN_EXTENSION_NAME)
        append(&required_extensions, vk.EXT_SHADER_OBJECT_EXTENSION_NAME)
        append(&required_extensions, vk.EXT_DESCRIPTOR_BUFFER_EXTENSION_NAME)
        append(&required_extensions, vk.KHR_DRAW_INDIRECT_COUNT_EXTENSION_NAME)
        if .Raytracing in ctx.features
        {
            append(&required_extensions, vk.KHR_DEFERRED_HOST_OPERATIONS_EXTENSION_NAME)
            append(&required_extensions, vk.KHR_RAY_QUERY_EXTENSION_NAME)
            append(&required_extensions, vk.KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME)
        }

        next: rawptr
        next = &vk.PhysicalDeviceVulkan12Features {
            sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
            pNext = next,
            runtimeDescriptorArray = true,
            shaderSampledImageArrayNonUniformIndexing = true,
            shaderStorageImageArrayNonUniformIndexing = true,
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
                samplerAnisotropy = true,
            }
        }
        raytracing_features := &vk.PhysicalDeviceAccelerationStructureFeaturesKHR {
            sType = .PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_FEATURES_KHR,
            pNext = next,
            accelerationStructure = true,
        }
        if .Raytracing in ctx.features do next = raytracing_features
        rayquery_features := &vk.PhysicalDeviceRayQueryFeaturesKHR {
            sType = .PHYSICAL_DEVICE_RAY_QUERY_FEATURES_KHR,
            pNext = next,
            rayQuery = true,
        }
        if .Raytracing in ctx.features do next = rayquery_features

        device_ci := vk.DeviceCreateInfo {
            sType = .DEVICE_CREATE_INFO,
            pNext = next,
            queueCreateInfoCount = u32(len(queue_create_infos)),
            pQueueCreateInfos = raw_data(queue_create_infos),
            enabledExtensionCount = u32(len(required_extensions)),
            ppEnabledExtensionNames = raw_data(required_extensions),
        }
        vk_check(vk.CreateDevice(ctx.phys_device, &device_ci, nil, &ctx.device))

        vk.load_proc_addresses_device(ctx.device)
        if vk.BeginCommandBuffer == nil do fatal_error("Failed to load Vulkan device API")
    }

    for &queue, type in ctx.queues {
        vk.GetDeviceQueue(ctx.device, queue.family_idx, queue.queue_idx, &queue.handle)
    }

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
            layout: vk.DescriptorSetLayout
            vk_check(vk.CreateDescriptorSetLayout(ctx.device, &layout_ci, nil, &layout))
            append(&ctx.desc_layouts, layout)
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
            layout: vk.DescriptorSetLayout
            vk_check(vk.CreateDescriptorSetLayout(ctx.device, &layout_ci, nil, &layout))
            append(&ctx.desc_layouts, layout)
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
            layout: vk.DescriptorSetLayout
            vk_check(vk.CreateDescriptorSetLayout(ctx.device, &layout_ci, nil, &layout))
            append(&ctx.desc_layouts, layout)
        }
        if .Raytracing in ctx.features
        {
            layout_ci := vk.DescriptorSetLayoutCreateInfo {
                sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
                flags = { .DESCRIPTOR_BUFFER_EXT },
                bindingCount = 1,
                pBindings = &vk.DescriptorSetLayoutBinding {
                    binding = 0,
                    descriptorType = .ACCELERATION_STRUCTURE_KHR,
                    descriptorCount = Max_BVHs,
                    stageFlags = { .VERTEX, .FRAGMENT, .COMPUTE },
                },
            }
            layout: vk.DescriptorSetLayout
            vk_check(vk.CreateDescriptorSetLayout(ctx.device, &layout_ci, nil, &layout))
            append(&ctx.desc_layouts, layout)
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
                setLayoutCount = u32(len(ctx.desc_layouts)),
                pSetLayouts = raw_data(ctx.desc_layouts),
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
                setLayoutCount = u32(len(ctx.desc_layouts)),
                pSetLayouts = raw_data(ctx.desc_layouts),
            }
            vk_check(vk.CreatePipelineLayout(ctx.device, &pipeline_layout_ci, nil, &ctx.common_pipeline_layout_compute))
        }
    }

    // Resource pools
    // NOTE: Reserve slot 0 for all resources as key 0 is invalid.
    pool_init(&ctx.textures)
    pool_init(&ctx.bvhs)
    pool_init(&ctx.shaders)
    pool_init(&ctx.command_buffers)
    pool_init(&ctx.semaphore_commands)

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

    // Init cmd_bufs_timelines
    {
        for type in Queue_Type
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
            vk_check(vk.CreateSemaphore(ctx.device, &sem_ci, nil, &ctx.cmd_bufs_timelines[type].sem))
        }
    }

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
get_tls :: proc() -> ^Thread_Local_Context
{
    @(thread_local)
    tls_ctx: ^Thread_Local_Context

    if tls_ctx != nil do return tls_ctx

    tls_ctx = new(Thread_Local_Context)

    for type in Queue_Type
    {
        cmd_pool_ci := vk.CommandPoolCreateInfo {
            sType = .COMMAND_POOL_CREATE_INFO,
            queueFamilyIndex = ctx.queues[type].family_idx,
            flags = { .TRANSIENT, .RESET_COMMAND_BUFFER }
        }
        vk_check(vk.CreateCommandPool(ctx.device, &cmd_pool_ci, nil, &tls_ctx.pools[type]))

        priority_queue.init(
            &tls_ctx.free_buffers[type],
            less = proc(a,b: Free_Command_Buffer) -> bool {
                return a.timeline_value < b.timeline_value
            },
            swap = proc(q: []Free_Command_Buffer, i, j: int) {
                q[i], q[j] = q[j], q[i]
            }
        )
    }

    if sync.guard(&ctx.lock) do append(&ctx.tls_contexts, tls_ctx)

    return tls_ctx
}

_cleanup :: proc()
{
    sync.guard(&ctx.lock)
    scratch, _ := acquire_scratch()

    {
        // Cleanup all TLS contexts
        for tls_context in ctx.tls_contexts {
            if tls_context != nil {
                for type in Queue_Type {
                    buffers := make([dynamic]vk.CommandBuffer, len(tls_context.buffers[type]), scratch)
                    for buf, i in tls_context.buffers[type] {
                        buf := get_resource(buf, ctx.command_buffers)
                        append(&buffers, transmute(vk.CommandBuffer) buf.handle)
                    }

                    if len(buffers) > 0 {
                        vk.FreeCommandBuffers(ctx.device, tls_context.pools[type], u32(len(buffers)), raw_data(buffers))
                    }

                    vk.DestroyCommandPool(ctx.device, tls_context.pools[type], nil)
                    priority_queue.destroy(&tls_context.free_buffers[type])
                    delete(tls_context.buffers[type])
                }

                free(tls_context)
            }
        }

        delete(ctx.tls_contexts)
        ctx.tls_contexts = {}
    }

    for &sampler in ctx.samplers {
        vk.DestroySampler(ctx.device, sampler.sampler, nil)
    }

    destroy_swapchain(&ctx.swapchain)

    for &layout in ctx.desc_layouts {
        vk.DestroyDescriptorSetLayout(ctx.device, layout, nil)
    }

    vk.DestroyPipelineLayout(ctx.device, ctx.common_pipeline_layout_graphics, nil)
    vk.DestroyPipelineLayout(ctx.device, ctx.common_pipeline_layout_compute, nil)

    for semaphore in ctx.cmd_bufs_timelines {
        vk.DestroySemaphore(ctx.device, semaphore.sem, nil)
    }

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
    queue_wait_idle(.Main)
    recreate_swapchain(size)
}

@(private="file")
recreate_swapchain :: proc(size: [2]u32)
{
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
        cmd_buf := vk_acquire_cmd_buf(.Main)

        vk_cmd_buf := transmute(vk.CommandBuffer) cmd_buf.handle

        cmd_buf_bi := vk.CommandBufferBeginInfo {
            sType = .COMMAND_BUFFER_BEGIN_INFO,
            flags = { .ONE_TIME_SUBMIT },
        }
        vk_check(vk.BeginCommandBuffer(vk_cmd_buf, &cmd_buf_bi))

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
        vk.CmdPipelineBarrier2(vk_cmd_buf, &vk.DependencyInfo {
            sType = .DEPENDENCY_INFO,
            imageMemoryBarrierCount = 1,
            pImageMemoryBarriers = &transition,
        })

        vk_check(vk.EndCommandBuffer(vk_cmd_buf))

        vk_submit_cmd_buf(cmd_buf)
    }

    return Texture {
        dimensions = { ctx.swapchain.width, ctx.swapchain.height, 1 },
        format = .BGRA8_Unorm,
        mip_count = 1,
        handle = transmute(Texture_Handle) ctx.swapchain.texture_keys[ctx.swapchain_image_idx],
    }
}

_swapchain_present :: proc(queue: Queue_Type, sem_wait: Semaphore, wait_value: u64)
{
    tls_ctx := get_tls()

    vk_queue := ctx.queues[queue].handle

    vk_sem_wait := transmute(vk.Semaphore) sem_wait

    present_semaphore := ctx.swapchain.present_semaphores[ctx.swapchain_image_idx]

    // NOTE: Workaround for the fact that swapchain presentation
    // only supports binary semaphores.
    // wait on sem_wait on wait_value and signal ctx.binary_sem
    {
        // Switch to optimal layout for presentation (this is mandatory)
        cmd_buf: ^Command_Buffer_Info
        {
            cmd_buf = vk_acquire_cmd_buf(queue)
            vk_cmd_buf := transmute(vk.CommandBuffer) cmd_buf.handle

            cmd_buf_bi := vk.CommandBufferBeginInfo {
                sType = .COMMAND_BUFFER_BEGIN_INFO,
                flags = { .ONE_TIME_SUBMIT },
            }
            vk_check(vk.BeginCommandBuffer(vk_cmd_buf, &cmd_buf_bi))

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
            vk.CmdPipelineBarrier2(vk_cmd_buf, &vk.DependencyInfo {
                sType = .DEPENDENCY_INFO,
                imageMemoryBarrierCount = 1,
                pImageMemoryBarriers = &transition,
            })

            vk_check(vk.EndCommandBuffer(vk_cmd_buf))
        }

        vk_cmd_buf := transmute(vk.CommandBuffer) cmd_buf.handle

        cmd_buf.timeline_value = sync.atomic_add(&ctx.cmd_bufs_timelines[cmd_buf.queue_type].val, 1) + 1
        queue_sem := ctx.cmd_bufs_timelines[cmd_buf.queue_type].sem

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
                cmd_buf.timeline_value,
            })
        }
        submit_info := vk.SubmitInfo {
            sType = .SUBMIT_INFO,
            pNext = next,
            commandBufferCount = 1,
            pCommandBuffers = &vk_cmd_buf,
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
                queue_sem,
            }),
        }

        if sync.guard(&ctx.lock) do vk_check(vk.QueueSubmit(vk_queue, 1, &submit_info, {}))

        recycle_cmd_buf(cmd_buf)
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

_features_available :: proc() -> Features
{
    return ctx.features
}

_device_limits :: proc() -> Device_Limits
{
    return {
        max_anisotropy = max(1.0, ctx.physical_properties.props2.properties.limits.maxSamplerAnisotropy),
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
            if .Raytracing in ctx.features {
                buf_usage += { .ACCELERATION_STRUCTURE_STORAGE_KHR, .ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR }
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
        meta := ctx.gpu_allocs[cpu_alloc]
        rbt.remove_key(&ctx.alloc_tree, Alloc_Range { u64(meta.device_address), u32(meta.buf_size) })
        vma.destroy_buffer(ctx.vma_allocator, meta.buf_handle, meta.allocation)
        delete_key(&ctx.cpu_ptr_to_alloc, ptr)
    }
    else if gpu_found
    {
        meta := ctx.gpu_allocs[gpu_alloc]
        rbt.remove_key(&ctx.alloc_tree, Alloc_Range { u64(meta.device_address), u32(meta.buf_size) })
        vma.destroy_buffer(ctx.vma_allocator, meta.buf_handle, meta.allocation)
        delete_key(&ctx.gpu_ptr_to_alloc, ptr)
    }
}

_host_to_device_ptr :: proc(ptr: rawptr) -> rawptr
{
    // We could do a tree search here but that would be more expensive
    sync.guard(&ctx.lock)

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
_texture_create :: proc(desc: Texture_Desc, storage: rawptr, queue: Queue_Type = .Main, signal_sem: Semaphore = {}, signal_value: u64 = 0) -> Texture
{
    vk_signal_sem := transmute(vk.Semaphore) signal_sem

    queue_to_use := queue

    alloc_idx, ok_s := search_alloc_from_gpu_ptr(storage)
    if !ok_s
    {
        log.error("Address does not reside in allocated GPU memory.")
        return {}
    }
    sync.lock(&ctx.lock)
    alloc := ctx.gpu_allocs[alloc_idx]
    sync.unlock(&ctx.lock)

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
        vk_cmd_buf := transmute(vk.CommandBuffer) cmd_buf.handle

        cmd_buf_bi := vk.CommandBufferBeginInfo {
            sType = .COMMAND_BUFFER_BEGIN_INFO,
            flags = { .ONE_TIME_SUBMIT },
        }
        vk_check(vk.BeginCommandBuffer(vk_cmd_buf, &cmd_buf_bi))

        transition := vk.ImageMemoryBarrier2 {
            sType = .IMAGE_MEMORY_BARRIER_2,
            image = image,
            subresourceRange = {
                aspectMask = plane_aspect,
                levelCount = desc.mip_count,
                layerCount = desc.layer_count,
            },
            oldLayout = .UNDEFINED,
            newLayout = .GENERAL,
            srcStageMask = { .ALL_COMMANDS },
            srcAccessMask = { .MEMORY_WRITE },
            dstStageMask = { .ALL_COMMANDS },
            dstAccessMask = { .MEMORY_READ, .MEMORY_WRITE },
        }
        vk.CmdPipelineBarrier2(vk_cmd_buf, &vk.DependencyInfo {
            sType = .DEPENDENCY_INFO,
            imageMemoryBarrierCount = 1,
            pImageMemoryBarriers = &transition,
        })

        vk_check(vk.EndCommandBuffer(vk_cmd_buf))
        if vk_signal_sem != {} {
            idx := pool_append(
                &ctx.semaphore_commands,
                Semaphore_Command {
                    sem = vk_signal_sem,
                    value = signal_value,
                    next = cmd_buf.signal_semaphores,
                },
            )
            cmd_buf.signal_semaphores = transmute(Semaphore_Command_Handle) Key { idx = cast(u64) idx }
        }
        vk_submit_cmd_buf(cmd_buf)
    }

    tex_info := Texture_Info { image, {} }
    return {
        dimensions = desc.dimensions,
        format = desc.format,
        mip_count = desc.mip_count,
        handle = transmute(Texture_Handle) u64(pool_append(&ctx.textures, tex_info))
    }
}

_texture_destroy :: proc(texture: ^Texture)
{
    tex_key := transmute(Key) texture.handle
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
    sync.guard(&ctx.lock)
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
            levelCount = texture.mip_count,
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
    if sampler_desc.max_anisotropy != 0.0 {
        ensure(
            sampler_desc.max_anisotropy >= 1.0 &&
            sampler_desc.max_anisotropy <= ctx.physical_properties.props2.properties.limits.maxSamplerAnisotropy,
            "Sampler anisotropy out of range. Call gpu.device_limits() to get the supported maximum anisotropy.",
        )
    }

    sampler_ci := vk.SamplerCreateInfo {
        sType = .SAMPLER_CREATE_INFO,
        magFilter = to_vk_filter(sampler_desc.mag_filter),
        minFilter = to_vk_filter(sampler_desc.min_filter),
        mipmapMode = to_vk_mipmap_filter(sampler_desc.mip_filter),
        addressModeU = to_vk_address_mode(sampler_desc.address_mode_u),
        addressModeV = to_vk_address_mode(sampler_desc.address_mode_v),
        addressModeW = to_vk_address_mode(sampler_desc.address_mode_w),
        mipLodBias = sampler_desc.mip_lod_bias,
        minLod = sampler_desc.min_lod,
        maxLod = sampler_desc.max_lod if sampler_desc.max_lod != 0.0 else vk.LOD_CLAMP_NONE,
        anisotropyEnable = b32(sampler_desc.max_anisotropy > 1.0),
        maxAnisotropy = sampler_desc.max_anisotropy,
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
_shader_create_internal :: proc(code: []u32, is_compute: bool, vk_stage: vk.ShaderStageFlags, entry_point_name: string = "main", group_size_x: u32 = 1, group_size_y: u32 = 1, group_size_z: u32 = 1) -> Shader
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

    entry_point_name_cstr := strings.clone_to_cstring(entry_point_name)
    defer delete(entry_point_name_cstr)

    shader_cis := vk.ShaderCreateInfoEXT {
        sType = .SHADER_CREATE_INFO_EXT,
        codeType = .SPIRV,
        codeSize = len(code) * size_of(code[0]),
        pCode = raw_data(code),
        pName = entry_point_name_cstr,
        stage = vk_stage,
        nextStage = next_stage,
        pushConstantRangeCount = u32(len(push_constant_ranges)),
        pPushConstantRanges = raw_data(push_constant_ranges),
        setLayoutCount = u32(len(ctx.desc_layouts)),
        pSetLayouts = raw_data(ctx.desc_layouts),
        pSpecializationInfo = spec_info_ptr,
    }

    vk_shader: vk.ShaderEXT
    vk_check(vk.CreateShadersEXT(ctx.device, 1, &shader_cis, nil, &vk_shader))

    shader: Shader_Info
    shader.handle = vk_shader
    shader.current_workgroup_size = { group_size_x, group_size_y, group_size_z }
    shader.is_compute = is_compute

    return transmute(Shader) Key { idx = cast(u64) pool_append(&ctx.shaders, shader) }
}

_shader_create :: proc(code: []u32, type: Shader_Type_Graphics, entry_point_name: string = "main") -> Shader
{
    vk_stage := to_vk_shader_stage(type)
    return _shader_create_internal(code, false, vk_stage, entry_point_name)
}

_shader_create_compute :: proc(code: []u32, group_size_x: u32, group_size_y: u32 = 1, group_size_z: u32 = 1, entry_point_name: string = "main") -> Shader
{
    return _shader_create_internal(code, true, { .COMPUTE }, entry_point_name, group_size_x, group_size_y, group_size_z)
}

_shader_destroy :: proc(shader: Shader)
{
    tls := get_tls()
    shader := get_resource(shader, ctx.shaders)
    vk_shader := transmute(vk.ShaderEXT) (shader.handle)
    vk.DestroyShaderEXT(ctx.device, vk_shader, nil)

    // Remove from any command buffer tracking
    for cmd_buf in shader.command_buffers
    {
        cmd_buf_info := get_resource(cmd_buf, ctx.command_buffers)
        cmd_buf_info.compute_shader = {}
    }

    delete(shader.command_buffers)
    pool_free_idx(&ctx.shaders, cast(u32) shader.handle)
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

// Raytracing
_blas_size_and_align :: proc(desc: BLAS_Desc) -> (size: u64, align: u64)
{
    return u64(get_vk_blas_size_info(desc).accelerationStructureSize), 16
}

_blas_create :: proc(desc: BLAS_Desc, storage: rawptr) -> BVH
{
    storage_buf, storage_offset, ok_s := compute_buf_offset_from_gpu_ptr(storage)
    if !ok_s
    {
        log.error("Alloc not found.")
        return {}
    }

    size_info := get_vk_blas_size_info(desc)

    bvh_handle: vk.AccelerationStructureKHR
    blas_ci := vk.AccelerationStructureCreateInfoKHR {
        sType = .ACCELERATION_STRUCTURE_CREATE_INFO_KHR,
        buffer = storage_buf,
        offset = vk.DeviceSize(storage_offset),
        size = size_info.accelerationStructureSize,
        type = .BOTTOM_LEVEL,
    }
    vk_check(vk.CreateAccelerationStructureKHR(ctx.device, &blas_ci, nil, &bvh_handle))

    new_desc := desc
    cloned_shapes := slice.clone_to_dynamic(new_desc.shapes)
    new_desc.shapes = cloned_shapes[:]
    bvh_info := BVH_Info {
        handle = bvh_handle,
        mem = storage,
        is_blas = true,
        shapes = cloned_shapes,
        blas_desc = desc,
    }
    return transmute(BVH) u64(pool_append(&ctx.bvhs, bvh_info))
}

_blas_build_scratch_buffer_size_and_align :: proc(desc: BLAS_Desc) -> (size: u64, align: u64)
{
    return u64(get_vk_blas_size_info(desc).buildScratchSize), u64(ctx.physical_properties.bvh_props.minAccelerationStructureScratchOffsetAlignment)
}

_tlas_size_and_align :: proc(desc: TLAS_Desc) -> (size: u64, align: u64)
{
    return u64(get_vk_tlas_size_info(desc).accelerationStructureSize), 1
}

_tlas_create :: proc(desc: TLAS_Desc, storage: rawptr) -> BVH
{
    storage_buf, storage_offset, ok_s := compute_buf_offset_from_gpu_ptr(storage)
    if !ok_s
    {
        log.error("Alloc not found.")
        return {}
    }

    size_info := get_vk_tlas_size_info(desc)

    bvh_handle: vk.AccelerationStructureKHR
    tlas_ci := vk.AccelerationStructureCreateInfoKHR {
        sType = .ACCELERATION_STRUCTURE_CREATE_INFO_KHR,
        buffer = storage_buf,
        offset = vk.DeviceSize(storage_offset),
        size = size_info.accelerationStructureSize,
        type = .TOP_LEVEL,
    }
    vk_check(vk.CreateAccelerationStructureKHR(ctx.device, &tlas_ci, nil, &bvh_handle))

    bvh_info := BVH_Info {
        handle = bvh_handle,
        mem = storage,
        is_blas = false,
        tlas_desc = desc
    }
    return transmute(BVH) u64(pool_append(&ctx.bvhs, bvh_info))
}

_tlas_build_scratch_buffer_size_and_align :: proc(desc: TLAS_Desc) -> (size: u64, align: u64)
{
    return u64(get_vk_tlas_size_info(desc).buildScratchSize), u64(ctx.physical_properties.bvh_props.minAccelerationStructureScratchOffsetAlignment)
}

_bvh_root_ptr :: proc(bvh: BVH) -> rawptr
{
    bvh_info := get_resource(bvh, ctx.bvhs)

    return transmute(rawptr) vk.GetAccelerationStructureDeviceAddressKHR(ctx.device, & {
        sType = .ACCELERATION_STRUCTURE_DEVICE_ADDRESS_INFO_KHR,
        accelerationStructure = bvh_info.handle
    })
}

_bvh_descriptor :: proc(bvh: BVH) -> BVH_Descriptor
{
    bvh_info := get_resource(bvh, ctx.bvhs)

    bvh_addr := vk.GetAccelerationStructureDeviceAddressKHR(ctx.device, &{
        sType = .ACCELERATION_STRUCTURE_DEVICE_ADDRESS_INFO_KHR,
        accelerationStructure = bvh_info.handle,
    })

    desc: BVH_Descriptor
    info := vk.DescriptorGetInfoEXT {
        sType = .DESCRIPTOR_GET_INFO_EXT,
        type = .ACCELERATION_STRUCTURE_KHR,
        data = { accelerationStructure = bvh_addr }
    }
    vk.GetDescriptorEXT(ctx.device, &info, int(ctx.bvh_desc_size), &desc)
    return desc
}

_get_bvh_descriptor_size :: proc() -> u32
{
    return ctx.bvh_desc_size
}

_bvh_destroy :: proc(bvh: ^BVH)
{
    bvh_key := transmute(Key) (bvh^)
    bvh_info := get_resource(bvh^, ctx.bvhs)

    vk.DestroyAccelerationStructureKHR(ctx.device, bvh_info.handle, nil)

    pool_free_idx(&ctx.bvhs, u32(bvh_key.idx))
    bvh^ = {}
}

@(private="file")
get_vk_blas_size_info :: proc(desc: BLAS_Desc) -> vk.AccelerationStructureBuildSizesInfoKHR
{
    scratch, _ := acquire_scratch()

    primitive_counts := make([]u32, len(desc.shapes), allocator = scratch)
    for shape, i in desc.shapes
    {
        switch s in shape
        {
            case BVH_Mesh_Desc: primitive_counts[i] = s.tri_count
            case BVH_AABB_Desc: primitive_counts[i] = s.aabb_count
        }
    }

    build_info := to_vk_blas_desc(desc, scratch)

    size_info := vk.AccelerationStructureBuildSizesInfoKHR { sType = .ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR }
    vk.GetAccelerationStructureBuildSizesKHR(ctx.device, .DEVICE, &build_info, raw_data(primitive_counts), &size_info)
    return size_info
}

@(private="file")
get_vk_tlas_size_info :: proc(desc: TLAS_Desc) -> vk.AccelerationStructureBuildSizesInfoKHR
{
    scratch, _ := acquire_scratch()

    build_info := to_vk_tlas_desc(desc, scratch)

    size_info := vk.AccelerationStructureBuildSizesInfoKHR { sType = .ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR }
    primitive_count := desc.instance_count
    vk.GetAccelerationStructureBuildSizesKHR(ctx.device, .DEVICE, &build_info, &primitive_count, &size_info)
    return size_info
}

// Command buffer

_queue_wait_idle :: proc(queue: Queue_Type)
{
    sync.guard(&ctx.lock)
    vk.QueueWaitIdle(ctx.queues[queue].handle)
}

_commands_begin :: proc(queue: Queue_Type) -> Command_Buffer
{
    cmd_buf := vk_acquire_cmd_buf(queue)

    cmd_buf_bi := vk.CommandBufferBeginInfo {
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = { .ONE_TIME_SUBMIT },
    }
    vk_cmd_buf := transmute(vk.CommandBuffer) cmd_buf.handle
    vk_check(vk.BeginCommandBuffer(vk_cmd_buf, &cmd_buf_bi))

    return cmd_buf.pool_handle
}

_queue_submit :: proc(queue: Queue_Type, cmd_bufs: []Command_Buffer)
{
    for cmd_buf in cmd_bufs
    {
        cmd_buf_info := get_resource(cmd_buf, ctx.command_buffers)

        // Validate that the provided queue matches the command buffer's associated queue
        ensure(cmd_buf_info.queue_type == queue, "queue_submit: provided queue does not match the queue associated with command buffer")

        vk_cmd_buf := cmd_buf_info.handle
        vk_check(vk.EndCommandBuffer(vk_cmd_buf))

        vk_submit_cmd_buf(cmd_buf_info)
    }
}

// Commands

_cmd_mem_copy :: proc(cmd_buf: Command_Buffer, src, dst: rawptr, #any_int bytes: i64)
{
    cmd_buf := get_resource(cmd_buf, ctx.command_buffers)

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
    vk.CmdCopyBuffer(cmd_buf.handle, src_buf, dst_buf, u32(len(copy_regions)), raw_data(copy_regions))
}

// TODO: dst is ignored atm.
_cmd_copy_to_texture :: proc(cmd_buf: Command_Buffer, texture: Texture, src, dst: rawptr)
{
    cmd_buf_info := get_resource(cmd_buf, ctx.command_buffers)
    tex_info := get_resource(texture.handle, ctx.textures)

    vk_image := tex_info.handle

    src_buf, src_offset, ok_s := compute_buf_offset_from_gpu_ptr(src)
    if !ok_s {
        log.error("Alloc not found.")
        return
    }

    plane_aspect: vk.ImageAspectFlags = { .DEPTH } if texture.format == .D32_Float else { .COLOR }

    vk.CmdCopyBufferToImage(cmd_buf_info.handle, src_buf, vk_image, .GENERAL, 1, &vk.BufferImageCopy {
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

_cmd_blit_texture :: proc(cmd_buf: Command_Buffer, src, dst: Texture, src_rects: []Blit_Rect, dst_rects: []Blit_Rect, filter: Filter)
{
    assert(len(src_rects) == len(dst_rects))

    cmd_buf_info := get_resource(cmd_buf, ctx.command_buffers)
    src_info := get_resource(src.handle, ctx.textures)
    dst_info := get_resource(dst.handle, ctx.textures)

    vk_filter := to_vk_filter(filter)

    // TODO: This needs to be thread-local!!!
    scratch, _ := acquire_scratch()
    regions := make([]vk.ImageBlit, len(src_rects), allocator = scratch)
    for &region, i in regions
    {
        src_rect := src_rects[i]
        dst_rect := dst_rects[i]

        src_dimensions := [3]i32 { i32(src.dimensions.x), i32(src.dimensions.y), i32(src.dimensions.z) }
        dst_dimensions := [3]i32 { i32(dst.dimensions.x), i32(dst.dimensions.y), i32(dst.dimensions.z) }

        src_offsets := [2][3]i32 { src_rect.offset_a, src_rect.offset_b }
        if src_offsets == ([2][3]i32 { { 0, 0, 0 }, { 0, 0, 0 } }) {
            src_offsets[1] = get_mip_dimensions_i32(src_dimensions, src_rect.mip_level)
        }

        dst_offsets := [2][3]i32 { dst_rect.offset_a, dst_rect.offset_b }
        if dst_offsets == ([2][3]i32 { { 0, 0, 0 }, { 0, 0, 0 } }) {
            dst_offsets[1] = get_mip_dimensions_i32(dst_dimensions, dst_rect.mip_level)
        }

        region = {
            srcSubresource = {
                aspectMask = { .COLOR },
                mipLevel = src_rect.mip_level,
                baseArrayLayer = src_rect.base_layer,
                layerCount = src_rect.layer_count if src_rect.layer_count > 0 else 1,  // TODO
            },
            srcOffsets = {
                { src_offsets[0].x, src_offsets[0].y, src_offsets[0].z },
                { src_offsets[1].x, src_offsets[1].y, src_offsets[1].z },
            },
            dstSubresource = {
                aspectMask = { .COLOR },
                mipLevel = dst_rect.mip_level,
                baseArrayLayer = dst_rect.base_layer,
                layerCount = dst_rect.layer_count if dst_rect.layer_count > 0 else 1,  // TODO
            },
            dstOffsets = {
                { dst_offsets[0].x, dst_offsets[0].y, dst_offsets[0].z },
                { dst_offsets[1].x, dst_offsets[1].y, dst_offsets[1].z },
            }
        }
    }

    vk.CmdBlitImage(cmd_buf_info.handle, src_info.handle, .GENERAL, dst_info.handle, .GENERAL, u32(len(regions)), raw_data(regions), vk_filter)
}

_cmd_copy_mips_to_texture :: proc(
    cmd_buf: Command_Buffer,
    texture: Texture,
    src_buffer: rawptr,
    regions: []Mip_Copy_Region,
)
{
    sync.lock(&ctx.lock)
    cmd := get_resource(cmd_buf, ctx.command_buffers)
    tex_info := get_resource(texture.handle, ctx.textures)
    sync.unlock(&ctx.lock)

    src_buf, base_offset, ok_s := compute_buf_offset_from_gpu_ptr(src_buffer)
    if !ok_s {
        fatal_error("Alloc not found.")
        return
    }

    if texture.mip_count < u32(len(regions)) {
        fatal_error("Texture mip count is less than the number of regions")
        return
    }

    plane_aspect: vk.ImageAspectFlags = { .DEPTH } if texture.format == .D32_Float else { .COLOR }
    is_compressed := is_block_compressed(texture.format)

    scratch, _ := acquire_scratch()

    copies := make([]vk.BufferImageCopy, len(regions), allocator = scratch)

    for region, i in regions {
        mip_width := max(1, texture.dimensions.x >> region.mip_level)
        mip_height := max(1, texture.dimensions.y >> region.mip_level)
        mip_depth := max(1, texture.dimensions.z >> region.mip_level)

        copies[i] = vk.BufferImageCopy{
            bufferOffset = vk.DeviceSize(u64(base_offset) + region.src_offset),
            bufferRowLength = 0 if is_compressed else mip_width,
            bufferImageHeight = 0 if is_compressed else mip_height,
            imageSubresource = {
                aspectMask = plane_aspect,
                mipLevel = region.mip_level,
                baseArrayLayer = region.array_layer,
                layerCount = region.layer_count,
            },
            imageOffset = {},
            imageExtent = { mip_width, mip_height, mip_depth },
        }
    }

    vk.CmdCopyBufferToImage(
        cmd.handle,
        src_buf,
        tex_info.handle,
        .GENERAL,
        cast(u32) len(copies),
        raw_data(copies),
    )
}

_cmd_set_desc_heap :: proc(cmd_buf: Command_Buffer, textures, textures_rw, samplers, bvhs: rawptr)
{
    cmd_buf := get_resource(cmd_buf, ctx.command_buffers)

    vk_cmd_buf := cmd_buf.handle

    if textures == nil && textures_rw == nil && samplers == nil && bvhs != nil do return

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
            sync.guard(&ctx.lock)
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
            sync.guard(&ctx.lock)
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
            sync.guard(&ctx.lock)
            if ctx.gpu_allocs[alloc].alloc_type != .Descriptors {
                log.error("Attempted to use cmd_set_texture_heap with memory that wasn't allocated with alloc_type = .Descriptors!")
                return
            }
        }
        if bvhs != nil
        {
            alloc, ok_s := search_alloc_from_gpu_ptr(bvhs)
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

    infos: [4]vk.DescriptorBufferBindingInfoEXT
    // Fill in infos with the subset of valid pointers
    cursor := u32(0)
    if textures != nil
    {
        infos[cursor] = {
            sType = .DESCRIPTOR_BUFFER_BINDING_INFO_EXT,
            address = transmute(vk.DeviceAddress) textures,
            usage = { .RESOURCE_DESCRIPTOR_BUFFER_EXT, .SHADER_DEVICE_ADDRESS, .TRANSFER_SRC, .TRANSFER_DST },
        }
        cursor += 1
    }
    if textures_rw != nil
    {
        infos[cursor] = {
            sType = .DESCRIPTOR_BUFFER_BINDING_INFO_EXT,
            address = transmute(vk.DeviceAddress) textures_rw,
            usage = { .RESOURCE_DESCRIPTOR_BUFFER_EXT, .SHADER_DEVICE_ADDRESS, .TRANSFER_SRC, .TRANSFER_DST },
        }
        cursor += 1
    }
    if samplers != nil
    {
        infos[cursor] = {
            sType = .DESCRIPTOR_BUFFER_BINDING_INFO_EXT,
            address = transmute(vk.DeviceAddress) samplers,
            usage = { .RESOURCE_DESCRIPTOR_BUFFER_EXT, .SHADER_DEVICE_ADDRESS, .TRANSFER_SRC, .TRANSFER_DST },
        }
        cursor += 1
    }
    if bvhs != nil
    {
        infos[cursor] = {
            sType = .DESCRIPTOR_BUFFER_BINDING_INFO_EXT,
            address = transmute(vk.DeviceAddress) bvhs,
            usage = { .RESOURCE_DESCRIPTOR_BUFFER_EXT, .SHADER_DEVICE_ADDRESS, .TRANSFER_SRC, .TRANSFER_DST },
        }
        cursor += 1
    }

    vk.CmdBindDescriptorBuffersEXT(vk_cmd_buf, cursor, &infos[0])

    buffer_offsets := []vk.DeviceSize { 0, 0, 0, 0 }
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
    if bvhs != nil {
        vk.CmdSetDescriptorBufferOffsetsEXT(vk_cmd_buf, .GRAPHICS, ctx.common_pipeline_layout_graphics, 3, 1, &cursor, &buffer_offsets[3])
        vk.CmdSetDescriptorBufferOffsetsEXT(vk_cmd_buf, .COMPUTE, ctx.common_pipeline_layout_compute, 3, 1, &cursor, &buffer_offsets[3])
        cursor += 1
    }
}

_cmd_add_wait_semaphore :: proc(cmd_buf: Command_Buffer, sem: Semaphore, wait_value: u64)
{
    cmd_buf_info := get_resource(cmd_buf, ctx.command_buffers)
    ensure(cmd_buf_info.recording, "cmd_add_wait_semaphore called on non-recording command buffer")
    idx := pool_append(
        &ctx.semaphore_commands,
        Semaphore_Command {
            sem = transmute(vk.Semaphore) sem,
            value = wait_value,
            next = cmd_buf_info.wait_semaphores,
        },
    )
    cmd_buf_info.wait_semaphores = transmute(Semaphore_Command_Handle) Key { idx = cast(u64) idx }
}

_cmd_add_signal_semaphore :: proc(cmd_buf: Command_Buffer, sem: Semaphore, signal_value: u64)
{
    cmd_buf_info := get_resource(cmd_buf, ctx.command_buffers)
    ensure(cmd_buf_info.recording, "cmd_add_signal_semaphore called on non-recording command buffer")
    idx := pool_append(
        &ctx.semaphore_commands,
        Semaphore_Command {
            sem = transmute(vk.Semaphore) sem,
            value = signal_value,
            next = cmd_buf_info.signal_semaphores,
        },
    )
    cmd_buf_info.signal_semaphores = transmute(Semaphore_Command_Handle) Key { idx = cast(u64) idx }
}

_cmd_barrier :: proc(cmd_buf: Command_Buffer, before: Stage, after: Stage, hazards: Hazard_Flags = {})
{
    cmd_buf := get_resource(cmd_buf, ctx.command_buffers)

    vk_cmd_buf := cmd_buf.handle

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
    if .BVHs in hazards
    {
        src_access += { .ACCELERATION_STRUCTURE_WRITE_KHR }
        dst_access += { .ACCELERATION_STRUCTURE_READ_KHR }
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
    cmd_buf := get_resource(cmd_buf, ctx.command_buffers)
    vert_shader := get_resource(vert_shader, ctx.shaders)
    frag_shader := get_resource(frag_shader, ctx.shaders)

    vk_cmd_buf := cmd_buf.handle
    vk_vert_shader := vert_shader.handle
    vk_frag_shader := frag_shader.handle

    shader_stages := []vk.ShaderStageFlags { { .VERTEX }, { .FRAGMENT } }
    to_bind := []vk.ShaderEXT { vk_vert_shader, vk_frag_shader }
    assert(len(shader_stages) == len(to_bind))
    vk.CmdBindShadersEXT(vk_cmd_buf, u32(len(shader_stages)), raw_data(shader_stages), raw_data(to_bind))
}

_cmd_set_depth_state :: proc(cmd_buf: Command_Buffer, state: Depth_State)
{
    cmd_buf := get_resource(cmd_buf, ctx.command_buffers)

    vk_cmd_buf := cmd_buf.handle

    vk.CmdSetDepthCompareOp(vk_cmd_buf, to_vk_compare_op(state.compare))
    vk.CmdSetDepthTestEnable(vk_cmd_buf, .Read in state.mode)
    vk.CmdSetDepthWriteEnable(vk_cmd_buf, .Write in state.mode)
    vk.CmdSetDepthBiasEnable(vk_cmd_buf, false)
    vk.CmdSetDepthClipEnableEXT(vk_cmd_buf, true)
    vk.CmdSetStencilTestEnable(vk_cmd_buf, false)
}

_cmd_set_blend_state :: proc(cmd_buf: Command_Buffer, state: Blend_State)
{
    cmd_buf := get_resource(cmd_buf, ctx.command_buffers)

    vk_cmd_buf := cmd_buf.handle

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
    cmd_buf := get_resource(cmd_buf, ctx.command_buffers)

    vk_cmd_buf := cmd_buf.handle

    shader_info := get_resource(compute_shader, ctx.shaders)
    vk_shader_info := shader_info.handle

    shader_stages := []vk.ShaderStageFlags { { .COMPUTE } }
    to_bind := []vk.ShaderEXT { vk_shader_info }
    assert(len(shader_stages) == len(to_bind))
    vk.CmdBindShadersEXT(vk_cmd_buf, u32(len(shader_stages)), raw_data(shader_stages), raw_data(to_bind))

    cmd_buf.compute_shader = compute_shader
}

_cmd_dispatch :: proc(cmd_buf: Command_Buffer, compute_data: rawptr, num_groups_x: u32, num_groups_y: u32 = 1, num_groups_z: u32 = 1)
{
    cmd_buf := get_resource(cmd_buf, ctx.command_buffers)

    vk_cmd_buf := cmd_buf.handle

    if _, ok := cmd_buf.compute_shader.?; !ok
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
    cmd_buf := get_resource(cmd_buf, ctx.command_buffers)

    vk_cmd_buf := cmd_buf.handle

    if _, ok := cmd_buf.compute_shader.?; !ok
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
    cmd_buf := get_resource(cmd_buf, ctx.command_buffers)

    ensure(cmd_buf.queue_type == .Main, "cmd_begin_render_pass called on a non-graphics command buffer")
    vk_cmd_buf := cmd_buf.handle

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
    cmd_buf := get_resource(cmd_buf, ctx.command_buffers)

    vk_cmd_buf := cmd_buf.handle
    vk.CmdEndRendering(vk_cmd_buf)
}

_cmd_draw_indexed_instanced :: proc(cmd_buf: Command_Buffer, vertex_data: rawptr, fragment_data: rawptr,
                                    indices: rawptr, index_count: u32, instance_count: u32 = 1)
{
    cmd_buf := get_resource(cmd_buf, ctx.command_buffers)

    vk_cmd_buf := cmd_buf.handle

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
    cmd_buf := get_resource(cmd_buf, ctx.command_buffers)

    vk_cmd_buf := cmd_buf.handle

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
    cmd_buf := get_resource(cmd_buf, ctx.command_buffers)

    vk_cmd_buf := cmd_buf.handle

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

_cmd_build_blas :: proc(cmd_buf: Command_Buffer, bvh: BVH, bvh_storage: rawptr, scratch_storage: rawptr, shapes: []BVH_Shape)
{
    cmd_buf := get_resource(cmd_buf, ctx.command_buffers)

    vk_cmd_buf := cmd_buf.handle

    bvh_info := get_resource(bvh, ctx.bvhs)

    if !bvh_info.is_blas
    {
        log.error("This BVH is not a BLAS.")
        return
    }

    if len(shapes) != len(bvh_info.blas_desc.shapes)
    {
        log.error("Length used in the shapes argument and length used in the shapes supplied during the creation of this BVH don't match.")
        return
    }

    // TODO: Check for mismatching types.
    /*
    for shape, i in shapes
    {
        switch s in shape
        {
            case BVH_Mesh: {}
            case BVH_AABBs: {}
        }
    }
    */

    scratch, _ := acquire_scratch()

    build_info := to_vk_blas_desc(bvh_info.blas_desc, arena = scratch)
    build_info.dstAccelerationStructure = bvh_info.handle
    build_info.scratchData.deviceAddress = transmute(vk.DeviceAddress) scratch_storage
    assert(u32(len(shapes)) == build_info.geometryCount)

    range_infos := make([]vk.AccelerationStructureBuildRangeInfoKHR, len(shapes), allocator = scratch)

    // Fill in actual data in shapes
    for i in 0..<build_info.geometryCount
    {
        range_infos[i] = {
            // primitiveCount = primitive_count,
            primitiveOffset = 0,
            firstVertex = 0,
            transformOffset = 0,
        }

        geom := &build_info.pGeometries[i]
        switch s in shapes[i]
        {
            case BVH_Mesh:
            {
                geom.geometry.triangles.vertexData.deviceAddress = transmute(vk.DeviceAddress) s.verts
                geom.geometry.triangles.indexData.deviceAddress = transmute(vk.DeviceAddress) s.indices
                range_infos[i].primitiveCount = bvh_info.blas_desc.shapes[i].(BVH_Mesh_Desc).tri_count
            }
            case BVH_AABBs:
            {
                geom.geometry.aabbs.data.deviceAddress = transmute(vk.DeviceAddress) s.data
            }
        }
    }

    // Vulkan expects an array of pointers (to arrays), one pointer per BVH to build.
    // We always build one at a time, so we only need a pointer to an array (double pointer).
    range_infos_ptr := raw_data(range_infos)
    vk.CmdBuildAccelerationStructuresKHR(vk_cmd_buf, 1, &build_info, &range_infos_ptr)
}

_cmd_build_tlas :: proc(cmd_buf: Command_Buffer, bvh: BVH, bvh_storage: rawptr, scratch_storage: rawptr, instances: rawptr)
{
    cmd_buf := get_resource(cmd_buf, ctx.command_buffers)
    bvh_info := get_resource(bvh, ctx.bvhs)

    vk_cmd_buf := cmd_buf.handle

    if bvh_info.is_blas
    {
        log.error("This BVH is not a TLAS.")
        return
    }

    scratch, _ := acquire_scratch()

    build_info := to_vk_tlas_desc(bvh_info.tlas_desc, arena = scratch)
    build_info.dstAccelerationStructure = bvh_info.handle
    build_info.scratchData.deviceAddress = transmute(vk.DeviceAddress) scratch_storage
    assert(build_info.geometryCount == 1)

    // Fill in actual data
    build_info.pGeometries[0].geometry.instances.data.deviceAddress = transmute(vk.DeviceAddress) instances

    // Vulkan expects an array of pointers (to arrays), one pointer per BVH to build.
    // We always build one at a time, and a TLAS always has only one geometry.
    range_info := []vk.AccelerationStructureBuildRangeInfoKHR {
        {
            primitiveCount = bvh_info.tlas_desc.instance_count
        }
    }
    range_info_ptr := raw_data(range_info)
    vk.CmdBuildAccelerationStructuresKHR(vk_cmd_buf, 1, &build_info, &range_info_ptr)
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
@(deferred_out = release_scratch)
acquire_scratch :: proc(used_allocators: ..mem.Allocator) -> (mem.Allocator, vmem.Arena_Temp)
{
    @(thread_local) scratch_arenas: [4]vmem.Arena = {}
    @(thread_local) initialized: bool = false
    if !initialized
    {
        for &scratch in scratch_arenas
        {
            error := vmem.arena_init_growing(&scratch)
            assert(error == nil)
        }

        initialized = true
    }

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
    sync.guard(&ctx.lock)
    alloc_idx, found := rbt.find_value(&ctx.alloc_tree, Alloc_Range { u64(uintptr(ptr)), 0 })
    return alloc_idx, found
}

@(private="file")
compute_buf_offset_from_gpu_ptr :: proc(ptr: rawptr) -> (buf: vk.Buffer, offset: u32, ok: bool)
{
    alloc_idx, ok_s := search_alloc_from_gpu_ptr(ptr)
    if !ok_s do return {}, {}, false

    sync.guard(&ctx.lock)
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

    sync.guard(&ctx.lock)
    // Get actual buffer size from metadata (not allocation size, which may be larger due to alignment)
    alloc := ctx.gpu_allocs[alloc_idx]
    return alloc.buf_size, true
}

// Command buffers
@(private="file")
vk_acquire_cmd_buf :: proc(queue_type: Queue_Type) -> ^Command_Buffer_Info
{
    tls_ctx := get_tls()

    // Check whether there is a free command buffer available with a timeline value that is less than or equal to the current semaphore value
    if handle, ok := priority_queue.pop_safe(&tls_ctx.free_buffers[queue_type]); ok {
        buf := get_resource(handle.pool_handle, ctx.command_buffers)
        ensure(buf.recording == false, "Command buffer on the free list is still recording")

        current_semaphore_value: u64
        vk_check(vk.GetSemaphoreCounterValue(ctx.device, ctx.cmd_bufs_timelines[queue_type].sem, &current_semaphore_value))

        if current_semaphore_value >= buf.timeline_value {
            buf.recording = true
            buf.queue_type = queue_type

            if buf.compute_shader != nil {
                shader_info := get_resource(buf.compute_shader, ctx.shaders)
                delete_key(&shader_info.command_buffers, buf.pool_handle)
                buf.compute_shader = {}
            }

            buf.thread_id = sync.current_thread_id()

            return buf
        } else {
            priority_queue.push(&tls_ctx.free_buffers[queue_type], handle)
        }
    }

    buf: Command_Buffer_Info
    buf.recording = true
    buf.queue_type = queue_type
    buf.compute_shader = {}
    buf.thread_id = sync.current_thread_id()

    // If no free command buffer is available, create a new one
    cmd_buf_ai := vk.CommandBufferAllocateInfo {
        sType = .COMMAND_BUFFER_ALLOCATE_INFO,
        commandPool = tls_ctx.pools[queue_type],
        level = .PRIMARY,
        commandBufferCount = 1,
    }

    vk_check(vk.AllocateCommandBuffers(ctx.device, &cmd_buf_ai, &buf.handle))

    idx := pool_append(&ctx.command_buffers, buf)
    buf_info := get_resource(Key { idx = cast(u64) idx }, ctx.command_buffers)

    buf_info.pool_handle = transmute(Command_Buffer) Key { idx = cast(u64) idx }
    append(&tls_ctx.buffers[queue_type], buf_info.pool_handle)

    return buf_info
}

@(private="file")
vk_submit_cmd_buf :: proc(cmd_buf: ^Command_Buffer_Info)
{
    scratch, _ := acquire_scratch()

    queue_info := ctx.queues[cmd_buf.queue_type]

    vk_queue := queue_info.handle
    queue_type := queue_info.queue_type

    ensure(cmd_buf.recording == true, "Command buffer is not recording. Reusing a command buffer after submit is forbidden.")
    ensure(cmd_buf.thread_id == sync.current_thread_id(), "You are trying to submit a command buffer on different thread than it was recorded on.")

    cmd_buf.timeline_value = sync.atomic_add(&ctx.cmd_bufs_timelines[queue_type].val, 1) + 1
    queue_sem := ctx.cmd_bufs_timelines[queue_type].sem

    wait_sems := make([dynamic]vk.Semaphore, 0, allocator = scratch)
    wait_values := make([dynamic]u64, 0, allocator = scratch)
    wait_stages := make([dynamic]vk.PipelineStageFlags, 0, allocator = scratch)
    for handle := cmd_buf.wait_semaphores; handle != nil; {
        cmd := get_resource(handle, ctx.semaphore_commands)
        append(&wait_sems, cmd.sem)
        append(&wait_values, cmd.value)
        append(&wait_stages, vk.PipelineStageFlags { .ALL_COMMANDS })
        handle = cmd.next
    }

    signal_sems := make([dynamic]vk.Semaphore, 0, allocator = scratch)
    signal_values := make([dynamic]u64, 0, allocator = scratch)
    append(&signal_sems, queue_sem)
    append(&signal_values, cmd_buf.timeline_value)
    for handle := cmd_buf.signal_semaphores; handle != nil; {
        cmd := get_resource(handle, ctx.semaphore_commands)
        append(&signal_sems, cmd.sem)
        append(&signal_values, cmd.value)
        handle = cmd.next
    }

    next: rawptr
    next = &vk.TimelineSemaphoreSubmitInfo {
        sType = .TIMELINE_SEMAPHORE_SUBMIT_INFO,
        pNext = next,
        waitSemaphoreValueCount = u32(len(wait_values)),
        pWaitSemaphoreValues = raw_data(wait_values),
        signalSemaphoreValueCount = u32(len(signal_values)),
        pSignalSemaphoreValues = raw_data(signal_values),
    }
    to_submit := []vk.CommandBuffer { transmute(vk.CommandBuffer) cmd_buf.handle }
    submit_info := vk.SubmitInfo {
        sType = .SUBMIT_INFO,
        pNext = next,
        commandBufferCount = u32(len(to_submit)),
        pCommandBuffers = raw_data(to_submit),
        waitSemaphoreCount = u32(len(wait_sems)),
        pWaitSemaphores = raw_data(wait_sems),
        pWaitDstStageMask = raw_data(wait_stages),
        signalSemaphoreCount = u32(len(signal_sems)),
        pSignalSemaphores = raw_data(signal_sems),
    }

    if sync.guard(&ctx.lock) do vk_check(vk.QueueSubmit(vk_queue, 1, &submit_info, {}))

    recycle_cmd_buf(cmd_buf)
}

@(private="file")
clear_semaphore_commands :: proc(head: ^Semaphore_Command_Handle)
{
    handle := head^
    for handle != nil {
        cmd := get_resource(handle, ctx.semaphore_commands)
        next := cmd.next
        key := transmute(Key) handle
        pool_free_idx(&ctx.semaphore_commands, u32(key.idx))
        handle = next
    }
    head^ = {}
}

@(private="file")
recycle_cmd_buf :: proc(cmd_buf: ^Command_Buffer_Info)
{
    tls_ctx := get_tls()
    cmd_buf.recording = false

    if cmd_buf.wait_semaphores != nil {
        clear_semaphore_commands(&cmd_buf.wait_semaphores)
    }

    if cmd_buf.signal_semaphores != nil {
        clear_semaphore_commands(&cmd_buf.signal_semaphores)
    }

    priority_queue.push(&tls_ctx.free_buffers[cmd_buf.queue_type], Free_Command_Buffer { pool_handle = cmd_buf.pool_handle, timeline_value = cmd_buf.timeline_value })
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
        case .Build_BVH: return { .ACCELERATION_STRUCTURE_BUILD_KHR }
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
        case .RGBA16_Float: return .R16G16B16A16_SFLOAT
        case .BC1_RGBA_Unorm: return .BC1_RGBA_UNORM_BLOCK
        case .BC3_RGBA_Unorm: return .BC3_UNORM_BLOCK
        case .BC7_RGBA_Unorm: return .BC7_UNORM_BLOCK
        case .ASTC_4x4_RGBA_Unorm: return .ASTC_4x4_UNORM_BLOCK
        case .ETC2_RGB8_Unorm: return .ETC2_R8G8B8_UNORM_BLOCK
        case .ETC2_RGBA8_Unorm: return .ETC2_R8G8B8A8_UNORM_BLOCK
        case .EAC_R11_Unorm: return .EAC_R11_UNORM_BLOCK
        case .EAC_RG11_Unorm: return .EAC_R11G11_UNORM_BLOCK
    }
    return {}
}

@(private="file")
is_block_compressed :: #force_inline proc(format: Texture_Format) -> bool
{
    #partial switch format
    {
        case .BC1_RGBA_Unorm,
             .BC3_RGBA_Unorm,
             .BC7_RGBA_Unorm,
             .ASTC_4x4_RGBA_Unorm,
             .ETC2_RGB8_Unorm,
             .ETC2_RGBA8_Unorm,
             .EAC_R11_Unorm,
             .EAC_RG11_Unorm:
            return true
    }

    return false
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
    if .Transfer_Src in usage do             res += { .TRANSFER_SRC }
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
to_vk_blas_desc :: proc(blas_desc: BLAS_Desc, arena: runtime.Allocator) -> vk.AccelerationStructureBuildGeometryInfoKHR
{
    geometries := make([]vk.AccelerationStructureGeometryKHR, len(blas_desc.shapes), allocator = arena)
    for &geom, i in geometries
    {
        switch shape in blas_desc.shapes[i]
        {
            case BVH_Mesh_Desc:
            {
                flags: vk.GeometryFlagsKHR = { .OPAQUE } if shape.opacity == .Fully_Opaque else {}
                geom = vk.AccelerationStructureGeometryKHR {
                    sType = .ACCELERATION_STRUCTURE_GEOMETRY_KHR,
                    flags = flags,
                    geometryType = .TRIANGLES,
                    geometry = { triangles = {
                        sType = .ACCELERATION_STRUCTURE_GEOMETRY_TRIANGLES_DATA_KHR,
                        vertexFormat = .R32G32B32_SFLOAT,
                        vertexData = {},
                        vertexStride = vk.DeviceSize(shape.vertex_stride),
                        maxVertex = shape.max_vertex,
                        indexType = .UINT32,
                        indexData = {},
                        transformData = {},
                    } }
                }
            }
            case BVH_AABB_Desc:
            {
                flags: vk.GeometryFlagsKHR = { .OPAQUE } if shape.opacity == .Fully_Opaque else {}
                geom = vk.AccelerationStructureGeometryKHR {
                    sType = .ACCELERATION_STRUCTURE_GEOMETRY_KHR,
                    flags = flags,
                    geometryType = .AABBS,
                    geometry = { aabbs = {
                        sType = .ACCELERATION_STRUCTURE_GEOMETRY_AABBS_DATA_KHR,
                        stride = vk.DeviceSize(shape.stride),
                        data = {},
                    } }
                }
            }
        }
    }

    return vk.AccelerationStructureBuildGeometryInfoKHR {
        sType = .ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
        flags = to_vk_bvh_flags(blas_desc.hint, blas_desc.caps),
        type = .BOTTOM_LEVEL,
        mode = .BUILD,
        geometryCount = u32(len(geometries)),
        pGeometries = raw_data(geometries)
    }
}

@(private="file")
to_vk_tlas_desc :: proc(tlas_desc: TLAS_Desc, arena: runtime.Allocator) -> vk.AccelerationStructureBuildGeometryInfoKHR
{
    geometry := new(vk.AccelerationStructureGeometryKHR)
    geometry^ = {
        sType = .ACCELERATION_STRUCTURE_GEOMETRY_KHR,
        geometryType = .INSTANCES,
        geometry = {
            instances = {
                sType = .ACCELERATION_STRUCTURE_GEOMETRY_INSTANCES_DATA_KHR,
                arrayOfPointers = false,
                data = {
                    // deviceAddress = vku.get_buffer_device_address(device, instances_buf)
                }
            }
        }
    }

    return vk.AccelerationStructureBuildGeometryInfoKHR {
        sType = .ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
        flags = to_vk_bvh_flags(tlas_desc.hint, tlas_desc.caps),
        type = .TOP_LEVEL,
        mode = .BUILD,
        geometryCount = 1,
        pGeometries = geometry
    }
}

@(private="file")
to_vk_bvh_flags :: proc(hint: BVH_Hint, caps: BVH_Capabilities) -> vk.BuildAccelerationStructureFlagsKHR
{
    flags: vk.BuildAccelerationStructureFlagsKHR
    if .Update in caps do            flags += { .ALLOW_UPDATE }
    if .Compaction in caps do        flags += { .ALLOW_COMPACTION }
    if hint == .Prefer_Fast_Trace do flags += { .PREFER_FAST_TRACE }
    if hint == .Prefer_Fast_Build do flags += { .PREFER_FAST_BUILD }
    if hint == .Prefer_Low_Memory do flags += { .LOW_MEMORY }

    return flags
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
            if props.queueCount == 0 do continue

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
            if props.queueCount == 0 do continue

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
    lock: sync.Atomic_Mutex,
}

@(private="file")
pool_init :: proc(using pool: ^Pool($T), allocated_elements: u32 = 2 >> 24)
{
    sync.guard(&pool.lock)
    array = make([dynamic]T, 0, allocated_elements)
    free_list = make([dynamic]u32, 0, allocated_elements)
    append(&array, T {})
}

@(private="file")
pool_append :: proc(using pool: ^Pool($T), el: T) -> u32
{
    sync.guard(&pool.lock)
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
    sync.guard(&pool.lock)
    if idx == u32(len(array)) {
        pop(&array)
    } else {
        append(&free_list, idx)
    }
}

@(private="file")
pool_destroy :: proc(using pool: ^Pool($T))
{
    sync.guard(&pool.lock)
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

@(private="file")
get_mip_dimensions_u32 :: proc(texture_dimensions: [3]u32, mip_level: u32) -> [3]u32
{
    return {
        max(1, u32(f32(texture_dimensions.x) / f32(u32(1) << mip_level))),
        max(1, u32(f32(texture_dimensions.y) / f32(u32(1) << mip_level))),
        max(1, u32(f32(texture_dimensions.z) / f32(u32(1) << mip_level))),
    }
}

@(private="file")
get_mip_dimensions_i32 :: proc(texture_dimensions: [3]i32, mip_level: u32) -> [3]i32
{
    return {
        max(1, i32(f32(texture_dimensions.x) / f32(i32(1) << mip_level))),
        max(1, i32(f32(texture_dimensions.y) / f32(i32(1) << mip_level))),
        max(1, i32(f32(texture_dimensions.z) / f32(i32(1) << mip_level))),
    }
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

_get_vulkan_queue :: proc(queue: Queue_Type) -> vk.Queue
{
    return ctx.queues[queue].handle
}

_get_vulkan_queue_family :: proc(queue: Queue_Type) -> u32
{
    return ctx.queues[queue].family_idx
}

_get_vulkan_command_buffer :: proc(cmd_buf: Command_Buffer) -> vk.CommandBuffer
{
    cmd_buf := get_resource(cmd_buf, ctx.command_buffers)
    return cmd_buf.handle
}

_get_swapchain_image_count :: proc() -> u32
{
    return u32(len(ctx.swapchain.images))
}
