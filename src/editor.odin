package pisc

import "core:fmt"
import ray "vendor:raylib"

Editor_Last_Key_State :: enum {
	Idle,
	First_Press,
	Waiting_For_Auto_Repeat,
	Auto_Repeating_Pressed,
	Auto_Repeating_Cooldown,
}

Editor_Last_Key :: struct {
	state: Editor_Last_Key_State,
	timer: f32,
	key:   ray.KeyboardKey,
	frame_count_of_last_update: int,
}

Editor_Nav_Keys :: struct {
	up:        bool,
	down:      bool,
	left:      bool,
	right:     bool,
	enter:     bool,
	backspace: bool,
}

editor_last_key := Editor_Last_Key{ key=.UP }
editor_nav_keys := Editor_Nav_Keys{}

update_editor_nav_keys :: proc() {
	update_editor_last_key :: proc() {
		using editor_last_key

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
			if timer > 0.03 do state = .Auto_Repeating_Pressed
		}
	}

	check_editor_key :: proc(key: ray.KeyboardKey) -> bool {
		if key != editor_last_key.key || editor_last_key.state == .Idle {
			pressed := ray.IsKeyPressed(key)
			if editor_last_key.state == .Idle && pressed {
				editor_last_key.key   = key
				editor_last_key.state = .First_Press
			}
			return pressed
		}

		return editor_last_key.state == .First_Press || editor_last_key.state == .Auto_Repeating_Pressed
	}

	update_editor_last_key()

	editor_nav_keys.up        = check_editor_key(.UP)
	editor_nav_keys.down      = check_editor_key(.DOWN)
	editor_nav_keys.left      = check_editor_key(.LEFT)
	editor_nav_keys.right     = check_editor_key(.RIGHT)
	editor_nav_keys.enter     = check_editor_key(.ENTER)
	editor_nav_keys.backspace = check_editor_key(.BACKSPACE)
}

push_label :: proc(str: string, line: u16) {
	label: Label
	
	for i := 0; i < len(str); i += 1 {
		sl_push(&label.name, str[i])
	}
	label.line = line

	for i : u32 = 0; i < main_cpu.labels.len; i += 1 {
		if u16(main_cpu.labels.data[i].line) > line {
			sl_insert(&main_cpu.labels, label, i)
			return
		}
	}

	sl_push(&main_cpu.labels, label)
}

push_comment :: proc(str: string, line: u16, pos: int) -> (new_comment_idx: int) {
	comment: Comment
	
	for i := 0; i < len(str); i += 1 {
		sl_push(&comment.content, str[i])
	}
	comment.line = line

	if pos != -1 {
		sl_insert(&main_cpu.comments, comment, u32(pos))
	} else {
		for i : u32 = 0; i < main_cpu.comments.len; i += 1 {
			if u16(main_cpu.comments.data[i].line) > line {
				sl_insert(&main_cpu.comments, comment, i)
				return
			}
		}
		sl_push(&main_cpu.comments, comment)
	}

	return
}