package pisc

import "core:fmt"
import ray "vendor:raylib"

Editor_Nav_Keys :: struct {
	up:        bool,
	down:      bool,
	left:      bool,
	right:     bool,
	enter:     bool,
	backspace: bool,
}

editor_last_nav_key := Nav_Last_Key{ key=.UP }
editor_nav_keys := Editor_Nav_Keys{}
editor_expected_cursor_char: u32 = 0

update_editor_nav_keys :: proc() {
	update_nav_last_key(&editor_last_nav_key)

	editor_nav_keys.up        = check_nav_key(&editor_last_nav_key, .UP)
	editor_nav_keys.down      = check_nav_key(&editor_last_nav_key, .DOWN)
	editor_nav_keys.left      = check_nav_key(&editor_last_nav_key, .LEFT)
	editor_nav_keys.right     = check_nav_key(&editor_last_nav_key, .RIGHT)
	editor_nav_keys.enter     = check_nav_key(&editor_last_nav_key, .ENTER)
	editor_nav_keys.backspace = check_nav_key(&editor_last_nav_key, .BACKSPACE)
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