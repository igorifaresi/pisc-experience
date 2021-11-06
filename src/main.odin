package pisc

import "core:fmt"
import "core:strconv"
import "core:strings"
import ray "vendor:raylib"

Config :: struct {
	window_width:        i32,
	window_height:       i32,
	editor_font_size:    i32,
	editor_line_height:  i32,
	editor_top_padding:  i32,
	editor_left_padding: i32,
	editor_param_margin: i32,
	editor_font:    ray.Font,
	memory_font_size:    i32, 
}

Cursor :: struct {
	ins:   u32,
	param: u32,
	char:  u32,
}

main_cpu: CPU
config := Config{
	window_width=1200,
	window_height=600,
	editor_font_size=20,
	editor_line_height=20,
	editor_top_padding=64,
	editor_left_padding=64,
	editor_param_margin=80,
	memory_font_size=16,
}
cursor: Cursor

check_line :: proc(i_ins: u32) {
	cstr: cstring

	ins := &main_cpu.instructions.data[i_ins]

	ins_buffer := &main_cpu.editing_buffers.data[i_ins * 4 + 0]
	cstr = strings.clone_to_cstring(string(sl_slice(ins_buffer)))
	ins_type, ok := mnemonics_table[cstr]
	if ok {
		ins.type = ins_type
		if cursor.ins != i_ins || cursor.param != 0 do sl_clear(ins_buffer)
	}

	switch instruction_param_type_table[ins.type] {
	case .Reg_And_Reg_And_Offset:

		reg1_type, reg2_type: Register_Type
		imediate: i64
		ok: bool

		p0_buffer := &main_cpu.editing_buffers.data[i_ins * 4 + 1]
		cstr = strings.clone_to_cstring(string(sl_slice(p0_buffer)))
		reg1_type, ok = registers_table[cstr]
		if ok {
			ins.p0 = u8(reg1_type)
			if cursor.ins != i_ins || cursor.param != 1 do sl_clear(p0_buffer)
		}

		p1_buffer := &main_cpu.editing_buffers.data[i_ins * 4 + 2]
		cstr = strings.clone_to_cstring(string(sl_slice(p1_buffer)))
		reg2_type, ok = registers_table[cstr]
		if ok {
			ins.p0 = u8(reg2_type)
			if cursor.ins != i_ins || cursor.param != 2 do sl_clear(p1_buffer)
		}

		p2_buffer := &main_cpu.editing_buffers.data[i_ins * 4 + 3]
		str := string(sl_slice(p2_buffer))
		imediate, ok = strconv.parse_i64(str)
		if ok {
			ins.p2 = i16(imediate)
			ins.imediate = true
			if cursor.ins != i_ins || cursor.param != 3 do sl_clear(p2_buffer)
		}

	case .Reg_And_Reg_Or_Imediate:
		reg1_type, reg2_type: Register_Type
		ok: bool

		p0_buffer := &main_cpu.editing_buffers.data[i_ins * 4 + 1]
		cstr = strings.clone_to_cstring(string(sl_slice(p0_buffer)))
		reg1_type, ok = registers_table[cstr]
		if ok {
			ins.p0 = u8(reg1_type)
			if cursor.ins != i_ins || cursor.param != 1 do sl_clear(p0_buffer)
		}

		p1_buffer := &main_cpu.editing_buffers.data[i_ins * 4 + 2]
		str := string(sl_slice(p1_buffer))
		cstr = strings.clone_to_cstring(str)
		reg2_type, ok = registers_table[cstr]
		if ok {
			ins.p0 = u8(reg2_type)
			if cursor.ins != i_ins || cursor.param != 2 do sl_clear(p1_buffer)
		} else {
			imediate, ok := strconv.parse_i64(str)
			if ok {
				ins.p2 = i16(imediate)
				ins.imediate = true
				if cursor.ins != i_ins || cursor.param != 2 do sl_clear(p1_buffer)
			}
		}

	case .Reg:

		reg_buffer := &main_cpu.editing_buffers.data[i_ins * 4 + 1]
		cstr = strings.clone_to_cstring(string(sl_slice(reg_buffer)))
		reg_type, ok := registers_table[cstr]
		if ok {
			ins.p0 = u8(reg_type)
			if cursor.ins != i_ins || cursor.param != 1 do sl_clear(reg_buffer)
		}
	
	case .Reg_Or_Imediate:

		p0_buffer := &main_cpu.editing_buffers.data[i_ins * 4 + 1]
		str := string(sl_slice(p0_buffer))
		cstr = strings.clone_to_cstring(str)
		reg_type, ok := registers_table[cstr]
		if ok {
			ins.p0 = u8(reg_type)
			if cursor.ins != i_ins || cursor.param != 1 do sl_clear(p0_buffer)
		} else {
			imediate, ok := strconv.parse_i64(str)
			if ok {
				ins.p2 = i16(imediate)
				ins.imediate = true
				if cursor.ins != i_ins || cursor.param != 1 do sl_clear(p0_buffer)
			}
		}
	
	case .Nothing:
	}
}

