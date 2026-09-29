"""CRSF reference model.

Used to generate frames and CRC vectors for the testbenches (see
gen_vectors.py) and to check the design's results. Pure Python, no
dependencies. Run this file directly for a self-test.
"""

CRSF_ADDR_FC = 0xC8     # flight controller address, first byte of a frame
CRSF_TYPE_RC = 0x16     # RC channels frame
CRSF_LEN_RC = 0x18      # type + 22 payload bytes + CRC
CRSF_TYPE_LINK = 0x14   # link statistics frame, 10 payload bytes
CRSF_POLY = 0xD5        # CRC-8/DVB-S2

CH_COUNT = 16
CH_BITS = 11
CH_MIN = 172            # -100 % stick,  988 us
CH_MID = 992            # centre,       1500 us
CH_MAX = 1811           # +100 % stick, 2012 us


def crc8(data: bytes) -> int:
    """CRC-8/DVB-S2: polynomial 0xD5, init 0x00, no reflection, no final XOR.

    Catalogue check value: crc8(b"123456789") == 0xBC.
    """
    crc = 0
    for byte in data:
        crc ^= byte
        for _ in range(8):
            if crc & 0x80:
                crc = ((crc << 1) ^ CRSF_POLY) & 0xFF
            else:
                crc = (crc << 1) & 0xFF
    return crc


def pack_channels(channels) -> bytes:
    """Pack 16 channels of 11 bits into 22 bytes, LSB first.

    Channel 0 is byte0[7:0] + byte1[2:0], channel 1 is byte1[7:3] + byte2[5:0].
    """
    if len(channels) != CH_COUNT:
        raise ValueError(f"need {CH_COUNT} channels, got {len(channels)}")
    bits = 0
    for i, ch in enumerate(channels):
        if not 0 <= ch < (1 << CH_BITS):
            raise ValueError(f"channel {i} = {ch} does not fit in {CH_BITS} bits")
        bits |= ch << (CH_BITS * i)
    return bits.to_bytes(CH_COUNT * CH_BITS // 8, "little")


def unpack_channels(payload: bytes) -> list:
    """Inverse of pack_channels."""
    if len(payload) != CH_COUNT * CH_BITS // 8:
        raise ValueError(f"payload must be {CH_COUNT * CH_BITS // 8} bytes")
    bits = int.from_bytes(payload, "little")
    mask = (1 << CH_BITS) - 1
    return [(bits >> (CH_BITS * i)) & mask for i in range(CH_COUNT)]


def frame(frame_type: int, payload: bytes) -> bytes:
    """Any frame: address, length, type, payload, CRC over type and payload."""
    body = bytes([frame_type]) + payload
    if len(body) + 1 > 62:
        raise ValueError("frame too long")
    return bytes([CRSF_ADDR_FC, len(body) + 1]) + body + bytes([crc8(body)])


def rc_frame(channels) -> bytes:
    """Full RC frame: address, length, type, 22 payload bytes, CRC. 26 bytes."""
    return frame(CRSF_TYPE_RC, pack_channels(channels))


def us_from_crsf(value: int) -> float:
    """Channel value to pulse width in microseconds: 172 -> 987.5, 992 -> 1500."""
    return (value - CH_MID) * 5 / 8 + 1500


def crsf_from_us(us: float) -> int:
    """Pulse width in microseconds to the nearest channel value."""
    return round(CH_MID + (us - 1500) * 8 / 5)


def _selftest():
    assert crc8(b"123456789") == 0xBC
    assert crc8(b"") == 0x00
    assert crc8(b"\x01") == 0xD5

    chans = [CH_MIN, CH_MID, CH_MAX] + [100 * k for k in range(3, CH_COUNT)]
    assert unpack_channels(pack_channels(chans)) == chans

    # bit layout from the specification
    p = pack_channels([0x7FF, 0] + [0] * 14)
    assert p[0] == 0xFF and p[1] == 0x07 and p[2] == 0x00
    p = pack_channels([0, 0x7FF] + [0] * 14)
    assert p[0] == 0x00 and p[1] == 0xF8 and p[2] == 0x3F

    f = rc_frame(chans)
    assert len(f) == 26
    assert f[0] == CRSF_ADDR_FC and f[1] == CRSF_LEN_RC and f[2] == CRSF_TYPE_RC
    assert crc8(f[2:-1]) == f[-1]
    assert unpack_channels(f[3:-1]) == chans

    assert us_from_crsf(CH_MIN) == 987.5
    assert us_from_crsf(CH_MID) == 1500.0
    assert us_from_crsf(CH_MAX) == 2011.875
    assert crsf_from_us(1500) == CH_MID
    print("crsf.py: self-test ok")


if __name__ == "__main__":
    _selftest()
