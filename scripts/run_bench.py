#!/usr/bin/env python3
"""Build the pipeline for every branch predictor, run every benchmark, print a results table.

  python3 scripts/run_bench.py                    # iverilog (default)
  python3 scripts/run_bench.py --sim verilator    # Verilator (macOS: export SDKROOT=.../MacOSX26.sdk first)
  python3 scripts/run_bench.py --check            # also compare final regs/memory with the single-cycle core
"""
import argparse, csv, os, re, subprocess, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
RTL = ["rtl/alu.sv", "rtl/regfile.sv", "rtl/imm_gen.sv", "rtl/control.sv", "rtl/mem.sv",
       "rtl/bpred.sv", "rtl/rv32i_pipe.sv"]
REF = ["rtl/alu.sv", "ref/regfile.sv", "rtl/imm_gen.sv", "rtl/control.sv", "rtl/mem.sv", "ref/rv32i_core.sv"]
PRED_NAMES = {0: "static-NT", 1: "static-BTFN", 2: "1-bit", 3: "2-bit", 4: "gshare64"}
BENCHES = ["bubble", "insertion", "fib_rec", "fib_iter", "sieve"]

def sh(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        sys.exit("command failed: %s\n%s%s" % (" ".join(cmd), r.stdout[-2000:], r.stderr[-3000:]))
    return r.stdout

def build(sim, top, files, tag, param=None):
    os.makedirs("build", exist_ok=True)
    if sim == "iverilog":
        out = f"build/{tag}.vvp"
        cmd = ["iverilog", "-g2012", "-o", out] + ([f"-P{top}.PRED={param}"] if param is not None else []) + ["-s", top] + files + [f"tb/{top}.sv"]
        sh(cmd); return ["vvp", "-n", out]
    mdir = f"build/obj_{tag}"
    cmd = ["verilator", "--binary", "--timing", "--top-module", top, "-Mdir", mdir, "-o", tag,
           "-Wno-fatal", "-Wno-lint", "-Wno-style"] + ([f"-GPRED={param}"] if param is not None else []) + files + [f"tb/{top}.sv"]
    sh(cmd); return [f"{mdir}/{tag}"]

def run(exe, hexfile, dump=False):
    out = sh(exe + [f"+hex={hexfile}"] + (["+dump"] if dump else []))
    res = {}; state = []
    for line in out.splitlines():
        if line.startswith("RESULT"):
            res = dict(kv.split("=") for kv in line.split()[1:] if "=" in kv)
        elif line.startswith(("REG", "MEM")):
            state.append(line.strip())
    return res, state

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sim", default="iverilog", choices=["iverilog", "verilator"])
    ap.add_argument("--preds", default="0,1,2,3,4")
    ap.add_argument("--benches", default=",".join(BENCHES))
    ap.add_argument("--check", action="store_true", help="compare architectural state with the single-cycle reference")
    a = ap.parse_args()
    preds = [int(x) for x in a.preds.split(",")]; benches = a.benches.split(",")
    hexes = {b: f"sw/hex/{b}.hex" for b in benches}
    hexes["isa_test"] = "sw/hex/isa_test.hex"

    if a.check:
        ref = build(a.sim, "tb_ref", REF, "ref")
        pipe = build(a.sim, "tb_pipe", RTL, "chk_p4", 4)
        ok = True
        for name, h in hexes.items():
            r, rs = run(ref, h, True)
            for p in preds:
                exe = pipe if p == 4 else build(a.sim, "tb_pipe", RTL, f"chk_p{p}", p)
                q, qs = run(exe, h, True)
                same = (rs == qs) and r["status"] == q["status"] == "PASS"
                ok &= same
                print(f"check {name:10s} pred={PRED_NAMES[p]:12s} ref={r['status']} pipe={q['status']} state {'MATCH' if rs==qs else 'DIFFER'}"
                      f" ({len(rs)} regs/mem words)")
        print("ALL CHECKS PASSED" if ok else "CHECK FAILED"); sys.exit(0 if ok else 1)

    rows = []
    for p in preds:
        exe = build(a.sim, "tb_pipe", RTL, f"p{p}", p)
        for b in benches:
            r, _ = run(exe, hexes[b])
            if r["status"] != "PASS": sys.exit(f"{b} with predictor {p}: {r}")
            rows.append(dict(pred=PRED_NAMES[p], bench=b, **{k: r[k] for k in
                ("cycles", "instrs", "cpi", "branches", "taken", "mispredicts", "accuracy",
                 "jal", "jalr", "load_use_stalls", "id_redirects", "ex_redirects", "mispred_pred_taken")}))
            # sanity: pipeline fill (3 cycles beyond one per instruction) + one cycle per instruction + every lost slot, counted independently
            c = {k: int(v) for k, v in rows[-1].items() if k not in ("pred", "bench", "cpi", "accuracy")}
            exp = c["instrs"] + 3 + c["load_use_stalls"] + c["id_redirects"] + 2 * c["ex_redirects"] - c["mispred_pred_taken"]
            if exp != c["cycles"]: print(f"WARNING: cycle accounting off for {b}/{PRED_NAMES[p]}: expected {exp}, got {c['cycles']}")
    with open("results.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=rows[0].keys()); w.writeheader(); w.writerows(rows)

    def table(title, key, fmt):
        print(f"\n{title}\n"); hdr = ["predictor"] + benches + ["ALL"]
        print("| " + " | ".join(hdr) + " |"); print("|" + "---|" * len(hdr))
        for p in preds:
            n = PRED_NAMES[p]; sel = [x for x in rows if x["pred"] == n]
            cells = [fmt(next(x for x in sel if x["bench"] == b)) for b in benches]
            cells.append(fmt(agg(sel, key)))
            print("| " + " | ".join([n] + cells) + " |")
    def agg(sel, key):
        s = lambda k: sum(int(x[k]) for x in sel)
        return dict(accuracy=100.0 * (s("branches") - s("mispredicts")) / max(1, s("branches")),
                    cpi=s("cycles") / s("instrs"), cycles=s("cycles"))
    table("Branch prediction accuracy (%), conditional branches only", "accuracy", lambda x: "%.1f" % float(x["accuracy"]))
    table("CPI (cycles / retired instructions)", "cpi", lambda x: "%.3f" % float(x["cpi"]))
    first = rows[0]["bench"]
    print("\nPer-benchmark counts (predictor = gshare64 if present)")
    for x in rows:
        if x["pred"] == PRED_NAMES[preds[-1]]:
            print(f"  {x['bench']:10s} instrs={x['instrs']:>6} cycles={x['cycles']:>6} branches={x['branches']:>5} jal={x['jal']:>4} "
                  f"jalr={x['jalr']:>4} load-use stalls={x['load_use_stalls']:>4}")
    print("\nwrote results.csv")

main()
