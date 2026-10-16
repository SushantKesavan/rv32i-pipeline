// 5-stage pipelined RV32I core: IF -> ID -> EX -> MEM -> WB
// Same port list as the single-cycle core, so it drops into the same testbench.
//
// Hazard handling
//   * Data hazards : forwarding EX/MEM -> EX and MEM/WB -> EX, register-file write-through for WB -> ID.
//   * Load-use     : 1-cycle stall (bubble into EX, hold PC and IF/ID).
//   * Control      : JAL redirects from ID (1 bubble).  Conditional branches are predicted in ID by
//                    `bpred` (taken => redirect from ID, 1 bubble) and resolved in EX
//                    (wrong => flush IF+ID, 2 bubbles).  JALR is resolved in EX (2 bubbles).
//   * Halt         : ECALL/EBREAK retiring in WB raises `halt`.
module rv32i_pipe #(
  parameter int PRED        = 4,    // 0 static-NT, 1 BTFN, 2 1-bit, 3 2-bit bimodal, 4 GShare
  parameter int PHT_ENTRIES = 64
) (
  input  logic        clk, rst,
  output logic [31:0] imem_addr,
  input  logic [31:0] imem_rdata,
  output logic [31:0] dmem_addr,
  output logic [31:0] dmem_wdata,
  output logic [3:0]  dmem_we,
  input  logic [31:0] dmem_rdata,
  output logic        halt
);
  localparam int IDXW = $clog2(PHT_ENTRIES);
  localparam logic [31:0] NOP = 32'h0000_0013;

  // ------------------------------------------------------------------ pipeline-wide signals
  logic        stall;                 // load-use stall
  logic        ex_redirect;           // EX resolved a mispredicted branch / JALR
  logic [31:0] ex_target;
  logic        id_redirect;           // ID redirects fetch (JAL or predicted-taken branch)
  logic [31:0] id_target;
  logic        halt_fetch;            // an ECALL/EBREAK is in flight: stop fetching past it

  // ================================================================== IF
  logic [31:0] pc;
  assign imem_addr = pc;

  // IF/ID
  logic [31:0] id_pc, id_instr;
  logic        id_valid;

  // ================================================================== ID
  wire [6:0] id_opcode = id_instr[6:0];
  wire [4:0] id_rd     = id_instr[11:7];
  wire [2:0] id_funct3 = id_instr[14:12];
  wire [4:0] id_rs1    = id_instr[19:15];
  wire [4:0] id_rs2    = id_instr[24:20];

  logic       c_reg_write, c_alu_a_pc, c_alu_b_imm, c_mem_write, c_branch, c_jal, c_jalr, c_is_system;
  logic [1:0] c_wb_sel;
  logic [3:0] c_alu_op;
  control u_ctl (.opcode(id_opcode), .funct3(id_funct3), .funct7_5(id_instr[30]),
                 .reg_write(c_reg_write), .alu_a_pc(c_alu_a_pc), .alu_b_imm(c_alu_b_imm),
                 .mem_write(c_mem_write), .branch(c_branch), .jal(c_jal), .jalr(c_jalr),
                 .is_system(c_is_system), .wb_sel(c_wb_sel), .alu_op(c_alu_op));

  logic [31:0] id_imm;
  imm_gen u_imm (.instr(id_instr), .imm(id_imm));

  // register file (write port driven from WB)
  logic [31:0] id_rs1d, id_rs2d;
  logic        wb_reg_write, wb_valid, wb_is_system;
  logic [4:0]  wb_rd;
  logic [31:0] wb_data;
  regfile rf (.clk, .we(wb_reg_write & wb_valid), .ra1(id_rs1), .ra2(id_rs2), .wa(wb_rd),
              .wd(wb_data), .rd1(id_rs1d), .rd2(id_rs2d));

  // which source registers does the instruction in ID really read?
  wire uses_rs1 = id_valid & ~(id_opcode == 7'b0110111 | id_opcode == 7'b0010111 |   // LUI, AUIPC
                               id_opcode == 7'b1101111 | id_opcode == 7'b1110011);   // JAL, SYSTEM
  wire uses_rs2 = id_valid &  (id_opcode == 7'b0110011 | id_opcode == 7'b0100011 |   // OP, STORE
                               id_opcode == 7'b1100011);                             // BRANCH

  // ---- ID/EX registers (declared here so hazard logic can use them)
  logic        ex_valid, ex_reg_write, ex_mem_write, ex_branch, ex_jal, ex_jalr, ex_is_system;
  logic        ex_alu_a_pc, ex_alu_b_imm, ex_pred_taken;
  logic [1:0]  ex_wb_sel;
  logic [3:0]  ex_alu_op;
  logic [2:0]  ex_funct3;
  logic [4:0]  ex_rd, ex_rs1, ex_rs2;
  logic [31:0] ex_pc, ex_imm, ex_rs1d, ex_rs2d;
  logic [IDXW-1:0] ex_pred_idx, ex_pred_ghr;

  // load-use hazard: load in EX, its result needed by the instruction in ID
  assign stall = ex_valid & ex_reg_write & (ex_wb_sel == 2'b01) & (ex_rd != 5'd0) &
                 ((uses_rs1 & (id_rs1 == ex_rd)) | (uses_rs2 & (id_rs2 == ex_rd)));

  // ---- branch prediction (ID)
  logic            bp_taken;
  logic [IDXW-1:0] bp_idx, bp_ghr;
  logic            upd_en, upd_taken, upd_mispred;
  wire id_is_branch = id_valid & c_branch;
  wire id_advance   = id_valid & ~stall & ~ex_redirect;   // the ID instruction moves on this cycle

  bpred #(.MODE(PRED), .ENTRIES(PHT_ENTRIES)) u_bp (
    .clk, .rst,
    .pc(id_pc), .backward(id_imm[31]),
    .pred_taken(bp_taken), .pred_idx(bp_idx), .pred_ghr(bp_ghr),
    .spec_en(id_is_branch & id_advance),
    .upd_en, .upd_taken, .upd_mispred, .upd_idx(ex_pred_idx), .upd_ghr(ex_pred_ghr));

  assign id_target   = id_pc + id_imm;
  assign id_redirect = id_advance & (c_jal | (c_branch & bp_taken));

  // ================================================================== EX
  // forwarding sources
  logic        mem_valid, mem_reg_write, mem_mem_write, mem_is_system;
  logic [1:0]  mem_wb_sel;
  logic [2:0]  mem_funct3;
  logic [4:0]  mem_rd;
  logic [31:0] mem_pc4, mem_alu_y, mem_rs2d, mem_imm;

  logic [31:0] mem_res;                        // EX/MEM result that can be forwarded (non-load)
  always_comb begin
    case (mem_wb_sel)
      2'b10:   mem_res = mem_pc4;
      2'b11:   mem_res = mem_imm;
      default: mem_res = mem_alu_y;
    endcase
  end
  wire mem_can_fwd = mem_reg_write & (mem_rd != 5'd0) & (mem_wb_sel != 2'b01); // loads: use stall
  wire wb_can_fwd  = wb_reg_write  & (wb_rd  != 5'd0);

  logic [31:0] fwd_a, fwd_b;
  always_comb begin
    if      (mem_can_fwd && mem_rd == ex_rs1) fwd_a = mem_res;
    else if (wb_can_fwd  && wb_rd  == ex_rs1) fwd_a = wb_data;
    else                                      fwd_a = ex_rs1d;
    if      (mem_can_fwd && mem_rd == ex_rs2) fwd_b = mem_res;
    else if (wb_can_fwd  && wb_rd  == ex_rs2) fwd_b = wb_data;
    else                                      fwd_b = ex_rs2d;
  end

  logic [31:0] alu_a, alu_b, alu_y;
  assign alu_a = ex_alu_a_pc  ? ex_pc  : fwd_a;
  assign alu_b = ex_alu_b_imm ? ex_imm : fwd_b;
  alu u_alu (.a(alu_a), .b(alu_b), .op(ex_alu_op), .y(alu_y));

  // branch comparison
  logic take_branch;
  always_comb begin
    case (ex_funct3)
      3'b000:  take_branch = (fwd_a == fwd_b);                      // BEQ
      3'b001:  take_branch = (fwd_a != fwd_b);                      // BNE
      3'b100:  take_branch = ($signed(fwd_a) <  $signed(fwd_b));    // BLT
      3'b101:  take_branch = ($signed(fwd_a) >= $signed(fwd_b));    // BGE
      3'b110:  take_branch = (fwd_a <  fwd_b);                      // BLTU
      3'b111:  take_branch = (fwd_a >= fwd_b);                      // BGEU
      default: take_branch = 1'b0;
    endcase
  end

  wire ex_is_cond_branch = ex_valid & ex_branch;
  wire br_mispred        = ex_is_cond_branch & (take_branch != ex_pred_taken);
  wire jalr_redirect     = ex_valid & ex_jalr;
  assign ex_redirect = br_mispred | jalr_redirect;
  assign ex_target   = ex_jalr     ? {alu_y[31:1], 1'b0} :
                       take_branch ? (ex_pc + ex_imm)    : (ex_pc + 32'd4);

  assign upd_en      = ex_is_cond_branch;
  assign upd_taken   = take_branch;
  assign upd_mispred = br_mispred;

  // ================================================================== MEM
  assign dmem_addr = mem_alu_y;
  wire [1:0] ba = mem_alu_y[1:0];
  always_comb begin
    dmem_wdata = mem_rs2d;
    dmem_we    = 4'b0000;
    if (mem_valid & mem_mem_write) begin
      case (mem_funct3[1:0])
        2'b00:   begin dmem_wdata = {4{mem_rs2d[7:0]}};  dmem_we = 4'b0001 << ba;               end // SB
        2'b01:   begin dmem_wdata = {2{mem_rs2d[15:0]}}; dmem_we = ba[1] ? 4'b1100 : 4'b0011;   end // SH
        default: begin                                   dmem_we = 4'b1111;                     end // SW
      endcase
    end
  end

  logic [7:0]  ld_b;
  logic [15:0] ld_h;
  logic [31:0] load_data, mem_wb_data;
  assign ld_b = dmem_rdata[8*ba      +: 8];
  assign ld_h = dmem_rdata[16*ba[1]  +: 16];
  always_comb begin
    case (mem_funct3)
      3'b000:  load_data = {{24{ld_b[7]}},  ld_b};   // LB
      3'b001:  load_data = {{16{ld_h[15]}}, ld_h};   // LH
      3'b100:  load_data = {24'b0, ld_b};            // LBU
      3'b101:  load_data = {16'b0, ld_h};            // LHU
      default: load_data = dmem_rdata;               // LW
    endcase
  end
  assign mem_wb_data = (mem_wb_sel == 2'b01) ? load_data : mem_res;

  // ================================================================== WB / halt
  assign halt       = wb_valid & wb_is_system;
  assign halt_fetch = (id_valid & c_is_system) | ex_is_system | mem_is_system | wb_is_system;

  // ================================================================== pipeline registers
  always_ff @(posedge clk) begin
    if (rst) begin
      pc <= 32'b0;
      id_valid <= 1'b0;  id_pc <= 32'b0;  id_instr <= NOP;
      ex_valid <= 1'b0;  ex_reg_write <= 1'b0; ex_mem_write <= 1'b0; ex_branch <= 1'b0;
      ex_jal <= 1'b0;    ex_jalr <= 1'b0;  ex_is_system <= 1'b0;     ex_wb_sel <= 2'b00;
      mem_valid <= 1'b0; mem_reg_write <= 1'b0; mem_mem_write <= 1'b0; mem_is_system <= 1'b0;
      mem_wb_sel <= 2'b00;
      wb_valid <= 1'b0;  wb_reg_write <= 1'b0; wb_is_system <= 1'b0;
    end else begin
      // ---------------- IF: PC
      if      (ex_redirect) pc <= ex_target;
      else if (stall | halt_fetch) pc <= pc;
      else if (id_redirect) pc <= id_target;
      else                  pc <= pc + 32'd4;

      // ---------------- IF/ID
      if (ex_redirect | id_redirect) begin
        id_valid <= 1'b0;  id_instr <= NOP;
      end else if (!stall) begin
        id_valid <= ~halt_fetch;  id_pc <= pc;  id_instr <= halt_fetch ? NOP : imem_rdata;
      end

      // ---------------- ID/EX
      if (ex_redirect | stall) begin               // insert a bubble
        ex_valid <= 1'b0;  ex_reg_write <= 1'b0;  ex_mem_write <= 1'b0;  ex_branch <= 1'b0;
        ex_jal <= 1'b0;    ex_jalr <= 1'b0;       ex_is_system <= 1'b0;  ex_wb_sel <= 2'b00;
      end else begin
        ex_valid     <= id_valid;
        ex_reg_write <= id_valid & c_reg_write;
        ex_mem_write <= id_valid & c_mem_write;
        ex_branch    <= id_valid & c_branch;
        ex_jal       <= id_valid & c_jal;
        ex_jalr      <= id_valid & c_jalr;
        ex_is_system <= id_valid & c_is_system;
        ex_wb_sel    <= c_wb_sel;
        ex_alu_op    <= c_alu_op;
        ex_alu_a_pc  <= c_alu_a_pc;
        ex_alu_b_imm <= c_alu_b_imm;
        ex_funct3    <= id_funct3;
        ex_rd        <= id_rd;   ex_rs1 <= id_rs1;  ex_rs2 <= id_rs2;
        ex_pc        <= id_pc;   ex_imm <= id_imm;
        ex_rs1d      <= id_rs1d; ex_rs2d <= id_rs2d;
        ex_pred_taken<= bp_taken;
        ex_pred_idx  <= bp_idx;  ex_pred_ghr <= bp_ghr;
      end

      // ---------------- EX/MEM
      mem_valid     <= ex_valid;
      mem_reg_write <= ex_reg_write;
      mem_mem_write <= ex_mem_write;
      mem_is_system <= ex_is_system;
      mem_wb_sel    <= ex_wb_sel;
      mem_funct3    <= ex_funct3;
      mem_rd        <= ex_rd;
      mem_pc4       <= ex_pc + 32'd4;
      mem_alu_y     <= alu_y;
      mem_rs2d      <= fwd_b;
      mem_imm       <= ex_imm;

      // ---------------- MEM/WB
      wb_valid      <= mem_valid;
      wb_reg_write  <= mem_reg_write;
      wb_is_system  <= mem_is_system;
      wb_rd         <= mem_rd;
      wb_data       <= mem_wb_data;
    end
  end
endmodule
