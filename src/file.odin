package pisc

import "core:os"
import "core:fmt"



to_bytes :: proc(v: $T) -> [size_of(T)]byte {
    return transmute([size_of(T)]byte)v
}

load_cpu_from_file :: proc(cpu: ^CPU, file_name: string) -> (success: bool) {
fmt.println("load")
	mem_append :: proc(src : $T, dst : []byte, p : ^int) {
		src_in_bytes := to_bytes(src)
		for i := 0; i < size_of(T); i += 1 {
			dst[i + p^] = src_in_bytes[i]
		}
		p^ += size_of(T)
	}

	src: []byte

	src, success = os.read_entire_file(file_name)
	if !success do return

	p := 0

	{
		i   := 0
		dst := ([^]byte)(&cpu.editing_buffers)
		for ; p < size_of(cpu.editing_buffers); p += 1 {
			dst[i] = src[p]
			i += 1
		}
	}

	{
		i   := 0
		dst := ([^]byte)(&cpu.labels)
		for ; p < size_of(cpu.labels); p += 1 {
			dst[i] = src[p]
			i += 1
		}
	}

	success = true
	return
}

dump_cpu_to_file :: proc(cpu: ^CPU, file_name: string) {
fmt.println("dump")
	mem_append :: proc(src : $T, dst : []byte, p : ^int) {
		src_in_bytes := to_bytes(src)
		for i := 0; i < size_of(T); i += 1 {
			dst[i + p^] = src_in_bytes[i]
		}
		p^ += size_of(T)
	}

	file_size := size_of(cpu.editing_buffers) + size_of(cpu.labels)

	output := make([]byte, file_size)

	p := 0

	mem_append(cpu.editing_buffers, output, &p)
	mem_append(cpu.labels         , output, &p)

	os.write_entire_file(file_name, output)
}