"""Transmit buffer: accepted words become exactly one ordered fragment stream."""
import random

import cocotb
from cocotb.triggers import Timer
import pytest


async def cycle(dut):
    dut.clk.value = 0
    await Timer(5, unit="ns")
    sample = (bool(dut.slv_ready.value), bool(dut.uart_slv_valid.value), int(dut.uart_slv_data.value))
    dut.clk.value = 1
    await Timer(5, unit="ns")
    return sample


@cocotb.test()
async def accepted_words_are_serialized_under_backpressure(dut):
    rng = random.Random(321)
    fragment_width = len(dut.uart_slv_data)
    chunks = len(dut.slv_data) // fragment_width
    words = [rng.getrandbits(len(dut.slv_data)) for _ in range(100)]
    expected = [(word >> (fragment_width * chunk)) & ((1 << fragment_width) - 1)
                for word in words for chunk in range(chunks)]
    dut.rst.value = 1
    dut.enable.value = 1
    dut.slv_valid.value = 0
    dut.slv_data.value = 0
    dut.uart_slv_ready.value = 0
    await cycle(dut)
    dut.rst.value = 0
    sent = received = 0
    held = None
    for tick in range(10000):
        valid = sent < len(words) and rng.randrange(4) != 0
        ready = tick % 37 > 15 and rng.randrange(3) != 0
        dut.slv_valid.value = int(valid)
        dut.slv_data.value = words[sent] if sent < len(words) else 0
        dut.uart_slv_ready.value = int(ready)
        word_ready, fragment_valid, data = await cycle(dut)
        if held is not None:
            assert fragment_valid and data == held, "Fragment changed during backpressure"
        held = data if fragment_valid and not ready else None
        if valid and word_ready:
            sent += 1
        if fragment_valid and ready:
            assert received < sent * chunks, "Data appeared before word acceptance"
            assert data == expected[received]
            received += 1
        if received == len(expected):
            break
    else:
        raise AssertionError(f"Transmit buffer stalled: sent={sent}, received={received}")
    assert sent == len(words)
    dut.slv_valid.value = 0
    dut.enable.value = 0
    await cycle(dut)
    assert not dut.slv_ready.value and not dut.uart_slv_valid.value
    dut.enable.value = 1
    await cycle(dut)
    assert dut.slv_ready.value and not dut.uart_slv_valid.value


@pytest.mark.parametrize("runner", [
    {"DATA_WIDTH": 32, "UART_DATA_WIDTH": 8},
    {"DATA_WIDTH": 16, "UART_DATA_WIDTH": 4},
    {"DATA_WIDTH": 8, "UART_DATA_WIDTH": 8},
], indirect=True)
def test_t_buffer(runner):
    runner.test(hdl_toplevel="t_buffer", test_module=__name__, test_args=["--trace"])
