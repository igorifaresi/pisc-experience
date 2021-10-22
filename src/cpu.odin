package pisc

Instruction_Type :: enum u8 {
	Add,   Sub,   Mul, Div,
	Or,    And,   Not, Xor,
	Load,  Store, Mov,
	Sl,    Srl,   Sra,
	Ceq,   Cgt,   Clt,
	Jmp,   Jt,    Jf,
	Pokev, Peekv,
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

CPU :: struct {
	reg_table: [31]i16,

	pc: u16,
	instructions: Static_List(Instruction, MAX_INSTRUCTIONS),
	labels: Static_List(Label, 4096),
}

cpu_clock :: proc(using cpu: ^CPU) {

}

