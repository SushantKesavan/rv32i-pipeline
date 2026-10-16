// ORIGINAL regfile (no write-through) -- the single-cycle reference needs it, since write-through would
// create a combinational loop through the ALU there.
// 32x32 register file: 2 async read ports, 1 sync write port, x0 = 0.
module regfile (
  input  logic        clk, we,
  input  logic [4:0]  ra1, ra2, wa,
  input  logic [31:0] wd,
  output logic [31:0] rd1, rd2
);
  logic [31:0] regs [32];
  integer i;
  initial for (i = 0; i < 32; i++) regs[i] = 32'b0;

  always_ff @(posedge clk)
    if (we && wa != 5'd0) regs[wa] <= wd;

  assign rd1 = (ra1 == 5'd0) ? 32'b0 : regs[ra1];
  assign rd2 = (ra2 == 5'd0) ? 32'b0 : regs[ra2];
endmodule
