package pisc

import "core:fmt"
import "core:strconv"
import "core:strings"
import "sfd"
import ray "vendor:raylib"

Config :: struct {
	window_width:                    i32,
	window_height:                   i32,
	background_color:                ray.Color,
	top_bar_height:                  i32,
	top_bar_shortcut_hint_font:      ray.Font,
	top_bar_shortcut_hint_font_size: i32,
	editor_font_size:                i32,
	editor_line_height:              i32,
	editor_top_padding:              i32,
	editor_left_padding:             i32,
	editor_mnemonic_left_margin:     i32,
	editor_param_left_margin:        i32,
	editor_font:                     ray.Font,
	editor_label_y_offset:           i32,
	editor_label_x_offset:           i32,
	editor_line_highlight_color:     ray.Color,
	editor_error_highlight_color:    ray.Color,
	editor_font_color:               ray.Color,
	memory_font:                     ray.Font,
	memory_font_size:                i32, 
	memory_label_font_color:         ray.Color,
	memory_value_font_color:         ray.Color,
	gamepad_input_table:             Input_Table,
}

Cursor :: struct {
	ins:      u32,
	param:    u32,
	char:     u32,
	label:    u32,
	in_label: bool,
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
	top_bar_shortcut_hint_font_size=12,
	editor_font_size=20,
	editor_line_height=20,
	editor_top_padding=64,
	editor_left_padding=64,
	editor_mnemonic_left_margin=120,
	editor_param_left_margin=60,
	editor_label_y_offset=12,
	editor_label_x_offset=8,
	editor_line_highlight_color=ray.Color{70, 70, 70, 255},
	editor_error_highlight_color=ray.Color{249, 36, 72, 255},
	editor_font_color=ray.WHITE,
	memory_font_size=16,
	memory_label_font_color=ray.Color{221, 199, 79, 255},
	memory_value_font_color=ray.WHITE,
}
cursor: Cursor
buffer_status: [MAX_INSTRUCTIONS*4]BufferStatus
has_errs         := false
err_qnt          := 0
execution_status := ExecutionStatus.Editing
editor_y_offset: i32

have_editing_path := false
editing_path: cstring

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

draw_video_buffer :: proc() {
	using config

	pisc_color_to_rbg :: proc(pisc_color: u16) -> (rgb: ray.Color) {
		rgb.r = u8(((pisc_color       & 0b00000000_00011111) * 255) / 31)
		rgb.g = u8(((pisc_color >> 5  & 0b00000000_00011111) * 255) / 31)
		rgb.b = u8(((pisc_color >> 10 & 0b00000000_00011111) * 255) / 31) 
		rgb.a = 255
		return
	}

	for y : i32 = 0; y < GPU_BUFFER_H; y += 1 {
		for x : i32 = 0; x < GPU_BUFFER_W; x += 1 {
			pisc_color := main_cpu.gpu.buffer[y*GPU_BUFFER_W + x]
			ray.DrawPixel(window_width  - 730 + x, y + 32 + top_bar_height, pisc_color_to_rbg(pisc_color));
		}
	}
}

