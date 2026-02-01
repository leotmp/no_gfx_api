
package gpu

import vk "vendor:vulkan"

get_vulkan_instance: proc() -> vk.Instance : _get_vulkan_instance
get_vulkan_physical_device: proc() -> vk.PhysicalDevice : _get_vulkan_physical_device
get_vulkan_device: proc() -> vk.Device : _get_vulkan_device
get_vulkan_queue: proc(queue: Queue_Type) -> vk.Queue : _get_vulkan_queue
get_vulkan_queue_family: proc(queue: Queue_Type) -> u32 : _get_vulkan_queue_family
get_vulkan_command_buffer: proc(cmd_buf: Command_Buffer) -> vk.CommandBuffer : _get_vulkan_command_buffer
get_swapchain_image_count: proc() -> u32 : _get_swapchain_image_count