lookup_buffer :: proc(i_ins: u32, i_param: u32) -> cstring {
	char_buffer := &main_cpu.editing_buffers.data[i_ins * 4 + i_param]
	return strings.clone_to_cstring(string(sl_slice(char_buffer)))
}

set_buffer :: proc(i_ins: u32, i_param: u32, str: string) {
	char_buffer := &main_cpu.editing_buffers.data[i_ins * 4 + i_param]
	sl_clear(char_buffer)
	for i := 0; i < len(str); i += 1 {
		sl_push(char_buffer, str[i])
	}
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

draw_status :: proc() {
	using config

	x : i32 = window_width  - 730
	y : i32 = 0
	i : i32 = 0
	ray.DrawText(ray.TextFormat("STATUS: %s", "RUNNING"), x, y + 8, memory_font_size, ray.LIGHTGRAY)
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
			x = window_width - 730 - 80
		}

		x += 80
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
		char_buffer := &main_cpu.editing_buffers.data[i_ins * 4 + i_param]
		
		if cursor.ins == i_ins && cursor.param == i_param {
			return ray.YELLOW
		}

		if char_buffer.len != 0 {
			return ray.RED
		}

		return ray.LIGHTGRAY
	}

	pass_through_cache :: proc(i_ins: u32, i_param: u32, cstr: cstring) -> cstring {
		char_buffer := &main_cpu.editing_buffers.data[i_ins * 4 + i_param]
		if char_buffer.len == 0 {
			if cursor.ins == i_ins && cursor.param == i_param {
				set_buffer(i_ins, i_param, string(cstr))
			}
			return cstr
		}
		return strings.clone_to_cstring(string(sl_slice(char_buffer)))
	}

	draw_text :: proc(cstr: cstring, x, y: i32, i_ins, i_param: u32) {
		v: ray.Vector2
		v.x = f32(x + config.editor_param_margin * i32(i_param))
		v.y = f32(y)

		//ray.DrawTextEx(config.editor_font, cstr, v,
		//	f32(editor_font_size), 1.0, get_color(i_ins, i_param))

		new_cstr := pass_through_cache(i_ins, i_param, cstr)
		ray.DrawText(new_cstr, i32(v.x), i32(v.y), editor_font_size, get_color(i_ins, i_param))

		if cursor.ins == i_ins && cursor.param == i_param {
			first_half    := strings.clone_to_cstring(string(new_cstr)[:cursor.char])
			cursor_offset := ray.MeasureText(first_half, config.editor_font_size)
			cursor_x      := i32(v.x) + cursor_offset
			ray.DrawLine(cursor_x, y, cursor_x, y + config.editor_font_size, ray.LIGHTGRAY)
		} 
	}

	i_ins: u32 = 0
	x: i32 = editor_left_padding
	y: i32 = 0
	line_number_x : i32 = editor_left_padding / 2 //TODO: gambiarra
	for ins in sl_slice(&main_cpu.instructions) {
		ray.DrawText(ray.TextFormat("%d", i_ins), line_number_x, y, editor_font_size, ray.GRAY)

		draw_text(instruction_type_to_str(ins.type), x, y, i_ins, 0)

		switch instruction_param_type_table[ins.type] {
		case .Reg_And_Reg_And_Offset:

			reg1_name := register_type_to_str(Register_Type(ins.p0));
			draw_text(reg1_name, x, y, i_ins, 1)

			reg2_name := register_type_to_str(Register_Type(ins.p1));
			draw_text(reg2_name, x, y, i_ins, 2)

			buffer: [80]byte
			fmt.bprint(buffer[:], ins.p2)
			cstr := strings.clone_to_cstring(string(buffer[:]))
			draw_text(cstr, x, y, i_ins, 3)

		case .Reg_And_Reg_Or_Imediate:

			reg_name := register_type_to_str(Register_Type(ins.p0));
			draw_text(reg_name, x, y, i_ins, 1)

			c := get_color(i_ins, 2)
			if ins.imediate {
				buffer: [80]byte
				strconv.itoa(buffer[:], int(ins.p2))
				cstr := strings.clone_to_cstring(string(buffer[:]))
				draw_text(cstr, x, y, i_ins, 2)
			} else {
				reg2_name := register_type_to_str(Register_Type(ins.p1));
				draw_text(reg2_name, x, y, i_ins, 2)
			}

		case .Reg:
		
			reg_name := register_type_to_str(Register_Type(ins.p0));
			draw_text(reg_name, x, y, i_ins, 1)
		
		case .Reg_Or_Imediate:

			c := get_color(i_ins, 1)
			if ins.imediate {
				buffer: [80]byte
				strconv.itoa(buffer[:], int(ins.p2))
				cstr := strings.clone_to_cstring(string(buffer[:]))
				draw_text(cstr, x, y, i_ins, 1)
			} else {
				reg_name := register_type_to_str(Register_Type(ins.p0));
				draw_text(reg_name, x, y, i_ins, 1)
			}
		
		case .Nothing:
		}

		y += editor_line_height
		i_ins += 1
	}
}

