"""CRSF reference model.

Used to generate frames for tests (cocotb, or vector files for $readmemh)
and to check the design's results.
"""

CRSF_ADDR_FC = 0xC8   # flight controller address, first byte of a frame
CRSF_TYPE_RC = 0x16   # RC channels frame
CRSF_LEN_RC = 0x18    # type + 22 payload bytes + CRC

CH_MIN = 172
CH_MID = 992
CH_MAX = 1811


def crc8(data: bytes) -> int:
    """CRC-8/DVB-S2: polynomial 0xD5, init 0x00, no reflection."""
    raise NotImplementedError


def pack_channels(channels: list[int]) -> bytes:
    """Pack 16 channels of 11 bits into 22 bytes, LSB first."""
    raise NotImplementedError


def rc_frame(channels: list[int]) -> bytes:
    """Full RC frame: address, length, type, payload, CRC."""
    raise NotImplementedError


def us_from_crsf(value: int) -> float:
    """Channel value 172..1811 to microseconds 988..2012."""
    raise NotImplementedError
