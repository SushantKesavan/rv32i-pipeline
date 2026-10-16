// Main decoder.  wb_sel: 00=ALU, 01=load data, 10=PC+4, 11=immediate (LUI)
module control (
  input  logic [6:0] opcode,
  input  logic [2:0] funct3,
  input  logic       funct7_5,
  output logic       reg_write,
  output logic       alu_a_pc,     // 1: ALU operand A = PC (AUIPC)
  output logic       alu_b_imm,    // 1: ALU operand B = immediate
  output logic       mem_write,
  output logic       branch, jal, jalr,
  output logic       is_system,    // ECALL/EBREAK -> halt (for simulation)
  output logic [1:0] wb_sel,
  output logic [3:0] alu_op
);
  always_comb begin
    reg_write = 0; alu_a_pc = 0; alu_b_imm = 0; mem_write = 0;
    branch = 0; jal = 0; jalr = 0; is_system = 0;
    wb_sel = 2'b00; alu_op = 4'b0000;
    case (opcode)
      7'b0110011: begin reg_write = 1; alu_op = {funct7_5, funct3}; end            // OP
      7'b0010011: begin reg_write = 1; alu_b_imm = 1;                               // OP-IMM
                        alu_op = {(funct3 == 3'b101) & funct7_5, funct3}; end
      7'b0000011: begin reg_write = 1; alu_b_imm = 1; wb_sel = 2'b01; end           // LOAD
      7'b0100011: begin alu_b_imm = 1; mem_write = 1; end                           // STORE
      7'b1100011: begin branch = 1; end                                             // BRANCH
      7'b1101111: begin reg_write = 1; jal = 1; wb_sel = 2'b10; end                 // JAL
      7'b1100111: begin reg_write = 1; jalr = 1; alu_b_imm = 1; wb_sel = 2'b10; end // JALR
      7'b0110111: begin reg_write = 1; wb_sel = 2'b11; end                          // LUI
      7'b0010111: begin reg_write = 1; alu_a_pc = 1; alu_b_imm = 1; end             // AUIPC
      7'b1110011: begin is_system = 1; end                                          // ECALL/EBREAK
      default: ;                                                                    // FENCE etc. = NOP
    endcase
  end
endmodule