draw_status :: proc(err_qnt: i32) {
	using config

	draw_text :: proc(cstr: cstring, x, y, font_size: i32, color: ray.Color) {
		ray.DrawTextEx(config.memory_font, cstr, ray.Vector2{f32(x), f32(y)}, f32(font_size), 1.0, color)
	}

	x: i32 = window_width  - 730
	y: i32 = top_bar_height
	i: i32 = 0
	draw_text(ray.TextFormat("STATUS: RUNNING, ERRORS: %d", err_qnt),
		x, y + 8, memory_font_size, ray.LIGHTGRAY)
	draw_text(ray.TextFormat("FPS: %d", ray.GetFPS()),
		x + 250, y + 8, memory_font_size, ray.LIGHTGRAY)
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

draw_top_bar_and_handle_shortcuts :: proc() {
	using config

	draw_text :: proc(cstr: cstring, x, y, font_size: i32, color: ray.Color) {
		ray.DrawTextEx(config.memory_font, cstr, ray.Vector2{f32(x), f32(y)}, f32(font_size), 1.0, color)
	}
	
	draw_text_shortcut_hint :: proc(cstr: cstring, x, y, font_size: i32, color: ray.Color) {
		ray.DrawTextEx(config.top_bar_shortcut_hint_font, cstr, ray.Vector2{f32(x), f32(y)}, f32(font_size), 1.0, color)
	}

	reset_top_bar :: proc(init_x: i32) {
		for i := 0; i < 7; i += 1 {
			btn_position[i] = init_x
			btn_alpha[i] = 0
		}
	}

	c := editor_line_highlight_color

	mouse_x := ray.GetMouseX()
	mouse_y := ray.GetMouseY()

	init_x : i32 = window_width - 730
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

	{
		if btn_state[NEW_BTN] == .Clicked || (ray.IsKeyDown(.LEFT_CONTROL) && ray.IsKeyPressed(.N)) {

		} else if btn_state[OPEN_BTN] == .Clicked || (ray.IsKeyDown(.LEFT_CONTROL) && ray.IsKeyPressed(.O)) {
			opt := sfd.Options{
				title="Open File",
				path=".",
				filter_name="PISC file",
				filter="*",
				extension="",
			}
			load_cpu_from_file(&main_cpu, sfd.open_dialog(&opt))
		} else if btn_state[SAVE_BTN] == .Clicked || (ray.IsKeyDown(.LEFT_CONTROL) && ray.IsKeyPressed(.S)) {
			if !have_editing_path {
				opt := sfd.Options{
					title="Save file as",
					path=".",
					filter_name="PISC file",
					filter="*",
					extension="",
				}
				editing_path = sfd.save_dialog(&opt)
				have_editing_path = true

				dump_cpu_to_file(&main_cpu, editing_path)
			} else {
				dump_cpu_to_file(&main_cpu, editing_path)
			}
		} else if btn_state[SAVE_BTN] == .Clicked || (ray.IsKeyDown(.LEFT_CONTROL) &&
		ray.IsKeyPressed(.LEFT_SHIFT) && ray.IsKeyPressed(.S)) {
			opt := sfd.Options{
				title="Save file as",
				path=".",
				filter_name="PISC file",
				filter="*",
				extension="",
			}
			editing_path = sfd.save_dialog(&opt)
			have_editing_path = true

			dump_cpu_to_file(&main_cpu, editing_path)
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
        		cpu_reset(&main_cpu)
        		execution_status = .Waiting
        		reset_top_bar(init_x)
        	}

        	if ray.IsKeyPressed(.F6) || btn_state[SAVE_AS_BTN + 2] == .Clicked {
        		cpu_reset(&main_cpu)
        		main_cpu.pc = u16(cursor.ins)
        		execution_status = .Waiting
        		reset_top_bar(init_x)
        	}

        	if ray.IsKeyPressed(.F4) || btn_state[SAVE_AS_BTN + 3] == .Clicked {
        		cpu_reset(&main_cpu)
        		execution_status = .Running
        		reset_top_bar(init_x)
        	}

        case .Running:

        	for i := 0; !cpu_clock(&main_cpu); i += 1 {}

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

			ray.DrawRectangle(x + 1, 1, button_width - 2, top_bar_height - 2, memory_label_font_color)

		case .Clicked:
			ray.DrawRectangle(x, 0, button_width, top_bar_height, ray.WHITE)
		}

		text_color.a          = u8(btn_alpha[i])
		shortcut_hint_color.a = u8(btn_alpha[i])

		draw_text(btn_text[i], x + 4, 2, memory_font_size, text_color)
		draw_text_shortcut_hint(btn_shortcut_text[i], x + 4, 2 + memory_font_size, top_bar_shortcut_hint_font_size, shortcut_hint_color)
	}
}

