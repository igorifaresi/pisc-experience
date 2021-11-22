package pisc

import ray "vendor:raylib"

Input_Entry_Type :: enum {
	Null = 0,
	Keyboard_Key,
	Gamepad_Axis,
	Gamepad_Button,
}

Keyboard_Key_Entry :: struct {
	key: ray.KeyboardKey,
}

Gamepad_Axis_Entry :: struct {
	axis_number: int,
	positive:    bool,
	death_zone:  f32,
}

Gamepad_Button_Entry :: struct {
	button: ray.GamepadButton,
}

Input_Entry :: struct {
	type: Input_Entry_Type, 
	using value: struct #raw_union {
		kb_key:  Keyboard_Key_Entry,
		gp_axis: Gamepad_Axis_Entry,
		gp_btn:  Gamepad_Button_Entry,
	},
}

Input_Table :: struct {
	up:               [2]Input_Entry,
	down:             [2]Input_Entry,
	left:             [2]Input_Entry,
	right:            [2]Input_Entry,
	a:                [2]Input_Entry,
	b:                [2]Input_Entry,
	x:                [2]Input_Entry,
	y:                [2]Input_Entry,
	l:                [2]Input_Entry,
	r:                [2]Input_Entry,
	start:            [2]Input_Entry,
	select:           [2]Input_Entry,
	mouse_left:       [2]Input_Entry,
	mouse_right:      [2]Input_Entry,
	mouse_wheel_up:   [2]Input_Entry,
	mouse_wheel_down: [2]Input_Entry,
}

check_input_entry :: proc(entries: [2]Input_Entry) -> (pressed := false) {
	for i := 0; i < 2; i += 1 {
		entry := entries[i]

		switch entry.type {

		case .Keyboard_Key:
			pressed = ray.IsKeyDown(entry.kb_key.key)

		case .Gamepad_Button:
			pressed = ray.IsGamepadButtonDown(0, entry.gp_btn.button)

		case .Gamepad_Axis:
			value := ray.GetGamepadAxisMovement(0, ray.GamepadAxis(entry.gp_axis.axis_number))
			if (value > 0 && value >  entry.gp_axis.death_zone) ||
			(value < 0 && value < -entry.gp_axis.death_zone) {
				if entry.gp_axis.positive {
					if value > 0 { pressed = true  } else { pressed = false }
				} else {
					if value > 0 { pressed = false } else { pressed = true  }	
				}
			}

		case .Null:
			pressed = false

		}

		if pressed do break
	}

	return
}

check_input_table :: proc(table: ^Input_Table) -> (gp_value: u16) {
	if check_input_entry(table.up)    do gp_value |= u16(Gamepad_Entries.Up)
	if check_input_entry(table.down)  do gp_value |= u16(Gamepad_Entries.Down)
	if check_input_entry(table.left)  do gp_value |= u16(Gamepad_Entries.Left)
	if check_input_entry(table.right) do gp_value |= u16(Gamepad_Entries.Right)

	if check_input_entry(table.a) do gp_value |= u16(Gamepad_Entries.A)
	if check_input_entry(table.b) do gp_value |= u16(Gamepad_Entries.B)
	if check_input_entry(table.x) do gp_value |= u16(Gamepad_Entries.X)
	if check_input_entry(table.y) do gp_value |= u16(Gamepad_Entries.Y)

	if check_input_entry(table.l)      do gp_value |= u16(Gamepad_Entries.L)
	if check_input_entry(table.r)      do gp_value |= u16(Gamepad_Entries.R)
	if check_input_entry(table.start)  do gp_value |= u16(Gamepad_Entries.Start)
	if check_input_entry(table.select) do gp_value |= u16(Gamepad_Entries.Select)

	if check_input_entry(table.mouse_left)       do gp_value |= u16(Gamepad_Entries.MouseLeft)
	if check_input_entry(table.mouse_right)      do gp_value |= u16(Gamepad_Entries.MouseRight)
	if check_input_entry(table.mouse_wheel_up)   do gp_value |= u16(Gamepad_Entries.MouseWheelUp)
	if check_input_entry(table.mouse_wheel_down) do gp_value |= u16(Gamepad_Entries.MouseWheelDown)

	return
}