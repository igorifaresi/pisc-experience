package pisc

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:math"
import "core:os"
import "sfd"
import ray "vendor:raylib"

Config :: struct {
	window_width:                    i32,
	window_height:                   i32,
	background_color:                ray.Color,
	top_bar_height:                  i32,
	shortcut_hint_font:      ray.Font,
	shortcut_hint_font_size: i32,
	shortcut_hint_char_width: i32,
	primary_font_size:                i32,
	editor_line_height:              i32,
	editor_top_padding:              i32,
	editor_left_padding:             i32,
	editor_mnemonic_left_margin:     i32,
	editor_param_left_margin:        i32,
	primary_font:                     ray.Font,
	primary_font_char_width:          i32,
	editor_label_y_offset:           i32,
	editor_label_x_offset:           i32,
	line_highlight_color:     ray.Color,
	error_color:                    ray.Color,
	primary_font_color:               ray.Color,
	secondary_font:                     ray.Font,
	secondary_font_size:                i32,
	secondary_font_char_width:          i32, 
	highlight_color:         ray.Color,
	secondary_font_color:         ray.Color,
	gamepad_input_table:             Input_Table,
	popup_background_alpha:          u8,
	line_color:                      ray.Color,
	cpu_view_area_width: i32,
	cpu_view_line_height: i32,
	box_gap: i32,
}

Cursor_Place :: enum {
	Label,
	Ins,
	Comment,
}

Cursor :: struct {
	ins:     u32,
	param:   u32,
	char:    u32,
	label:   u32,
	comment: u32,
	place:   Cursor_Place,
}

BufferStatus :: enum {
	Valid,
	Invalid,
}

ExecutionStatus :: enum {
	Editing,
	Running,
	Waiting,
}

main_cpu: CPU
config := Config{
	window_width=1200,
	window_height=600,
	background_color=ray.Color{30, 31, 25, 255},
	top_bar_height=32,
	shortcut_hint_font_size=12,
	primary_font_size=20,
	editor_line_height=20,
	editor_top_padding=64,
	editor_left_padding=64,
	editor_mnemonic_left_margin=120,
	editor_param_left_margin=60,
	editor_label_y_offset=12,
	editor_label_x_offset=8,
	line_highlight_color=ray.Color{70, 70, 70, 255},
	error_color=ray.Color{249, 36, 72, 255},
	primary_font_color=ray.WHITE,
	secondary_font_size=16,
	highlight_color=ray.Color{221, 199, 79, 255},
	secondary_font_color=ray.WHITE,
	popup_background_alpha=196,
	line_color=ray.Color{200, 200, 200, 48},
	cpu_view_area_width=730,
	cpu_view_line_height=28,
	box_gap=4,
}
cursor: Cursor
buffer_status: [MAX_INSTRUCTIONS*4]BufferStatus
has_errs         := false
err_qnt          := 0
execution_status := ExecutionStatus.Editing
editor_y_offset: i32
video_buffer_texture: ray.Texture2D

unsaved := false
have_editing_path := false
editing_path: cstring
editing_file_name: string

dialog_alpha : f64 = 0.0
dialog_msg: cstring = "There is some errors in code."
dialog_bad := true

is_yes_or_no_popup_open := false
actual_popup_background_alpha := 0.0
actual_popup_position: i32 = -8000
popup_msg: cstring = "Abacaxi?"
popup_first_frame: bool
popup_callback: proc()
popup_refuse_callback: proc()
popup_height: i32

comment_buffer := make([]byte, 1024*1024)

dummy_callback :: proc() {
	fmt.println("Dummy callback")
}

compile :: proc() -> (success := true, err_qnt: int) {
	sl_clear(&main_cpu.instructions)

	line    := 0
	buffers := sl_slice(&main_cpu.editing_buffers)
	for i := 0; i < len(buffers); i += 4 {
		ins, ok := compile_line(u32(line))
		if ok {
			if success do sl_push(&main_cpu.instructions, ins)
		} else {
			sl_clear(&main_cpu.instructions)
			err_qnt += 1
			success =  false
		}

		line += 1
	}

	return
}

check_label :: proc(str: string) -> (number: i16, found := false) {
	labels := sl_slice(&main_cpu.labels)
	for i := 0; i < len(labels); i += 1 {
		label := &labels[i]

		tmp := sl_slice(&label.name)
		label_str := string(tmp)

		if str == label_str {
			number = i16(i)
			found  = true
			return
		} 
	}

	return
}

compile_line :: proc(line: u32) -> (ins: Instruction, success := true) {
	cstr: cstring

	buffer_idx := int(line*4)

	rows: [4]cstring = {
		lookup_buffer(line, 0),
		lookup_buffer(line, 1),
		lookup_buffer(line, 2),
		lookup_buffer(line, 3),
	}

	buffer_status[buffer_idx    ] = .Valid
	buffer_status[buffer_idx + 1] = .Valid
	buffer_status[buffer_idx + 2] = .Valid
	buffer_status[buffer_idx + 3] = .Valid

	check_line_qnt :: proc(rows: ^[4]cstring, success: ^bool, expected: int, buffer_idx: int) {
		qnt := 0
		for qnt < 4 && len(rows[qnt]) > 0 {
			qnt += 1
		}
		
		if qnt != expected {
			success^ = false
			for i := expected; i < qnt; i += 1 {
				buffer_status[buffer_idx + i] = .Invalid
			}
		} else {
			for i := qnt + 1; i < 4; i += 1 {
				if len(rows[i]) > 0 {
					success^ = false
					buffer_status[buffer_idx + i] = .Invalid
				}
			}
		}
	}

	ins_type, ok := mnemonics_table[rows[0]]
	if ok {
		ins.type = ins_type
	} else {
		buffer_status[buffer_idx] = .Invalid
		success = false
		return
	}

	switch instruction_param_type_table[ins.type] {
	case .Reg_And_Reg_And_Offset:

		check_line_qnt(&rows, &success, 4, buffer_idx)

		reg1_type, reg2_type: Register_Type
		imediate: i64
		ok: bool

		reg1_type, ok = registers_table[rows[1]]
		if ok {
			ins.p0 = u8(reg1_type)
		} else {
			buffer_status[buffer_idx + 1] = .Invalid
			success = false
		}

		reg2_type, ok = registers_table[rows[2]]
		if ok {
			ins.p0 = u8(reg2_type)
		} else {
			buffer_status[buffer_idx + 2] = .Invalid
			success = false
		}

		imediate, ok = strconv.parse_i64(string(rows[3]))
		if ok {
			ins.p2 = i16(imediate)
			ins.imediate = true
		} else {
			buffer_status[buffer_idx + 3] = .Invalid
			success = false
		}

	case .Reg_And_Reg_Or_Imediate:

		check_line_qnt(&rows, &success, 3, buffer_idx)

		reg1_type, reg2_type: Register_Type
		ok: bool

		reg1_type, ok = registers_table[rows[1]]
		if ok {
			ins.p0 = u8(reg1_type)
		} else {
			buffer_status[buffer_idx + 1] = .Invalid
			success = false
		}

		buff := rows[2]

		reg2_type, ok = registers_table[buff]
		if ok {
			ins.p1 = u8(reg2_type)
			ins.imediate = false
		} else {
			imediate, ok := strconv.parse_i64(string(buff))
			if ok {
				ins.p2 = i16(imediate)
				ins.imediate = true
			} else {
				buffer_status[buffer_idx + 2] = .Invalid
				success = false
			}
		}

	case .Reg:

		check_line_qnt(&rows, &success, 2, buffer_idx)

		reg_type, ok := registers_table[rows[1]]
		if ok {
			ins.p0 = u8(reg_type)
		} else {
			buffer_status[buffer_idx + 1] = .Invalid
			success = false
		}
	
	case .Reg_Or_Imediate:

		check_line_qnt(&rows, &success, 2, buffer_idx)

		buff := rows[1]

		reg_type, ok := registers_table[buff]
		if ok {
			ins.p0 = u8(reg_type)
		} else {
			imediate, ok := strconv.parse_i64(string(buff))
			if ok {
				ins.p2 = i16(imediate)
				ins.imediate = true
			} else {
				label_idx, found := check_label(string(buff))
				if found {
					ins.p2 = label_idx
					ins.imediate = true
				} else {
					buffer_status[buffer_idx + 1] = .Invalid
					success = false
				}
			}
		}
	
	case .Nothing:

		check_line_qnt(&rows, &success, 1, buffer_idx)

	}

	return
}