draw_memory :: proc() {
	using config

	draw_text :: proc(cstr: cstring, x, y, font_size: i32, color: ray.Color) {
		ray.DrawTextEx(config.memory_font, cstr, ray.Vector2{f32(x), f32(y)}, f32(font_size), 1.0, color)
	}

	x : i32 =  window_width  - 730
	y : i32 = (window_height - 28*4) - 28
	i : i32
	draw_text("REGISTERS", x, y + 8, memory_font_size, ray.LIGHTGRAY)
	for name, reg in registers_table {
		if i%8 == 0 { 
			y += 28
			x = window_width - 730 - 90
		}

		x += 90
		draw_text(ray.TextFormat("%s:", name), x, y, memory_font_size, memory_label_font_color)

		value := main_cpu.reg_table[int(reg)]
		draw_text(ray.TextFormat("%d", value), x + 32, y, memory_font_size, memory_value_font_color)

		i += 1
	}

	x = window_width - 730 + 7*90
	draw_text("pc:", x, y, memory_font_size, memory_label_font_color)
	draw_text(ray.TextFormat("%d", main_cpu.pc), x + 32, y, memory_font_size, memory_value_font_color)

	x = window_width - 80*3
	y = top_bar_height
	i = 0
	draw_text("RAM", x, y + 8, memory_font_size, ray.LIGHTGRAY)

	regs_len := window_height - 28*5
	for b := 0; b < len(main_cpu.mem); b += 1 {
		if i%4 == 0 { 
			y += 28
			if y >= regs_len do break

			x = window_width - 80*3

			draw_text(ray.TextFormat("%d", i), x, y, memory_font_size, memory_label_font_color)
			x += 48
		}

		draw_text(ray.TextFormat("%x", main_cpu.mem[b]), x, y, memory_font_size, memory_value_font_color)
		x += 46

		i += 1
	}

	x =  window_width  - 730
	y = GPU_BUFFER_H + 32 + top_bar_height
	i = 0
	draw_text("CALL STACK", x, y + 8, memory_font_size, ray.LIGHTGRAY)
	call_stack := sl_slice(&main_cpu.call_stack)
	if len(call_stack) != 0 {
		for addr in call_stack {
			//TODO
		}
	} else {
		draw_text("EMPTY CALL STACK", x, y + 8 + 28, memory_font_size, ray.GRAY)
	}
}

