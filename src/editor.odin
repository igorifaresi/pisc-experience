package pisc

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