lookup_buffer :: proc(i_ins: u32, i_param: u32) -> cstring {
	char_buffer := &main_cpu.editing_buffers.data[i_ins * 4 + i_param]
	return strings.clone_to_cstring(string(sl_slice(char_buffer)))
}

lookup_label :: proc(label: u32) -> cstring {
	tmp  := sl_slice(&main_cpu.labels.data[label].name)
	return strings.clone_to_cstring(string(tmp))
}

lookup_comment :: proc(comment: u32) -> cstring {
	tmp := sl_slice(&main_cpu.comments.data[comment].content)
	return strings.clone_to_cstring(string(tmp))
}

lookup_comment_str :: proc(comment: u32) -> string {
	tmp := sl_slice(&main_cpu.comments.data[comment].content)
	return string(tmp)
}

to_cstr :: proc(str: string) -> cstring {
	return strings.clone_to_cstring(str)
}

set_buffer :: proc(i_ins: u32, i_param: u32, str: string) {
	idx := i_ins * 4 + i_param
	char_buffer := &main_cpu.editing_buffers.data[idx]
	sl_clear(char_buffer)
	for i := 0; i < len(str); i += 1 {
		sl_push(char_buffer, str[i])
	}
	if main_cpu.editing_buffers.len <= idx {
		new_len := idx + 1
		main_cpu.editing_buffers.len = new_len + (4 - new_len%4) 
	}
}

push_label :: proc(str: string, line: u16) {
	label: Label
	
	for i := 0; i < len(str); i += 1 {
		sl_push(&label.name, str[i])
	}
	label.line = line

	sl_push(&main_cpu.labels, label)
}

insert_comment :: proc(str: string, line: u16, pos: int) {
	comment: Comment
	
	for i := 0; i < len(str); i += 1 {
		sl_push(&comment.content, str[i])
	}
	comment.line = line

	if pos != -1 {
		sl_insert(&main_cpu.comments, comment, u32(pos))
	} else {
		sl_push(&main_cpu.comments, comment)		
	}
}

open_yes_or_no_popup :: proc(text: cstring, callback: proc(), refuse_callback: proc()) {
	using config
	popup_height = top_bar_height + 8*4 + primary_font_size
	actual_popup_position = -popup_height
	actual_popup_background_alpha = 0.0
	popup_msg = text
	popup_callback = callback
	popup_refuse_callback = refuse_callback
	popup_first_frame = true
	is_yes_or_no_popup_open = true
}

hide_yes_or_no_popup :: proc() {
	using config

	draw_text :: proc(cstr: cstring, x, y, font_size: i32, color: ray.Color) {
		ray.DrawTextEx(config.primary_font, cstr, ray.Vector2{f32(x), f32(y)}, f32(font_size), 1.0, color)
	}

	draw_text_btn :: proc(cstr: cstring, x, y, font_size: i32, color: ray.Color) {
		ray.DrawTextEx(config.secondary_font, cstr, ray.Vector2{f32(x), f32(y)}, f32(font_size), 1.0, color)
	}

	draw_text_shortcut_hint :: proc(cstr: cstring, x, y, font_size: i32, color: ray.Color) {
		ray.DrawTextEx(config.shortcut_hint_font, cstr, ray.Vector2{f32(x), f32(y)}, f32(font_size), 1.0, color)
	}

	{
		actual_popup_background_alpha -= actual_popup_background_alpha / 12
		if actual_popup_background_alpha < 0 do actual_popup_background_alpha = 0 

		c := ray.BLACK
		c.a = u8(f64(popup_background_alpha) * actual_popup_background_alpha)

		ray.DrawRectangle(0, 0, window_width, window_height, c)
	}

	{
		line_color := ray.LIGHTGRAY
		line_color.a = 48

		target_y := window_height / 2 - popup_height / 2
		actual_popup_position -= (actual_popup_position - popup_height * -1 + 32) / 6
		x := window_width / 2 - 400 / 2

		c := background_color

		ray.DrawRectangle(x, actual_popup_position, 400, popup_height, c)
		ray.DrawRectangleLines(x, actual_popup_position, 400, popup_height, line_color)
		draw_text(popup_msg, x + 8, actual_popup_position + 8, primary_font_size, primary_font_color)

		end_x := x + 400 - 8
		y := actual_popup_position + 8*2 + primary_font_size
		ray.DrawLine(x + 8, y, end_x, y, line_color)

		button_width : i32 = 80

		{
			text_c := ray.LIGHTGRAY

			background_c := ray.GREEN
			background_c.a = 128
			btn_x := i32(x) + 400 - 8*2 - button_width*2
			btn_y := actual_popup_position + popup_height - top_bar_height - 8
			
			ray.DrawRectangleLines(btn_x, btn_y, button_width, top_bar_height, background_c)

			draw_text_btn("Yes", btn_x + 4, btn_y + 2, secondary_font_size, text_c)
			draw_text_shortcut_hint("ctrl+Y", btn_x + 4, btn_y + 2 + secondary_font_size, shortcut_hint_font_size, text_c)
		}

		{
			text_c := ray.LIGHTGRAY

			background_c := error_color
			background_c.a = 128
			btn_x := i32(x) + 400 - 8 - button_width
			btn_y := actual_popup_position + popup_height - top_bar_height - 8

			ray.DrawRectangleLines(btn_x, btn_y, button_width, top_bar_height, background_c)

			draw_text_btn("No", btn_x + 4, btn_y + 2, secondary_font_size, text_c)
			draw_text_shortcut_hint("ctrl+N", btn_x + 4, btn_y + 2 + secondary_font_size, shortcut_hint_font_size, text_c)
		}
	}
}

