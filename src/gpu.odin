package pisc

import ray "vendor:raylib"

GPU_BUFFER_W :: 480
GPU_BUFFER_H :: 270

GPU :: struct {
	buffer: ray.Image,
}

init_gpu :: proc(gpu: ^GPU) {
	gpu.buffer = ray.GenImageColor(GPU_BUFFER_W, GPU_BUFFER_H, ray.BLACK)
}