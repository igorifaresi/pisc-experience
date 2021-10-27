package pisc

import "core:fmt"
import "core:strconv"
import "core:strings"
import ray "vendor:raylib"

Config :: struct {
	window_width:        i32,
	window_height:       i32,
	font_size:           i32,
	editor_line_height:  i32,
	editor_top_padding:  i32,
	editor_left_padding: i32,
	editor_param_margin: i32,
}

Cursor :: struct {
	ins:   u32,
	param: u32,
}

main_cpu: CPU
config := Config{
	window_width=800,
	window_height=450,
	font_size=20,
	editor_line_height=20,
	editor_top_padding=64,
	editor_left_padding=64,
	editor_param_margin=64,
}
cursor: Cursor

draw_ui :: proc() {
	using config

	get_color :: proc(i_ins: u32, i_param: u32) -> ray.Color {
		if cursor.ins == i_ins && cursor.param == i_param {
			return ray.YELLOW
		}
		return ray.LIGHTGRAY
	}

	v1: ray.Vector2
	v2: ray.Vector2

	ray.DrawLineEx(v1, v2, 2.0, ray.WHITE)

	i_ins: u32 = 0
	x: i32 = editor_left_padding
	y: i32 = editor_top_padding
	for ins in sl_slice(&main_cpu.instructions) {
		ray.DrawText(instruction_type_to_str(ins.type), x, y, font_size, get_color(i_ins, 0))

		switch instruction_param_type_table[ins.type] {
		case .Reg_And_Reg_And_Offset:

			reg1_name := register_type_to_str(Register_Type(ins.p0));
			ray.DrawText(reg1_name, x + editor_param_margin, y, font_size, get_color(i_ins, 1))

			reg2_name := register_type_to_str(Register_Type(ins.p1));
			ray.DrawText(reg2_name, x + editor_param_margin*2, y, font_size, get_color(i_ins, 2))

			buffer: [80]byte
			fmt.bprint(buffer[:], "[", ins.p2, "]")
			cstr := strings.clone_to_cstring(string(buffer[:]))
			ray.DrawText(cstr, x + editor_param_margin*3, y, font_size, get_color(i_ins, 3))

		case .Reg_And_Reg_Or_Imediate:

			reg_name := register_type_to_str(Register_Type(ins.p0));
			ray.DrawText(reg_name, x + editor_param_margin, y, font_size, get_color(i_ins, 1))

			c := get_color(i_ins, 2)
			if ins.imediate {
				buffer: [80]byte
				strconv.itoa(buffer[:], int(ins.p2))
				cstr := strings.clone_to_cstring(string(buffer[:]))
				ray.DrawText(cstr, x + editor_param_margin*2, y, font_size, c)
			} else {
				reg_name := register_type_to_str(Register_Type(ins.p1));
				ray.DrawText(reg_name, x + editor_param_margin*2, y, font_size, c)
			}

		case .Reg:
		
			reg_name := register_type_to_str(Register_Type(ins.p0));
			ray.DrawText(reg_name, x + editor_param_margin, y, font_size, get_color(i_ins, 1))
		
		case .Reg_Or_Imediate:

			c := get_color(i_ins, 1)
			if ins.imediate {
				buffer: [80]byte
				strconv.itoa(buffer[:], int(ins.p2))
				cstr := strings.clone_to_cstring(string(buffer[:]))
				ray.DrawText(cstr, x + editor_param_margin, y, font_size, c);
			} else {
				reg_name := register_type_to_str(Register_Type(ins.p0));
				ray.DrawText(reg_name, x + editor_param_margin, y, font_size, c);
			}
		
		case .Nothing:
		}

		y += editor_line_height
		i_ins += 1
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

    ray.InitWindow(config.window_width, config.window_height, "PISC Experience");

    ray.SetTargetFPS(60);

    for !ray.WindowShouldClose() {
    	if ray.IsKeyPressed(.UP) && cursor.ins > 0 do cursor.ins -= 1
    		
 		if ray.IsKeyPressed(.DOWN) && cursor.ins < (main_cpu.instructions.len - 1) do cursor.ins += 1

    	if ray.IsKeyDown(.LEFT_CONTROL) {
 			if ray.IsKeyPressed(.LEFT) && cursor.param > 0 do cursor.param -= 1

    		param_qnt := get_instruction_param_qnt(main_cpu.instructions.data[cursor.ins].type)
 			if ray.IsKeyPressed(.RIGHT) && cursor.param < u32(param_qnt) do cursor.param += 1
 		}

 		if ray.IsKeyPressed(.ENTER) {
 			sl_insert(&main_cpu.instructions, Instruction{ type=.Nop }, u32(cursor.ins) + 1)	
 		}
 		
 		if ray.IsKeyPressed(.DELETE) {
  			sl_remove(&main_cpu.instructions, u32(cursor.ins))	
 		}

        ray.BeginDrawing();

        ray.ClearBackground(ray.BLACK);

        draw_ui();

        ray.EndDrawing();
    }

    ray.CloseWindow()
}
