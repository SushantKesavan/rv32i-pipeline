// Instruction memory: async read, preloaded from a hex file (one 32-bit word per line).
// The file can be overridden at run time with  +hex=<file>.
module imem #(parameter WORDS = 1024, parameter string FILE = "sw/hex/isa_test.hex") (
  input  logic [31:0] addr,
  output logic [31:0] rdata
);
  logic [31:0] mem [WORDS];
  string fn;
  integer i;
  initial begin
    for (i = 0; i < WORDS; i++) mem[i] = 32'h0000_0013; // NOP
    if ($value$plusargs("hex=%s", fn)) $readmemh(fn, mem);
    else                               $readmemh(FILE, mem);
  end
  assign rdata = mem[addr[$clog2(WORDS)+1:2]];
endmodule

// Data memory: word array, byte write enables, async read.
// Only addr[11:2] is decoded, so a 4 KB window repeats through the address space
// (the linker script puts .bss at 0x4000 and the stack top at 0x5000, both inside this window).
module dmem #(parameter WORDS = 1024) (
  input  logic        clk,
  input  logic [31:0] addr,
  input  logic [31:0] wdata,
  input  logic [3:0]  we,
  output logic [31:0] rdata
);
  logic [31:0] mem [WORDS];
  integer i;
  initial for (i = 0; i < WORDS; i++) mem[i] = 32'b0;
  wire [$clog2(WORDS)-1:0] widx = addr[$clog2(WORDS)+1:2];
  assign rdata = mem[widx];
  always_ff @(posedge clk)
    for (int b = 0; b < 4; b++)
      if (we[b]) mem[widx][8*b +: 8] <= wdata[8*b +: 8];
endmodule
