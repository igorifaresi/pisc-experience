package pisc

import "core:fmt"
import ray "vendor:raylib"

Gamepad_Entries :: enum u16 {
	Up             = 1,
	Down           = 1 << 1,
	Left           = 1 << 2,
	Right          = 1 << 3,
	A              = 1 << 4,
	B              = 1 << 5,
	X              = 1 << 6,
	Y              = 1 << 7,
	L              = 1 << 8,
	R              = 1 << 9,
	Start          = 1 << 10,
	Select         = 1 << 11,
	MouseLeft      = 1 << 12,
	MouseRight     = 1 << 13,
	MouseWheelUp   = 1 << 14,
	MouseWheelDown = 1 << 15,
}

Instruction_Type :: enum u8 {
	Add,    Sub,    Mul, Div,
	Or,     And,    Not, Xor,
	Load,   Store,  Move,
	Sl,     Sr,
	Ceq,    Cgt,    Clt,
	Jmp,    Jt,     Jf,  Cmp,
	Vpoke,  Vpeek,  Vswap,
	Mpeekx, Mpeeky,
	Call,   Ret,    Nop,
}

Instruction_Param_Type :: enum u8 {
	Reg_And_Reg_And_Offset,
	Reg_And_Reg_Or_Imediate,
	Reg,
	Reg_Or_Imediate,
	Nothing,
}

instruction_param_type_table := map[Instruction_Type]Instruction_Param_Type {
	.Add   = .Reg_And_Reg_Or_Imediate, .Sub = .Reg_And_Reg_Or_Imediate,
	.Mul = .Reg_And_Reg_Or_Imediate, .Div = .Reg_And_Reg_Or_Imediate,

	.Or = .Reg_And_Reg_Or_Imediate, .And = .Reg_And_Reg_Or_Imediate, .Not = .Reg, .Xor = .Reg_And_Reg_Or_Imediate,
	.Load  = .Reg_And_Reg_And_Offset, .Store = .Reg_And_Reg_And_Offset, .Move = .Reg_And_Reg_Or_Imediate,
	
	.Sl = .Reg_And_Reg_Or_Imediate, .Sr = .Reg_And_Reg_Or_Imediate,
	
	.Ceq = .Reg_And_Reg_Or_Imediate, .Cgt = .Reg_And_Reg_Or_Imediate, .Clt = .Reg_And_Reg_Or_Imediate,
	
	.Jmp = .Reg_Or_Imediate, .Jt = .Reg_Or_Imediate, .Jf = .Reg_Or_Imediate, .Cmp = .Reg_And_Reg_Or_Imediate,
	
	.Vpoke = .Reg, .Vpeek = .Reg, .Vswap = .Nothing,

	.Mpeekx = .Reg, .Mpeeky = .Reg,
	
	.Call = .Reg_Or_Imediate, .Ret = .Nothing, .Nop = .Nothing,
}

get_instruction_param_qnt :: proc(ins: Instruction_Type) -> int {
	switch instruction_param_type_table[ins] {
	case .Reg_And_Reg_And_Offset:  return 3
	case .Reg_And_Reg_Or_Imediate: return 2
	case .Reg:                     return 1
	case .Reg_Or_Imediate:         return 1
	case .Nothing:
	}

	return 0
}

mnemonics_table := map[cstring]Instruction_Type {
	"add"    = .Add   , "sub"    = .Sub   , "mul"   = .Mul , "div" = .Div,
	"or"     = .Or    , "and"    = .And   , "not"   = .Not , "xor" = .Xor,
	"load"   = .Load  , "store"  = .Store , "move"  = .Move,
	"sl"     = .Sl    , "sr"     = .Sr    ,
	"ceq"    = .Ceq   , "cgt"    = .Cgt   , "clt"   = .Clt ,
	"jmp"    = .Jmp   , "jt"     = .Jt    , "jf"    = .Jf, "cmp" = .Cmp,
	"vpoke"  = .Vpoke , "vpeek"  = .Vpeek , "vswap" = .Vswap,
	"mpeekx" = .Mpeekx, "mpeeky" = .Mpeeky,
	"call"   = .Call  , "ret"    = .Ret   , "nop"   = .Nop,
}

instruction_type_to_str :: proc(t: Instruction_Type) -> cstring {
	s: cstring
	for key, v in mnemonics_table {
		if t == v {
			s = key
		}
	}
	return s
}

Register_Type :: enum u8 {
	r0 , r1 , r2 , r3 , r4 , r5 , r6 , r7, // general use
	r8 , r9 , ra , rb , rc , rd , re , rf,
	
	ri0, ri1, ri2, ri3, ri4, ri5, ri6, ri7, // function input
	
	ro0, ro1, // function output
	
	sp , pc, // special
	
	x  , y, // coordinates

	gp, // input
}

registers_table := map[cstring]Register_Type {
	"r0" = .r0, "r1" = .r1, "r2" = .r2, "r3" = .r3, "r4" = .r4, "r5" = .r5, "r6" = .r6, "r7" = .r7,
	"r8" = .r8, "r9" = .r9, "ra" = .ra, "rb" = .rb, "rc" = .rc, "rd" = .rd, "re" = .re, "rf" = .rf,

	"ri0" = .ri0, "ri1" = .ri1, "ri2" = .ri2, "ri3" = .ri3, "ri4" = .ri4, "ri5" = .ri5, "ri6" = .ri6, "ri7" = .ri7,

	"ro0" = .ro0, "ro1" = .ro1,

	"sp" = .sp, "pc" = .pc,

	"x" = .x, "y" = .y,

	"gp" = .gp,
}

