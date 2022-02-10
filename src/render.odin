package pisc

import ray "vendor:raylib"

/*draw_text_primary :: proc(cstr: cstring, x, y: i32, color: ray.Color) {
	ray.DrawTextEx(config.primary_font, cstr, ray.Vector2{f32(x), f32(y)}, config.primary_font_size, 1.0, color)
}

draw_text_secondary :: proc(cstr: cstring, x, y: i32, color: ray.Color) {
	ray.DrawTextEx(config.secondary_font, cstr, ray.Vector2{f32(x), f32(y)}, config.secondary_font_size, 1.0, color)
}*/

_draw_text_shortcut_hint :: proc(cstr: cstring, x, y: i32, color: ray.Color) {
	ray.DrawTextEx(config.shortcut_hint_font, cstr, ray.Vector2{f32(x), f32(y)}, f32(config.shortcut_hint_font_size), 1.0, color)
}