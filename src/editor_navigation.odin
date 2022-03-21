package pisc

import "core:fmt"
import ray "vendor:raylib"

update_char_cursor :: proc() {
	cstr: cstring
	length: u32

	switch cursor.place {
	case .Ins:     cstr = lookup_buffer(cursor.ins, cursor.param)
	case .Label:   cstr = lookup_label(cursor.label)
	case .Comment: cstr = lookup_comment(cursor.comment)
	}
	length = u32(len(cstr))

	//TODO: Look how to do it with comments

	if editor_expected_cursor_char >= length {
		cursor.char = length
	} else {
		cursor.char = editor_expected_cursor_char
	}		
}

add_ins :: proc(_idx: u32) {
	clean_buffer: Static_List(byte, 16)

	idx := _idx * 4

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

	comments := sl_slice(&main_cpu.comments)
	for i := 0; i < len(comments); i += 1 {
		comment := &comments[i]

		if comment.line > u16(cursor.ins) {
			comment.line += 1
		}
	}
	
	cursor.param = 0

	unsaved = true	
}

process_editor_input_from_comment :: proc() {
	move_up :: proc() {
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

		if !search_comment_above_comment() && !search_label_above_comment() {
			ins := main_cpu.comments.data[cursor.comment].line
			if ins > 0 {
				cursor.ins   = u32(ins - 1)
				cursor.place = .Ins
			}
		}

		update_char_cursor()
	}

	move_down :: proc() {
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

		if !search_comment_below_comment() {
			ins := main_cpu.comments.data[cursor.comment].line
			cursor.ins   = u32(ins)
			cursor.place = .Ins
		}

		update_char_cursor()
	}

	if editor_nav_keys.up   do move_up()
	if editor_nav_keys.down do move_down()

	left  := editor_nav_keys.left
	right := editor_nav_keys.right
	l     := ray.IsKeyPressed(.L)
	if ray.IsKeyDown(.LEFT_CONTROL) {
		if l {
			push_label("", u16(cursor.ins))
			move_up()
			unsaved = true
		}
	} else {
		if left {
			if cursor.char == 0 {
				if cursor.comment > 0 {
					it := &main_cpu.comments.data[cursor.comment - 1]
					if it.have_next {
						cursor.char = 64
						cursor.comment -= 1
					} else {
						move_up()
					}
				}
			} else {
				cursor.char -= 1
			}
		}
		if right {
			cursor.char += 1

			line   := main_cpu.comments.data[cursor.comment].line
			cstr   := lookup_comment(cursor.comment)
			length := u32(len(cstr))
			if cursor.char > length { 
				if cursor.comment < (main_cpu.comments.len - 1) && 
				main_cpu.comments.data[cursor.comment + 1].line == line {
					cursor.comment += 1
					cursor.char = 1
				} else {
					cursor.char = length
				}
			}
		}
	}

	push_comment_below :: proc() {
		push_comment("", main_cpu.comments.data[cursor.comment].line, int(cursor.comment) + 1)
		cursor.comment += 1
		cursor.char = 0
		unsaved = true	
	}

	if editor_nav_keys.enter do push_comment_below()
		
	if ray.IsKeyPressed(.DELETE) {
		sl_remove(&main_cpu.comments, cursor.comment)
		unsaved = true
	}

	if editor_nav_keys.backspace {
		backspace_loop :: proc(comment_idx, char_to_remove_idx: u32) -> (removed: byte, node_deleted := false) {
			it     := &main_cpu.comments.data[comment_idx]
			buffer := &it.content

			if buffer.len > 1 {
				removed = sl_remove(buffer, char_to_remove_idx)

				if it.have_next {
					child_first_char, child_deleted := backspace_loop(comment_idx + 1, 0)
					if child_deleted do it.have_next = false

					sl_push(buffer, child_first_char)
				}
			} else {
				removed = buffer.data[0]
				node_deleted = true

				sl_clear(buffer)
				sl_remove(&main_cpu.comments, comment_idx)
			}

			return
		}

		if cursor.char > 0 {
			cursor.char -= 1

			it     := &main_cpu.comments.data[cursor.comment]
			buffer := &it.content
			if cursor.char == 0 && buffer.len == 1 {
				sl_pop(buffer)
			} else {
				backspace_loop(cursor.comment, cursor.char)
			}
		} else {
			if cursor.comment > 0 &&
			main_cpu.comments.data[cursor.comment].line == main_cpu.comments.data[cursor.comment - 1].line {
				cursor.comment -= 1

				if main_cpu.comments.data[cursor.comment].content.len != 0 {
					it_a     := &main_cpu.comments.data[cursor.comment]
					buffer_a := &it_a.content

					it_b     := &main_cpu.comments.data[cursor.comment + 1]
					buffer_b := &it_b.content

					it_a.have_next = true

					if buffer_a.len < 64 do sl_push(buffer_a, ' ') // check this

					cursor.char = buffer_a.len

					comment_idx := cursor.comment

					for {
						stop := false

						for buffer_a.len < 64 { // make this for all forward nodes
							if buffer_b.len > 0 {
								sl_push(buffer_a, sl_remove(buffer_b, 0))
							} else {
								it_a.have_next = false
								sl_clear(buffer_b)
								sl_remove(&main_cpu.comments, comment_idx + 1)
								stop = true
								break
							}
						}

						if stop do break

						if it_b.have_next {
							comment_idx += 1

							it_a     = &main_cpu.comments.data[comment_idx]
							buffer_a = &it_a.content

							it_b     = &main_cpu.comments.data[comment_idx + 1]
							buffer_b = &it_b.content
						} else {
							break
						}
					}
				} else {
					sl_clear(&main_cpu.comments.data[cursor.comment].content)
					sl_remove(&main_cpu.comments, cursor.comment)
				}
			} else {
				it     := &main_cpu.comments.data[cursor.comment]
				buffer := &it.content
				sl_clear(buffer)
				sl_remove(&main_cpu.comments, cursor.comment)
				cursor.char = 1
				move_down()
			}
		}
	}

	for key := ray.GetCharPressed(); key > 0; key = ray.GetCharPressed() {
	    if !(key >= 32 && key <= 125) do continue

	    if key == '#' {
	    	push_comment_below()
	    	continue
	    }
	    
		c           := byte(key)
		char_idx    := cursor.char
		comment_idx := cursor.comment

		if char_idx < 64 {
			cursor.char += 1
		} else {
			cursor.char = 1
			cursor.comment += 1
		}

		for {
			it     := &main_cpu.comments.data[comment_idx]
			buffer := &it.content

			if char_idx == 64 {
				char_idx = 0
				if !it.have_next {
					it.have_next = true
					push_comment(string([]byte{c}), u16(cursor.ins), int(comment_idx) + 1)
					break
				}
			} else if buffer.len >= 64 {
				old_c := c
				c = buffer.data[63]

				for i := 63; i > int(char_idx); i -= 1 do buffer.data[i] = buffer.data[i - 1]
				buffer.data[char_idx] = old_c

				if !it.have_next {
					it.have_next = true
					push_comment(string([]byte{c}), u16(cursor.ins), int(comment_idx) + 1)
					break
				}

				char_idx = 0 
			} else {
				sl_insert(buffer, c, char_idx)	    				
				unsaved = true
				break
			}
			comment_idx += 1
		}
	}
}