draw_yes_or_no_popup :: proc() {
	using config

	draw_text :: proc(cstr: cstring, x, y, font_size: i32, color: ray.Color) {
		ray.DrawTextEx(config.primary_font, cstr, ray.Vector2{f32(x), f32(y)}, f32(font_size), 1.0, color)
	}

	draw_text_btn :: proc(cstr: cstring, x, y, font_size: i32, color: ray.Color) {
		ray.DrawTextEx(config.secondary_font, cstr, ray.Vector2{f32(x), f32(y)}, f32(font_size), 1.0, color)
	}

	draw_text_shortcut_hint :: proc(cstr: cstring, x, y, font_size: i32, color: ray.Color) {
		ray.DrawTextEx(config.shortcut_hint_font, cstr, ray.Vector2{f32(x), f32(y)}, f32(font_size), 1.0, color)
	}

	{
		actual_popup_background_alpha += (1.0 - actual_popup_background_alpha) / 12 

		c := ray.BLACK
		c.a = u8(f64(popup_background_alpha) * actual_popup_background_alpha)

		ray.DrawRectangle(0, 0, window_width, window_height, c)
	}

	{
		line_color := ray.LIGHTGRAY
		line_color.a = 48

		target_y := window_height / 2 - popup_height / 2
		actual_popup_position += (target_y - actual_popup_position) / 6
		x := window_width / 2 - 400 / 2

		c := background_color

		ray.DrawRectangle(x, actual_popup_position, 400, popup_height, c)
		ray.DrawRectangleLines(x, actual_popup_position, 400, popup_height, line_color)
		draw_text(popup_msg, x + 8, actual_popup_position + 8, primary_font_size, primary_font_color)

		end_x := x + 400 - 8
		y := actual_popup_position + 8*2 + primary_font_size
		ray.DrawLine(x + 8, y, end_x, y, line_color)

		button_width : i32 = 80

		mouse_x := ray.GetMouseX()
		mouse_y := ray.GetMouseY()

		ctrl      := ray.IsKeyDown(.LEFT_CONTROL)
		y_pressed := ray.IsKeyPressed(.Y)
		n_pressed := ray.IsKeyPressed(.N)

		{
			text_c: ray.Color

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
		}

		{
			text_c: ray.Color

			background_c := error_color
			background_c.a = 128
			btn_x := i32(x) + 400 - 8 - button_width
			btn_y := actual_popup_position + popup_height - top_bar_height - 8

			if ctrl && n_pressed && !popup_first_frame {
				background_c.a = 255	
				ray.DrawRectangle(btn_x, btn_y, button_width, top_bar_height, background_c)
				popup_refuse_callback()
				is_yes_or_no_popup_open = false
			}

			if mouse_x >= btn_x && mouse_x < (btn_x + button_width) && mouse_y >= btn_y && mouse_y <= (btn_y + top_bar_height) {
				text_c = ray.BLACK

				if ray.IsMouseButtonPressed(.LEFT) {
					background_c.a = 255	
					ray.DrawRectangle(btn_x, btn_y, button_width, top_bar_height, background_c)
					popup_refuse_callback()
					is_yes_or_no_popup_open = false
				} else {
					ray.DrawRectangle(btn_x, btn_y, button_width, top_bar_height, background_c)
				}
			} else {
				text_c = ray.LIGHTGRAY
				ray.DrawRectangleLines(btn_x, btn_y, button_width, top_bar_height, background_c)
			}

			draw_text_btn("No", btn_x + 4, btn_y + 2, secondary_font_size, text_c)
			draw_text_shortcut_hint("ctrl+N", btn_x + 4, btn_y + 2 + secondary_font_size, shortcut_hint_font_size, text_c)
		}
	}

	popup_first_frame = false
}

open_dialog :: proc(text: cstring, bad: bool) {
	dialog_msg   = text
	dialog_alpha = 1.0
	dialog_bad   = bad
}

draw_dialog_if_exists :: proc() {
	using config

	draw_text :: proc(cstr: cstring, x, y, font_size: i32, color: ray.Color) {
		ray.DrawTextEx(config.secondary_font, cstr, ray.Vector2{f32(x), f32(y)}, f32(font_size), 1.0, color)
	}

	x : i32 = 12
	width  : i32 = window_width - 12*2 - 730 
	height : i32 = secondary_font_size + 4*2
	y : i32 = window_height - height - 12
	
	c := background_color
	c.r += 8
	c.g += 8
	c.b += 8
	c.a = u8(f64(c.a) * dialog_alpha)

	ray.DrawRectangle(x, y, width, height, c)

	c = ray.LIGHTGRAY
	c.r += 8
	c.g += 8
	c.b += 8
	c.a = 48
	c.a = u8(f64(c.a) * dialog_alpha)
	
	ray.DrawRectangleLines(x, y, width, height, c)

	if dialog_bad {
		c = error_color
	} else {
		c = primary_font_color
	}

	c.a = u8(f64(c.a) * dialog_alpha)
	draw_text(dialog_msg, x + 12, y + 3, secondary_font_size, c)

	if dialog_bad {
		dialog_alpha -= (1.00001 - dialog_alpha) / 32
	} else {
		dialog_alpha -= (1.00001 - dialog_alpha) / 8		
	}
	if dialog_alpha < 0 do dialog_alpha = 0
}

draw_video_buffer :: proc() {
	using config

	
}

draw_status :: proc(err_qnt: i32) {
	using config

	draw_text :: proc(cstr: cstring, x, y, font_size: i32, color: ray.Color) {
		ray.DrawTextEx(config.secondary_font, cstr, ray.Vector2{f32(x), f32(y)}, f32(font_size), 1.0, color)
	}

	
}

//btn_position: [7]i32 = {730, 730, 730, 730, 730, 730, 730}
Button_Actual_State :: enum {
	None = 0,
	Hover,
	Clicked,
}

btn_position: [7]i32
btn_alpha:    [7]u32
btn_state:    [7]Button_Actual_State

top_bar_btn_qnt: i32 = 7

save :: proc() {
	if !have_editing_path {
		opt := sfd.Options{
			title="Save file as",
			path=".",
			filter_name="PISC file",
			filter="*",
			extension="",
		}
		editing_path = sfd.save_dialog(&opt)
		tmp := strings.split(string(editing_path), "/")
		editing_file_name = tmp[len(tmp) - 1]
		have_editing_path = true

		dump_cpu_to_file(&main_cpu, editing_path)
	} else {
		dump_cpu_to_file(&main_cpu, editing_path)
	}

	unsaved = false
	open_dialog("Saved.", false)
}

