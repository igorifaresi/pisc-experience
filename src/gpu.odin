package pisc

GPU_BUFFER_W :: 480
GPU_BUFFER_H :: 270

GPU :: struct {
	buffer: [GPU_BUFFER_W * GPU_BUFFER_H]u16,
}