process_editor_input_from_label :: proc() {
	move_up :: proc() {
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

		update_char_cursor()
	}

	move_down :: proc() {
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

		if !search_label_below_label() && !search_comment_below_label() {
			actual_label := &main_cpu.labels.data[cursor.label]
			if u32(actual_label.line) < (main_cpu.editing_buffers.len/4) {
				cursor.ins   = u32(actual_label.line)
				cursor.place = .Ins
			}
		}

		update_char_cursor()
	}

	delete_line :: proc() {
		cursor.ins   = u32(main_cpu.labels.data[cursor.label].line) // make jump to top label
		cursor.place = .Ins
		sl_remove(&main_cpu.labels, u32(cursor.label))

		unsaved = true
	}

	if editor_nav_keys.up   do move_up()
	if editor_nav_keys.down do move_down()

	if ray.IsKeyDown(.LEFT_CONTROL) {
		if ray.IsKeyPressed(.L) {
			push_label("", u16(cursor.ins))
			move_up()
			unsaved = true
		}
	} else {
		if editor_nav_keys.left && cursor.char > 0 {
			cursor.char -= 1
			editor_expected_cursor_char = cursor.char
		}
		
		if editor_nav_keys.right {
			cursor.char += 1

			cstr   := lookup_label(cursor.label)
			length := u32(len(cstr))
			if cursor.char > length {
				cursor.char = length
			}

			editor_expected_cursor_char = cursor.char
		}
	}

	if editor_nav_keys.enter {
		add_ins(u32(main_cpu.labels.data[cursor.label].line))
		cursor.char  = 0
		cursor.place = .Ins
		cursor.ins   = u32(main_cpu.labels.data[cursor.label].line)
	}
		
	if ray.IsKeyPressed(.DELETE) do delete_line()

	it     := &main_cpu.labels.data[cursor.label]
	buffer := &it.name

	if editor_nav_keys.backspace && cursor.char > 0 {
		sl_remove(buffer, cursor.char - 1)
		cursor.char -= 1
		unsaved = true
	}

	for key := ray.GetCharPressed(); key > 0; key = ray.GetCharPressed() {
	    if !(key >= 32 && key <= 125) do continue

	    if buffer.len < LABEL_NAME_MAX {
	    	sl_insert(buffer, byte(key), cursor.char)
	    	cursor.char += 1
	    	unsaved = true
	    }	    				
	}
}

