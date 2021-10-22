package pisc

BUFFER_W :: 480
BUFFER_H :: 270

GPU :: struct {
	buffer: [BUFFER_W * BUFFER_H]u16,
}


show_buffer :: proc(gpu: ^GPU) {
	
}