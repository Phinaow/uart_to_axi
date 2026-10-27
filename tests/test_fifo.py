"""FIFO: a deque oracle checks full/empty, boundary rejection and pointer wrap."""
from collections import deque
import os
import random

import cocotb
from cocotb.triggers import Timer
import pytest


@cocotb.test()
async def capacity_wrap_and_simultaneous_operations(dut):
    depth = int(os.environ["TEST_DEPTH"])
    reference = deque()
    rng = random.Random(0xF1F0)

    async def cycle(write=False, read=False, reset=False):
        dut.clk.value = 0
        dut.rst.value = int(reset)
        dut.wr_en.value = int(write)
        dut.rd_en.value = int(read)
        data = rng.getrandbits(len(dut.wr_data))
        dut.wr_data.value = data
        await Timer(5, unit="ns")
        if not reset:
            assert int(dut.full.value) == int(len(reference) == depth)
            assert int(dut.empty.value) == int(not reference)
            push = write and len(reference) < depth
            pop = read and bool(reference)
            if pop:
                assert int(dut.rd_data.value) == reference.popleft()
            if push:
                reference.append(data)
        else:
            reference.clear()
        dut.clk.value = 1
        await Timer(5, unit="ns")
        assert int(dut.full.value) == int(len(reference) == depth)
        assert int(dut.empty.value) == int(not reference)

    await cycle(reset=True)
    for _ in range(3):
        for _ in range(depth):
            await cycle(write=True)
        await cycle(write=True)
        await cycle(write=True, read=True)
        for _ in range(depth):
            await cycle(read=True)
        await cycle(read=True)
    for _ in range(2000):
        await cycle(write=bool(rng.getrandbits(1)), read=bool(rng.getrandbits(1)))
    await cycle(reset=True)


@pytest.mark.parametrize("runner", [{"DEPTH": depth} for depth in (1, 2, 3, 16, 256)], indirect=True)
def test_fifo(runner):
    runner.test(hdl_toplevel="fifo", test_module=__name__, test_args=["--trace"],
                extra_env={"TEST_DEPTH": str(runner.parameters["DEPTH"])})
