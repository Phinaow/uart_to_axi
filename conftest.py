"""Build UART-only DUTs independently of the cache project's test fixture."""
from pathlib import Path
import sys

import pytest
from cocotb_tools.runner import get_runner

UART_ROOT = Path(__file__).resolve().parent
RTL_ROOT = UART_ROOT / "src"
sys.path.insert(0, str(UART_ROOT / "tests"))

SOURCES = {
    name: [f"{name}.sv"]
    for name in ("fifo", "r_buffer", "t_buffer", "uart_rx", "uart_tx", "data_to_axi")
}
SOURCES["uart_to_axi"] = [
    "uart_rx.sv", "uart_tx.sv", "r_buffer.sv", "t_buffer.sv",
    "data_to_axi.sv", "uart_to_axi.sv",
]
SOURCES["top_uart"] = [
    "uart_rx.sv", "uart_tx.sv", "r_buffer.sv", "t_buffer.sv",
    "fifo.sv", "top_uart.sv",
]


@pytest.fixture
def runner(request):
    top = request.module.__name__.split(".")[-1].removeprefix("test_")
    parameters = getattr(request, "param", {})
    if top == "uart_to_cache":
        cache_root = UART_ROOT.parent
        manifest = cache_root / "src/cache.f"
        if not manifest.exists():
            pytest.fail("Optional cache integration requires ../src/cache.f and its RTL sources")
        sources = [cache_root / line.strip() for line in manifest.read_text().splitlines()
                   if line.strip()]
        sources += [RTL_ROOT / name for name in SOURCES["uart_to_axi"]]
        sources += [RTL_ROOT / "uart_to_cache.sv", cache_root / "src/top_cache.sv",
                    UART_ROOT / "cache_integration/rtl/adam_mig_model.sv",
                    UART_ROOT / "cache_integration/rtl/clk_ref_mig_model.sv"]
    else:
        if top not in SOURCES:
            pytest.fail(f"No UART source list configured for {top}")
        sources = [RTL_ROOT / name for name in SOURCES[top]]
    configuration = "_".join(f"{name}_{value}" for name, value in sorted(parameters.items()))
    build_name = f"{top}_{configuration}" if configuration else top
    sim = get_runner("verilator")
    sim.build(
        sources=sources,
        hdl_toplevel=top,
        build_dir=UART_ROOT / "sim_build/tests" / build_name,
        parameters=parameters,
        build_args=[
            "--assert", "--trace-vcd", "--trace-structs", "-Wno-MULTIDRIVEN",
            "-CFLAGS", "-DVM_TRACE=1", "-CFLAGS", "-DVM_TRACE_VCD=1",
        ],
    )
    return sim
