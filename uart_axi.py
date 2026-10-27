"""Synchronous UART-to-AXI-Lite client; transport implements read/write.

No automatic retries: a timed-out write may already have taken effect.
"""
from dataclasses import dataclass
import struct
import threading


class ProtocolError(RuntimeError):
    """Unexpected or truncated serial response; reset before reuse."""


class AxiError(RuntimeError):
    """Completed transaction with an AXI error response."""

    def __init__(self, results):
        self.results = results
        super().__init__(f"AXI access failed: {results}")


@dataclass(frozen=True)
class Result:
    data: int | None
    status: int


def _word(value):
    if not isinstance(value, int) or not 0 <= value <= 0xFFFFFFFF:
        raise ValueError("Expected an unsigned 32-bit integer")
    return struct.pack("<I", value)


class UartAxi:
    """Use with a finite-timeout pyserial port, or an equivalent transport.

    One instance owns the transport. Calls are serialized, never retried.
    After a transport/protocol failure this instance cannot be reused.
    """

    def __init__(self, transport):
        self.transport = transport
        self._lock = threading.Lock()
        self._broken = False

    def _exchange(self, request, size):
        with self._lock:
            if self._broken:
                raise ProtocolError("Connection state unknown; reset hardware and create a new client")
            try:
                offset = 0
                while offset < len(request):
                    count = self.transport.write(request[offset:])
                    if count is None or count <= 0 or count > len(request) - offset:
                        raise ProtocolError("Incomplete UART write")
                    offset += count
                response = bytearray()
                while len(response) < size:
                    chunk = self.transport.read(size - len(response))
                    if not chunk:
                        raise ProtocolError(f"UART timeout: received {len(response)}/{size} bytes")
                    response.extend(chunk)
                return bytes(response)
            except Exception:
                self._broken = True
                raise

    def ping(self):
        if self._exchange(b"CMDA", 4) != b"RESP":
            self._broken = True
            raise ProtocolError("Invalid CMDA response")

    def counter(self):
        return int.from_bytes(self._exchange(b"TEMP", 4), "little")

    def info(self):
        raw = int.from_bytes(self._exchange(b"INFO", 4), "little")
        if raw >> 24 != 1:
            self._broken = True
            raise ProtocolError("Unsupported protocol version")
        return {"version": raw >> 24, "max_words": ((raw >> 8) & 0xFFFF) + 1,
                "capabilities": raw & 0xFF}

    def read32(self, address):
        response = self._exchange(b"READ" + _word(address), 8)
        self._legacy_status(response[4:])
        return int.from_bytes(response[:4], "little")

    def write32(self, address, value):
        self._legacy_status(self._exchange(b"WRIT" + _word(address) + _word(value), 4))

    def _legacy_status(self, status):
        if status == b"ERR!":
            raise AxiError([Result(None, -1)])
        if status != b"OKAY":
            self._broken = True
            raise ProtocolError(f"Invalid status: {status!r}")

    def _check(self, results, check):
        if any(result.status not in range(4) for result in results):
            self._broken = True
            raise ProtocolError("Invalid AXI status word")
        if check and any(result.status != 0 for result in results):
            raise AxiError(results)
        return results

    def read_result(self, address, *, check=False):
        data, status = struct.unpack("<II", self._exchange(b"RDEX" + _word(address), 8))
        return self._check([Result(data, status)], check)[0]

    def write_masked(self, address, value, mask=15, *, check=True):
        if not isinstance(mask, int) or not 0 <= mask <= 15:
            raise ValueError("Mask must be between 0 and 15")
        request = b"WMSK" + _word(address) + _word(value) + _word(mask)
        status = int.from_bytes(self._exchange(request, 4), "little")
        return self._check([Result(None, status)], check)[0]

    @staticmethod
    def _control(address, count, fixed):
        _word(address)
        if not isinstance(count, int) or not 1 <= count <= 256:
            raise ValueError("Block length must be between 1 and 256")
        if not fixed and address + 4 * (count - 1) > 0xFFFFFFFF:
            raise ValueError("Block address would overflow")
        return _word(count | (bool(fixed) << 16))

    def read_block(self, address, count, *, fixed=False, check=True):
        control = self._control(address, count, fixed)
        raw = self._exchange(b"RBLK" + _word(address) + control, count * 8)
        results = [Result(data, status) for data, status in struct.iter_unpack("<II", raw)]
        return self._check(results, check)

    def write_block(self, address, values, *, fixed=False, check=True):
        values = list(values)
        control = self._control(address, len(values), fixed)
        request = b"WBLK" + _word(address) + control + b"".join(map(_word, values))
        raw = self._exchange(request, len(values) * 4)
        results = [Result(None, status) for (status,) in struct.iter_unpack("<I", raw)]
        return self._check(results, check)
