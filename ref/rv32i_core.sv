// Single-cycle RV32I core (Harvard: separate instruction / data memory ports).
// Assumes naturally aligned loads/stores (no misaligned-access support).
module rv32i_core (
  input  logic        clk, rst,
  output logic [31:0] imem_addr,
  input  logic [31:0] imem_rdata,
  output logic [31:0] dmem_addr,
  output logic [31:0] dmem_wdata,
  output logic [3:0]  dmem_we,
  input  logic [31:0] dmem_rdata,
  output logic        halt
);
  logic [31:0] pc, pc_plus4, pc_next, instr;
  assign imem_addr = pc;
  assign instr     = imem_rdata;
  assign pc_plus4  = pc + 32'd4;

  wire [6:0] opcode   = instr[6:0];
  wire [4:0] rd       = instr[11:7];
  wire [2:0] funct3   = instr[14:12];
  wire [4:0] rs1      = instr[19:15];
  wire [4:0] rs2      = instr[24:20];
  wire       funct7_5 = instr[30];

  // ---- decode ----
  logic reg_write, alu_a_pc, alu_b_imm, mem_write, branch, jal, jalr, is_system;
  logic [1:0] wb_sel;
  logic [3:0] alu_op;
  control u_ctl (.opcode, .funct3, .funct7_5, .reg_write, .alu_a_pc, .alu_b_imm,
                 .mem_write, .branch, .jal, .jalr, .is_system, .wb_sel, .alu_op);

  logic [31:0] imm;
  imm_gen u_imm (.instr, .imm);

  // ---- register file ----
  logic [31:0] rs1_data, rs2_data, wb_data;
  regfile rf (.clk, .we(reg_write & ~halt), .ra1(rs1), .ra2(rs2), .wa(rd),
              .wd(wb_data), .rd1(rs1_data), .rd2(rs2_data));

  // ---- execute ----
  logic [31:0] alu_a, alu_b, alu_y;
  assign alu_a = alu_a_pc  ? pc  : rs1_data;
  assign alu_b = alu_b_imm ? imm : rs2_data;
  alu u_alu (.a(alu_a), .b(alu_b), .op(alu_op), .y(alu_y));

  // ---- branch compare ----
  logic take_branch;
  always_comb begin
    case (funct3)
      3'b000:  take_branch = (rs1_data == rs2_data);                      // BEQ
      3'b001:  take_branch = (rs1_data != rs2_data);                      // BNE
      3'b100:  take_branch = ($signed(rs1_data) <  $signed(rs2_data));    // BLT
      3'b101:  take_branch = ($signed(rs1_data) >= $signed(rs2_data));    // BGE
      3'b110:  take_branch = (rs1_data <  rs2_data);                      // BLTU
      3'b111:  take_branch = (rs1_data >= rs2_data);                      // BGEU
      default: take_branch = 1'b0;
    endcase
  end

  // ---- next PC ----
  always_comb begin
    if (jalr)                              pc_next = {alu_y[31:1], 1'b0};  // rs1 + imm, bit0 cleared
    else if (jal | (branch & take_branch)) pc_next = pc + imm;
    else                                   pc_next = pc_plus4;
  end

  assign halt = is_system & ~rst;
  always_ff @(posedge clk)
    if (rst)        pc <= 32'b0;
    else if (!halt) pc <= pc_next;

  // ---- data memory interface ----
  wire [1:0] ba = alu_y[1:0];
  assign dmem_addr = alu_y;
  always_comb begin
    dmem_wdata = rs2_data;
    dmem_we    = 4'b0000;
    if (mem_write) begin
      case (funct3[1:0])
        2'b00:   begin dmem_wdata = {4{rs2_data[7:0]}};  dmem_we = 4'b0001 << ba; end         // SB
        2'b01:   begin dmem_wdata = {2{rs2_data[15:0]}}; dmem_we = ba[1] ? 4'b1100 : 4'b0011; end // SH
        default: begin dmem_we = 4'b1111; end                                                  // SW
      endcase
    end
  end

  logic [7:0]  ld_b;
  logic [15:0] ld_h;
  logic [31:0] load_data;
  assign ld_b = dmem_rdata[8*ba     +: 8];
  assign ld_h = dmem_rdata[16*ba[1] +: 16];
  always_comb begin
    case (funct3)
      3'b000:  load_data = {{24{ld_b[7]}},  ld_b};   // LB
      3'b001:  load_data = {{16{ld_h[15]}}, ld_h};   // LH
      3'b100:  load_data = {24'b0, ld_b};            // LBU
      3'b101:  load_data = {16'b0, ld_h};            // LHU
      default: load_data = dmem_rdata;               // LW
    endcase
  end

  // ---- writeback ----
  always_comb begin
    case (wb_sel)
      2'b00:   wb_data = alu_y;
      2'b01:   wb_data = load_data;
      2'b10:   wb_data = pc_plus4;
      default: wb_data = imm;
    endcase
  end
endmodule
