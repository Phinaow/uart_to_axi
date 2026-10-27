"""Exercise RX from an independent 8N1 source, including framing and overrun."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer
import pytest


async def transmit_frame(dut, word, bit_time=80, stop=1):
    for bit in [0] + [(word >> i) & 1 for i in range(len(dut.mst_data))] + [stop]:
        dut.rx.value = bit
        await Timer(bit_time, unit="ns")
    dut.rx.value = 1


@cocotb.test()
async def byte_values_stalls_and_bad_frames(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.rst.value = 1
    dut.rx.value = 1
    dut.mst_ready.value = 0
    errors = {"framing": 0, "overrun": 0}

    async def watch_errors():
        while True:
            await FallingEdge(dut.clk)
            errors["framing"] += int(dut.framing_error_o.value)
            errors["overrun"] += int(dut.overrun_error_o.value)

    cocotb.start_soon(watch_errors())
    for _ in range(3):
        await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.rst.value = 0
    for word in range(256):
        # Sweep phase and a small transmitter baud mismatch.
        await Timer(3, unit="ns")
        await transmit_frame(dut, word, bit_time=79 + word % 3)
        for _ in range(4):
            await FallingEdge(dut.clk)
            assert dut.mst_valid.value and int(dut.mst_data.value) == word
        dut.mst_ready.value = 1
        await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)
        dut.mst_ready.value = 0
    assert errors == {"framing": 0, "overrun": 0}
    await transmit_frame(dut, 0x55, stop=0)
    await Timer(160, unit="ns")
    assert not dut.mst_valid.value and errors["framing"] >= 1
    await transmit_frame(dut, 0x12)
    await transmit_frame(dut, 0x34)
    await Timer(80, unit="ns")
    assert dut.mst_valid.value and int(dut.mst_data.value) == 0x12
    assert errors["overrun"] == 1


@pytest.mark.parametrize("runner", [{"CLK_FREQ": 8000000, "BAUD_RATE": 1000000}], indirect=True)
def test_uart_rx(runner):
    runner.test(hdl_toplevel="uart_rx", test_module=__name__, test_args=["--trace"])
