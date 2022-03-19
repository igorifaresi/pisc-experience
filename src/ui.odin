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

mouse_pos: [2]i32
mouse_left_pressed: bool

update_ui :: proc() {
	mouse_pos.x = ray.GetMouseX()
	mouse_pos.y = ray.GetMouseY()
	mouse_left_pressed = ray.IsMouseButtonPressed(.LEFT)
}

draw_shortcut_btn :: proc(pos: [2]i32, size: [2]i32, main_text: cstring, shortcut_hint: cstring, border_color := config.line_color, alpha := 1) -> (clicked: bool) {
	/*text_c: ray.Color

	background_c := ray.GREEN
	background_c.a = 128
	btn_x := i32(x) + 400 - 8*2 - button_width*2
	btn_y := actual_popup_position + popup_height - top_bar_height - 8

	if ctrl && y_pressed && !popup_first_frame {
		background_c.a = 255	
		ray.DrawRectangle(btn_x, btn_y, button_width, top_bar_height, background_c)
		popup_callback()
		is_yes_or_no_popup_open = false
	}

	if mouse_x >= btn_x && mouse_x < (btn_x + button_width) && mouse_y >= btn_y && mouse_y <= (btn_y + top_bar_height) {
		text_c = ray.BLACK

		if ray.IsMouseButtonPressed(.LEFT) {
			background_c.a = 255	
			ray.DrawRectangle(btn_x, btn_y, button_width, top_bar_height, background_c)
			popup_callback()
			is_yes_or_no_popup_open = false
		} else {
			ray.DrawRectangle(btn_x, btn_y, button_width, top_bar_height, background_c)
		}
	} else {
		text_c = ray.LIGHTGRAY
		ray.DrawRectangleLines(btn_x, btn_y, button_width, top_bar_height, background_c)
	}

	draw_text_btn("Yes", btn_x + 4, btn_y + 2, secondary_font_size, text_c)
	draw_text_shortcut_hint("ctrl+Y", btn_x + 4, btn_y + 2 + secondary_font_size, shortcut_hint_font_size, text_c)
	*/
	return
}

// push_layer()
// 