# UART → AXI-Lite scope

Read [README.md](README.md) before making changes. Instructions from the parent
repository still apply in this workspace.

- Communicate with the user in French; write documentation, code comments and
  docstrings in English.
- The reusable component is `uart_to_axi`, a 32-bit AXI-Lite master. Its minimal
  six-source list is in the README and `conftest.py`; RTL sources are in `src/`.
- Local work is limited to this directory. Do not modify the cache, ADAM, IP
  blocks or physical constraints for changes affecting only the UART bridge.
- Keep Cocotb, independent references, RTL assertions and separate builds for each
  configuration. Reference commands are in the README.
- `tests/` is the local suite, initially copied from `../test/`. Do not import its
  helpers from the parent repository. `COPIED_FROM.json` records initial
  provenance; it does not require the copies to remain identical.
- The parent originals remain available. A local change does not automatically
  update its regression; document divergences and carry over relevant fixes if
  the requested scope includes the parent.
- The `cache_integration/` test is optional and depends on `../src/`. Its MIG and
  clock models must never be included in a physical build.
- Read the protocol limitations before extending it: one command at a time,
  full `WSTRB` for legacy writes and blocks (explicit masks through `WMSK`), no
  timeout or CRC, and UART errors requiring reset. Do not promise recovery or
  cancellation of a write that has already started.
- Protocol changes require a specification of request and response bytes,
  updated documentation and serial → AXI → serial tests.
- Do not use the DDR hardware test as a generic AXI peripheral test: it
  deliberately writes memory. Local tests do not require FPGA programming.