process_input :: proc() {
	update_char_cursor :: proc() {
		cstr   := lookup_buffer(cursor.ins, cursor.param)
		length := u32(len(cstr))
		if cursor.char >= length do cursor.char = length
	}

	update_param_cursor :: proc() {
		param_qnt := get_instruction_param_qnt(main_cpu.instructions.data[cursor.ins].type)
		if cursor.param >= u32(param_qnt) do cursor.param = u32(param_qnt)
	}

	if ray.IsKeyPressed(.UP) && cursor.ins > 0 {
		cursor.ins -= 1
        check_line(cursor.ins + 1)
		update_param_cursor()
		update_char_cursor()
	}
		
	if ray.IsKeyPressed(.DOWN) && cursor.ins < (main_cpu.instructions.len - 1) {
		cursor.ins += 1
        check_line(cursor.ins - 1)
		update_param_cursor()
		update_char_cursor()
	}

	left  := ray.IsKeyPressed(.LEFT)
	right := ray.IsKeyPressed(.RIGHT)
	if ray.IsKeyDown(.LEFT_CONTROL) {
		if left && cursor.param > 0 {
			cursor.param -= 1
			update_char_cursor()
		}

		param_qnt := get_instruction_param_qnt(main_cpu.instructions.data[cursor.ins].type)
		if right && cursor.param < u32(param_qnt) {
			cursor.param += 1
			update_char_cursor()
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

			cstr      := lookup_buffer(cursor.ins, cursor.param)
			length    := u32(len(cstr))
			param_qnt := get_instruction_param_qnt(main_cpu.instructions.data[cursor.ins].type)
			if cursor.char > length {
				if cursor.param < u32(param_qnt) {
					cursor.param += 1
					cursor.char = 0
				} else {
					cursor.char = length
				}
			}
		}
	}

	if ray.IsKeyPressed(.ENTER) {
		cursor.ins += 1
		check_line(cursor.ins - 1)
		sl_insert(&main_cpu.instructions, Instruction{ type=.Nop }, u32(cursor.ins))
		update_param_cursor()
		update_char_cursor()
	}
		
	if ray.IsKeyPressed(.DELETE) {
		sl_remove(&main_cpu.instructions, u32(cursor.ins))
	}

	char_buffer := &main_cpu.editing_buffers.data[cursor.ins * 4 + cursor.param]

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
	sl_push(&main_cpu.instructions, Instruction{ type=.Nop })
	sl_push(&main_cpu.instructions, Instruction{ type=.Add })
	sl_push(&main_cpu.instructions, Instruction{ type=.Sub })
	sl_push(&main_cpu.instructions, Instruction{ type=.Nop })
	sl_push(&main_cpu.instructions, Instruction{ type=.Jmp, imediate=true , p2=3000 })
	sl_push(&main_cpu.instructions, Instruction{ type=.Jmp, imediate=false, p0=u8(Register_Type.r0) })
	sl_push(&main_cpu.instructions, Instruction{ type=.Load })

	for i := 0; i < GPU_BUFFER_H * GPU_BUFFER_W; i += 1 {
		main_cpu.gpu.buffer[i] = u16(i)
	}

	set_buffer(0, 0, "nopis")
	set_buffer(1, 0, "adding")

	config.editor_font = ray.GetFontDefault()
    ray.InitWindow(config.window_width, config.window_height, "PISC Experience");

    ray.SetTargetFPS(60);

    for !ray.WindowShouldClose() {
        ray.BeginDrawing()

        ray.ClearBackground(ray.BLACK)

        check_line(cursor.ins)

        process_input()

        draw_editor()

        draw_memory()

        draw_status()

        draw_video_buffer()

        ray.EndDrawing()
    }

    ray.CloseWindow()
}
