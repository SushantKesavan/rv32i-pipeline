// Reference testbench: the original single-cycle core, used to check the pipeline's architectural
// results.  Prints the same REG / MEM dump lines as tb_pipe (+dump).
module tb_ref;
  logic clk, rst, halt;
  logic [31:0] imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_rdata;
  logic [3:0]  dmem_we;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  rv32i_core dut (.clk, .rst, .imem_addr, .imem_rdata, .dmem_addr, .dmem_wdata,
                  .dmem_we, .dmem_rdata, .halt);
  imem u_imem (.addr(imem_addr), .rdata(imem_rdata));
  dmem u_dmem (.clk, .addr(dmem_addr), .wdata(dmem_wdata), .we(dmem_we), .rdata(dmem_rdata));

  int cycles, max_cycles;
  string status;
  initial begin
    cycles = 0; max_cycles = 5_000_000;
    void'($value$plusargs("max=%d", max_cycles));
    rst = 1'b1;
    repeat (2) @(negedge clk);
    rst = 1'b0;
    @(negedge clk);
    while (!halt && cycles < max_cycles) begin cycles++; @(negedge clk); end
    if (!halt)                        status = "TIMEOUT";
    else if (dut.rf.regs[3] == 32'd1) status = "PASS";
    else                              status = "FAIL";
    $display("RESULT ref status=%s x3=%0d instrs=%0d", status, dut.rf.regs[3], cycles + 1);
    if ($test$plusargs("dump")) begin
      for (int i = 1; i < 32; i++) $display("REG %0d %08x", i, dut.rf.regs[i]);
      for (int i = 0; i < 1024; i++) if (u_dmem.mem[i] != 32'b0) $display("MEM %0d %08x", i, u_dmem.mem[i]);
    end
    $finish;
  end
endmodule
