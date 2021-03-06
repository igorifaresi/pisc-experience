// NOTE(samuel): This file is the place for randon but usefull functions
package pisc

import "core:math"
import "core:mem"
import ray "vendor:raylib"

format_number :: proc{format_u8, format_u8_u8, format_u16}

format_u16 :: proc(v: u16, hex := false) -> (num_as_cstr: cstring) {
    if hex {
        num_as_cstr = ray.TextFormat("0x%04x", i32(v))       
    } else {
        num_as_cstr = ray.TextFormat("%d", i32(v))
    }
    return
}

format_u8 :: proc(v: u8, hex := false) -> (num_as_cstr: cstring) {
    if hex {
        num_as_cstr = ray.TextFormat("0x%02x", i32(v))
    } else {
        num_as_cstr = ray.TextFormat("%d", i32(v))
    }
    return
}

format_u8_u8 :: proc(v1: u8, v2: u8, hex := false) -> (num_as_cstr: cstring) {
    if hex {
        num_as_cstr = ray.TextFormat("0x%02x%02x", i32(v1), i32(v2))
    } else {
        num_as_cstr = ray.TextFormat("%d", i32(v1) + i32(v2))
    }
    return
}

Fixed_List :: struct(T: typeid) {
    data: []T,
    len: u32,
}

fl_slice :: proc(list: Fixed_List($T)) -> []T {
    return list.data[0:list.len]
}

fl_clear :: proc(list: ^Fixed_List($T)) {
    for d in list.data do d = {}
    list.len = 0
}

fl_push :: proc(list: ^Fixed_List($T), val: T) -> (error: bool) {
    if list.len >= len(list.data) do return true
    list.data[list.len] = val
    list.len += 1
    return
}

fl_pop :: proc(list: ^Fixed_List($T)) -> (result: T) {
    if list.len > 0 {
        result = list.data[list.len - 1]
        list.len -= 1
    }
    return
}

Static_List :: struct(T: typeid, size: u32) {
    data: [size]T,
    len: u32,
}

sl_slice :: #force_inline proc(list: ^Static_List($T, $S)) -> []T {
    return list.data[:int(list.len)]
}

sl_clear :: proc(list: ^Static_List($T, $S)) {
    for i: int = 0; i < len(list.data); i += 1 do list.data[i] = {}
    list.len = 0
}

sl_insert :: proc(list: ^Static_List($T, $S), value: T, pos: u32) {
    if int(list.len) >= len(list.data) do return

    for i := list.len; i > pos; i -= 1 do list.data[i] = list.data[i - 1]
    list.len += 1
    list.data[pos] = value
}

sl_remove :: proc(list: ^Static_List($T, $S), pos: u32) -> (value: T) {
    if list.len == 0 do return

    value = list.data[pos]

    list.len -= 1
    for i := pos; i < list.len; i += 1 do list.data[i] = list.data[i + 1]

    return
}

sl_push :: proc(list: ^Static_List($T, $S), val: T) -> (error: bool) {
    if list.len >= len(list.data) do return true
    list.data[list.len] = val
    list.len += 1
    return
}

sl_pop :: proc(list: ^Static_List($T, $S)) -> (result: T) {
    if list.len > 0 {
        result = list.data[list.len - 1]
        list.len -= 1
    }
    return
}
