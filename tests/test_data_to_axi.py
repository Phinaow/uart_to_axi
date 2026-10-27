"""Command bridge: captured operands, delayed B, error status and independent reads."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from axi_lite_slave import AxiLiteSlave


@cocotb.test()
async def concurrent_commands_capture_operands_and_wait_for_responses(dut):
    slave = AxiLiteSlave(dut)
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.rst.value = 1
    dut.start_write.value = 0
    dut.start_read.value = 0
    dut.write_receive.value = 0
    dut.read_receive.value = 0
    dut.w_addr.value = 0
    dut.w_data.value = 0
    dut.r_addr.value = 0
    cocotb.start_soon(slave.run())
    for _ in range(3):
        await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.rst.value = 0
    for command_index, status in enumerate((0, 2, 3, 0)):
        slave.next_write_status = status
        slave.next_read_status = status
        dut.w_addr.value = 0x1000
        dut.w_data.value = 0xDEADBEEF
        dut.r_addr.value = 0x2000
        dut.start_write.value = 1
        dut.start_read.value = 1
        await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)
        dut.start_write.value = 0
        dut.start_read.value = 0
        dut.w_addr.value = 0xFFFF
        dut.w_data.value = 0
        dut.r_addr.value = 0xFFFF
        for _ in range(100):
            await FallingEdge(dut.clk)
            assert not dut.write_done.value or slave.completed_writes == command_index + 1
            assert not dut.read_done.value or slave.completed_reads == command_index + 1
            if dut.write_done.value and dut.read_done.value:
                break
        else:
            raise AssertionError("Bridge command did not finish")
        assert int(dut.write_status.value) == status
        assert int(dut.read_status.value) == status
        assert int(dut.r_data.value) == 0x12345678
        assert slave.memory[0x1000] == 0xDEADBEEF
        for _ in range(5):
            await FallingEdge(dut.clk)
            assert dut.write_done.value and dut.read_done.value
        dut.write_receive.value = 1
        dut.read_receive.value = 1
        await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)
        dut.write_receive.value = 0
        dut.read_receive.value = 0
        assert not dut.write_done.value and not dut.read_done.value
    assert len(slave.events) == 8


def test_data_to_axi(runner):
    runner.test(hdl_toplevel="data_to_axi", test_module=__name__, test_args=["--trace"])
