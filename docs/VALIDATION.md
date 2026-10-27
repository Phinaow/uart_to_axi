# UART extension validation

Campaign dated October 22, 2026; sources are identified in
[VALIDATION_SOURCES.json](VALIDATION_SOURCES.json). No push, FPGA programming or
physical DDR writes were performed during this campaign.

## Standalone Docker mount — October 23, 2026

The current container mounts `/home/johann/cache/uart_src` directly at `/phinaow`.
The test launcher now also recognizes the container-created `/phinaow/.venv`,
validates test dependencies and libpython, and uses a non-login shell. No image
rebuild or environment replacement was needed.

- `./test_docker.sh`: **29 local pytest cases passed** in 40.49 seconds;
  log: `sim_build/docker_mount_regression.log`.
- Calling the launcher by absolute path from `/tmp` with
  `-q tests/test_client.py`: **13 cases passed**.
- RTL and client source hashes remain unchanged.

The parent cache is not exposed by this UART-only mount. Cache integration and
parent regression were not rerun in this container; their previous results below
refer to the earlier parent-directory mount.

## Source directory reorganization

The nine top-level `.sv` files were moved into `src/` by the local model through
OpenCode. Independent SHA256 comparisons confirmed that every source file was
preserved byte for byte. The two simulation-only models remain unchanged in
`cache_integration/rtl/`; no `.sv` source remains at the project root.

Local test paths, the standalone synthesis script, documentation and validation
source paths were updated. In the parent cache project, `test/conftest.py` and
`scripts/build_fpga.tcl` now resolve the UART sources under `uart_src/src/`.

Checks repeated after the move:

- Local suite and extended cache integration: **30 pytest cases passed**;
  log: `sim_build/src_reorganization.log`.
- Full parent cache regression: **44 pytest cases passed**;
  log: `sim_build/parent_src_reorganization.log`.
- Standalone Vivado synthesis using the new paths: passed;
  log: `sim_build/synthesis/console.log` (`UART_SYNTHESIS_PASS`).

No commit, push, FPGA programming or physical memory test was performed.

## Compatibility and tests

- `uart_to_axi` ports, parameters and default values were compared textually
  against a copy taken before modification: identical.
- Legacy CMDA/TEMP/WRIT/READ and unknown-command responses are checked byte for
  byte, including AXI errors.
- `./test_docker.sh -q tests cache_integration`: **30 pytest cases passed**
  (29 standalone cases, including 13 client tests, plus one cache integration).
  Log: `sim_build/final_regression.log`.
- The `test_uart_to_axi` pytest case runs three Cocotb scenarios: legacy protocol,
  extensions/bounds, then reset/incomplete block/fault during AXI.
- `../scripts/test_docker.sh -q test/test_uart_to_axi.py test/test_uart_to_cache.py test/test_data_to_axi.py`:
  **3 cases passed**, using the original parent tests and local UART sources.
- `../scripts/test_docker.sh -q test`: **44 cases passed** in the cache project.
  Those parent tests were not modified.

Extension coverage includes all 16 masks, all four AXI response codes,
blocks of 1/3/256 words, fixed/incrementing addresses, invalid control words
and masks, address overflow and valid upper address boundaries. Blocks continue
after an AXI error and return every status.
The extended cache test also checks a masked write, a 256-word block,
legacy eviction scenarios and address errors.

An incomplete WBLK block issues no write; reset discards it.
A serial fault while waiting for B produces ERR! and blocks commands,
but allows the issued write to finish. Further faults remain silent until reset.
RTL assertions check AXI request stability and retention of results under
backpressure.

The client is tested with fragmented reads/writes, independently specified
expected encodings, incomplete/invalid responses, invalid arguments and errors
within a block. It consumes every result before raising AxiError and never
retries automatically.

## Tools and synthesis

Cocotb 2.0.1, pytest 9.1.1 and Verilator 5.053 devel in `cache_design`.
The Python environment and libpython3.13 were installed temporarily in the
existing container, without rebuilding the image. The launcher uses
`/tmp/cache-cocotb-venv`; do not assume it will survive container replacement.

Verilator lint with `--lint-only --Wall` on all six sources: no warnings.
Verible lint on `uart_to_axi.sv` and `data_to_axi.sv`: no warnings.

`scripts/synth_uart.tcl` synthesizes the six standalone sources with Vivado 2025.2
for `xc7a200tsbg484-1`, in out-of-context mode. Reports, checkpoint and log are
under `sim_build/synthesis/`. The 1 KiB temporary WBLK buffer is inferred as
distributed RAM, without resetting its contents; only entries received for the
current command are used. Vivado synthesis ignores concurrent assertions,
but they remain enabled in simulation.

Synthesis passed with no errors or critical warnings: 596 LUTs and 430 registers,
including 128 LUTs for distributed RAM. The internal estimate at 100 MHz gives
WNS +2.678 ns; this is before placement/routing and does not constrain the future
integrating design's input/output delays.
The out-of-context CDC report identifies no unsafe paths; the skew report has
no constraints, since the bridge has a single clock domain.
DRC reports CFGBVS-1: board configuration voltages are not defined in this
standalone check. Vivado also warns that some DRCs are not run out of context
and that HD.CLK_SRC is missing for clock skew estimation. These limitations
are not masked.

## Limitations

No true AXI bursts, atomicity, CRC, AXI timeout, cancellation or recovery without
reset after a serial error. The top remains AXI-Lite. A stalled slave can block
a command indefinitely. An error does not guarantee the absence of side effects;
the Python model may modify memory even when returning a B error.

A fault during transmission may leave a partial response followed by ERR!;
the client must then treat the dialogue state as unknown and coordinate a reset
before reuse. Resets at every cycle of every channel, metastability and all
baud-rate variations are not covered.

Out-of-context synthesis does not prove physical closure of the cache integration.
No new complete bitstream or board test was performed; the parent's previous
hardware results do not validate this extended RTL. Timing/CDC/DRC/skew checks
for the complete design must be repeated before claiming new physical validation.
