#!/usr/bin/env python3
"""Run every directed test of the verification plan and print one result per vplan ID.

Usage (from the repo root):  python3 scripts/vplan_report.py [--skip-programs] [BLOCK ...]
    BLOCK: UART SPI I2C TIMER IRQC GPIO BUS SOC (default: all)
    --skip-programs: do not run riscv-tests and firmware (BUS-17, SOC-01..06 become NOT RUN)

Block sheets: each testbench prints a per-item table (tb/common/vplan_pkg.sv),
which is parsed from sim/report/sim_<top>.log. A class-based testbench
(tb/class_tb/<top>, tests in testcases/<top>/) is run with `make tests TOP=<top>`;
its tests each run part of the items and their tables are merged
(an item FAILs if it fails in any test, PASSes if it ran and never failed).
Program items: BUS-17 and SOC-01..06 are decided from riscv-tests and firmware runs.
Output: the table on stdout and sim/report/vplan_results.csv (ID, result, detail).
Exit code 0 only if every item that was run passed.
"""
import csv
import glob
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
REPORT = os.path.join(ROOT, "sim", "report")

UNITS = [("UART", "uart_apb", 44), ("SPI", "spi_apb", 38), ("I2C", "i2c_apb", 38),
         ("TIMER", "timer_apb", 32), ("IRQC", "irqc_apb", 19), ("GPIO", "gpio_apb", 23),
         ("BUS", "bus_sys", 17)]
# Blocks verified by a class-based testbench: block -> TOP (tb/class_tb/<TOP>)
CLASS_TB = {"TIMER": "timer", "UART": "uart", "GPIO": "gpio", "IRQC": "irqc", "SPI": "spi", "I2C": "i2c", "BUS": "bus"}
NOTES = []
ITEM_RE = re.compile(r"^([A-Z0-9]+-\d\d)\s+(PASS|FAIL|NOT RUN|EXT)\s*(\((\d+) checks, (\d+) failed\))?")


