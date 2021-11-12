package pisc

import "core:fmt"
import "core:strconv"
import "core:strings"
import ray "vendor:raylib"

Config :: struct {
	window_width:                i32,
	window_height:               i32,
	editor_font_size:            i32,
	editor_line_height:          i32,
	editor_top_padding:          i32,
	editor_left_padding:         i32,
	editor_mnemonic_left_margin: i32,
	editor_param_left_margin:    i32,
	editor_font:            ray.Font,
	editor_label_y_offset:       i32,
	editor_label_x_offset:       i32,
	memory_font_size:            i32, 
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

main_cpu: CPU
config := Config{
	window_width=1200,
	window_height=600,
	editor_font_size=20,
	editor_line_height=20,
	editor_top_padding=64,
	editor_left_padding=64,
	editor_mnemonic_left_margin=120,
	editor_param_left_margin=60,
	editor_label_y_offset=12,
	editor_label_x_offset=8,
	memory_font_size=16,
}
cursor: Cursor

buffer_status: [MAX_INSTRUCTIONS*4]BufferStatus
has_errs := false
err_qnt  := 0

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
			ins.p0 = u8(reg2_type)
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
				buffer_status[buffer_idx + 1] = .Invalid
				success = false
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
			ray.DrawPixel(window_width  - 730 + x, y + 32, pisc_color_to_rbg(pisc_color));
		}
	}
}

draw_status :: proc(err_qnt: i32) {
	using config

	x: i32 = window_width  - 730
	y: i32 = 0
	i: i32 = 0
	ray.DrawText(ray.TextFormat("STATUS: RUNNING, ERRORS: %d", err_qnt),
		x, y + 8, memory_font_size, ray.LIGHTGRAY)
}

draw_memory :: proc() {
	using config

	x : i32 =  window_width  - 730
	y : i32 = (window_height - 28*4) - 28
	i : i32
	ray.DrawText("REGISTERS", x, y + 8, memory_font_size, ray.LIGHTGRAY)
	for name, reg in registers_table {
		if i%8 == 0 { 
			y += 28
			x = window_width - 730 - 90
		}

		x += 90
		ray.DrawText(ray.TextFormat("%s:", name), x, y, memory_font_size, ray.GRAY)

		value := main_cpu.reg_table[int(reg)]
		ray.DrawText(ray.TextFormat("%d", value), x + 32, y, memory_font_size, ray.LIGHTGRAY)

		i += 1
	}

	x = window_width - 80*3
	y = 0
	i = 0
	ray.DrawText("RAM", x, y + 8, memory_font_size, ray.LIGHTGRAY)
	for b in main_cpu.mem[0:64] {
		if i%4 == 0 { 
			y += 28
			x = window_width - 80*3

			ray.DrawText(ray.TextFormat("%d", i), x, y, memory_font_size, ray.GRAY)
			x += 48
		}

		ray.DrawText(ray.TextFormat("%x", b), x, y, memory_font_size, ray.LIGHTGRAY)
		x += 46

		i += 1
	}

	x =  window_width  - 730
	y = GPU_BUFFER_H + 32
	i = 0
	ray.DrawText("CALL STACK", x, y + 8, memory_font_size, ray.LIGHTGRAY)
	call_stack := sl_slice(&main_cpu.call_stack)
	if len(call_stack) != 0 {
		for addr in call_stack {
			//TODO
		}
	} else {
		ray.DrawText("EMPTY CALL STACK", x, y + 8 + 28, memory_font_size, ray.GRAY)
	}
}

