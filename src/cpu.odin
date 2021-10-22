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