draw_top_bar_and_handle_shortcuts :: proc() {
	using config

	draw_text :: proc(cstr: cstring, x, y, font_size: i32, color: ray.Color) {
		ray.DrawTextEx(config.secondary_font, cstr, ray.Vector2{f32(x), f32(y)}, f32(font_size), 1.0, color)
	}
	
	draw_text_shortcut_hint :: proc(cstr: cstring, x, y, font_size: i32, color: ray.Color) {
		ray.DrawTextEx(config.shortcut_hint_font, cstr, ray.Vector2{f32(x), f32(y)}, f32(font_size), 1.0, color)
	}

	reset_top_bar :: proc(init_x: i32) {
		for i := 0; i < 7; i += 1 {
			btn_position[i] = init_x
			btn_alpha[i] = 0
		}
	}

	c := line_highlight_color

	mouse_x := ray.GetMouseX()
	mouse_y := ray.GetMouseY()

	init_x : i32 = window_width - cpu_view_area_width - box_gap - 1
	end_x  : i32 = window_width
	init_y : i32 = 0
	end_y  : i32 = top_bar_height

	button_width := (end_x - init_x) / top_bar_btn_qnt + 1

	NEW_BTN     :: 0
	OPEN_BTN    :: 1
	SAVE_BTN    :: 2
	SAVE_AS_BTN :: 3

	editing_top_bar_text: [7]cstring = {"New", "Open", "Save", "Save as", "Debug", "Debug here", "Run"}
	editing_top_bar_shortcut_text: [7]cstring = {"ctrl+N", "ctrl+O", "ctrl+S", "ctrl+shift+S", "F3", "F6", "F4"}

	waiting_top_bar_text: [7]cstring = {"New", "Open", "Save", "Save as", "Edit", "Step", "Run"}
	waiting_top_bar_shortcut_text: [7]cstring = {"ctrl+N", "ctrl+O", "ctrl+S", "ctrl+shift+S", "E", "F7", "F4"}

	running_top_bar_text: [6]cstring = {"New", "Open", "Save", "Save as", "Edit", "Debug"}
	running_top_bar_shortcut_text: [6]cstring = {"ctrl+N", "ctrl+O", "ctrl+S", "ctrl+shift+S", "E", "F3"}

	btn_text:          []cstring
	btn_shortcut_text: []cstring

	switch execution_status {
	case .Editing:

		btn_text = editing_top_bar_text[:]
		btn_shortcut_text = editing_top_bar_shortcut_text[:]
		top_bar_btn_qnt = 7
	
	case .Waiting:

		btn_text = waiting_top_bar_text[:]
		btn_shortcut_text = waiting_top_bar_shortcut_text[:]
		top_bar_btn_qnt = 7

	case .Running:

		btn_text = running_top_bar_text[:]
		btn_shortcut_text = running_top_bar_shortcut_text[:]
		top_bar_btn_qnt = 6

	} 

	if mouse_x >= init_x && mouse_x < end_x && mouse_y >= init_y && mouse_y <= end_y {
		relative_mouse_x := mouse_x - init_x

		for i : i32 = 0; i < top_bar_btn_qnt; i += 1 {
			if (relative_mouse_x / button_width) == i {
				if ray.IsMouseButtonPressed(.LEFT) {
					btn_state[i] = .Clicked
				} else {
					btn_state[i] = .Hover
				}
			} else {
				btn_state[i] = .None				
			}
		} 
	} else {
		for i : i32 = 0; i < top_bar_btn_qnt; i += 1 {
			btn_state[i] = .None
		}
	}

	if !is_yes_or_no_popup_open {
		clean :: proc() {
			sl_clear(&main_cpu.editing_buffers)
			sl_clear(&main_cpu.labels)

			set_buffer(0, 0, "nop")
			push_label("RESET", 0)

			cursor.char     = 0
			cursor.ins      = 0
			cursor.param    = 0
			cursor.place    = .Ins
			cursor.label    = 0

			have_editing_path = false
			unsaved = false

			open_dialog("Reseted.", false)
		}

		save_and_clean :: proc() {
			save()
			clean()
		}

		extract_filename :: proc(str: string) {
			when os.OS == "windows" {
				tmp := strings.split(str, "\\")
				editing_file_name = tmp[len(tmp) - 1]
			} else {
				tmp := strings.split(str, "/")
				editing_file_name = tmp[len(tmp) - 1]
			}
		}

		if btn_state[NEW_BTN] == .Clicked || (ray.IsKeyDown(.LEFT_CONTROL) && ray.IsKeyPressed(.N)) {
			if unsaved {
				open_yes_or_no_popup("There is unsaved things. Want to save?", save_and_clean, clean)
			} else {
				clean()
			}
		} else if btn_state[OPEN_BTN] == .Clicked || (ray.IsKeyDown(.LEFT_CONTROL) && ray.IsKeyPressed(.O)) {
			opt := sfd.Options{
				title="Open File",
				path=".",
				filter_name="PISC file",
				filter="*",
				extension="",
			}

			editing_path = sfd.open_dialog(&opt)
			extract_filename(string(editing_path))
			have_editing_path = true

			load_cpu_from_file(&main_cpu, editing_path)
		} else if btn_state[SAVE_BTN] == .Clicked || (ray.IsKeyDown(.LEFT_CONTROL) && ray.IsKeyPressed(.S)) {
			save()
		} else if btn_state[SAVE_AS_BTN] == .Clicked || (ray.IsKeyDown(.LEFT_CONTROL) &&
		ray.IsKeyPressed(.LEFT_SHIFT) && ray.IsKeyPressed(.S)) {
			opt := sfd.Options{
				title="Save file as",
				path=".",
				filter_name="PISC file",
				filter="*",
				extension="",
			}
			editing_path = sfd.save_dialog(&opt)
			extract_filename(string(editing_path))
			have_editing_path = true

			dump_cpu_to_file(&main_cpu, editing_path)

			unsaved = false
			open_dialog("Saved.", false)
		}

		compile_and_check :: proc() -> (ok := false) {
			success, err_qnt := compile()
			if !success {
				open_dialog("There is compile errors.", true)
				return
			}
			ok = true
			return
		}

		switch execution_status {
		case .Waiting:
        		
        	if ray.IsKeyPressed(.E)  || btn_state[SAVE_AS_BTN + 1] == .Clicked {
        		execution_status = .Editing
        		reset_top_bar(init_x)
        	}

        	if ray.IsKeyPressed(.F7) || btn_state[SAVE_AS_BTN + 2] == .Clicked {
        		cpu_clock(&main_cpu)
        	}

        	if ray.IsKeyPressed(.F4) || btn_state[SAVE_AS_BTN + 3] == .Clicked {
        		cpu_reset(&main_cpu)
        		execution_status = .Running
        		reset_top_bar(init_x)
        	}

        case .Editing:

        	if ray.IsKeyPressed(.F3) || btn_state[SAVE_AS_BTN + 1] == .Clicked {
        		if compile_and_check() {
	        		cpu_reset(&main_cpu)
	        		execution_status = .Waiting
	        		reset_top_bar(init_x)
        		}
        	}

        	if ray.IsKeyPressed(.F6) || btn_state[SAVE_AS_BTN + 2] == .Clicked {
        		if compile_and_check() {
	        		cpu_reset(&main_cpu)
	        		main_cpu.pc = u16(cursor.ins)
	        		execution_status = .Waiting
	        		reset_top_bar(init_x)
        		}
        	}

        	if ray.IsKeyPressed(.F4) || btn_state[SAVE_AS_BTN + 3] == .Clicked {
        		if compile_and_check() {
	        		cpu_reset(&main_cpu)
	        		execution_status = .Running
	        		reset_top_bar(init_x)
        		}
        	}

        case .Running:

        	if ray.IsKeyPressed(.E)  || btn_state[SAVE_AS_BTN + 1] == .Clicked {
        		execution_status = .Editing
        		reset_top_bar(init_x)
        	}

			if ray.IsKeyPressed(.F3) || btn_state[SAVE_AS_BTN + 2] == .Clicked {
				execution_status = .Waiting
        		reset_top_bar(init_x)
			}
        } 
	}

	for i : i32 = 0; i < top_bar_btn_qnt; i += 1 {
		target_x := init_x + button_width * i

		dist := target_x - btn_position[i]
		if dist <= 3 && dist > 0 {
			btn_position[i] += 1
		} else {
			btn_position[i] += dist / 3
		}

		x := btn_position[i]

		btn_alpha[i] += (255 - btn_alpha[i]) / 8

		text_color          : ray.Color 
		shortcut_hint_color : ray.Color 

		switch btn_state[i] {
		case .None:

			text_color          = ray.LIGHTGRAY
			shortcut_hint_color = ray.LIGHTGRAY

			c := ray.LIGHTGRAY
			c.a = 48
			if (x + button_width) > window_width {
				ray.DrawRectangleLines(x + 1, 1, (window_width - x) - 2, top_bar_height - 2, c)
			} else {
				ray.DrawRectangleLines(x + 1, 1, button_width - 2, top_bar_height - 2, c)				
			}
		case .Hover:
			
			text_color          = ray.BLACK
			shortcut_hint_color = ray.BLACK

			ray.DrawRectangle(x + 1, 1, button_width - 2, top_bar_height - 2, highlight_color)

		case .Clicked:
			ray.DrawRectangle(x, 0, button_width, top_bar_height, ray.WHITE)
		}

		text_color.a          = u8(btn_alpha[i])
		shortcut_hint_color.a = u8(btn_alpha[i])

		draw_text(btn_text[i], x + 4, 2, secondary_font_size, text_color)
		draw_text_shortcut_hint(btn_shortcut_text[i], x + 4, 2 + secondary_font_size, shortcut_hint_font_size, shortcut_hint_color)
	}
}

