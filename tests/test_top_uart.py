"""Serial burst loopback checks all UART/buffer/FIFO connections together."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, with_timeout
import pytest

from serial_link import send_bytes, receive_bytes


@cocotb.test()
async def complete_bursts_are_echoed_in_order(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.sys_rst.value = 0
    dut.rx.value = 1
    for _ in range(4):
        await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.sys_rst.value = 1
    for burst in (bytes(range(12)), bytes(range(100, 112))):
        response = cocotb.start_soon(receive_bytes(dut.tx, len(burst)))
        await send_bytes(dut.rx, burst)
        assert await with_timeout(response, 100, "us") == burst


@pytest.mark.parametrize("runner", [{"CLK_FREQ": 8000000, "UART_BAUD_RATE": 1000000,
                                     "DATA_WIDTH": 32, "BURST_LEN": 3}], indirect=True)
def test_top_uart(runner):
    runner.test(hdl_toplevel="top_uart", test_module=__name__, test_args=["--trace"])
