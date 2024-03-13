package utils

import "core:mem"
import "core:runtime"
import "shared:imgui"

static_string :: struct(CAP: int) {
    len  : int,
    data : [CAP+1] u8, // 1 byte added for extra null terminator
}

static_string_to_string :: proc(s: ^static_string($CAP)) -> string {
    return transmute(string) runtime.Raw_String {
        &s.data[0], s.len, 
    }
}

static_string_to_c_string :: proc(s: ^static_string($CAP)) -> cstring {
    s.data[min(s.len, CAP)] = 0
    return cstring(raw_data(s.data[:]))
}

static_string_clone_from_string :: proc(dst: ^static_string($CAP), src: string) -> bool {
    if len(src) > CAP {
        return false
    }
    dst.len = len(src)
    mem.copy(raw_data(dst.data[:]), raw_data(src), dst.len)
    dst.data[dst.len] = 0
    return true
}

imgui_input_static_string :: proc(
    label     : cstring, 
    str       : ^static_string($CAP), 
    flags     : imgui.InputTextFlags    = {}, 
    callback  : imgui.InputTextCallback = {}, 
    user_data : rawptr                  = nil
) -> bool {
    result := imgui.InputTextEx(
        label, static_string_to_c_string(str), 
        uint(CAP+1), flags, callback, user_data,
    )
    if result {
        str.len = len(cstring(raw_data(str.data[:])))
    }
    return result
}


imgui_input_static_string_multiline :: proc(
    label     : cstring, 
    str       : ^static_string($CAP), 
    size      : imgui.Vec2 = {},
) -> bool {
    result := imgui.InputTextMultilineEx(
        label, 
        static_string_to_c_string(str), 
        uint(CAP+1),
        size, {}, nil, nil,
    )
    if result {
        str.len = len(cstring(raw_data(str.data[:])))
    }
    return result
}
