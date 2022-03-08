package pisc

import ray "vendor:raylib"

// platform nav keys detection

Nav_Last_Key_State :: enum {
	Idle,
	First_Press,
	Waiting_For_Auto_Repeat,
	Auto_Repeating_Pressed,
	Auto_Repeating_Cooldown,
}

Nav_Last_Key :: struct {
	state: Nav_Last_Key_State,
	timer: f32,
	key:   ray.KeyboardKey,
	frame_count_of_last_update: int,
}

update_nav_last_key :: proc(last_key: ^Nav_Last_Key, autorepeat_interval: f32 = 0.3) {
	using last_key

	defer frame_count_of_last_update = frame_count

	if !ray.IsKeyDown(key) || (frame_count - frame_count_of_last_update) > 1 {
		state = .Idle
		return
	}

	switch state {
	case .Idle:
		state = .First_Press
	case .First_Press:
		timer = 0
		state = .Waiting_For_Auto_Repeat
	case .Waiting_For_Auto_Repeat: 
		timer += delta
		if timer > 0.4 do state = .Auto_Repeating_Pressed
	case .Auto_Repeating_Pressed:
		timer = 0
		state = .Auto_Repeating_Cooldown
	case .Auto_Repeating_Cooldown:
		timer += delta
		if timer > autorepeat_interval do state = .Auto_Repeating_Pressed
	}
}

check_nav_key :: proc(last_key: ^Nav_Last_Key, key: ray.KeyboardKey) -> bool {
	if key != last_key.key || last_key.state == .Idle {
		pressed := ray.IsKeyPressed(key)
		if last_key.state == .Idle && pressed {
			last_key.key   = key
			last_key.state = .First_Press
		}
		return pressed
	}

	return last_key.state == .First_Press || last_key.state == .Auto_Repeating_Pressed
}

// "in game" input detection

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