# Using the UART → AXI-Lite bridge

## Hardware integration

Compile these six files and instantiate `uart_to_axi`:
`src/uart_rx.sv`, `src/uart_tx.sv`, `src/r_buffer.sv`, `src/t_buffer.sv`, `src/data_to_axi.sv`,
`src/uart_to_axi.sv`. No cache source files are required.

- Connect `clk` to the AXI-Lite slave clock and `rst` to an active-high synchronous reset.
- Set `CLK_FREQ` to the actual clock frequency and `BAUD_RATE` to the host baud rate
  (defaults: 100 MHz and 115200 baud; integer division, at least 4 cycles per bit).
- Connect all AXI-Lite channels and RX/TX, with a common ground and suitable electrical levels.
- Keep `ADDR_WIDTH=32`, `DATA_WIDTH=32`, `UART_DATA_WIDTH=8`.
- Connect `cycle_ct` to a counter or zero; `rx_error_o` indicates a serial error
  latched until reset. No additional ports are required.
- If the slave requires AWPROT/ARPROT, tie them to appropriate values in the integrating design.

Block transfers are successive AXI-Lite accesses, not AXI bursts.
The bridge processes one command at a time. Ports remain compatible with
previous integrations, and legacy commands retain their response formats.

## Writing a Python script

Using Python 3.10 or later, install `python -m pip install pyserial`, then place
`uart_axi.py` next to your script or on its Python import path. Example:

```python
import serial
from uart_axi import UartAxi, AxiError

with serial.Serial("/dev/serial/by-id/my-adapter", 115200,
                   timeout=2, write_timeout=2) as port:
    bridge = UartAxi(port)
    bridge.ping()                       # CMDA -> RESP, compatible with legacy RTL
    bridge.write32(0x1000, 0xDEADBEEF)   # WRIT -> OKAY
    assert bridge.read32(0x1000) == 0xDEADBEEF

    print(bridge.info())                # Requires the extended RTL
    bridge.write_masked(0x1000, 0xAA, mask=1)  # Least significant byte only
    bridge.write_block(0x2000, [10, 20, 30])
    values = [r.data for r in bridge.read_block(0x2000, 3)]
    assert values == [10, 20, 30]

    # Inspect every response without raising on AXI errors:
    results = bridge.read_block(0x2000, 3, check=False)
    for result in results:
        print(result.data, result.status)
```

Use `fixed=True` to repeat the same address (FIFOs/registers).
Blocks contain 1 to 256 words. `read_result()` also exposes the raw status of
an individual read; `counter()` reads the `cycle_ct` input.
`read32`, `write32`, `write_masked` and block operations report AXI errors through
`AxiError`. For new commands, the exception retains all results in
`exception.results`. By default, `read_result()` returns the status without raising.

The client handles fragmented serial reads and writes. Each instance exclusively
owns its port; calls are serialized. Set a finite timeout long enough for the
complete block and slave latency (at 115200 baud, a maximum-length RBLK transfer
uses approximately 180 ms of wire time, excluding AXI waits).

After a timeout or protocol error, perform a coordinated reset of the bridge and
slave, discard stale port bytes, then create a new client.
There are no automatic retries: a write may already have taken effect.
UART errors also require reset. No AXI timeout or CRC is provided.

The exact byte format is specified in [docs/PROTOCOL.md](docs/PROTOCOL.md).

## Checking an integration

```bash
./test_docker.sh                         # Standalone RTL and client tests
./test_docker.sh -q cache_integration     # With the cache from the parent directory
../scripts/test_docker.sh -q test/test_uart_to_axi.py test/test_uart_to_cache.py test/test_data_to_axi.py
```

The local command uses the existing `cache_design` container with this project
mounted directly at `/phinaow`. Python is taken from `/opt/cache-venv`, the
container-created `/phinaow/.venv`, or the legacy temporary venv.
Cache integration and parent tests require a separate mount exposing the parent
cache as well; it is not visible through the current UART-only mount. They do not program
the board. The cache test uses simulation-only MIG and clock substitutes.
Run the standalone synthesis check with `vivado -mode batch -source scripts/synth_uart.tcl`.
It does not replace timing and physical checks for the integrating design.