def run(cmd, env=None, log=None):
    e = dict(os.environ)
    if env:
        e.update(env)
    p = subprocess.run(cmd, cwd=ROOT, env=e, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if log:
        with open(os.path.join(REPORT, log), "w") as f:
            f.write(p.stdout)
    return p.returncode, p.stdout


def unit_results(block, top, n):
    rc, out = run(["make", "--no-print-directory", "-C", "sim", "sim", "TOP=" + top])
    res = {}
    path = os.path.join(REPORT, "sim_%s.log" % top)
    text = open(path).read() if os.path.exists(path) else ""
    for line in text.splitlines():
        m = ITEM_RE.match(line)
        if m and m.group(1).startswith(block + "-"):
            det = "%s checks, %s failed" % (m.group(4), m.group(5)) if m.group(3) else ""
            res[m.group(1)] = (m.group(2), det)
    if not res:
        why = "build or run failed, see sim/report/sim_%s.log" % top
        for i in range(1, n + 1):
            res["%s-%02d" % (block, i)] = ("FAIL", why)
    return res


def class_results(block, top, n):
    tests = []
    for f in sorted(glob.glob(os.path.join(ROOT, "testcases", top, "*.sv"))):
        tests += re.findall(r"^class (\w+) extends %s_base_test" % top, open(f).read(), re.M)
    for f in glob.glob(os.path.join(REPORT, "sim_%s_*.log" % top)):
        os.remove(f)
    run(["make", "--no-print-directory", "-C", "sim", "tests", "TOP=" + top])
    checks, failed, where = {}, {}, {}
    bad_logs = []
    for t in tests:
        path = os.path.join(REPORT, "sim_%s_%s.log" % (top, t))
        text = open(path).read() if os.path.exists(path) else ""
        if "TEST PASSED" not in text and "TEST FAILED" not in text:
            bad_logs.append(t)
        extra = re.findall(r"^(%s-[A-Z]+)\s+FAIL" % block, text, re.M)
        if extra:
            NOTES.append("%s: %s FAIL (extra item, not in the vplan table), see sim/report/sim_%s_%s.log"
                         % (t, ", ".join(extra), top, t))
        for line in text.splitlines():
            m = ITEM_RE.match(line)
            if m and m.group(1).startswith(block + "-") and m.group(3):
                iid = m.group(1)
                checks[iid] = checks.get(iid, 0) + int(m.group(4))
                failed[iid] = failed.get(iid, 0) + int(m.group(5))
                if int(m.group(4)):
                    where.setdefault(iid, []).append(t)
    res = {}
    for i in range(1, n + 1):
        iid = "%s-%02d" % (block, i)
        c, f = checks.get(iid, 0), failed.get(iid, 0)
        det = "%d checks, %d failed (%s)" % (c, f, ", ".join(where.get(iid, [])))
        if c == 0:
            why = "; tests without a result: " + ", ".join(bad_logs) if bad_logs else ""
            res[iid] = ("NOT RUN", why.lstrip("; "))
        else:
            res[iid] = ("FAIL" if f else "PASS", det)
        if bad_logs and res[iid][0] == "PASS":
            res[iid] = ("FAIL", det + "; tests without a result: " + ", ".join(bad_logs))
    return res


def riscv(tb, suites, log):
    rc, out = run(["bash", "scripts/run_riscv_tests.sh"] + suites, env={"TB": tb}, log=log)
    summ = [l for l in out.splitlines() if l.startswith("riscv-tests:")]
    fails = [l for l in out.splitlines() if l.startswith("FAIL")]
    return rc == 0, (summ[-1] if summ else "no summary") + ("; " + "; ".join(fails) if fails else ""), out


def soc(prog):
    rc, out = run(["make", "--no-print-directory", "-C", "sim", "soc", "PROG=" + prog])
    path = os.path.join(REPORT, "sim_soc_top.log")
    text = open(path).read() if os.path.exists(path) else ""
    with open(os.path.join(REPORT, "sim_soc_%s.log" % prog), "w") as f:
        f.write(text)
    return rc == 0, text


def program_results(blocks):
    res = {}
    if "BUS" in blocks:
        ok, det, _ = riscv("cpu_axi", ["bus"], "riscv_tests_bus.log")
        res["BUS-17"] = ("PASS" if ok else "FAIL", "bus_apb.S on tb_cpu_axi: " + det)
    if "SOC" in blocks:
        ok1, det1, _ = riscv("cpu_wrapper", ["rv32ui", "rv32um", "rv32mi"], "riscv_tests_wrapper.log")
        ok2, det2, _ = riscv("cpu_axi", ["rv32ui", "rv32um", "rv32mi"], "riscv_tests_axi.log")
        res["SOC-01"] = ("PASS" if ok1 and ok2 else "FAIL", "cpu_wrapper: %s | cpu_axi: %s" % (det1, det2))
        ok, det, out = riscv("cpu_wrapper", ["local"], "riscv_tests_local.log")
        irq = [l for l in out.splitlines() if "irq_fault" in l]
        res["SOC-02"] = ("PASS" if ok and irq and irq[0].startswith("PASS") else "FAIL",
                         irq[0] if irq else det)
        ok, text = soc("hello")
        good = ok and "Hello from RISC-V SoC!" in text and "@@PASS" in text
        res["SOC-03"] = ("PASS" if good else "FAIL", "make soc PROG=hello")
        ok, text = soc("periph")
        n_ok = len(re.findall(r"UART:\s+ok ", text))
        res["SOC-04"] = ("PASS" if ok and n_ok == 9 and "@@PASS" in text else "FAIL",
                         "%d of 9 'ok' lines" % n_ok)
        irq_ok = ("ok   gpio edge irq" in text) and ("ok   timer irq" in text)
        res["SOC-05"] = ("PASS" if irq_ok else "FAIL", "periph items 'gpio edge irq' and 'timer irq'")
        ok, text = soc("de2_demo")
        good = ("=== RISC-V SoC on DE2-115 ===" in text and re.search(r"EEPROM @0x50: .*PASS", text)
                and "(no card)" in text)
        res["SOC-06"] = ("PASS" if good else "FAIL", "banner, EEPROM PASS, SD (no card)")
    return res


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    skip = "--skip-programs" in sys.argv
    blocks = [a.upper() for a in args] or [u[0] for u in UNITS] + ["SOC"]
    os.makedirs(REPORT, exist_ok=True)
    table = {}
    for block, top, n in UNITS:
        if block in blocks:
            if block in CLASS_TB:
                print("running tests of tb_%s ..." % CLASS_TB[block], flush=True)
                table.update(class_results(block, CLASS_TB[block], n))
            else:
                print("running tb_%s ..." % top, flush=True)
                table.update(unit_results(block, top, n))
    if not skip:
        print("running riscv-tests and firmware ...", flush=True)
        table.update(program_results(blocks))
    rows = []
    order = [u[0] for u in UNITS] + ["SOC"]
    counts = {"PASS": 0, "FAIL": 0, "NOT RUN": 0}
    for block in order:
        if block not in blocks:
            continue
        n = dict((u[0], u[2]) for u in UNITS).get(block, 6)
        for i in range(1, n + 1):
            iid = "%s-%02d" % (block, i)
            st, det = table.get(iid, ("NOT RUN", ""))
            if st == "EXT":
                st, det = "NOT RUN", "program item, run without --skip-programs"
            counts[st] = counts.get(st, 0) + 1
            rows.append((iid, st, det))
    with open(os.path.join(REPORT, "vplan_results.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["ID", "Result", "Detail"])
        w.writerows(rows)
    print()
    for iid, st, det in rows:
        print("%-9s %-8s %s" % (iid, st, det))
    print()
    for block in order:
        if block in blocks:
            r = [x for x in rows if x[0].startswith(block + "-")]
            print("%-6s %3d items: %3d PASS, %3d FAIL, %3d NOT RUN" % (
                block, len(r), sum(x[1] == "PASS" for x in r), sum(x[1] == "FAIL" for x in r),
                sum(x[1] == "NOT RUN" for x in r)))
    print("TOTAL  %3d items: %3d PASS, %3d FAIL, %3d NOT RUN" % (
        len(rows), counts["PASS"], counts["FAIL"], counts["NOT RUN"]))
    print("CSV: sim/report/vplan_results.csv")
    for note in NOTES:
        print("note: " + note)
    sys.exit(1 if counts["FAIL"] or NOTES else 0)


if __name__ == "__main__":
    main()
