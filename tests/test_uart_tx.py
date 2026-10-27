"""Decode the actual TX pin independently; do not rely on our RX implementation."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer, with_timeout
import pytest


async def receive_frame(dut, bit_time):
    await FallingEdge(dut.tx)
    await Timer(bit_time / 2, unit="ns")
    assert dut.tx.value == 0, "Missing start bit"
    result = 0
    for bit in range(len(dut.slv_data)):
        await Timer(bit_time, unit="ns")
        result |= int(dut.tx.value) << bit
    await Timer(bit_time, unit="ns")
    assert dut.tx.value == 1, "Missing stop bit"
    return result


@cocotb.test()
async def all_byte_values_and_captured_input(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.rst.value = 1
    dut.slv_valid.value = 0
    dut.slv_data.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.rst.value = 0
    for word in range(1 << len(dut.slv_data)):
        receiver = cocotb.start_soon(receive_frame(dut, 80))
        for _ in range(100):
            await FallingEdge(dut.clk)
            if dut.slv_ready.value:
                break
        else:
            raise AssertionError("TX did not become ready")
        dut.slv_data.value = word
        dut.slv_valid.value = 1
        await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)
        dut.slv_valid.value = 0
        dut.slv_data.value = word ^ ((1 << len(dut.slv_data)) - 1)
        assert not dut.slv_ready.value
        assert await with_timeout(receiver, 2, "us") == word
    await Timer(160, unit="ns")
    assert dut.tx.value == 1 and dut.slv_ready.value


@pytest.mark.parametrize("runner", [{"CLK_FREQ": 8000000, "BAUD_RATE": 1000000}], indirect=True)
def test_uart_tx(runner):
    runner.test(hdl_toplevel="uart_tx", test_module=__name__, test_args=["--trace"])
