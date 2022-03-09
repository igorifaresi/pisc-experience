package pisc

import "core:fmt"
import "core:strings"
import ray "vendor:raylib"

CPU_Viewer_Nav_Keys :: struct {
	up:        bool,
	down:      bool,
	left:      bool,
	right:     bool,
}

cpu_viewer_last_nav_key := Nav_Last_Key{ key=.UP }
cpu_viewer_nav_keys := CPU_Viewer_Nav_Keys{}

update_cpu_viewer_nav_keys :: proc() {
	update_nav_last_key(&cpu_viewer_last_nav_key, 0.05)

	cpu_viewer_nav_keys.up    = check_nav_key(&cpu_viewer_last_nav_key, .UP)
	cpu_viewer_nav_keys.down  = check_nav_key(&cpu_viewer_last_nav_key, .DOWN)
	cpu_viewer_nav_keys.left  = check_nav_key(&cpu_viewer_last_nav_key, .LEFT)
	cpu_viewer_nav_keys.right = check_nav_key(&cpu_viewer_last_nav_key, .RIGHT)
}

CPU_Viewer_State :: struct {
	ram_offset:             int,
	ram_row_byte_qnt:       int,
	ram_view_page_byte_qnt: int,
	ram_addr_as_hex:        bool,
	ram_data_as_hex:        bool,
	ram_data_as_u16:        bool,
}

cpu_viewer_state := CPU_Viewer_State{
	ram_row_byte_qnt=4,
	ram_view_page_byte_qnt=64,
}

process_cpu_viewer_input :: proc() -> (interacted: bool) {
	using cpu_viewer_state

	if ray.IsKeyDown(.LEFT_CONTROL) && ray.IsKeyDown(.R) {
		if cpu_viewer_nav_keys.down {
			ram_offset += ram_row_byte_qnt
			if ram_offset > (1024 * 64) do ram_offset = (1024 * 64) - 1
		}
		if cpu_viewer_nav_keys.up {
			ram_offset -= ram_row_byte_qnt
			if ram_offset < 0 do ram_offset = 0
		}

		if cpu_viewer_nav_keys.right {
			ram_offset += ram_view_page_byte_qnt
			if ram_offset > (1024 * 64) do ram_offset = (1024 * 64) - 1
		}
		if cpu_viewer_nav_keys.left {
			ram_offset -= ram_view_page_byte_qnt
			if ram_offset < 0 do ram_offset = 0
		}

		if ray.IsKeyPressed(.I) do ram_addr_as_hex = !ram_addr_as_hex
		if ray.IsKeyPressed(.N) do ram_data_as_hex = !ram_data_as_hex
		if ray.IsKeyPressed(.B) do ram_data_as_u16 = !ram_data_as_u16

		interacted = true
	}

	return
}

