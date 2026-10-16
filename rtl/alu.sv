// ALU. op encoding = {funct7[5], funct3} so decode is trivial.
module alu (
  input  logic [31:0] a, b,
  input  logic [3:0]  op,
  output logic [31:0] y
);
  always_comb begin
    case (op)
      4'b0000: y = a + b;                                   // ADD
      4'b1000: y = a - b;                                   // SUB
      4'b0001: y = a << b[4:0];                             // SLL
      4'b0010: y = {31'b0, $signed(a) < $signed(b)};        // SLT
      4'b0011: y = {31'b0, a < b};                          // SLTU
      4'b0100: y = a ^ b;                                   // XOR
      4'b0101: y = a >> b[4:0];                             // SRL
      4'b1101: y = $unsigned($signed(a) >>> b[4:0]);        // SRA
      4'b0110: y = a | b;                                   // OR
      4'b0111: y = a & b;                                   // AND
      default: y = 32'b0;
    endcase
  end
endmodule
