package pisc

import "core:fmt"
import ray "vendor:raylib"

process_editor_input_from_comment :: proc() {
	fmt.println(cursor)

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

	if ray.IsKeyPressed(.UP)  do move_up()
		
	if ray.IsKeyPressed(.DOWN) do move_down()

	left  := ray.IsKeyPressed(.LEFT)
	right := ray.IsKeyPressed(.RIGHT)
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

	if ray.IsKeyPressed(.ENTER) {
		push_comment("-", main_cpu.comments.data[cursor.comment].line, int(cursor.comment) + 1)
		cursor.comment += 1
		cursor.char = 1
		unsaved = true	
	}
		
	if ray.IsKeyPressed(.DELETE) {
		sl_remove(&main_cpu.comments, cursor.comment)
		unsaved = true
	}

	if ray.IsKeyPressed(.BACKSPACE) {
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
				
				it_a     := &main_cpu.comments.data[cursor.comment]
				buffer_a := &it_a.content

				it_b     := &main_cpu.comments.data[cursor.comment + 1]
				buffer_b := &it_b.content

				it_a.have_next = true

				if buffer_a.len < 64 do sl_push(buffer_a, ' ')

				for buffer_a.len < 64 {
					if buffer_b.len > 0 {
						sl_push(buffer_a, sl_remove(buffer_b, 0))
					} else {
						it_a.have_next = false
						sl_clear(buffer_b)
						sl_remove(&main_cpu.comments, cursor.comment + 1)
						break
					}
				}

				cursor.char = buffer_a.len
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