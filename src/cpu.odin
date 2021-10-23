package pisc

Instruction_Type :: enum u8 {
	Add,   Sub,   Mul, Div,
	Or,    And,   Not, Xor,
	Load,  Store, Move,
	Sl,    Sr,
	Ceq,   Cgt,   Clt,
	Jmp,   Jt,    Jf,
	Pokev, Peekv, Swap,
	Call,  Ret,
}

mnemonics_table := map[string]Instruction_Type {
	"add"   = .Add  , "sub"   = .Sub  , "mul"  = .Mul , "div" = .Div,
	"or"    = .Or   , "and"   = .And  , "not"  = .Not , "xor" = .Xor,
	"load"  = .Load , "store" = .Store, "move" = .Move,
	"sl"    = .Sl   , "sr"    = .Sr   ,
	"ceq"   = .Ceq  , "cgt"   = .Cgt  , "clt"  = .Clt ,
	"jmp"   = .Jmp  , "jt"    = .Jt   , "jf"   = .Jf  ,
	"pokev" = .Pokev, "peekv" = .Peekv, "swap" = .Swap,
	"call"  = .Call , "ret"   = .Ret  ,  
}

Register_Type :: enum u8 {
	r0 , r1 , r2 , r3 , r4 , r5 , r6 , r7, // general use
	r8 , r9 , ra , rb , rc , rd , re , rf,
	
	ri0, ri1, ri2, ri3, ri4, ri5, ri6, ri7, // function input
	
	ro0, ro1, // function output
	
	sp , pc, // special
	
	x  , y, // coordinates
}

registers_table := map[string]Register_Type {
	"r0" = .r0, "r1" = .r1, "r2" = .r2, "r3" = .r3, "r4" = .r4, "r5" = .r5, "r6" = .r6, "r7" = .r7,
	"r8" = .r8, "r9" = .r9, "ra" = .ra, "rb" = .rb, "rc" = .rc, "rd" = .rd, "re" = .re, "rf" = .rf,

	"ri0" = .ri0, "ri1" = .ri1, "ri2" = .ri2, "ri3" = .ri3, "ri4" = .ri4, "ri5" = .ri5, "ri6" = .ri6, "ri7" = .ri7,

	"ro0" = .ro0, "ro1" = .ro1,

	"sp" = .sp, "pc" = .pc,

	"x" = .x, "y" = .y,
}

Instruction :: struct {
	type: Instruction_Type,
	imediate: bool, // if uses a imediate as paremeter
	p0, p1: u8,
	p2: i16,
}

Label :: struct {
	name:  string,
	value: u16,
}

MAX_INSTRUCTIONS :: 1024 * 16

REG_SP :: 30

CPU :: struct {
	reg_table: [31]i16,

	pc: u16,
	call_stack: Static_List(u16, 256),

	instructions: Static_List(Instruction, MAX_INSTRUCTIONS),
	labels: Static_List(Label, 4096),
	mem: [1024 * 64]byte,

	cmp_flag: bool,

	gpu: GPU,
}

cpu_clock :: proc(using cpu: ^CPU) {

	for inst, idx in sl_slice(&cpu.instructions) {
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
		case .Jmp:  pc = labels.data[inst.p2].value

		case .Jt:
			if cmp_flag {
				pc = labels.data[inst.p2].value
			}

		case .Jf:
			if !cmp_flag {
				pc = labels.data[inst.p2].value
			}

		case .Pokev:
			addr  := reg_table[inst.p1] + inst.p2
			value := transmute(u16)(reg_table[inst.p0])
			gpu.buffer[addr] = value

		case .Peekv:
			addr := reg_table[inst.p1] + inst.p2
			reg_table[inst.p0] = transmute(i16)(gpu.buffer[addr])

		case .Call:
			sl_push(&call_stack, pc)
			pc = labels.data[inst.p2].value

		case .Ret:
			pc = sl_pop(&call_stack)

		case .Swap:
		} // end switch
	}
}