draw_editor :: proc() {
	using config

	get_color :: proc(i_ins: u32, i_param: u32) -> ray.Color {		
		if !cursor.in_label && cursor.ins == i_ins && cursor.param == i_param {
			return ray.YELLOW
		}

		return ray.LIGHTGRAY
	}

	get_buffer_cstr :: proc(i: int) -> cstring {
		char_buffer := &main_cpu.editing_buffers.data[i]
		return strings.clone_to_cstring(string(sl_slice(char_buffer)))
	}

	draw_cursor :: proc(x: i32, y: i32, i_ins: u32, i_param: u32) {
		cstr          := lookup_buffer(i_ins, i_param)
		first_half    := strings.clone_to_cstring(string(cstr)[:cursor.char])
		cursor_offset := ray.MeasureText(first_half, config.editor_font_size)
		cursor_x      := x + cursor_offset
		ray.DrawLine(cursor_x, y, cursor_x, y + config.editor_font_size, ray.LIGHTGRAY)
	}

	draw_cursor_label :: proc(x: i32, y: i32, cstr: cstring) {
		first_half    := strings.clone_to_cstring(string(cstr)[:cursor.char])
		cursor_offset := ray.MeasureText(first_half, config.editor_font_size)
		cursor_x      := x + cursor_offset
		ray.DrawLine(cursor_x, y, cursor_x, y + config.editor_font_size, ray.LIGHTGRAY)
	}

	draw_err_indication :: proc(x: i32, y: i32, cstr: cstring) {
		word_size := ray.MeasureText(cstr, config.editor_font_size)
		tmp_y := y + config.editor_font_size
		ray.DrawLine(x, tmp_y, x + word_size, tmp_y, ray.RED)
	}

	i_ins: u32 = 0
	x: i32 = editor_left_padding
	y: i32 = 0
	line_number_x: i32 = editor_left_padding / 2 //TODO: gambiarra

	buffers := sl_slice(&main_cpu.editing_buffers)
	for line := 0; line < len(buffers); line += 4 {

		labels := sl_slice(&main_cpu.labels)
		for i := 0; i < len(labels); i += 1 {
			label := &labels[i]

			if label.line == u16(i_ins) {
				cstr := lookup_label(u32(i))
				c := ray.LIGHTGRAY
				if cursor.in_label && cursor.label == u32(i) do c = ray.YELLOW

				y += editor_label_y_offset
				ray.DrawText(ray.TextFormat("%s:", cstr), 
					editor_label_x_offset, y, editor_font_size, c)

				if cursor.in_label && cursor.label == u32(i) {
					draw_cursor_label(editor_label_x_offset, y, cstr)
				}
				y += editor_line_height
			}
		}

		ray.DrawText(ray.TextFormat("%d", i_ins), line_number_x, y, editor_font_size, ray.GRAY)

		tmp_x := x

		cstr := get_buffer_cstr(line)
		ray.DrawText(cstr, tmp_x, y, editor_font_size, get_color(i_ins, 0))
		if !cursor.in_label && cursor.ins == i_ins && cursor.param == 0 do draw_cursor(tmp_x, y, i_ins, 0)
		if buffer_status[line] == .Invalid do draw_err_indication(tmp_x, y, cstr)

		tmp_x += editor_mnemonic_left_margin

		for i: u32 = 1; i < 4; i += 1 {
			cstr := get_buffer_cstr(line + int(i))
			ray.DrawText(cstr, tmp_x, y, editor_font_size, get_color(i_ins, i))
			if !cursor.in_label && cursor.ins == i_ins && cursor.param == i do draw_cursor(tmp_x, y, i_ins, i)
			if buffer_status[line + int(i)] == .Invalid do draw_err_indication(tmp_x, y, cstr)

			tmp_x += editor_param_left_margin
		}

		y     += editor_line_height
		i_ins += 1
	}
}

process_input :: proc() {
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
				cursor.ins -= 1
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
	}

	if ray.IsKeyPressed(.UP) && cursor.ins > 0 do move_up()
		
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

	if ray.IsKeyPressed(.ENTER) {
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
		
		move_down()

		cursor.param = 0
	}
		
	if ray.IsKeyPressed(.DELETE) {
		if !cursor.in_label {
			idx := u32(cursor.ins)*4
			sl_remove(&main_cpu.editing_buffers, idx)
			sl_remove(&main_cpu.editing_buffers, idx)
			sl_remove(&main_cpu.editing_buffers, idx)
			sl_remove(&main_cpu.editing_buffers, idx)

			if cursor.ins >= (main_cpu.editing_buffers.len/4) do cursor.ins = main_cpu.editing_buffers.len/4 - 1
		} else {
			sl_remove(&main_cpu.labels, u32(cursor.label))
		}
	}

	char_buffer: ^Static_List(byte, 16)
	if !cursor.in_label {
		char_buffer = &main_cpu.editing_buffers.data[cursor.ins * 4 + cursor.param]
	} else {
		char_buffer = &main_cpu.labels.data[cursor.label].name
	}

	if ray.IsKeyPressed(.BACKSPACE) && cursor.char > 0 {
		sl_remove(char_buffer, cursor.char - 1)
		cursor.char -= 1
	}

	key := ray.GetCharPressed()

	for key > 0 {
	    if key >= 32 && key <= 125 && char_buffer.len < 16 {
	    	sl_insert(char_buffer, byte(key), cursor.char)
	    	cursor.char += 1
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

	for i := 0; i < GPU_BUFFER_H * GPU_BUFFER_W; i += 1 {
		main_cpu.gpu.buffer[i] = u16(i)
	}

	set_buffer(0, 0, "nopis")
	set_buffer(1, 0, "adding")
	set_buffer(1, 1, "r0")
	set_buffer(1, 2, "100")

	push_label("LOOP", 1)

	config.editor_font = ray.GetFontDefault()
    ray.InitWindow(config.window_width, config.window_height, "PISC Experience");

    ray.SetTargetFPS(60);

    for !ray.WindowShouldClose() {
        ray.BeginDrawing()

        ray.ClearBackground(ray.BLACK)

        //check_line(cursor.ins)

        process_input()

        draw_editor()
        draw_memory()
        draw_status(i32(err_qnt))
        draw_video_buffer()

        has_errs, err_qnt = compile()

        ray.EndDrawing()
    }

    ray.CloseWindow()
}
