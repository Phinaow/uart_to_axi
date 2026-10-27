"""Client wire contract, fragmented I/O and failures without automatic retries."""
import struct

import pytest

from uart_axi import AxiError, ProtocolError, UartAxi


class Transport:
    def __init__(self, response, fragment=3):
        self.response = bytearray(response)
        self.sent = bytearray()
        self.fragment = fragment

    def write(self, data):
        count = min(len(data), self.fragment)
        self.sent.extend(data[:count])
        return count

    def read(self, count):
        count = min(count, self.fragment)
        data = bytes(self.response[:count])
        del self.response[:count]
        return data


def words(*values):
    return struct.pack("<" + "I" * len(values), *values)


def test_legacy_and_extended_client_wire_contract():
    transport = Transport(b"RESP" + words(17) + b"OKAY" + words(42) + b"OKAY"
                          + words(0x0100FFFF, 123, 2, 0, 7, 0, 8, 3, 0, 2))
    client = UartAxi(transport)
    client.ping()
    assert client.counter() == 17
    client.write32(0x1000, 42)
    assert client.read32(0x1000) == 42
    assert client.info() == {"version": 1, "max_words": 256, "capabilities": 255}
    assert client.read_result(0x1000).status == 2
    assert client.write_masked(0x1000, 0xAA, 1).status == 0
    results = client.read_block(0x2000, 2, fixed=True, check=False)
    assert [(r.data, r.status) for r in results] == [(7, 0), (8, 3)]
    results = client.write_block(0x3000, [9, 10], check=False)
    assert [r.status for r in results] == [0, 2]
    assert bytes(transport.sent) == (b"CMDATEMPWRIT" + words(0x1000, 42)
        + b"READ" + words(0x1000) + b"INFORDEX" + words(0x1000)
        + b"WMSK" + words(0x1000, 0xAA, 1) + b"RBLK" + words(0x2000, 0x10002)
        + b"WBLK" + words(0x3000, 2, 9, 10))
    assert not transport.response


def test_axi_error_consumes_whole_block_and_preserves_results():
    transport = Transport(words(11, 2, 12, 0) + b"RESP")
    client = UartAxi(transport)
    with pytest.raises(AxiError) as error:
        client.read_block(0, 2)
    assert [r.data for r in error.value.results] == [11, 12]
    client.ping()


@pytest.mark.parametrize("response", [b"", b"O", b"BAD!", words(9)])
def test_bad_or_truncated_response_prevents_reuse(response):
    transport = Transport(response)
    client = UartAxi(transport)
    with pytest.raises(ProtocolError):
        client.write_masked(0, 42)
    sent = bytes(transport.sent)
    with pytest.raises(ProtocolError):
        client.ping()
    assert bytes(transport.sent) == sent


@pytest.mark.parametrize("operation", [
    lambda c: c.write_masked(0, 1, 16),
    lambda c: c.write32(-1, 0),
    lambda c: c.read_block(0, 0),
    lambda c: c.read_block(0, 257),
    lambda c: c.read_block(0xFFFFFFFC, 2),
    lambda c: c.write_block(0, []),
    lambda c: c.write_block(0, [0x100000000]),
])
def test_invalid_arguments_send_nothing(operation):
    transport = Transport(b"")
    with pytest.raises(ValueError):
        operation(UartAxi(transport))
    assert not transport.sent