draw_editor :: proc() {
	using config

	get_color :: proc(i_ins: u32, i_param: u32) -> ray.Color {		
		if execution_status == .Editing && !cursor.in_label && cursor.ins == i_ins && cursor.param == i_param {
			return ray.YELLOW
		}

		return config.editor_font_color
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
		cursor_offset := i32(ray.MeasureTextEx(config.editor_font, first_half, f32(config.editor_font_size), 1.0).x)
		cursor_x      := x + cursor_offset
		ray.DrawLine(cursor_x, y, cursor_x, y + config.editor_font_size, ray.LIGHTGRAY)
	}

	draw_cursor_label :: proc(x, y: i32, cstr: cstring) {
		lerp_cursor(y)

		first_half    := strings.clone_to_cstring(string(cstr)[:cursor.char])
		cursor_offset := i32(ray.MeasureTextEx(config.editor_font, first_half, f32(config.editor_font_size), 1.0).x)
		cursor_x      := x + cursor_offset
		ray.DrawLine(cursor_x, y, cursor_x, y + config.editor_font_size, ray.LIGHTGRAY)
	}

	draw_err_indication :: proc(x: i32, y: i32, cstr: cstring) {
		word_size := i32(ray.MeasureTextEx(config.editor_font, cstr, f32(config.editor_font_size), 1.0).x)
		tmp_y := y + config.editor_font_size
		ray.DrawLine(x, tmp_y, x + word_size, tmp_y, config.editor_error_highlight_color)
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
		ray.DrawTextEx(config.editor_font, cstr, ray.Vector2{f32(x), f32(y)}, f32(font_size), 1.0, color)
	}

	i_ins: u32 = 0
	x: i32 = editor_left_padding
	y: i32 = editor_y_offset

	line_number_x: i32 = editor_left_padding / 2 //TODO: gambiarra

	highlight_line_width := window_width - 730 - 8

	buffers := sl_slice(&main_cpu.editing_buffers)
	for line := 0; line < len(buffers); line += 4 {

		labels := sl_slice(&main_cpu.labels)
		for i := 0; i < len(labels); i += 1 {
			label := &labels[i]

			if label.line == u16(i_ins) {
				cstr := lookup_label(u32(i))
				c := config.editor_font_color
				if cursor.in_label && cursor.label == u32(i) do c = ray.YELLOW

				y += editor_label_y_offset
				draw_text(ray.TextFormat("%s:", cstr), 
					editor_label_x_offset, y, editor_font_size, c)

				if cursor.in_label && cursor.label == u32(i) {
					draw_cursor_label(editor_label_x_offset, y, cstr)
				}
				y += editor_line_height
			}
		}

		if execution_status == .Waiting && u16(i_ins) == main_cpu.pc {
			ray.DrawRectangle(0, y, highlight_line_width, editor_font_size, editor_line_highlight_color)
		}

		draw_text(ray.TextFormat("%d", i_ins), line_number_x, y, editor_font_size, ray.GRAY)

		tmp_x := x

		cstr := get_buffer_cstr(line)
		draw_text(cstr, tmp_x, y, editor_font_size, get_color(i_ins, 0))
		if execution_status == .Editing {
			if !cursor.in_label && cursor.ins == i_ins && cursor.param == 0 do draw_cursor(tmp_x, y, i_ins, 0)
			if buffer_status[line] == .Invalid do draw_err_indication(tmp_x, y, cstr)
		}

		tmp_x += editor_mnemonic_left_margin

		for i: u32 = 1; i < 4; i += 1 {
			cstr := get_buffer_cstr(line + int(i))
			draw_text(cstr, tmp_x, y, editor_font_size, get_color(i_ins, i))
			if execution_status == .Editing {
				if !cursor.in_label && cursor.ins == i_ins && cursor.param == i do draw_cursor(tmp_x, y, i_ins, i)
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
		length: u32

		if !cursor.in_label {
 			cstr   := lookup_buffer(cursor.ins, cursor.param)
			length = u32(len(cstr))
		} else {
			cstr   := lookup_label(cursor.label)
			length = u32(len(cstr))
		}

		if cursor.char >= length do cursor.char = length		
	}

	move_up :: proc() {
		if !cursor.in_label {
			found_label := false

			labels := sl_slice(&main_cpu.labels)
			for i := 0; i < len(labels); i += 1 {
				label := &labels[i]

				for label.line == u16(cursor.ins) {
					found_label  = true
					cursor.label = u32(i)
					i += 1
					if i < len(labels) { label = &labels[i] } else { break }
				}

				if found_label do break
			}

			if !found_label {
				if cursor.ins > 0 do cursor.ins -= 1
			} else {
				cursor.in_label = true
				fmt.println(cursor)
			}
		} else {
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
				cursor.ins      = u32(actual_label.line) - 1
				cursor.in_label = false
			}
		}
		update_char_cursor()
/*
		cursor_y := get_cursor_y_offset()
	fmt.println("cursor_y = ", cursor_y)
	
		if cursor_y < (config.editor_line_height * 2) {
			editor_y_offset = (config.editor_line_height * 2) - cursor_y
		}*/
	}

	move_down :: proc() {
		if !cursor.in_label {
			cursor.ins += 1

			found_label := false

			labels := sl_slice(&main_cpu.labels)
			for i := 0; i < len(labels); i += 1 {
				label := &labels[i]

				if label.line == u16(cursor.ins) {
					found_label  = true
					cursor.label = u32(i)
					break
				}
			}

			if !found_label {
				if cursor.ins >= (main_cpu.editing_buffers.len/4) do cursor.ins -= 1
			} else {
				cursor.in_label = true
			}
		} else {
			has_label_below := false
			actual_label    := &main_cpu.labels.data[cursor.label]

			if cursor.label < (main_cpu.labels.len - 1) {
				below_label  := &main_cpu.labels.data[cursor.label + 1]
				if actual_label.line == below_label.line {
					cursor.label += 1
					has_label_below = true
				}
			}

			if !has_label_below && u32(actual_label.line) < (main_cpu.editing_buffers.len/4) {
				cursor.ins      = u32(actual_label.line)
				cursor.in_label = false
			}
		}
		update_char_cursor()	
/*
		cursor_y := get_cursor_y_offset()
	fmt.println("cursor_y = ", cursor_y)
	
		if cursor_y > (config.window_height - config.editor_line_height * 2) {
			editor_y_offset = -(cursor_y - (config.window_height - config.editor_line_height * 2)) 
		}*/
	}

	add_line :: proc() {
		clean_buffer: Static_List(byte, 16)

		idx: u32 
		if !cursor.in_label {
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
	}

	delete_line :: proc() {
		if !cursor.in_label {
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
		} else {
			cursor.ins      = u32(main_cpu.labels.data[cursor.label].line)
			cursor.in_label = false
			sl_remove(&main_cpu.labels, u32(cursor.label))
		}
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

			if !cursor.in_label {
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
			} else {
				cstr   := lookup_label(cursor.label)
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
	if !cursor.in_label {
		char_buffer = &main_cpu.editing_buffers.data[cursor.ins * 4 + cursor.param]
	} else {
		char_buffer = &main_cpu.labels.data[cursor.label].name
	}

	if ray.IsKeyPressed(.BACKSPACE) {
		if cursor.char > 0 {
			sl_remove(char_buffer, cursor.char - 1)
			cursor.char -= 1
		} else if cursor.param > 0 {
			cursor.param -= 1
			update_char_cursor()
		}
	}

	key := ray.GetCharPressed()

	for key > 0 {
	    if key >= 32 && key <= 125 && char_buffer.len < 16 {
	    	if !(key == ' ' && cursor.param < 3) {
	    		sl_insert(char_buffer, byte(key), cursor.char)
	    		cursor.char += 1
			} else {
				cursor.param += 1
				update_char_cursor()
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

	if !load_cpu_from_file(&main_cpu, "save.pisc") {
		set_buffer(0, 0, "nopis")
		set_buffer(1, 0, "adding")
		set_buffer(1, 1, "r0")
		set_buffer(1, 2, "100")

		push_label("LOOP", 1)
	}

	config.editor_font = ray.GetFontDefault()
	ray.SetConfigFlags({.WINDOW_RESIZABLE})
    ray.InitWindow(config.window_width, config.window_height, "PISC Experience");

    ray.SetTargetFPS(60);

    //toggle_fullscreen()

    config.editor_font = ray.LoadFontEx("assets/Inconsolata-Regular.ttf", config.editor_font_size, nil, 0) 
    config.memory_font = ray.LoadFontEx("assets/Inconsolata-Regular.ttf", config.memory_font_size, nil, 0)
    config.top_bar_shortcut_hint_font = ray.LoadFontEx("assets/Inconsolata-Regular.ttf", config.top_bar_shortcut_hint_font_size, nil, 0)


    for !ray.WindowShouldClose() {
        ray.BeginDrawing()

        if ray.IsWindowResized() {
        	config.window_width  = ray.GetScreenWidth()
        	config.window_height = ray.GetScreenHeight()
        }

        ray.ClearBackground(config.background_color)

        //check_line(cursor.ins)

        if execution_status == .Editing {
        	process_editor_input() //TODO
        } else {
        	set_gamepad_flags()
        }

        draw_editor()
        draw_top_bar_and_handle_shortcuts()
        draw_memory()
        draw_status(i32(err_qnt))
        draw_video_buffer()

        has_errs, err_qnt = compile()

        ray.EndDrawing()
    }

    dump_cpu_to_file(&main_cpu, "save.pisc")

    ray.CloseWindow()
}
