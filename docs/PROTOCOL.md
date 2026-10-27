# Extended UART protocol — version 1

Top-level ports and parameters remain unchanged. UART uses 8N1 and little-endian
32-bit words. Send one complete request, then receive its complete response;
there is no pipelining. Legacy commands and their responses are unchanged.

| ASCII command | Following words | Response |
|---|---|---|
| `CMDA` | none | `RESP` |
| `TEMP` | none | 32-bit counter |
| `WRIT` | address, data | `OKAY` or `ERR!` |
| `READ` | address | data, `OKAY` or `ERR!` |
| `INFO` | none | `0x0100FFFF`: major version 1, maximum 256 words, capabilities 0xFF |
| `RDEX` | address | data, AXI status in a 32-bit word |
| `WMSK` | address, data, mask | AXI status in a 32-bit word |
| `RBLK` | address, control | N pairs of (data, AXI status) |
| `WBLK` | address, control, N data words | N AXI status words |

Raw statuses are 0/1/2/3 (OKAY/EXOKAY/SLVERR/DECERR), with upper bits zero.
`WMSK` accepts only mask bits 3:0, one bit per WDATA byte.
A zero mask is passed through unchanged. Blocks use WSTRB=15.

Control: bits 15:0 = N (1 to 256), bit 16 = fixed address; all other bits zero.
Otherwise, the address increases by four after each access. An incrementing block
exceeding 0xFFFFFFFF is rejected. The bridge does not filter unaligned addresses.
Each access is an independent AXI-Lite transaction, without atomicity or true
AXI bursts. AXI errors do not stop the block; every status is returned.

An invalid control word or mask returns only `ERR!`, without any AXI access.
For an invalid WBLK control word, do not send data: the response is immediate;
a client must validate the control word before sending its request.
All data for a valid WBLK request is received before the first AXI access.

There is no CRC, AXI timeout, cancellation, automatic retry or recovery after a
UART error. An undetected lost byte can misalign the protocol. A host timeout
leaves the dialogue state unknown; coordinated reset is required before reuse.
An issued write may already have taken effect even if an error is reported.

INFO capabilities (bits 7:0): RDEX, WMSK, RBLK, WBLK, fixed address,
incrementing address, raw statuses, and reception of all WBLK data before execution.
Bits 23:8 encode the maximum word count minus one (255).