draw_cpu :: proc() {
	using config

	draw_text :: proc(cstr: cstring, x, y, font_size: i32, color: ray.Color) {
		ray.DrawTextEx(config.secondary_font, cstr, ray.Vector2{f32(x), f32(y)}, f32(font_size), 1.0, color)
	}

	draw_border :: proc(init_x, init_y, end_x, end_y: i32) {
		init_border_x := init_x - 4
		init_border_y := init_y - 2
		end_border_x  := (end_x - init_border_x) - box_gap
		end_border_y  := (end_y - init_border_y) - box_gap
		ray.DrawRectangleLines(init_border_x, init_border_y, end_border_x, end_border_y, config.line_color)
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
	space_between_cols = (window_width - ram_init_x) / 5
	i = 0
	draw_text("RAM", x, ram_init_y, secondary_font_size, ray.LIGHTGRAY)

	for b := 0; b < len(main_cpu.mem); b += 1 {
		if i%4 == 0 { 
			y += cpu_view_line_height
			if y >= (reg_init_y - secondary_font_size - box_gap - 3) do break

			x = ram_init_x

			draw_text(ray.TextFormat("%d", i), x, y, secondary_font_size, highlight_color)
			x += space_between_cols
		}

		draw_text(ray.TextFormat("%x", main_cpu.mem[b]), x, y, secondary_font_size, secondary_font_color)
		x += space_between_cols

		i += 1
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

	{
		cstr := ray.TextFormat("FPS: %d", ray.GetFPS())
		fps_size := i32(ray.MeasureTextEx(secondary_font, cstr, f32(secondary_font_size), 1.0).x)
		new_x := (x + GPU_BUFFER_W) - fps_size
		draw_text(cstr, new_x, screen_init_y, secondary_font_size, ray.LIGHTGRAY)
	}

	{
		x = window_width - cpu_view_area_width
		y = cpu_view_line_height + top_bar_height

		ray.DrawTexture(video_buffer_texture, x, y, ray.WHITE)
	}

	draw_border(screen_init_x, screen_init_y, ram_init_x - 4, call_s_init_y - 2)
}

draw_editor :: proc() {
	using config

	get_color :: proc(i_ins: u32, i_param: u32) -> ray.Color {		
		if execution_status == .Editing && cursor.place == .Ins && cursor.ins == i_ins && cursor.param == i_param {
			return ray.YELLOW
		}

		return config.primary_font_color
	}

	get_buffer_cstr :: proc(i: int) -> cstring {
		char_buffer := &main_cpu.editing_buffers.data[i]
		return strings.clone_to_cstring(string(sl_slice(char_buffer)))
	}

	lerp_cursor :: proc(y: i32) {
		if y > config.window_height - 64 {
			offset := y - (config.window_height - 64)
			editor_y_offset -= offset / 2
		}

		if y < 64 {
			offset := 64 - y
			editor_y_offset += offset / 2
		}
	} 

	draw_cursor :: proc(x, y: i32, i_ins: u32, i_param: u32) {
		lerp_cursor(y)

		cstr          := lookup_buffer(i_ins, i_param)
		first_half    := strings.clone_to_cstring(string(cstr)[:cursor.char])
		cursor_offset := i32(ray.MeasureTextEx(config.primary_font, first_half, f32(config.primary_font_size), 1.0).x)
		cursor_x      := x + cursor_offset
		ray.DrawLine(cursor_x, y, cursor_x, y + config.primary_font_size, ray.LIGHTGRAY)
	}

	draw_cursor_label :: proc(x, y: i32, cstr: cstring) {
		lerp_cursor(y)

		first_half    := strings.clone_to_cstring(string(cstr)[:cursor.char])
		cursor_offset := i32(ray.MeasureTextEx(config.primary_font, first_half, f32(config.primary_font_size), 1.0).x)
		cursor_x      := x + cursor_offset
		ray.DrawLine(cursor_x, y, cursor_x, y + config.primary_font_size, ray.LIGHTGRAY)
	}

	draw_cursor_comment :: proc(x, y, char_qnt: i32) {
		lerp_cursor(y)

		cursor_offset := char_qnt * (primary_font_char_width + 1)
		cursor_x      := x + cursor_offset
		ray.DrawLine(cursor_x, y, cursor_x, y + config.primary_font_size, ray.LIGHTGRAY)
	}

	draw_err_indication :: proc(x: i32, y: i32, cstr: cstring) {
		word_size := i32(ray.MeasureTextEx(config.primary_font, cstr, f32(config.primary_font_size), 1.0).x) //todo: replace this
		tmp_y := y + config.primary_font_size
		ray.DrawLine(x, tmp_y, x + word_size, tmp_y, config.error_color)
	}

	get_total_editor_height :: proc() -> (y: i32) {
		using config

		i_ins: u32 = 0

		buffers := sl_slice(&main_cpu.editing_buffers)
		for line := 0; line < len(buffers); line += 4 {

			labels := sl_slice(&main_cpu.labels)
			for i := 0; i < len(labels); i += 1 {
				label := &labels[i]

				if label.line == u16(i_ins) {
					y += editor_label_y_offset
					y += editor_line_height
				}
			}

			y     += editor_line_height
			i_ins += 1
		}

		return
	}

	draw_text :: proc(cstr: cstring, x, y, font_size: i32, color: ray.Color) {
		ray.DrawTextEx(config.primary_font, cstr, ray.Vector2{f32(x), f32(y)}, f32(font_size), 1.0, color)
	}

	i_ins: u32 = 0
	x: i32 = editor_left_padding
	y: i32 = editor_y_offset

	line_number_x: i32 = editor_left_padding / 2 //TODO: gambiarra

	highlight_line_width := window_width - 730 - 4

	buffers := sl_slice(&main_cpu.editing_buffers)
	for line := 0; line < len(buffers); line += 4 {

		labels := sl_slice(&main_cpu.labels)
		for i := 0; i < len(labels); i += 1 {
			label := &labels[i]

			if label.line == u16(i_ins) {
				cstr := lookup_label(u32(i))
				c := config.primary_font_color
				if execution_status == .Editing && cursor.place == .Label && cursor.label == u32(i) do c = ray.YELLOW

				y += editor_label_y_offset
				draw_text(ray.TextFormat("%s:", cstr), 
					editor_label_x_offset, y, primary_font_size, c)

				if execution_status == .Editing && cursor.place == .Label && cursor.label == u32(i) {
					draw_cursor_label(editor_label_x_offset, y, cstr)
				}
				y += editor_line_height
			}
		}

		first_comment := true

		comments := sl_slice(&main_cpu.comments)
		for i := 0; i < len(comments); i += 1 {
			comment := &comments[i]

			if comment.line == u16(i_ins) {
				c := ray.GRAY

				if execution_status == .Editing && cursor.place == .Comment && cursor.comment == u32(i) {
					c   = ray.YELLOW
					c.a = 96
				}

				if first_comment {
					y += editor_label_y_offset / 2
					first_comment = false
				}

				/*{
					length := len(tmp)
					tmp    := lookup_comment_str(u32(i))
					i :=
					for 
				}*/
				str := lookup_comment_str(u32(i))

				have_cursor       := execution_status == .Editing && cursor.place == .Comment && cursor.comment == u32(i) 
				horizontal_offset := primary_font_char_width * 2 + 2 + editor_label_x_offset
				max_line_char_qnt := (window_width - horizontal_offset - cpu_view_area_width) / (primary_font_char_width + 1)

				fmt_cstr: cstring
				p: i32
			
				for len(str) > 0 {
					have_cursor_in_this_line: bool = ---
					old_p := p

					if (horizontal_offset + (i32(len(str)) * (primary_font_char_width + 1))) > (window_width - cpu_view_area_width) {
						insersection_idx := max_line_char_qnt
						for str[insersection_idx] != byte(' ') { insersection_idx -= 1 }
						fmt_cstr = ray.TextFormat("# %s", to_cstr(str[:insersection_idx]))

						if p != 0 {
							have_cursor_in_this_line = have_cursor && i32(cursor.char) >  p && i32(cursor.char) <= (insersection_idx + p)
						} else {
							have_cursor_in_this_line = have_cursor && i32(cursor.char) >= p && i32(cursor.char) <= (insersection_idx + p)
						}

						p += insersection_idx
						str = str[insersection_idx:]
					} else {
						fmt_cstr = ray.TextFormat("# %s", to_cstr(str))

						insersection_idx := i32(len(str))

						if p != 0 {
							have_cursor_in_this_line = have_cursor && i32(cursor.char) >  p && i32(cursor.char) <= (insersection_idx + p)
						} else {
							have_cursor_in_this_line = have_cursor && i32(cursor.char) >= p && i32(cursor.char) <= (insersection_idx + p)
						}

						str = ""
					}

					draw_text(fmt_cstr, editor_label_x_offset, y, primary_font_size, c)

					if have_cursor_in_this_line do draw_cursor_comment(horizontal_offset, y, i32(cursor.char) - old_p)

					y += editor_line_height
				}

				//never gonna give you up, never gonna let you down

				/*if execution_status == .Editing && cursor.place == .Comment && cursor.comment == u32(i) {
					draw_cursor_comment(editor_label_x_offset, y, fmt_cstr)
				}

				y += editor_line_height*/
			}
		}

		if execution_status == .Waiting && u16(i_ins) == main_cpu.pc {
			lerp_cursor(y)
			
			first_part_width := highlight_line_width - 150
			second_part_width := highlight_line_width - first_part_width

			ray.DrawRectangle(0, y, first_part_width, primary_font_size, line_highlight_color)

			c := line_highlight_color
			c.a = 212
			ray.DrawRectangleGradientH(first_part_width, y, second_part_width, primary_font_size,
				line_highlight_color, background_color) 
		}

		draw_text(ray.TextFormat("%d", i_ins), line_number_x, y, primary_font_size, ray.GRAY)

		tmp_x := x

		cstr := get_buffer_cstr(line)
		draw_text(cstr, tmp_x, y, primary_font_size, get_color(i_ins, 0))
		if execution_status == .Editing {
			if cursor.place == .Ins && cursor.ins == i_ins && cursor.param == 0 do draw_cursor(tmp_x, y, i_ins, 0)
			if buffer_status[line] == .Invalid do draw_err_indication(tmp_x, y, cstr)
		}

		tmp_x += editor_mnemonic_left_margin

		for i: u32 = 1; i < 4; i += 1 {
			cstr := get_buffer_cstr(line + int(i))
			draw_text(cstr, tmp_x, y, primary_font_size, get_color(i_ins, i))
			if execution_status == .Editing {
				if cursor.place == .Ins && cursor.ins == i_ins && cursor.param == i do draw_cursor(tmp_x, y, i_ins, i)
				if buffer_status[line + int(i)] == .Invalid do draw_err_indication(tmp_x, y, cstr)
			}

			tmp_x += editor_param_left_margin
		}

		y     += editor_line_height
		i_ins += 1
	}
}

set_gamepad_flags :: proc() {
	v := check_input_table(&config.gamepad_input_table) 

	main_cpu.reg_table[int(Register_Type.gp)] = i16(v)
}

process_editor_input :: proc() {
	update_char_cursor :: proc() {
		cstr: cstring
		length: u32

		switch cursor.place {
 		case .Ins:     cstr = lookup_buffer(cursor.ins, cursor.param)
		case .Label:   cstr = lookup_label(cursor.label)
		case .Comment: cstr = lookup_comment(cursor.comment)
		}
		length = u32(len(cstr))

		if cursor.char >= length do cursor.char = length		
	}

	move_up :: proc() {
		fmt.println(cursor)

		search_label_above_ins :: proc() -> (found_label := false) {
			labels := sl_slice(&main_cpu.labels)
			for i := 0; i < len(labels); i += 1 {
				label := &labels[i]

				for label.line == u16(cursor.ins) {
					found_label  = true
					cursor.label = u32(i)
					i += 1
					if i < len(labels) { label = &labels[i] } else { break }
				}

				if found_label {
					cursor.place = .Label
					break
				}
			}
			return
		}

		search_comment_above_ins :: proc() -> (found_comment := false) {
			comments := sl_slice(&main_cpu.comments)
			for i := 0; i < len(comments); i += 1 {
				comment := &comments[i]

				for comment.line == u16(cursor.ins) {
					found_comment  = true
					cursor.comment = u32(i)
					i += 1
					if i < len(comments) { comment = &comments[i] } else { break }
				}

				if found_comment {
					cursor.place = .Comment
					break
				}
			}
			return
		}

		search_comment_above_comment :: proc() -> bool {
			actual_comment := &main_cpu.comments.data[cursor.comment]

			if cursor.comment == 0 do return false

			for i := int(cursor.comment - 1); i >= 0; i -= 1 {
				it := &main_cpu.comments.data[i]

				if it.line == actual_comment.line {
					cursor.comment = u32(i)
					return true
				} else {
					break
				}
			}

			return false
		}

		search_label_above_comment :: proc() -> (found_label := false) {
			line := main_cpu.comments.data[cursor.comment].line

			labels := sl_slice(&main_cpu.labels)
			for i := 0; i < len(labels); i += 1 { //len(labels) in wrong!!! TODO
				label := &labels[i]

				for label.line == line {
					found_label  = true
					cursor.label = u32(i)
					i += 1
					if i < len(labels) { label = &labels[i] } else { break }
				}

				if found_label {
					cursor.place = .Label
					break
				}
			}
			return
		}

		switch cursor.place {
		case .Ins:
			if !search_comment_above_ins() && !search_label_above_ins() {
				if cursor.ins > 0 do cursor.ins -= 1
			}
		case .Label:
			has_label_above := false
			actual_label    := &main_cpu.labels.data[cursor.label]

			if cursor.label > 0 {
				above_label := &main_cpu.labels.data[cursor.label - 1]
				if actual_label.line == above_label.line {
					cursor.label -= 1
					has_label_above = true
				}
			}

			if !has_label_above && u32(actual_label.line) > 0 {
				cursor.ins   = u32(actual_label.line) - 1
				cursor.place = .Ins
			}
		case .Comment:
			if !search_comment_above_comment() && !search_label_above_comment() {
				ins := main_cpu.comments.data[cursor.comment].line
				if ins > 0 {
					cursor.ins   = u32(ins - 1)
					cursor.place = .Ins
				}
			}
		}
		update_char_cursor()
	}

	move_down :: proc() {
		search_label_below_ins :: proc() -> (found_label := false) {
			labels := sl_slice(&main_cpu.labels)
			for i := 0; i < len(labels); i += 1 {
				if labels[i].line == u16(cursor.ins + 1) {
					found_label  = true
					cursor.label = u32(i)
					cursor.place = .Label
					break
				}
			}
			return
		}

		search_comment_below_ins :: proc() -> (found_comment := false) {
			comments := sl_slice(&main_cpu.comments)
			for i := 0; i < len(comments); i += 1 {
				if comments[i].line == u16(cursor.ins + 1) {
					found_comment  = true
					cursor.comment = u32(i)
					cursor.place = .Comment
					break
				}
			}
			return
		}

		search_label_below_label :: proc() -> (found_label := false) {
			if cursor.label < (main_cpu.labels.len - 1) {
				below_label  := &main_cpu.labels.data[cursor.label + 1]
				if main_cpu.labels.data[cursor.label].line == below_label.line {
					cursor.label += 1
					cursor.place = .Label
					found_label = true
				}
			}
			return
		}

		search_comment_below_label :: proc() -> bool {
			line :=  main_cpu.labels.data[cursor.label].line

			length := main_cpu.comments.len

			for i := 0; i < int(length); i += 1 {
				it := &main_cpu.comments.data[i]

				if it.line == line {
					cursor.comment = u32(i)
					cursor.place   = .Comment
					return true
				} else {
					break
				}
			}

			return false
		}

		search_comment_below_comment :: proc() -> bool {
			actual_comment := &main_cpu.comments.data[cursor.comment]

			length := main_cpu.comments.len

			for i := int(cursor.comment + 1); i < int(length); i += 1 {
				it := &main_cpu.comments.data[i]

				if it.line == actual_comment.line {
					cursor.comment = u32(i)
					return true
				} else {
					break
				}
			}

			return false
		}

		switch cursor.place {
		case .Ins:
			if !search_comment_below_ins() && !search_label_below_ins() {
				length := main_cpu.editing_buffers.len / 4
				if cursor.ins < length - 1 do cursor.ins += 1
			}
		case .Label:
			if !search_label_below_label() && !search_comment_below_label() {
				actual_label := &main_cpu.labels.data[cursor.label]
				if u32(actual_label.line) < (main_cpu.editing_buffers.len/4) {
					cursor.ins   = u32(actual_label.line)
					cursor.place = .Ins
				}
			}
		case .Comment:
			if !search_comment_below_comment() {
				ins := main_cpu.comments.data[cursor.comment].line
				cursor.ins   = u32(ins)
				cursor.place = .Ins
			}
		}
		update_char_cursor()
	}

	add_line :: proc() {
		clean_buffer: Static_List(byte, 16)

		idx: u32 
		if cursor.place == .Ins {
			idx = u32(cursor.ins + 1)
		} else {
			idx = u32(main_cpu.labels.data[cursor.label].line)
		}
		idx *= 4

		sl_insert(&main_cpu.editing_buffers, clean_buffer, idx)
		sl_insert(&main_cpu.editing_buffers, clean_buffer, idx)
		sl_insert(&main_cpu.editing_buffers, clean_buffer, idx)
		sl_insert(&main_cpu.editing_buffers, clean_buffer, idx)

		labels := sl_slice(&main_cpu.labels)
		for i := 0; i < len(labels); i += 1 {
			label := &labels[i]

			if label.line > u16(cursor.ins) {
				label.line += 1
			}
		}
		
		move_down()

		cursor.param = 0

		unsaved = true	
	}

	delete_line :: proc() {
		switch cursor.place {
		case .Ins:
			idx := u32(cursor.ins)*4
			sl_remove(&main_cpu.editing_buffers, idx)
			sl_remove(&main_cpu.editing_buffers, idx)
			sl_remove(&main_cpu.editing_buffers, idx)
			sl_remove(&main_cpu.editing_buffers, idx)

			labels := sl_slice(&main_cpu.labels)
			for i := 0; i < len(labels); i += 1 {
				label := &labels[i]

				if label.line > u16(cursor.ins) {
					label.line -= 1
				}
			}

			if cursor.ins >= (main_cpu.editing_buffers.len/4) do cursor.ins = main_cpu.editing_buffers.len/4 - 1
		case .Label:
			cursor.ins   = u32(main_cpu.labels.data[cursor.label].line)
			cursor.place = .Ins
			sl_remove(&main_cpu.labels, u32(cursor.label))
		case .Comment:
			// TODO
		}
		unsaved = true
	}

	if ray.IsKeyPressed(.UP)  do move_up()
		
	if ray.IsKeyPressed(.DOWN) do move_down()

	left  := ray.IsKeyPressed(.LEFT)
	right := ray.IsKeyPressed(.RIGHT)
	l     := ray.IsKeyPressed(.L)
	if ray.IsKeyDown(.LEFT_CONTROL) {
		if left && cursor.param > 0 {
			cursor.param -= 1
			update_char_cursor()
		}

		if right && cursor.param < 3 {
			cursor.param += 1
			update_char_cursor()
		}

		if l {
			push_label("", u16(cursor.ins))
			move_up()
			unsaved = true
		}
	} else {
		if left {
			if cursor.char == 0 {
				if cursor.param > 0 {
					cursor.param -= 1
					cstr := lookup_buffer(cursor.ins, cursor.param) 
					cursor.char = u32(len(cstr))
					fmt.println(cursor.char)
				} else {
					cursor.char = 0
				}
			} else {
				cursor.char -= 1
			}
		}
		if right {
			cursor.char += 1

			switch cursor.place {
			case .Ins:
	 			cstr      := lookup_buffer(cursor.ins, cursor.param)
				length    := u32(len(cstr))
				if cursor.char > length {
					if cursor.param < 3 {
						cursor.param += 1
						cursor.char = 0
					} else {
						cursor.char = length
					}
				}
			case .Label:
				cstr   := lookup_label(cursor.label)
				length := u32(len(cstr))
				if cursor.char > length {
					cursor.char = length
				}
			case .Comment:
				cstr   := lookup_comment(cursor.comment)
				length := u32(len(cstr))
				if cursor.char > length {
					cursor.char = length
				}
			}
		}
	}

	if ray.IsKeyPressed(.ENTER) do add_line()
		
	if ray.IsKeyPressed(.DELETE) do delete_line()

	char_buffer: ^Static_List(byte, 16)
	char_buffer_comment: ^Static_List(byte, 64)

	switch cursor.place {
	case .Ins:
		char_buffer = &main_cpu.editing_buffers.data[cursor.ins * 4 + cursor.param]
	case .Label:
		char_buffer = &main_cpu.labels.data[cursor.label].name
	case .Comment:
		char_buffer_comment = &main_cpu.comments.data[cursor.comment].content
	}

	if ray.IsKeyPressed(.BACKSPACE) {
		if cursor.char > 0 {
			if cursor.place != .Comment {
				sl_remove(char_buffer, cursor.char - 1)
			} else {
				sl_remove(char_buffer_comment, cursor.char - 1)
			}
			cursor.char -= 1
			unsaved = true
		} else if cursor.param > 0 {
			cursor.param -= 1
			update_char_cursor()
		}
	}

	key := ray.GetCharPressed()

	for key > 0 {
	    if key >= 32 && key <= 125 {
	    	switch cursor.place {
	    	case .Label, .Ins:
				if char_buffer.len < 16 { 
					if !(key == ' ' && cursor.param < 3) { //TODO
						if key != '#' {
							sl_insert(char_buffer, byte(key), cursor.char)
							cursor.char += 1
							unsaved = true
						} else {
							insert_comment("O rato roeu a roupa do rei de roma", u16(cursor.ins), -1)
						}
					} else {
						cursor.param += 1
						update_char_cursor()
					}
				}
			case .Comment:
				if char_buffer_comment.len < 64 {
					if key != '#' {
						sl_insert(char_buffer_comment, byte(key), cursor.char)	    				
						cursor.char += 1
						unsaved = true
					} else {
						insert_comment("O rato roeu a roupa do rei de roma", u16(cursor.ins), -1)
					}
				} else {
					main_cpu.comments.data[cursor.comment].have_next = true
					cursor.comment += 1
					insert_comment("O rato roeu a roupa do rei de roma", u16(cursor.ins), int(cursor.comment))
					cursor.char = 0
				}
			}
	    	
	    }

	    key = ray.GetCharPressed()
	}
}

toggle_fullscreen :: proc() {
	display := ray.GetCurrentMonitor()
 
	if (ray.IsWindowFullscreen()) {
	    ray.SetWindowSize(config.window_width, config.window_height);
	} else {
	    ray.SetWindowSize(ray.GetMonitorWidth(display), ray.GetMonitorHeight(display))
	}

	ray.ToggleFullscreen()
}

run := true

main :: proc() {
	/*sl_push(&main_cpu.instructions, Instruction{ type=.Nop })
	sl_push(&main_cpu.instructions, Instruction{ type=.Add })
	sl_push(&main_cpu.instructions, Instruction{ type=.Sub })
	sl_push(&main_cpu.instructions, Instruction{ type=.Nop })
	sl_push(&main_cpu.instructions, Instruction{ type=.Jmp, imediate=true , p2=3000 })
	sl_push(&main_cpu.instructions, Instruction{ type=.Jmp, imediate=false, p0=u8(Register_Type.r0) })
	sl_push(&main_cpu.instructions, Instruction{ type=.Load })*/

	config.gamepad_input_table.up[0].type   = .Keyboard_Key
	config.gamepad_input_table.up[0].kb_key = Keyboard_Key_Entry{ key=.UP }
	config.gamepad_input_table.up[1].type   = .Gamepad_Axis
	config.gamepad_input_table.up[1].gp_axis = Gamepad_Axis_Entry{ axis_number=1, positive=false }

	config.gamepad_input_table.down[0].type   = .Keyboard_Key
	config.gamepad_input_table.down[0].kb_key = Keyboard_Key_Entry{ key=.DOWN }
	config.gamepad_input_table.down[1].type   = .Gamepad_Axis
	config.gamepad_input_table.down[1].gp_axis = Gamepad_Axis_Entry{ axis_number=1, positive=true }

	config.gamepad_input_table.left[0].type   = .Keyboard_Key
	config.gamepad_input_table.left[0].kb_key = Keyboard_Key_Entry{ key=.LEFT }
	config.gamepad_input_table.left[1].type   = .Gamepad_Axis
	config.gamepad_input_table.left[1].gp_axis = Gamepad_Axis_Entry{ axis_number=0, positive=false }

	config.gamepad_input_table.right[0].type   = .Keyboard_Key
	config.gamepad_input_table.right[0].kb_key = Keyboard_Key_Entry{ key=.RIGHT }
	config.gamepad_input_table.right[1].type   = .Gamepad_Axis
	config.gamepad_input_table.right[1].gp_axis = Gamepad_Axis_Entry{ axis_number=0, positive=true }

	/*if !load_cpu_from_file(&main_cpu, "save.pisc") {
		set_buffer(0, 0, "nopis")
		set_buffer(1, 0, "adding")
		set_buffer(1, 1, "r0")
		set_buffer(1, 2, "100")

		push_label("LOOP", 1)
	}*/

	set_buffer(0, 0, "nop")
	push_label("RESET", 0)

	config.primary_font = ray.GetFontDefault()
	ray.SetConfigFlags({.WINDOW_RESIZABLE})
    ray.InitWindow(config.window_width, config.window_height, "PISC Experience");

    ray.SetTargetFPS(60);

    //toggle_fullscreen()

    init_gpu(&main_cpu.gpu) //TODO: maybe you must to put this in another places, like in open
	video_buffer_texture = ray.LoadTextureFromImage(main_cpu.gpu.buffer)

    config.primary_font = ray.LoadFontEx("assets/Inconsolata-Regular.ttf", config.primary_font_size, nil, 0) 
    config.secondary_font = ray.LoadFontEx("assets/Inconsolata-Regular.ttf", config.secondary_font_size, nil, 0)
    config.shortcut_hint_font = ray.LoadFontEx("assets/Inconsolata-Regular.ttf", config.shortcut_hint_font_size, nil, 0)

    config.primary_font_char_width = i32(
    	ray.MeasureTextEx(config.primary_font, " ", f32(config.primary_font_size), 1.0).x)
    config.secondary_font_char_width = i32(
    	ray.MeasureTextEx(config.secondary_font, " ", f32(config.secondary_font_size), 1.0).x)
    config.shortcut_hint_char_width = i32(
    	ray.MeasureTextEx(config.shortcut_hint_font, " ", f32(config.shortcut_hint_font_size), 1.0).x)

    save_and_go_out :: proc() {
    	save()
        run = false
    }

    go_out :: proc() {
    	run = false
    }

    for run {
        ray.BeginDrawing()

        if ray.WindowShouldClose() {
        	if unsaved {
				open_yes_or_no_popup("There is unsaved things. Want to save?", save_and_go_out, go_out)
			} else {
				run = false
			}
        }

        if ray.IsWindowResized() {
        	config.window_width  = ray.GetScreenWidth()
        	config.window_height = ray.GetScreenHeight()
        }

        ray.ClearBackground(config.background_color)

        //check_line(cursor.ins)

        if !is_yes_or_no_popup_open {
	        if execution_status == .Editing {
    	    	process_editor_input() //TODO
	        } else {
    	    	set_gamepad_flags()
        	}
        }

        draw_editor()
        draw_top_bar_and_handle_shortcuts()
        draw_cpu()
        draw_status(i32(err_qnt))
        draw_video_buffer()
        draw_dialog_if_exists()

		if !is_yes_or_no_popup_open {
        	hide_yes_or_no_popup()

        	has_errs, err_qnt = compile()

	        if execution_status == .Running {
				for i := 0; !cpu_clock(&main_cpu); i += 1 {}
				ray.UpdateTexture(video_buffer_texture, main_cpu.gpu.buffer.data)
			}
		} else {
			draw_yes_or_no_popup()
		}

        ray.EndDrawing()
    }

    //dump_cpu_to_file(&main_cpu, "save.pisc")

    ray.CloseWindow()
}
