"""AXI-Lite memory responder for UART bridge tests; AW and W are independent."""
import random

from cocotb.triggers import FallingEdge, RisingEdge, Timer


class AxiLiteSlave:
    def __init__(self, dut):
        self.dut = dut
        self.memory = {}
        self.events = []
        self.next_write_status = 0
        self.next_read_status = 0
        self.write_address = None
        self.write_data = None
        self.write_response = None
        self.read_response = None
        self.write_strobes = 15
        self.delay = 0
        self.completed_writes = 0
        self.completed_reads = 0
        self.rng = random.Random(2026)

    async def run(self):
        dut = self.dut
        while True:
            await FallingEdge(dut.clk)
            if dut.rst.value:
                self.write_address = self.write_data = None
                self.write_response = self.read_response = None
            dut.axi_awready.value = int(self.write_address is None and self.write_response is None and self.rng.randrange(3) != 0)
            dut.axi_wready.value = int(self.write_data is None and self.write_response is None and self.rng.randrange(3) != 0)
            dut.axi_arready.value = int(self.read_response is None and self.rng.randrange(3) != 0)
            dut.axi_bvalid.value = int(self.write_response is not None and self.delay == 0)
            dut.axi_bresp.value = self.write_response or 0
            dut.axi_rvalid.value = int(self.read_response is not None)
            dut.axi_rdata.value = self.read_response[0] if self.read_response else 0
            dut.axi_rresp.value = self.read_response[1] if self.read_response else 0
            await Timer(1, unit="ns")
            aw = bool(dut.axi_awvalid.value and dut.axi_awready.value)
            w = bool(dut.axi_wvalid.value and dut.axi_wready.value)
            ar = bool(dut.axi_arvalid.value and dut.axi_arready.value)
            b = bool(dut.axi_bvalid.value and dut.axi_bready.value)
            r = bool(dut.axi_rvalid.value and dut.axi_rready.value)
            address = int(dut.axi_awaddr.value)
            data = int(dut.axi_wdata.value)
            strobes = int(dut.axi_wstrb.value)
            read_address = int(dut.axi_araddr.value)
            await RisingEdge(dut.clk)
            if dut.rst.value:
                continue
            if aw:
                self.write_address = address
            if w:
                self.write_data = data
                self.write_strobes = strobes
            if ar:
                self.read_response = (self.memory.get(read_address, 0x12345678), self.next_read_status)
                self.next_read_status = 0
                self.events.append(("read", read_address))
            if b:
                self.completed_writes += 1
                self.write_response = None
                self.write_address = self.write_data = None
            if r:
                self.completed_reads += 1
                self.read_response = None
            if self.delay:
                self.delay -= 1
            if self.write_address is not None and self.write_data is not None and self.write_response is None:
                previous = self.memory.get(self.write_address, 0)
                mask = sum(0xFF << (8 * lane) for lane in range(4)
                           if self.write_strobes & (1 << lane))
                self.memory[self.write_address] = (previous & ~mask) | (self.write_data & mask)
                self.events.append(("write", self.write_address, self.write_data))
                self.write_response = self.next_write_status
                self.next_write_status = 0
                self.delay = 8
