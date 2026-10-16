// Branch direction predictor, looked up in ID, updated when the branch resolves in EX.
//   MODE 0 : static not-taken
//   MODE 1 : static backward-taken / forward-not-taken (BTFN)
//   MODE 2 : 1-bit, ENTRIES-entry table indexed by PC
//   MODE 3 : 2-bit saturating counters (bimodal), indexed by PC
//   MODE 4 : GShare, 2-bit counters indexed by PC ^ global history
// The global history register is updated speculatively with the predicted
// direction and repaired from a snapshot when a branch is found mispredicted.
module bpred #(
  parameter int MODE    = 4,
  parameter int ENTRIES = 64,
  parameter int IDXW    = $clog2(ENTRIES)
) (
  input  logic            clk, rst,
  // prediction (ID stage)
  input  logic [31:0]     pc,
  input  logic            backward,       // branch offset is negative
  output logic            pred_taken,
  output logic [IDXW-1:0] pred_idx,       // table index used (carried to EX for the update)
  output logic [IDXW-1:0] pred_ghr,       // history snapshot at prediction time
  input  logic            spec_en,        // a branch is leaving ID: shift predicted bit into history
  // update (EX stage)
  input  logic            upd_en,
  input  logic            upd_taken,
  input  logic            upd_mispred,
  input  logic [IDXW-1:0] upd_idx,
  input  logic [IDXW-1:0] upd_ghr
);
  logic [IDXW-1:0] ghr;
  logic [1:0]      ctr [ENTRIES];

  wire [IDXW-1:0] pc_idx = pc[IDXW+1:2];
  assign pred_idx = (MODE == 4) ? (pc_idx ^ ghr) : pc_idx;
  assign pred_ghr = ghr;

  wire [1:0] ctr_rd = ctr[pred_idx];
  always_comb begin
    case (MODE)
      0:       pred_taken = 1'b0;
      1:       pred_taken = backward;
      2:       pred_taken = ctr_rd[0];
      default: pred_taken = ctr_rd[1];
    endcase
  end

  wire [1:0] ctr_upd = ctr[upd_idx];
  integer i;
  always_ff @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < ENTRIES; i++) ctr[i] <= (MODE == 2) ? 2'b00 : 2'b01; // not-taken / weakly not-taken
      ghr <= '0;
    end else begin
      if (upd_en) begin
        if (MODE == 2)
          ctr[upd_idx] <= {1'b0, upd_taken};
        else if (MODE >= 3) begin
          if ( upd_taken && ctr_upd != 2'b11) ctr[upd_idx] <= ctr_upd + 2'b01;
          if (!upd_taken && ctr_upd != 2'b00) ctr[upd_idx] <= ctr_upd - 2'b01;
        end
      end
      if (upd_en && upd_mispred) ghr <= {upd_ghr[IDXW-2:0], upd_taken};
      else if (spec_en)          ghr <= {ghr[IDXW-2:0], pred_taken};
    end
  end
endmodule
