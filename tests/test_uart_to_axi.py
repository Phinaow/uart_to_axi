"""UART commands against an independent AXI-Lite memory, including errors."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer, with_timeout
import pytest

from axi_lite_slave import AxiLiteSlave
from serial_link import send_bytes, receive_bytes


@cocotb.test()
async def command_protocol_and_axi_errors(dut):
    slave = AxiLiteSlave(dut)
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    cocotb.start_soon(slave.run())
    dut.rst.value = 1
    dut.rx.value = 1
    dut.cycle_ct.value = 0x1234
    for _ in range(4):
        await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.rst.value = 0

    async def command(request, expected):
        response = cocotb.start_soon(receive_bytes(dut.tx, len(expected)))
        await send_bytes(dut.rx, request)
        assert await with_timeout(response, 100, "us") == expected
        assert not dut.rx_error_o.value

    await command(b"CMDA", b"RESP")
    await command(b"????", b"????")
    await command(b"TEMP", (0x1234).to_bytes(4, "little"))
    address = (0x1000).to_bytes(4, "little")
    data = (0xDEADBEEF).to_bytes(4, "little")
    await command(b"WRIT" + address + data, b"OKAY")
    await command(b"READ" + address, data + b"OKAY")
    slave.next_write_status = 2
    await command(b"WRIT" + address + data, b"ERR!")
    slave.next_read_status = 2
    await command(b"READ" + address, data + b"ERR!")
    assert len(slave.events) == 4
    # A corrupt serial byte invalidates framing: halt until reset, no shifted write.
    response = cocotb.start_soon(receive_bytes(dut.tx, 4))
    for bit in [0] + [1] * 8 + [0]:
        dut.rx.value = bit
        await Timer(80, unit="ns")
    dut.rx.value = 1
    assert await with_timeout(response, 100, "us") == b"ERR!"
    assert dut.rx_error_o.value
    await send_bytes(dut.rx, b"WRIT" + address + data)
    assert len(slave.events) == 4
    await FallingEdge(dut.clk)
    dut.rst.value = 1
    for _ in range(4):
        await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.rst.value = 0
    await command(b"CMDA", b"RESP")


@pytest.mark.parametrize("runner", [{"CLK_FREQ": 8000000, "BAUD_RATE": 1000000}], indirect=True)
def test_uart_to_axi(runner):
    runner.test(hdl_toplevel="uart_to_axi", test_module=__name__, test_args=["--trace"])


@cocotb.test()
async def extended_commands_masks_blocks_and_bounds(dut):
    import struct
    slave = AxiLiteSlave(dut)
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    cocotb.start_soon(slave.run())
    dut.rst.value = 1
    dut.rx.value = 1
    dut.cycle_ct.value = 0
    for _ in range(4):
        await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.rst.value = 0

    def words(*values):
        return struct.pack("<" + "I" * len(values), *values)

    async def exchange(request, expected):
        response = cocotb.start_soon(receive_bytes(dut.tx, len(expected)))
        await send_bytes(dut.rx, request)
        assert await with_timeout(response, 10, "ms") == expected
        assert not dut.rx_error_o.value

    await exchange(b"INFO", words(0x0100FFFF))
    for mask in range(16):
        slave.memory[0x1000] = 0x12345678
        slave.next_write_status = mask % 4
        await exchange(b"WMSK" + words(0x1000, 0xABCDEF01, mask), words(mask % 4))
        expected = sum(((0xABCDEF01 if mask & (1 << lane) else 0x12345678)
                        >> (lane * 8) & 255) << (lane * 8) for lane in range(4))
        assert slave.memory[0x1000] == expected
    for status in range(4):
        slave.next_read_status = status
        await exchange(b"RDEX" + words(0x1000), words(slave.memory[0x1000], status))

    for fixed in (False, True):
        for count in (1, 3, 256):
            values = [0xCAFE0000 + index for index in range(count)]
            control = count | (int(fixed) << 16)
            before = len(slave.events)
            slave.next_write_status = 2
            await exchange(b"WBLK" + words(0x2000, control, *values),
                           words(2, *([0] * (count - 1))))
            events = slave.events[before:]
            assert events == [("write", 0x2000 + (0 if fixed else index * 4), value)
                              for index, value in enumerate(values)]
            slave.next_read_status = 3
            expected = b"".join(words(values[-1] if fixed else value, 3 if index == 0 else 0)
                                for index, value in enumerate(values))
            await exchange(b"RBLK" + words(0x2000, control), expected)

    before = len(slave.events)
    for command in (b"RBLK", b"WBLK"):
        for address, control in ((0, 0), (0, 257), (0, 0x20001), (0xFFFFFFFC, 2)):
            await exchange(command + words(address, control), b"ERR!")
    await exchange(b"WMSK" + words(0, 1, 16), b"ERR!")
    assert len(slave.events) == before
    await exchange(b"RBLK" + words(0xFFFFFFFC, 0x10002),
                   words(0x12345678, 0, 0x12345678, 0))
    await exchange(b"RBLK" + words(0xFFFFFFF8, 2),
                   words(0x12345678, 0, 0x12345678, 0))
    # A zero mask must not leak into the next legacy full-word write.
    await exchange(b"WMSK" + words(0x3000, 0, 0), words(0))
    # Legacy traffic still works after every extended operation and error.
    await exchange(b"WRIT" + words(0x3000, 0xDEADBEEF), b"OKAY")
    await exchange(b"READ" + words(0x3000), words(0xDEADBEEF) + b"OKAY")


@cocotb.test()
async def reset_partial_block_and_fault_during_axi(dut):
    slave = AxiLiteSlave(dut)
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    cocotb.start_soon(slave.run())
    dut.rx.value = 1
    dut.cycle_ct.value = 0

    async def reset():
        await FallingEdge(dut.clk)
        dut.rst.value = 1
        for _ in range(4):
            await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)
        dut.rst.value = 0

    async def ping():
        response = cocotb.start_soon(receive_bytes(dut.tx, 4))
        await send_bytes(dut.rx, b"CMDA")
        assert await with_timeout(response, 100, "us") == b"RESP"

    await reset()
    # Incomplete staged block must not write anything, even after reset.
    await send_bytes(dut.rx, b"WBLK" + (0x1000).to_bytes(4, "little")
                     + (3).to_bytes(4, "little") + (42).to_bytes(4, "little"))
    assert not slave.events
    await reset()
    await ping()
    assert not slave.events

    # Keep B pending while corrupting a serial byte. The write is not cancelled.
    slave_task = cocotb.start_soon(send_bytes(dut.rx, b"WRIT"
        + (0x1000).to_bytes(4, "little") + (99).to_bytes(4, "little")))
    for _ in range(2000):
        await FallingEdge(dut.clk)
        if slave.events:
            slave.delay = 3000
            break
    else:
        raise AssertionError("Expected AXI write before fault injection")
    await slave_task
    response = cocotb.start_soon(receive_bytes(dut.tx, 4))
    for bit in [0] + [1] * 8 + [0]:
        dut.rx.value = bit
        await Timer(80, unit="ns")
    dut.rx.value = 1
    assert await with_timeout(response, 100, "us") == b"ERR!"
    assert dut.rx_error_o.value
    for _ in range(3100):
        await FallingEdge(dut.clk)
    assert slave.completed_writes == 1
    assert slave.memory[0x1000] == 99
    # A second framing fault stays silent: one report per reset.
    async def no_output():
        for _ in range(600):
            await FallingEdge(dut.clk)
            assert dut.tx.value == 1
    monitor = cocotb.start_soon(no_output())
    for bit in [0] + [1] * 8 + [0]:
        dut.rx.value = bit
        await Timer(80, unit="ns")
    dut.rx.value = 1
    await monitor
    await reset()
    await ping()