draw_cpu_viewer :: proc() {
	using config
	using cpu_viewer_state

	draw_text :: proc(cstr: cstring, x, y, font_size: i32, color: ray.Color) {
		ray.DrawTextEx(config.secondary_font, cstr, ray.Vector2{f32(x), f32(y)}, f32(font_size), 1.0, color)
	}

	draw_border :: proc(init_x, init_y, end_x, end_y: i32, c := config.line_color) {
		init_border_x := init_x - 4
		init_border_y := init_y - 2
		end_border_x  := (end_x - init_border_x) - box_gap
		end_border_y  := (end_y - init_border_y) - box_gap
		ray.DrawRectangleLines(init_border_x, init_border_y, end_border_x, end_border_y, c)
	}

	stop_on_h_border :: proc(x: i32) -> i32 {
		return (config.window_width - x) - 1 
	}

	stop_on_v_border :: proc(x: i32) -> i32 {
		return (config.window_height - x) - 1 
	}

	reg_init_x : i32 = window_width  - cpu_view_area_width
	reg_init_y : i32 = window_height - cpu_view_line_height * 4 - secondary_font_size
	x := reg_init_x
	y := reg_init_y - 8
	space_between_cols := cpu_view_area_width / 8
	i : i32
	draw_text("REGISTERS", x, reg_init_y, secondary_font_size, ray.LIGHTGRAY)
	for name, reg in registers_table {
		if i%8 == 0 { 
			y += cpu_view_line_height
			x = window_width - cpu_view_area_width - space_between_cols
		}

		x += space_between_cols
		draw_text(ray.TextFormat("%s:", name), x, y, secondary_font_size, highlight_color)

		value := main_cpu.reg_table[int(reg)]
		draw_text(ray.TextFormat("%d", value), x + 32, y, secondary_font_size, secondary_font_color)

		i += 1
	}

	x = window_width - cpu_view_area_width + 7*space_between_cols
	draw_text("pc:", x, y, secondary_font_size, highlight_color)
	draw_text(ray.TextFormat("%d", main_cpu.pc), x + 32, y, secondary_font_size, secondary_font_color)

	draw_border(reg_init_x, reg_init_y, window_width + 3, window_height + 3)
	
	ram_init_x : i32 = window_width - cpu_view_area_width + GPU_BUFFER_W + box_gap + 8
	ram_init_y : i32 = top_bar_height + 4
	x = ram_init_x
	y = ram_init_y - 8
	space_between_addr := ((window_width - ram_init_x) / 12) * 3
	space_between_cols = (window_width - ram_init_x - space_between_addr) / 4
	i = 0
	draw_text("RAM", x, ram_init_y, secondary_font_size, ray.LIGHTGRAY)

	last_mmio_entry_id: MMIO_Entry_ID
	for b := ram_offset; b < len(main_cpu.mem); b += ram_data_as_u16 ? 2 : 1 {
		if i%4 == 0 {
			x = ram_init_x

			/*is_mmio_addr, mmio_label := check_mmio_in_ram(u16(b))
			if is_mmio_addr {
				_draw_text_shortcut_hint(mmio_label_to_cstring(mmio_label), x + space_between_cols,
					y + 4 + cpu_view_line_height / 2, highlight_color)
			}*/

			y += cpu_view_line_height
			if y >= (reg_init_y - secondary_font_size - box_gap - 3) do break

			draw_text(format_number(u16(b), ram_addr_as_hex), x, y, secondary_font_size, highlight_color)
			x += space_between_addr
		}

		mmio_entry, found, remaining := get_mmio_entry(u16(b))
		if found && last_mmio_entry_id != mmio_entry.id {
			mmio_label_y := y - config.shortcut_hint_font_size + 2

			tmp := space_between_cols * i32(remaining > 4 ? 4 : remaining)
			ray.DrawRectangle(x - 2, mmio_label_y, tmp - 1, 
				(i32(remaining / 4 + 1) * cpu_view_line_height) - 1, mmio_entry.color)

			ray.DrawRectangle(x - 1, y, tmp - 3, (i32(remaining / 4 + 1) * secondary_font_size), background_color)
			
			_draw_text_shortcut_hint(mmio_entry.cstr, x, mmio_label_y, ray.WHITE)	
		}
		last_mmio_entry_id = mmio_entry.id



		draw_text(
			ram_data_as_u16 ? format_number(main_cpu.mem[b], main_cpu.mem[b + 1], ram_data_as_hex) : 
				format_number(main_cpu.mem[b], ram_data_as_hex),
			x, y, secondary_font_size, secondary_font_color)
		x += ram_data_as_u16 ? space_between_cols * 2 : space_between_cols

		i += ram_data_as_u16 ? 2 : 1
	}

	draw_border(ram_init_x, ram_init_y, window_width + 3, reg_init_y - 2)

	call_s_init_x : i32 = window_width  - cpu_view_area_width
	call_s_init_y : i32 = GPU_BUFFER_H + 32 + top_bar_height + 6
	x = call_s_init_x
	y = call_s_init_y - 8
	i = 0
	draw_text("CALL STACK", x, call_s_init_y, secondary_font_size, ray.LIGHTGRAY)
	call_stack := sl_slice(&main_cpu.call_stack)
	if len(call_stack) != 0 {
		for addr in call_stack {
			//TODO
		}
	} else {
		draw_text("EMPTY CALL STACK", x, y + 8 + cpu_view_line_height, secondary_font_size, ray.GRAY)
	}

	draw_border(call_s_init_x, call_s_init_y, ram_init_x - 4, reg_init_y - 2)

	screen_init_x := window_width  - cpu_view_area_width
	screen_init_y := top_bar_height + 4
	x = screen_init_x
	y = screen_init_y - 8 
	i = 0

	switch execution_status {
	case .Running:
		draw_text("RUNNING", x, screen_init_y, secondary_font_size, ray.LIGHTGRAY)
	case .Waiting:
		draw_text("DEBUGGING", x, screen_init_y, secondary_font_size, ray.LIGHTGRAY)
	case .Editing:
		draw_text(ray.TextFormat("EDITING(%d)errors", err_qnt), x, screen_init_y, secondary_font_size, ray.LIGHTGRAY)
	}

	{
		cstr: cstring
		if have_editing_path {
			cstr = strings.clone_to_cstring(editing_file_name)
			if unsaved do cstr = ray.TextFormat("*%s", cstr)
			file_name_size := i32(ray.MeasureTextEx(secondary_font, cstr, f32(secondary_font_size), 1.0).x)
			new_x := (x + (x + GPU_BUFFER_W)) / 2 - file_name_size / 2
			draw_text(cstr, new_x, screen_init_y, secondary_font_size, ray.LIGHTGRAY)
		} else {
			if !unsaved {
				cstr = "untitled"
			} else {
				cstr = "*untitled"
			}
			file_name_size := i32(ray.MeasureTextEx(secondary_font, cstr, f32(secondary_font_size), 1.0).x)
			new_x := (x + (x + GPU_BUFFER_W)) / 2 - file_name_size / 2
			draw_text(cstr, new_x, screen_init_y, secondary_font_size, highlight_color)		
		}
	}

	/*{
		cstr := ray.TextFormat("FPS: %d", ray.GetFPS())
		fps_size := i32(ray.MeasureTextEx(secondary_font, cstr, f32(secondary_font_size), 1.0).x)
		new_x := (x + GPU_BUFFER_W) - fps_size
		draw_text(cstr, new_x, screen_init_y, secondary_font_size, ray.LIGHTGRAY)
	}*/

	{
		
	}

	{
		x = window_width - cpu_view_area_width
		y = cpu_view_line_height + top_bar_height

		ray.DrawTexture(video_buffer_texture, x, y, ray.WHITE)
	}

	draw_border(screen_init_x, screen_init_y, ram_init_x - 4, call_s_init_y - 2)
}