process_editor_input_from_ins :: proc() {
	/*get_ins_last_filled_param :: proc() -> u32 {
		if main_cpu.editing_buffers.data[cursor.ins * 4 + 1].len == 0 do return 0
		if main_cpu.editing_buffers.data[cursor.ins * 4 + 2].len == 0 do return 1
		if main_cpu.editing_buffers.data[cursor.ins * 4 + 3].len == 0 do return 2
		return 3
	} */

	move_up :: proc() {
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

		if !search_comment_above_ins() && !search_label_above_ins() {
			if cursor.ins > 0 do cursor.ins -= 1
			/*
			ins_above_last_filled_param := get_ins_last_filled_param()
			if cursor.param >= ins_above_last_filled_param do cursor.param = ins_above_last_filled_param
			*/
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

		if !search_comment_below_ins() && !search_label_below_ins() {
			length := main_cpu.editing_buffers.len / 4
			if cursor.ins < length - 1 do cursor.ins += 1
		}

		update_char_cursor()
	}

	delete_line :: proc() {
		idx := u32(cursor.ins)*4
		sl_remove(&main_cpu.editing_buffers, idx)
		sl_remove(&main_cpu.editing_buffers, idx)
		sl_remove(&main_cpu.editing_buffers, idx)
		sl_remove(&main_cpu.editing_buffers, idx)

		labels := sl_slice(&main_cpu.labels)
		for i := 0; i < len(labels); i += 1 {
			label := &labels[i]

			if label.line > u16(cursor.ins) do label.line -= 1
		}

		comments := sl_slice(&main_cpu.comments)
		for i := 0; i < len(comments); i += 1 {
			comment := &comments[i]

			if comment.line > u16(cursor.ins) do comment.line -= 1
		}

		if cursor.ins >= (main_cpu.editing_buffers.len/4) do cursor.ins = main_cpu.editing_buffers.len/4 - 1

		unsaved = true
	}

	if editor_nav_keys.up   do move_up()
	if editor_nav_keys.down do move_down()

	ctrl_left :: proc() {
		if cursor.char > 0 {
			cursor.char = 0
		} else {
			if cursor.param > 0 {
				cursor.param -= 1
				update_char_cursor()
			}
		}
	}

	ctrl_right :: proc() {
		buffer_length := u32(len(lookup_buffer(cursor.ins, cursor.param)))
		if cursor.char < buffer_length {
			cursor.char = buffer_length
		} else {
			if cursor.param < 3 {
				cursor.param += 1
				update_char_cursor()
			}
		}
	}

	if ray.IsKeyDown(.LEFT_CONTROL) {
		if editor_nav_keys.left  do ctrl_left()
		if editor_nav_keys.right do ctrl_right()

		if ray.IsKeyPressed(.L) {
			push_label("", u16(cursor.ins))
			move_up()
			unsaved = true
		}
	} else {
		if editor_nav_keys.left {
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

			editor_expected_cursor_char = cursor.char
		}

		if editor_nav_keys.right {
			cursor.char += 1

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

			editor_expected_cursor_char = cursor.char
		}
	}

	if editor_nav_keys.enter {
		add_ins(u32(cursor.ins + 1))
		move_down()
	}
		
	if ray.IsKeyPressed(.DELETE) do delete_line()


	buffer := &main_cpu.editing_buffers.data[cursor.ins * 4 + cursor.param]

	if editor_nav_keys.backspace {
		if cursor.char > 0 {
			sl_remove(buffer, cursor.char - 1)
			cursor.char -= 1
			unsaved = true
		} else if cursor.param > 0 {
			cursor.param -= 1
			update_char_cursor()
		}
	}

	for key := ray.GetCharPressed(); key > 0; key = ray.GetCharPressed() {
	    if !(key >= 32 && key <= 125) do continue

	    if buffer.len < EDITING_BUFFER_MAX {
	    	if key == ' ' && cursor.param < 3 {
				cursor.param += 1
				update_char_cursor()
			} else {
				if key != '#' {
					sl_insert(buffer, byte(key), cursor.char)
					cursor.char += 1
					unsaved = true
				} else {
					push_comment("", u16(cursor.ins), -1)
					move_up()
				}
			}
	    }	    				
	}
}

process_editor_input :: proc() {
	switch cursor.place {
	case .Ins:     process_editor_input_from_ins()
	case .Label:   process_editor_input_from_label()
	case .Comment: process_editor_input_from_comment()
	}
}