register_type_to_str :: proc(t: Register_Type) -> cstring {
	s: cstring
	for key, v in registers_table {
		if t == v {
			s = key
		}
	}
	return s
}

Instruction :: struct {
	type:              Instruction_Type,
	imediate:          bool,
	imediate_as_label: bool,
	p0, p1:            u8,
	p2:                i16,
}

Label :: struct {
	name: Static_List(byte, 16),
	line: u16,
}

Comment :: struct {
	content: Static_List(byte, 64),
	line: u16,
}

MAX_INSTRUCTIONS :: 1024 * 16

CPU :: struct {
	reg_table: [31]i16,

	pc: u16,
	call_stack: Static_List(u16, 256),

	instructions: Static_List(Instruction, MAX_INSTRUCTIONS),
	editing_buffers: Static_List(Static_List(byte, 16), MAX_INSTRUCTIONS * 4),
	labels: Static_List(Label, 4096),
	comments: Static_List(Comment, 4096),
	mem: [1024 * 64]byte,

	cmp_flag: bool,

	gpu: GPU,
}

cpu_reset :: proc(using cpu: ^CPU) {
	pc = 0

	for i := 0; i < len(reg_table); i += 1 {
		reg_table = 0
	}

	for i := 0; i < len(mem); i += 1 {
		mem = 0
	}

	sl_clear(&call_stack)

	init_gpu(&cpu.gpu)
}

cpu_clock :: proc(using cpu: ^CPU) -> (stop := false) {
	pisc_color_to_rbg :: proc(pisc_color: u16) -> (rgb: ray.Color) {
		rgb.r = u8(((pisc_color       & 0b00000000_00011111) * 255) / 31)
		rgb.g = u8(((pisc_color >> 5  & 0b00000000_00011111) * 255) / 31)
		rgb.b = u8(((pisc_color >> 10 & 0b00000000_00011111) * 255) / 31) 
		rgb.a = 255
		return
	}

	if u32(pc) >= instructions.len do return

//fmt.println("pc = ", pc)
	inst := instructions.data[pc]

	pc += 1

	b := inst.imediate ? inst.p2 : reg_table[inst.p1]

	switch inst.type {

	case .Add: reg_table[inst.p0] += b
	case .Sub: reg_table[inst.p0] -= b
	case .Mul: reg_table[inst.p0] *= b
	case .Div: reg_table[inst.p0] /= b
	case .Or:  reg_table[inst.p0] |= b
	case .And: reg_table[inst.p0] &= b
	case .Xor: reg_table[inst.p0] &~= b // Note: Maybe this is XOR???
	case .Not: reg_table[inst.p0] ~= reg_table[inst.p0]

	case .Load:
		addr := reg_table[inst.p1] + inst.p2
		mem_l := u16(mem[addr])
		mem_h := u16(mem[addr + 1]) << 8
		reg_table[inst.p0] = transmute(i16)(mem_l | mem_h)

	case .Store:
		addr  := reg_table[inst.p1] + inst.p2
		value := transmute(u16)(reg_table[inst.p0])
		mem[addr]     = cast(byte)(value & 0xff)
		mem[addr + 1] = cast(byte)(value >> 8)

	case .Move: reg_table[inst.p0] = b
	case .Sl:   reg_table[inst.p0] <<= cast(u8)b
	case .Sr:   reg_table[inst.p0] >>= cast(u8)b
	case .Ceq:  cmp_flag = reg_table[inst.p0] == b
	case .Cgt:  cmp_flag = reg_table[inst.p0] > b
	case .Clt:  cmp_flag = reg_table[inst.p0] < b
	case .Jmp:  pc = labels.data[inst.p2].line

	case .Jt:
		if cmp_flag {
			pc = labels.data[inst.p2].line
		}

	case .Jf:
		if !cmp_flag {
			pc = labels.data[inst.p2].line
		}

	case .Cmp:
		cmp_flag = reg_table[inst.p0] == b

	case .Vpoke:
		x := i32(reg_table[int(Register_Type.x)])
		y := i32(reg_table[int(Register_Type.y)])	

		if x >= 0 && x < GPU_BUFFER_W && y >= 0 && y < GPU_BUFFER_H {
			color_pisc := transmute(u16)(reg_table[inst.p0])
			color_rgb  := pisc_color_to_rbg(color_pisc)
			ray.ImageDrawPixel(&cpu.gpu.buffer, x, y, color_rgb)
		}

	case .Vpeek:
		//addr := reg_table[inst.p1] + inst.p2
		//reg_table[inst.p0] = transmute(i16)(gpu.buffer[addr])

	case .Mpeekx:

	case .Mpeeky:

	case .Call:
		sl_push(&call_stack, pc)
		pc = labels.data[inst.p2].line

	case .Ret:
		pc = sl_pop(&call_stack)

	case .Vswap:
		stop = true
		return
	case .Nop:
	} // end switch

	return
}

