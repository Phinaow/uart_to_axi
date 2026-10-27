"""Independent 8N1 source and sink for serial integration tests."""
from cocotb.triggers import FallingEdge, Timer


async def send_bytes(rx, data, bit_time=80):
    for byte in data:
        for bit in [0] + [(byte >> index) & 1 for index in range(8)] + [1]:
            rx.value = bit
            await Timer(bit_time, unit="ns")
    rx.value = 1


async def receive_bytes(tx, count, bit_time=80):
    result = bytearray()
    for _ in range(count):
        await FallingEdge(tx)
        await Timer(bit_time * 1.5, unit="ns")
        byte = 0
        for bit in range(8):
            byte |= int(tx.value) << bit
            await Timer(bit_time, unit="ns")
        assert tx.value == 1, "Missing serial stop bit"
        result.append(byte)
    return bytes(result)
