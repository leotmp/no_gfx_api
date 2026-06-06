package gltf2

import "base:runtime"
import "core:encoding/base64"
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"


GLB_MAGIC :: 0x46546c67
GLB_HEADER_SIZE :: size_of(GLB_Header)
GLB_CHUNK_HEADER_SIZE :: size_of(GLB_Chunk_Header)
GLTF_MIN_VERSION :: 2


/*
    Main library interface procedures
*/
@(require_results)
load_from_file :: proc(file_name: string, allocator := context.allocator) -> (data: ^Data, err: Error) {
    if !os.exists(file_name) {
        return nil, GLTF_Error{type = .No_File, proc_name = #procedure, param = {name = file_name}}
    }

    file_content, file_err := os.read_entire_file(file_name, allocator)
    if file_err != nil {
        return nil, GLTF_Error{type = .Cant_Read_File, proc_name = #procedure, param = {name = file_name}}
    }

    gltf_dir := filepath.dir(file_name)

    options := Options {
        delete_content = true,
        gltf_dir       = gltf_dir,
    }
    switch strings.to_lower(filepath.ext(file_name), context.temp_allocator) {
    case ".gltf":
        return parse(file_content, options, allocator)
    case ".glb":
        options.is_glb = true
        return parse(file_content, options, allocator)
    case:
        return nil, GLTF_Error{type = .Unknown_File_Type, proc_name = #procedure, param = {name = file_name}}
    }
}

@(require_results)
parse :: proc(file_content: []byte, opt := Options{}, allocator := context.allocator) -> (data: ^Data, err: Error) {
    defer if opt.delete_content {
        delete(file_content)
    }

    if len(file_content) < GLB_HEADER_SIZE {
        return data, GLTF_Error{type = .Data_Too_Short, proc_name = #procedure}
    }

    context.allocator = allocator
    data = new(Data)
    defer if err != nil {
        unload(data)
    }

    json_data := file_content
    content_index: u32

    if opt.is_glb {
        header := (cast(^GLB_Header)(raw_data(file_content[:GLB_HEADER_SIZE])))
        content_index += GLB_HEADER_SIZE

        switch {
        case header.magic != GLB_MAGIC:
            return data, GLTF_Error{type = .Bad_GLB_Magic, proc_name = #procedure}
        case header.version < GLTF_MIN_VERSION:
            return data, GLTF_Error{type = .Unsupported_Version, proc_name = #procedure}
        }

        // GLB file format expects 1 JSON chunk right after header
        json_header := (cast(^GLB_Chunk_Header)(raw_data(file_content[content_index:content_index + GLB_CHUNK_HEADER_SIZE])))
        if json_header.type != CHUNK_TYPE_JSON {
            return data, GLTF_Error{type = .Wrong_Chunk_Type, proc_name = #procedure, param = {name = "JSON Chunk"}}
        }

        content_index += GLB_CHUNK_HEADER_SIZE
        json_data = file_content[content_index:content_index + u32(json_header.length)]
        content_index += u32(json_header.length)
    }

    json_parser := json.make_parser(json_data)
    parsed_object, json_err := json.parse_object(&json_parser)
    data.json_value = parsed_object
    if json_err != .None && json_err != .EOF {
        return data, JSON_Error{type = json_err, parser = json_parser}
    }

    data.asset = asset_parse(parsed_object.(json.Object)) or_return
    data.accessors = accessors_parse(parsed_object.(json.Object)) or_return
    data.animations = animations_parse(parsed_object.(json.Object)) or_return
    data.buffers = buffers_parse(parsed_object.(json.Object), opt.gltf_dir, allocator) or_return
    data.buffer_views = buffer_views_parse(parsed_object.(json.Object)) or_return
    data.cameras = cameras_parse(parsed_object.(json.Object)) or_return
    data.images = images_parse(parsed_object.(json.Object), opt.gltf_dir, allocator) or_return
    data.materials = materials_parse(parsed_object.(json.Object)) or_return
    data.meshes = meshes_parse(parsed_object.(json.Object)) or_return
    data.nodes = nodes_parse(parsed_object.(json.Object)) or_return
    data.samplers = samplers_parse(parsed_object.(json.Object)) or_return
    if scene, ok := parsed_object.(json.Object)[SCENE_KEY]; ok {
        data.scene = Integer(scene.(f64))
    }
    data.scenes = scenes_parse(parsed_object.(json.Object)) or_return
    data.skins = skins_parse(parsed_object.(json.Object)) or_return
    data.textures = textures_parse(parsed_object.(json.Object)) or_return
    data.extensions_used = extensions_names_parse(parsed_object.(json.Object), EXTENSIONS_USED_KEY)
    data.extensions_required = extensions_names_parse(parsed_object.(json.Object), EXTENSIONS_REQUIRED_KEY)
    if extensions, ok := parsed_object.(json.Object)[EXTENSIONS_KEY]; ok {
        data.extensions = extensions
    }
    if extras, ok := parsed_object.(json.Object)[EXTRAS_KEY]; ok {
        data.extras = extras
    }

    // Load remaining binary chunks.
    for buf_idx := 0; opt.is_glb && buf_idx < len(data.buffers) && int(content_index) < len(file_content); buf_idx += 1 {
        chunk_header := (cast(^GLB_Chunk_Header)(raw_data(file_content[content_index:content_index + GLB_CHUNK_HEADER_SIZE])))
        content_index += GLB_CHUNK_HEADER_SIZE

        data.buffers[buf_idx].uri = make([]byte, chunk_header.length)
        mem.copy(raw_data(data.buffers[buf_idx].uri.([]byte)), raw_data(file_content[content_index:]), int(chunk_header.length))
        content_index += u32(chunk_header.length)
    }

    return data, nil
}

// It is safe to pass nil here
unload :: proc(data: ^Data) {
    if data == nil {
        return
    }

    json.destroy_value(data.json_value)
    accessors_free(data.accessors)
    animations_free(data.animations)
    buffers_free(data.buffers)
    buffer_views_free(data.buffer_views)
    cameras_free(data.cameras)
    images_free(data.images)
    materials_free(data.materials)
    meshes_free(data.meshes)
    nodes_free(data.nodes)
    samplers_free(data.samplers)
    scenes_free(data.scenes)
    skins_free(data.skins)
    textures_free(data.textures)
    extensions_names_free(data.extensions_required)
    extensions_names_free(data.extensions_used)
    free(data)
}

/*
    Utilitiy procedures
*/
@(require_results)
extensions_names_parse :: proc(object: json.Object, name: string) -> (res: []string) {
    if name not_in object {
        return
    }

    name_array := object[name].(json.Array)
    res = make([]string, len(name_array))

    for n, i in name_array {
        res[i] = n.(string)
    }

    return res
}

extensions_names_free :: proc(names: []string) {
    if len(names) == 0 {
        return
    }
    delete(names)
}

@(require_results)
uri_parse :: proc(uri: Uri, gltf_dir: string, allocator: runtime.Allocator) -> Uri {
    if uri == nil {
        return uri
    }
    if _, ok := uri.([]byte); ok {
        return uri
    }

    str_data := uri.(string)
    type_idx := strings.index_rune(str_data, ':')
    if type_idx == -1 {
        // Check if this is possible file and if so load it
        bytes, err := os.read_entire_file(fmt.tprintf("%s/%s", gltf_dir, str_data), allocator)
        if err != nil {
            return uri
        }
        return bytes
    }

    type := str_data[:type_idx]
    switch type {
    case "data":
        encoding_start_idx := strings.index_rune(str_data, ';') + 1
        if encoding_start_idx == 0 {
            return uri
        }
        encoding_end_idx := strings.index_rune(str_data, ',')
        if encoding_end_idx == -1 {
            return uri
        }

        encoding := str_data[encoding_start_idx:encoding_end_idx]

        switch encoding {
        case "base64":
            data: []u8
            if data, err := base64.decode(str_data[encoding_end_idx + 1:]); err != nil {
                return uri
            }
            return data
        }
    }

    return uri
}

uri_free :: proc(uri: Uri) {
    if data, ok := uri.([]byte); ok {
        delete(data)
    }
}

@(private)
warning_unexpected_data :: proc(proc_name, key: string, val: json.Value, idx := 0) {
    fmt.printf("WARINING: Unexpected data in proc: %v at index: %v\nKey: %v, valalue: %v\n", proc_name, idx, key, val)
}

/*
    Asseet parsing
*/
@(require_results)
asset_parse :: proc(object: json.Object) -> (res: Asset, err: Error) {
    if ASSET_KEY not_in object {
        return res, GLTF_Error{type = .JSON_Missing_Section, proc_name = #procedure, param = {name = ASSET_KEY}}
    }

    version_found: bool

    for k, v in object[ASSET_KEY].(json.Object) {
        switch k {
        case "copyright":
            res.copyright = v.(string)

        case "generator":
            res.generator = v.(string)

        case "version":
            // Required
            version, ok := strconv.parse_f64(v.(string))
            if !ok {
                return res, GLTF_Error{type = .Invalid_Type, proc_name = #procedure, param = {name = "version"}}
            }
            res.version = Number(version)
            version_found = true

        case "minVersion":
            version, ok := strconv.parse_f64(v.(string))
            if !ok {
                continue
            }
            res.min_version = Number(version)

        case EXTENSIONS_KEY:
            res.extensions = v

        case EXTRAS_KEY:
            res.extras = v

        case:
            warning_unexpected_data(#procedure, k, v)
        }
    }

    if !version_found {
        return res, GLTF_Error{type = .Missing_Required_Parameter, proc_name = #procedure, param = {name = "version"}}
    } else if res.version > GLTF_MIN_VERSION {
        return res, GLTF_Error{type = .Unsupported_Version, proc_name = #procedure}
    }
    return res, nil
}

/*
    Accessors parsing
*/
@(require_results)
accessors_parse :: proc(object: json.Object) -> (res: []Accessor, err: Error) {
    if ACCESSORS_KEY not_in object {
        return
    }

    accessor_array := object[ACCESSORS_KEY].(json.Array)
    res = make([]Accessor, len(accessor_array))

    for access, idx in accessor_array {
        component_type_set, count_set, type_set: bool

        for k, v in access.(json.Object) {
            switch k {
            case "bufferView":
                res[idx].buffer_view = Integer(v.(f64))

            case "byteOffset":
                res[idx].byte_offset = Integer(v.(f64))

            case "componentType":
                // Required
                res[idx].component_type = Component_Type(v.(f64))
                component_type_set = true

            case "normalized":
                res[idx].normalized = v.(bool)

            case "count":
                // Required
                res[idx].count = Integer(v.(f64))
                count_set = true

            case "type":
                // Required
                switch v.(string) {
                case "SCALAR":
                    res[idx].type = .Scalar
                    type_set = true

                case "VEC2":
                    res[idx].type = .Vector2
                    type_set = true

                case "VEC3":
                    res[idx].type = .Vector3
                    type_set = true

                case "VEC4":
                    res[idx].type = .Vector4
                    type_set = true

                case "MAT2":
                    res[idx].type = .Matrix2
                    type_set = true

                case "MAT3":
                    res[idx].type = .Matrix3
                    type_set = true

                case "MAT4":
                    res[idx].type = .Matrix4
                    type_set = true

                case:
                    return res,
                        GLTF_Error{type = .Invalid_Type, proc_name = #procedure, param = {name = v.(string), index = idx}}
                }

            case "max":
                max: [16]Number
                for num, i in v.(json.Array) {
                    max[i] = Number(num.(f64))
                }
                res[idx].max = max

            case "min":
                min: [16]Number
                for num, i in v.(json.Array) {
                    min[i] = Number(num.(f64))
                }
                res[idx].min = min

            case "sparse":
                res[idx].sparse = accessor_sparse_parse(v.(json.Object)) or_return

            case "name":
                res[idx].name = v.(string)

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v

            case:
                warning_unexpected_data(#procedure, k, v, idx)
            }
        }

        if !component_type_set {
            return res,
                GLTF_Error {
                    type = .Missing_Required_Parameter,
                    proc_name = #procedure,
                    param = {name = "componentType", index = idx},
                }
        }
        if !count_set {
            return res,
                GLTF_Error{type = .Missing_Required_Parameter, proc_name = #procedure, param = {name = "count", index = idx}}
        }
        if !type_set {
            return res,
                GLTF_Error{type = .Missing_Required_Parameter, proc_name = #procedure, param = {name = "type", index = idx}}
        }
    }

    return res, nil
}

accessors_free :: proc(accessors: []Accessor) {
    if len(accessors) == 0 {
        return
    }
    for accessor in accessors {
        if accessor.sparse == nil {
            continue
        }
        if len(accessor.sparse.?.indices) > 0 {
            delete(accessor.sparse.?.indices)
        }
        if len(accessor.sparse.?.values) > 0 {
            delete(accessor.sparse.?.values)
        }
    }
    delete(accessors)
}

@(require_results)
accessor_sparse_parse :: proc(object: json.Object) -> (res: Accessor_Sparse, err: Error) {
    for k, v in object {
        switch k {
        case "count": // Not used by this implementation
        case "indices":
            // Required
            res.indices = sparse_indices_parse(v.(json.Array)) or_return

        case "values":
            // Required
            res.values = sparse_values_parse(v.(json.Array)) or_return

        case EXTENSIONS_KEY:
            res.extensions = v

        case EXTRAS_KEY:
            res.extras = v

        case:
            warning_unexpected_data(#procedure, k, v)
        }
    }

    if len(res.indices) == 0 {
        return res, GLTF_Error{type = .Missing_Required_Parameter, proc_name = #procedure, param = {name = "indices"}}
    }
    if len(res.values) == 0 {
        return res, GLTF_Error{type = .Missing_Required_Parameter, proc_name = #procedure, param = {name = "values"}}
    }

    return res, nil
}

@(require_results)
sparse_indices_parse :: proc(array: json.Array) -> (res: []Accessor_Sparse_Indices, err: Error) {
    res = make([]Accessor_Sparse_Indices, len(array))

    for index, idx in array {
        buffer_view_set, component_type_set: bool

        for k, v in index.(json.Object) {
            switch k {
            case "bufferView":
                // Required
                res[idx].buffer_view = Integer(v.(f64))
                buffer_view_set = true

            case "byteOffset":
                // Default 0
                res[idx].byte_offset = Integer(v.(f64))

            case "componentType":
                // Required
                res[idx].component_type = Component_Type(v.(f64))
                component_type_set = true

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v

            case:
                warning_unexpected_data(#procedure, k, v, idx)
            }
        }

        if !buffer_view_set {
            return res,
                GLTF_Error {
                    type = .Missing_Required_Parameter,
                    proc_name = #procedure,
                    param = {name = "bufferView", index = idx},
                }
        }
        if !component_type_set {
            return res,
                GLTF_Error {
                    type = .Missing_Required_Parameter,
                    proc_name = #procedure,
                    param = {name = "componentType", index = idx},
                }
        }
    }

    return res, nil
}

@(require_results)
sparse_values_parse :: proc(array: json.Array) -> (res: []Accessor_Sparse_Values, err: Error) {
    res = make([]Accessor_Sparse_Values, len(array))

    for value, idx in array {
        buffer_view_set: bool

        for k, v in value.(json.Object) {
            switch k {
            case "bufferView":
                // Required
                res[idx].buffer_view = Integer(v.(f64))
                buffer_view_set = true

            case "byteOffset":
                // Defalt 0
                res[idx].byte_offset = Integer(v.(f64))

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v

            case:
                warning_unexpected_data(#procedure, k, v, idx)
            }
        }

        if !buffer_view_set {
            return res,
                GLTF_Error {
                    type = .Missing_Required_Parameter,
                    proc_name = #procedure,
                    param = {name = "bufferView", index = idx},
                }
        }
    }

    return res, nil
}

/*
    Animations parsing
*/
@(require_results)
animations_parse :: proc(object: json.Object) -> (res: []Animation, err: Error) {
    if ANIMATIONS_KEY not_in object {
        return
    }

    animations_array := object[ANIMATIONS_KEY].(json.Array)
    res = make([]Animation, len(animations_array))

    for animation, idx in animations_array {
        for k, v in animation.(json.Object) {
            switch k {
            case "channels":
                // Required
                res[idx].channels = animation_channels_parse(v.(json.Array)) or_return

            case "samplers":
                // Required
                res[idx].samplers = animation_samplers_parse(v.(json.Array)) or_return

            case "name":
                res[idx].name = v.(string)

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v

            case:
                warning_unexpected_data(#procedure, k, v, idx)
            }
        }

        if len(res[idx].channels) == 0 {
            return res,
                GLTF_Error{type = .Missing_Required_Parameter, proc_name = #procedure, param = {name = "channels", index = idx}}
        }
        if len(res[idx].samplers) == 0 {
            return res,
                GLTF_Error{type = .Missing_Required_Parameter, proc_name = #procedure, param = {name = "samplers", index = idx}}
        }
    }
    return res, nil
}

animations_free :: proc(animations: []Animation) {
    if len(animations) == 0 {
        return
    }
    for animation in animations {
        if len(animation.channels) > 0 {
            delete(animation.channels)
        }
        if len(animation.samplers) > 0 {
            delete(animation.samplers)
        }
    }
    delete(animations)
}

@(require_results)
animation_channels_parse :: proc(array: json.Array) -> (res: []Animation_Channel, err: Error) {
    res = make([]Animation_Channel, len(array))

    for channel, idx in array {
        sampler_set, target_set: bool

        for k, v in channel.(json.Object) {
            switch k {
            case "sampler":
                // Required
                res[idx].sampler = Integer(v.(f64))
                sampler_set = true

            case "target":
                // Required
                res[idx].target = animation_channel_target_parse(v.(json.Object)) or_return
                target_set = true

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v

            case:
                warning_unexpected_data(#procedure, k, v, idx)
            }
        }

        if !sampler_set {
            return res,
                GLTF_Error{type = .Missing_Required_Parameter, proc_name = #procedure, param = {name = "sampler", index = idx}}
        }
        if !target_set {
            return res,
                GLTF_Error{type = .Missing_Required_Parameter, proc_name = #procedure, param = {name = "target", index = idx}}
        }
    }

    return res, nil
}

@(require_results)
animation_channel_target_parse :: proc(object: json.Object) -> (res: Animation_Channel_Target, err: Error) {
    path_set: bool

    for k, v in object {
        switch k {
        case "node":
            res.node = Integer(v.(f64))

        case "path":
            // Required
            if path, ok := v.(string); ok {
                path_set = true
                switch path {
                case "translation":
                    res.path = .Translation
                case "rotation":
                    res.path = .Rotation
                case "scale":
                    res.path = .Scale
                case "weights":
                    res.path = .Weights
                case:
                    path_set = false
                }
            }

        case EXTENSIONS_KEY:
            res.extensions = v

        case EXTRAS_KEY:
            res.extras = v

        case:
            warning_unexpected_data(#procedure, k, v)
        }
    }

    if !path_set {
        return res, GLTF_Error{type = .Missing_Required_Parameter, proc_name = #procedure, param = {name = "path"}}
    }

    return res, nil
}

@(require_results)
animation_samplers_parse :: proc(array: json.Array) -> (res: []Animation_Sampler, err: Error) {
    res = make([]Animation_Sampler, len(array))

    for sampler, idx in array {
        input_set, output_set: bool

        for k, v in sampler.(json.Object) {
            switch k {
            case "input":
                // Required
                res[idx].input = Integer(v.(f64))
                input_set = true

            case "interpolation":
                // Defalt Linear(0)
                switch v.(string) {
                case "LINEAR":
                    res[idx].interpolation = .Linear
                case "STEP":
                    res[idx].interpolation = .Step
                case "CUBICSPLINE":
                    res[idx].interpolation = .Cubic_Spline
                case:
                    return res,
                        GLTF_Error{type = .Invalid_Type, proc_name = #procedure, param = {name = v.(string), index = idx}}
                }

            case "output":
                // Required
                res[idx].output = Integer(v.(f64))
                output_set = true

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v

            case:
                warning_unexpected_data(#procedure, k, v)
            }
        }

        if !input_set {
            return res,
                GLTF_Error{type = .Missing_Required_Parameter, proc_name = #procedure, param = {name = "input", index = idx}}
        }
        if !output_set {
            return res,
                GLTF_Error{type = .Missing_Required_Parameter, proc_name = #procedure, param = {name = "output", index = idx}}
        }
    }
    return res, nil
}

/*
    Buffers parsing
*/
@(require_results)
buffers_parse :: proc(object: json.Object, gltf_dir: string, allocator: runtime.Allocator) -> (res: []Buffer, err: Error) {
    if BUFFERS_KEY not_in object {
        return
    }

    buffers_array := object[BUFFERS_KEY].(json.Array)
    res = make([]Buffer, len(buffers_array))

    for buffer, idx in buffers_array {
        byte_length_set: bool

        for k, v in buffer.(json.Object) {
            switch k {
            case "byteLength":
                // Required
                res[idx].byte_length = Integer(v.(f64))
                byte_length_set = true

            case "name":
                res[idx].name = v.(string)

            case "uri":
                res[idx].uri = uri_parse(v.(string), gltf_dir, allocator)

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v

            case:
                warning_unexpected_data(#procedure, k, v, idx)
            }
        }

        if !byte_length_set {
            return res,
                GLTF_Error {
                    type = .Missing_Required_Parameter,
                    proc_name = #procedure,
                    param = {name = "byteLength", index = idx},
                }
        }
    }

    return res, nil
}

buffers_free :: proc(buffers: []Buffer) {
    if len(buffers) == 0 {
        return
    }
    for buffer in buffers {
        uri_free(buffer.uri)
    }
    delete(buffers)
}

/*
    Buffer Views parsing
*/
@(require_results)
buffer_views_parse :: proc(object: json.Object) -> (res: []Buffer_View, err: Error) {
    if BUFFER_VIEWS_KEY not_in object {
        return
    }

    views_array := object[BUFFER_VIEWS_KEY].(json.Array)
    res = make([]Buffer_View, len(views_array))

    for view, idx in views_array {
        buffer_set, byte_length_set: bool

        for k, v in view.(json.Object) {
            switch k {
            case "buffer":
                // Required
                res[idx].buffer = Integer(v.(f64))
                buffer_set = true

            case "byteLength":
                // Required
                res[idx].byte_length = Integer(v.(f64))
                byte_length_set = true

            case "byteOffset":
                res[idx].byte_offset = Integer(v.(f64))

            case "byteStride":
                res[idx].byte_stride = Integer(v.(f64))

            case "name":
                res[idx].name = v.(string)

            case "target":
                res[idx].target = Buffer_Type_Hint(v.(f64))

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v

            case:
                warning_unexpected_data(#procedure, k, v, idx)
            }
        }

        if !buffer_set {
            return res,
                GLTF_Error{type = .Missing_Required_Parameter, proc_name = #procedure, param = {name = "buffer", index = idx}}
        }
        if !byte_length_set {
            return res,
                GLTF_Error {
                    type = .Missing_Required_Parameter,
                    proc_name = #procedure,
                    param = {name = "byteLength", index = idx},
                }
        }
    }

    return res, nil
}

buffer_views_free :: proc(views: []Buffer_View) {
    if len(views) == 0 {
        return
    }
    delete(views)
}

/*
    Cameras parsing
*/
@(require_results)
cameras_parse :: proc(object: json.Object) -> (res: []Camera, err: Error) {
    if CAMERAS_KEY not_in object {
        return
    }

    cameras_array := object[CAMERAS_KEY].(json.Array)
    res = make([]Camera, len(cameras_array))

    for camera, idx in cameras_array {
        for k, v in camera.(json.Object) {
            switch k {
            case "name":
                res[idx].name = v.(string)

            case "type": // Required and not used here. Camera.type is union that can contain only:
            // Orthographic_Camera or Perspective_Camera struct
            case "orthographic":
                res[idx].type = orthographic_camera_parse(v.(json.Object)) or_return

            case "perspective":
                res[idx].type = perspective_camera_parse(v.(json.Object)) or_return

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v

            case:
                warning_unexpected_data(#procedure, k, v, idx)
            }
        }

        if res[idx].type == nil {
            return res,
                GLTF_Error{type = .Missing_Required_Parameter, proc_name = #procedure, param = {name = "type", index = idx}}
        }
    }

    return res, nil
}

cameras_free :: proc(cameras: []Camera) {
    if len(cameras) == 0 {
        return
    }
    delete(cameras)
}

@(require_results)
orthographic_camera_parse :: proc(object: json.Object) -> (res: Orthographic_Camera, err: Error) {
    xmag_set, ymag_set, zfar_set, znear_set: bool

    for k, v in object {
        switch k {
        case "xmag":
            // Required
            res.xmag = Number(v.(f64))
            xmag_set = true

        case "ymag":
            // Required
            res.ymag = Number(v.(f64))
            ymag_set = true

        case "zfar":
            // Required
            res.zfar = Number(v.(f64))
            zfar_set = true

        case "znear":
            // Required
            res.znear = Number(v.(f64))
            znear_set = true

        case EXTENSIONS_KEY:
            res.extensions = v

        case EXTRAS_KEY:
            res.extras = v

        case:
            warning_unexpected_data(#procedure, k, v)
        }
    }

    if !xmag_set {
        return res, GLTF_Error{type = .Missing_Required_Parameter, proc_name = #procedure, param = {name = "xmag"}}
    }
    if !ymag_set {
        return res, GLTF_Error{type = .Missing_Required_Parameter, proc_name = #procedure, param = {name = "ymag"}}
    }
    if !zfar_set {
        return res, GLTF_Error{type = .Missing_Required_Parameter, proc_name = #procedure, param = {name = "zfar"}}
    }
    if !znear_set {
        return res, GLTF_Error{type = .Missing_Required_Parameter, proc_name = #procedure, param = {name = "znear"}}
    }

    return res, nil
}

@(require_results)
perspective_camera_parse :: proc(object: json.Object) -> (res: Perspective_Camera, err: Error) {
    yfov_set, znear_set: bool

    for k, v in object {
        switch k {
        case "aspectRatio":
            res.aspect_ratio = Number(v.(f64))

        case "yfov":
            // Required
            res.yfov = Number(v.(f64))
            yfov_set = true

        case "zfar":
            res.zfar = Number(v.(f64))

        case "znear":
            // Required
            res.znear = Number(v.(f64))
            znear_set = true

        case EXTENSIONS_KEY:
            res.extensions = v

        case EXTRAS_KEY:
            res.extras = v

        case:
            warning_unexpected_data(#procedure, k, v)
        }
    }

    if !yfov_set {
        return res, GLTF_Error{type = .Missing_Required_Parameter, proc_name = #procedure, param = {name = "yfov"}}
    }
    if !znear_set {
        return res, GLTF_Error{type = .Missing_Required_Parameter, proc_name = #procedure, param = {name = "znear"}}
    }

    return res, nil
}

/*
    Images parsing
*/
@(require_results)
images_parse :: proc(object: json.Object, gltf_dir: string, allocator: runtime.Allocator) -> (res: []Image, err: Error) {
    if IMAGES_KEY not_in object {
        return
    }

    images_array := object[IMAGES_KEY].(json.Array)
    res = make([]Image, len(images_array))

    for image, idx in images_array {
        for k, v in image.(json.Object) {
            switch k {
            case "bufferView":
                res[idx].buffer_view = Integer(v.(f64))

            case "mimeType":
                switch v.(string) {
                case "image/jpeg":
                    res[idx].type = .JPEG
                case "image/png":
                    res[idx].type = .PNG
                case:
                    return res,
                        GLTF_Error{type = .Unknown_File_Type, proc_name = #procedure, param = {name = v.(string), index = idx}}
                }

            case "name":
                res[idx].name = v.(string)

            case "uri":
                res[idx].uri = uri_parse(v.(string), gltf_dir, allocator)

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v

            case:
                warning_unexpected_data(#procedure, k, v, idx)
            }
        }
    }

    return res, nil
}

images_free :: proc(images: []Image) {
    if len(images) == 0 {
        return
    }
    for image in images {
        uri_free(image.uri)
    }
    delete(images)
}

/*
    Materials parsing
*/
@(require_results)
materials_parse :: proc(object: json.Object) -> (res: []Material, err: Error) {
    if MATERIALS_KEY not_in object {
        return
    }

    materials_array := object[MATERIALS_KEY].(json.Array)
    res = make([]Material, len(materials_array))

    for material, idx in materials_array {
        res[idx].alpha_cutoff = 0.5

        for k, v in material.(json.Object) {
            switch k {
            case "alphaMode":
                // Default Opaque
                switch v.(string) {
                case "OPAQUE":
                    res[idx].alpha_mode = .Opaque
                case "MASK":
                    res[idx].alpha_mode = .Mask
                case "BLEND":
                    res[idx].alpha_mode = .Blend
                case:
                    return res,
                        GLTF_Error{type = .Invalid_Type, proc_name = #procedure, param = {name = v.(string), index = idx}}
                }

            case "alphaCutoff":
                // Default 0.5
                res[idx].alpha_cutoff = Number(v.(f64))

            case "doubleSided":
                // Default false
                res[idx].double_sided = v.(bool)

            case "emissiveFactor":
                // Default [0, 0, 0]
                for num, i in v.(json.Array) {
                    res[idx].emissive_factor[i] = Number(num.(f64))
                }

            case "emissiveTexture":
                res[idx].emissive_texture = texture_info_parse(v.(json.Object)) or_return

            case "name":
                res[idx].name = v.(string)

            case "normalTexture":
                res[idx].normal_texture = normal_texture_info_parse(v.(json.Object)) or_return

            case "occlusionTexture":
                res[idx].occlusion_texture = occlusion_texture_info_parse(v.(json.Object)) or_return

            case "pbrMetallicRoughness":
                res[idx].metallic_roughness = pbr_metallic_roughness_parse(v.(json.Object)) or_return

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v

            case:
                warning_unexpected_data(#procedure, k, v, idx)
            }
        }
    }
    return res, nil
}

materials_free :: proc(materials: []Material) {
    if len(materials) == 0 {
        return
    }
    delete(materials)
}

@(require_results)
normal_texture_info_parse :: proc(object: json.Object) -> (res: Material_Normal_Texture_Info, err: Error) {
    index_set: bool
    res.scale = 1

    for k, v in object {
        switch k {
        case "index":
            // Required
            res.index = Integer(v.(f64))
            index_set = true

        case "texCoord":
            // Default 0
            res.tex_coord = Integer(v.(f64))

        case "scale":
            // Default 1
            res.scale = Number(v.(f64))

        case EXTENSIONS_KEY:
            res.extras = v

        case EXTRAS_KEY:
            res.extras = v

        case:
            warning_unexpected_data(#procedure, k, v)
        }
    }

    if !index_set {
        return res, GLTF_Error{type = .Missing_Required_Parameter, proc_name = #procedure, param = {name = "index"}}
    }

    return res, nil
}

@(require_results)
occlusion_texture_info_parse :: proc(object: json.Object) -> (res: Material_Occlusion_Texture_Info, err: Error) {
    index_set: bool
    res.strength = 1

    for k, v in object {
        switch k {
        case "index":
            // Required
            res.index = Integer(v.(f64))
            index_set = true

        case "texCoord":
            // Default 0
            res.tex_coord = Integer(v.(f64))

        case "strength":
            // Default 1
            res.strength = Number(v.(f64))

        case EXTENSIONS_KEY:
            res.extras = v

        case EXTRAS_KEY:
            res.extras = v

        case:
            warning_unexpected_data(#procedure, k, v)
        }
    }

    if !index_set {
        return res, GLTF_Error{type = .Missing_Required_Parameter, proc_name = #procedure, param = {name = "index"}}
    }

    return res, nil
}

@(require_results)
pbr_metallic_roughness_parse :: proc(object: json.Object) -> (res: Material_Metallic_Roughness, err: Error) {
    res.base_color_factor = {1, 1, 1, 1}
    res.metallic_factor = 1
    res.roughness_factor = 1

    for k, v in object {
        switch k {
        case "baseColorFactor":
            // Default [ 1, 1, 1, 1 ]
            for num, i in v.(json.Array) {
                res.base_color_factor[i] = Number(num.(f64))
            }

        case "baseColorTexture":
            res.base_color_texture = texture_info_parse(v.(json.Object)) or_return

        case "metallicFactor":
            // Default 1
            res.metallic_factor = Number(v.(f64))

        case "roughnessFactor":
            // Default 1
            res.roughness_factor = Number(v.(f64))

        case "metallicRoughnessTexture":
            res.metallic_roughness_texture = texture_info_parse(v.(json.Object)) or_return

        case EXTENSIONS_KEY:
            res.extras = v

        case EXTRAS_KEY:
            res.extras = v

        case:
            warning_unexpected_data(#procedure, k, v)
        }
    }

    return res, nil
}

/*
    Meshes parsing
*/
@(require_results)
meshes_parse :: proc(object: json.Object) -> (res: []Mesh, err: Error) {
    if MESHES_KEY not_in object {
        return
    }

    meshes_array := object[MESHES_KEY].(json.Array)
    res = make([]Mesh, len(meshes_array))

    for mesh, idx in meshes_array {
        for k, v in mesh.(json.Object) {
            switch k {
            case "name":
                res[idx].name = v.(string)

            case "primitives":
                // Required
                res[idx].primitives = mesh_primitives_parse(v.(json.Array)) or_return

            case "weights":
                res[idx].weights = make([]Number, len(v.(json.Array)))
                for num, i in v.(json.Array) {
                    res[idx].weights[i] = Number(num.(f64))
                }

            case EXTENSIONS_KEY:
                res[idx].extras = v

            case EXTRAS_KEY:
                res[idx].extras = v

            case:
                warning_unexpected_data(#procedure, k, v, idx)
            }
        }

        if len(res[idx].primitives) == 0 {
            return res,
                GLTF_Error {
                    type = .Missing_Required_Parameter,
                    proc_name = #procedure,
                    param = {name = "primitives", index = idx},
                }
        }
    }
    return res, nil
}

meshes_free :: proc(meshes: []Mesh) {
    if len(meshes) == 0 {
        return
    }
    for mesh in meshes {
        if len(mesh.weights) > 0 {
            delete(mesh.weights)
        }
        mesh_primitives_free(mesh.primitives)
    }
    delete(meshes)
}

@(require_results)
mesh_primitives_parse :: proc(array: json.Array) -> (res: []Mesh_Primitive, err: Error) {
    res = make([]Mesh_Primitive, len(array))

    for primitive, idx in array {
        res[idx].mode = .Triangles

        for key, val in primitive.(json.Object) {
            switch key {
            case "attributes":
                // Required
                for k, v in val.(json.Object) {
                    res[idx].attributes[k] = Integer(v.(f64))
                }

            case "indices":
                res[idx].indices = Integer(val.(f64))

            case "material":
                res[idx].material = Integer(val.(f64))

            case "mode":
                // Default Triangles(4)
                res[idx].mode = Mesh_Primitive_Mode(val.(f64))

            case "targets":
                res[idx].targets = mesh_targets_parse(val.(json.Object)) or_return

            case EXTENSIONS_KEY:
                res[idx].extensions = val

            case EXTRAS_KEY:
                res[idx].extras = val

            case:
                warning_unexpected_data(#procedure, key, val, idx)
            }
        }

        if len(res[idx].attributes) == 0 {
            return res,
                GLTF_Error {
                    type = .Missing_Required_Parameter,
                    proc_name = #procedure,
                    param = {name = "attributes", index = idx},
                }
        }
    }

    return res, nil
}

mesh_primitives_free :: proc(primitives: []Mesh_Primitive) {
    if len(primitives) == 0 {
        return
    }
    for primitive in primitives {
        if len(primitive.attributes) > 0 {
            delete(primitive.attributes)
        }
    }
    delete(primitives)
}

@(require_results)
mesh_targets_parse :: proc(object: json.Object) -> (res: []Mesh_Target, err: Error) {
    unimplemented(#procedure)
}

/*
    Nodes parsing
*/
@(require_results)
nodes_parse :: proc(object: json.Object) -> (res: []Node, err: Error) {
    if NODES_KEY not_in object {
        return
    }

    nodes_array := object[NODES_KEY].(json.Array)
    res = make([]Node, len(nodes_array))

    for node, idx in nodes_array {
        res[idx].mat = Matrix4(1)
        res[idx].rotation = Quaternion(1)
        res[idx].scale = {1, 1, 1}

        for k, v in node.(json.Object) {
            switch k {
            case "camera":
                res[idx].camera = Integer(v.(f64))

            case "children":
                res[idx].children = make([]Integer, len(v.(json.Array)))
                for child, i in v.(json.Array) {
                    res[idx].children[i] = Integer(child.(f64))
                }

            case "matrix":
                // Default identity matrix
                // Matrices are stored in column-major order. Odin matrices are indexed like this [row, col]
                for num, i in v.(json.Array) {
                    res[idx].mat[i % 4, i / 4] = Number(num.(f64))
                }

            case "mesh":
                res[idx].mesh = Integer(v.(f64))

            case "name":
                res[idx].name = v.(string)

            case "scale":
                // Default [1, 1, 1]
                for num, i in v.(json.Array) {
                    res[idx].scale[i] = Number(num.(f64))
                }

            case "skin":
                res[idx].skin = Integer(v.(f64))

            case "rotation":
                // Default [0, 0, 0, 1]
                rotation: [4]Number
                for num, i in v.(json.Array) {
                    rotation[i] = Number(num.(f64))
                }
                mem.copy(&res[idx].rotation, &rotation, size_of(Quaternion))

            case "translation":
                // Defalt [0, 0, 0]
                for num, i in v.(json.Array) {
                    res[idx].translation[i] = Number(num.(f64))
                }

            case "weights":
                res[idx].weights = make([]Number, len(v.(json.Array)))
                for weight, i in v.(json.Array) {
                    res[idx].weights[i] = Number(weight.(f64))
                }

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v

            case:
                warning_unexpected_data(#procedure, k, v, idx)
            }
        }
    }
    return res, nil
}

nodes_free :: proc(nodes: []Node) {
    if len(nodes) == 0 {
        return
    }
    for node in nodes {
        if len(node.children) > 0 {
            delete(node.children)
        }
        if len(node.weights) > 0 {
            delete(node.weights)
        }
    }
    delete(nodes)
}

/*
    Samplers parsing
*/
@(require_results)
samplers_parse :: proc(object: json.Object) -> (res: []Sampler, err: Error) {
    if SAMPLERS_KEY not_in object {
        return
    }

    samplers_array := object[SAMPLERS_KEY].(json.Array)
    res = make([]Sampler, len(samplers_array))

    for sampler, idx in samplers_array {
        res[idx].wrapS = .Repeat
        res[idx].wrapT = .Repeat

        for k, v in sampler.(json.Object) {
            switch k {
            case "magFilter":
                res[idx].mag_filter = Magnification_Filter(v.(f64))

            case "minFilter":
                res[idx].min_filter = Minification_Filter(v.(f64))

            case "wrapS":
                // Default Repeat(10497)
                res[idx].wrapS = Wrap_Mode(v.(f64))

            case "wrapT":
                // Default Repeat(10497)
                res[idx].wrapT = Wrap_Mode(v.(f64))

            case "name":
                res[idx].name = v.(string)

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v

            case:
                warning_unexpected_data(#procedure, k, v, idx)
            }
        }
    }
    return res, nil
}

samplers_free :: proc(samplers: []Sampler) {
    if len(samplers) == 0 {
        return
    }
    delete(samplers)
}

/*
    Scenes parsing
*/
@(require_results)
scenes_parse :: proc(object: json.Object) -> (res: []Scene, err: Error) {
    if SCENES_KEY not_in object {
        return
    }

    scenes_array := object[SCENES_KEY].(json.Array)
    res = make([]Scene, len(scenes_array))

    for scene, idx in scenes_array {
        for k, v in scene.(json.Object) {
            switch k {
            case "nodes":
                res[idx].nodes = make([]Integer, len(v.(json.Array)))
                for node, i in v.(json.Array) {
                    res[idx].nodes[i] = Integer(node.(f64))
                }

            case "name":
                res[idx].name = v.(string)

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v

            case:
                warning_unexpected_data(#procedure, k, v, idx)
            }
        }
    }

    return res, nil
}

scenes_free :: proc(scenes: []Scene) {
    if len(scenes) == 0 {
        return
    }
    for scene in scenes {
        if len(scene.nodes) > 0 {
            delete(scene.nodes)
        }
    }
    delete(scenes)
}

/*
    Skins parsing
*/
skins_parse :: proc(object: json.Object) -> (res: []Skin, err: Error) {
    if SKINS_KEY not_in object {
        return
    }

    skins_array := object[SKINS_KEY].(json.Array)
    res = make([]Skin, len(skins_array))

    for skin, idx in skins_array {
        for k, v in skin.(json.Object) {
            switch k {
            case "inverseBindMatrices":
                res[idx].inverse_bind_matrices = Integer(v.(f64))

            case "joints":
                // Required
                res[idx].joints = make([]Integer, len(v.(json.Array)))
                for joint, i in v.(json.Array) {
                    res[idx].joints[i] = Integer(joint.(f64))
                }

            case "name":
                res[idx].name = v.(string)

            case "skeleton":
                res[idx].skeleton = Integer(v.(f64))

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v

            case:
                warning_unexpected_data(#procedure, k, v, idx)
            }
        }

        if len(res[idx].joints) == 0 {
            return res,
                GLTF_Error{type = .Missing_Required_Parameter, proc_name = #procedure, param = {name = "joints", index = idx}}
        }
    }

    return res, nil
}

skins_free :: proc(skins: []Skin) {
    if len(skins) == 0 {
        return
    }
    for skin in skins {
        if len(skin.joints) > 0 {
            delete(skin.joints)
        }
    }
    delete(skins)
}

/*
    Textures parsing
*/
@(require_results)
textures_parse :: proc(object: json.Object) -> (res: []Texture, err: Error) {
    if TEXTURES_KEY not_in object {
        return
    }

    textures_array := object[TEXTURES_KEY].(json.Array)
    res = make([]Texture, len(textures_array))

    for texture, idx in textures_array {
        for k, v in texture.(json.Object) {
            switch k {
            case "sampler":
                res[idx].sampler = Integer(v.(f64))

            case "source":
                res[idx].source = Integer(v.(f64))

            case "name":
                res[idx].name = v.(string)

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v

            case:
                warning_unexpected_data(#procedure, k, v, idx)
            }
        }
    }

    return res, nil
}

textures_free :: proc(textures: []Texture) {
    if len(textures) == 0 {
        return
    }
    delete(textures)
}

@(require_results)
texture_info_parse :: proc(object: json.Object) -> (res: Texture_Info, err: Error) {
    index_set: bool
    for k, v in object {
        switch k {
        case "index":
            //Required
            res.index = Integer(v.(f64))
            index_set = true

        case "texCoord":
            // Default 0
            res.tex_coord = Integer(v.(f64))

        case EXTENSIONS_KEY:
            res.extensions = v

        case EXTRAS_KEY:
            res.extras = v

        case:
            warning_unexpected_data(#procedure, k, v)
        }
    }

    if !index_set {
        return res, GLTF_Error{type = .Missing_Required_Parameter, proc_name = #procedure, param = {name = "index"}}
    }

    return res, nil
}
