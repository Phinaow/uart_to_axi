"""Receive buffer: fragment order, backpressure, held words and disable flush."""
import random

import cocotb
from cocotb.triggers import Timer
import pytest


async def cycle(dut):
    dut.clk.value = 0
    await Timer(5, unit="ns")
    sample = (bool(dut.uart_mst_ready.value), bool(dut.mst_valid.value), int(dut.mst_data.value))
    dut.clk.value = 1
    await Timer(5, unit="ns")
    return sample


@cocotb.test()
async def fragments_are_assembled_once_and_held(dut):
    rng = random.Random(123)
    fragment_width = len(dut.uart_mst_data)
    chunks = len(dut.mst_data) // fragment_width
    words = [rng.getrandbits(len(dut.mst_data)) for _ in range(100)]
    fragments = [(word >> (fragment_width * chunk)) & ((1 << fragment_width) - 1)
                 for word in words for chunk in range(chunks)]
    dut.rst.value = 1
    dut.enable.value = 1
    dut.uart_mst_valid.value = 0
    dut.uart_mst_data.value = 0
    dut.mst_ready.value = 0
    await cycle(dut)
    dut.rst.value = 0
    sent = received = 0
    held = None
    for tick in range(10000):
        valid = sent < len(fragments) and rng.randrange(4) != 0
        ready = tick % 37 > 15 and rng.randrange(3) != 0
        dut.uart_mst_valid.value = int(valid)
        dut.uart_mst_data.value = fragments[sent] if sent < len(fragments) else 0
        dut.mst_ready.value = int(ready)
        fragment_ready, word_valid, data = await cycle(dut)
        if held is not None:
            assert word_valid and data == held, "Word changed during backpressure"
        held = data if word_valid and not ready else None
        if valid and fragment_ready:
            sent += 1
        if word_valid and ready:
            assert data == words[received]
            received += 1
        if received == len(words):
            break
    else:
        raise AssertionError(f"Receive buffer stalled: sent={sent}, received={received}")
    assert sent == len(fragments)
    dut.uart_mst_valid.value = 0
    dut.enable.value = 0
    await cycle(dut)
    assert not dut.mst_valid.value and not dut.uart_mst_ready.value
    dut.enable.value = 1
    await cycle(dut)
    assert not dut.mst_valid.value and dut.uart_mst_ready.value


@pytest.mark.parametrize("runner", [
    {"DATA_WIDTH": 32, "UART_DATA_WIDTH": 8},
    {"DATA_WIDTH": 16, "UART_DATA_WIDTH": 4},
    {"DATA_WIDTH": 8, "UART_DATA_WIDTH": 8},
], indirect=True)
def test_r_buffer(runner):
    runner.test(hdl_toplevel="r_buffer", test_module=__name__, test_args=["--trace"])
