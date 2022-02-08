package pisc

import "core:fmt"
import ray "vendor:raylib"

process_editor_input_from_comment :: proc() {
	update_char_cursor :: proc() {
		cstr: cstring
		length: u32

		switch cursor.place {
 		case .Ins:     cstr = lookup_buffer(cursor.ins, cursor.param)
		case .Label:   cstr = lookup_label(cursor.label)
		case .Comment: cstr = lookup_comment(cursor.comment)
		}
		length = u32(len(cstr))

		if cursor.char >= length do cursor.char = length		
	}

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

	if editor_nav_keys.enter {
		push_comment("-", main_cpu.comments.data[cursor.comment].line, int(cursor.comment) + 1)
		cursor.comment += 1
		cursor.char = 1
		unsaved = true	
	}
		
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
	update_char_cursor :: proc() {
		cstr: cstring
		length: u32

		switch cursor.place {
 		case .Ins:     cstr = lookup_buffer(cursor.ins, cursor.param)
		case .Label:   cstr = lookup_label(cursor.label)
		case .Comment: cstr = lookup_comment(cursor.comment)
		}
		length = u32(len(cstr))

		if cursor.char >= length do cursor.char = length		
	}

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

	add_line :: proc() {
		clean_buffer: Static_List(byte, 16)

		idx: u32 
		if cursor.place == .Ins {
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

		unsaved = true	
	}

	delete_line :: proc() {
		cursor.ins   = u32(main_cpu.labels.data[cursor.label].line)
		cursor.place = .Ins
		sl_remove(&main_cpu.labels, u32(cursor.label))

		unsaved = true
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
			unsaved = true
		}
	} else {
		if left {
			if cursor.char > 0 do cursor.char -= 1
		}
		if right {
			cursor.char += 1

			cstr   := lookup_label(cursor.label)
			length := u32(len(cstr))
			if cursor.char > length {
				cursor.char = length
			}
		}
	}

	if ray.IsKeyPressed(.ENTER) do add_line()
		
	if ray.IsKeyPressed(.DELETE) do delete_line()

	char_buffer: ^Static_List(byte, 16)
	char_buffer_comment: ^Static_List(byte, 64)

	switch cursor.place {
	case .Ins:
		char_buffer = &main_cpu.editing_buffers.data[cursor.ins * 4 + cursor.param]
	case .Label:
		char_buffer = &main_cpu.labels.data[cursor.label].name
	case .Comment:
		char_buffer_comment = &main_cpu.comments.data[cursor.comment].content
	}

	if ray.IsKeyPressed(.BACKSPACE) {
		if cursor.char > 0 {
			if cursor.place != .Comment {
				sl_remove(char_buffer, cursor.char - 1)
			} else {
				sl_remove(char_buffer_comment, cursor.char - 1)
			}
			cursor.char -= 1
			unsaved = true
		} else if cursor.param > 0 {
			cursor.param -= 1
			update_char_cursor()
		}
	}

	for key := ray.GetCharPressed(); key > 0; key = ray.GetCharPressed() {
	    if !(key >= 32 && key <= 125) do continue
	    
	    it     := &main_cpu.labels.data[cursor.label]
		buffer := &it.name

	    //sl_insert(buffer, c, char_idx)	    				
	}
}