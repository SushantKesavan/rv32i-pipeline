// Testbench for the 5-stage core.  Runs the program in sw/hex/*.hex (select with +hex=file)
// until ECALL retires.  Convention (as in riscv-tests): x3 == 1 -> PASS, else x3 = failing test number.
// Prints one machine-readable RESULT line.  +dump also prints the final registers and data memory.
module tb_pipe #(parameter int PRED = 4, parameter int PHT_ENTRIES = 64);
  logic clk, rst, halt;
  logic [31:0] imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_rdata;
  logic [3:0]  dmem_we;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  rv32i_pipe #(.PRED(PRED), .PHT_ENTRIES(PHT_ENTRIES)) dut (
    .clk, .rst, .imem_addr, .imem_rdata, .dmem_addr, .dmem_wdata, .dmem_we, .dmem_rdata, .halt);
  imem u_imem (.addr(imem_addr), .rdata(imem_rdata));
  dmem u_dmem (.clk, .addr(dmem_addr), .wdata(dmem_wdata), .we(dmem_we), .rdata(dmem_rdata));

  // ---------------- performance counters (sampled at negedge, when everything has settled)
  longint unsigned cycles, instrs, branches, mispredicts, taken_br, jal_n, jalr_n;
  longint unsigned ld_use_stalls, id_redirects, ex_redirects, mp_pt;
  logic done, timeout, started;
  always @(posedge clk) if (!rst) started <= 1'b1;
  localparam longint unsigned MAX_CYCLES = 5_000_000;

  initial begin
    cycles = 0; instrs = 0; branches = 0; mispredicts = 0; taken_br = 0; jal_n = 0; jalr_n = 0;
    ld_use_stalls = 0; id_redirects = 0; ex_redirects = 0; mp_pt = 0; done = 0; timeout = 0; started = 0;
  end

  always @(negedge clk) if (started && !done) begin
    cycles = cycles + 1;
    if (dut.wb_valid)                      instrs        = instrs + 1;
    if (dut.ex_valid && dut.ex_branch) begin
      branches = branches + 1;
      if (dut.take_branch) taken_br = taken_br + 1;
    end
    if (dut.br_mispred)                    mispredicts   = mispredicts + 1;
    if (dut.br_mispred && dut.ex_pred_taken) mp_pt       = mp_pt + 1;
    if (dut.ex_valid && dut.ex_jal)        jal_n         = jal_n + 1;
    if (dut.ex_valid && dut.ex_jalr)       jalr_n        = jalr_n + 1;
    if (dut.stall)                         ld_use_stalls = ld_use_stalls + 1;
    if (dut.id_redirect)                   id_redirects  = id_redirects + 1;
    if (dut.ex_redirect)                   ex_redirects  = ex_redirects + 1;
    if (halt)                              done          = 1'b1;
    if (cycles >= MAX_CYCLES)              begin timeout = 1'b1; done = 1'b1; end
  end

  initial begin
    rst = 1'b1;
    repeat (2) @(negedge clk);
    rst = 1'b0;
    wait (done);
    report();
    $finish;
  end

  task automatic report();
    string status;
    real cpi, acc;
    if (timeout)                       status = "TIMEOUT";
    else if (dut.rf.regs[3] == 32'd1)  status = "PASS";
    else                               status = "FAIL";
    cpi = (instrs == 0) ? 0.0 : real'(cycles) / real'(instrs);
    acc = (branches == 0) ? 100.0 : 100.0 * real'(branches - mispredicts) / real'(branches);
    $display("RESULT pred=%0d status=%s x3=%0d cycles=%0d instrs=%0d cpi=%0.4f branches=%0d taken=%0d mispredicts=%0d accuracy=%0.2f jal=%0d jalr=%0d load_use_stalls=%0d id_redirects=%0d ex_redirects=%0d mispred_pred_taken=%0d",
             PRED, status, dut.rf.regs[3], cycles, instrs, cpi, branches, taken_br, mispredicts, acc,
             jal_n, jalr_n, ld_use_stalls, id_redirects, ex_redirects, mp_pt);
    if ($test$plusargs("dump")) begin
      for (int i = 1; i < 32; i++) $display("REG %0d %08x", i, dut.rf.regs[i]);
      for (int i = 0; i < 1024; i++) if (u_dmem.mem[i] != 32'b0) $display("MEM %0d %08x", i, u_dmem.mem[i]);
    end
  endtask
endmodule
