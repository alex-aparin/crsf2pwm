#!/usr/bin/env python3
"""Play an ELRS receiver: send CRSF RC frames from the PC over a serial port.

Uses the reference model in tb/model/crsf.py, so the bytes on the wire are
the same ones the testbenches were built on. The board's own USB-UART
bridge is the port when rx sits on M2 (see docs/pinout.md).

    tools/crsf_send.py                              centre both channels, 250 frames/s
    tools/crsf_send.py --steer 172 --throttle 1811  fixed values, CRSF units 172..1811
    tools/crsf_send.py --us --steer 1000 --throttle 2000
    tools/crsf_send.py --sweep 4                    steer sweeps end to end and back every 4 s
    tools/crsf_send.py --interactive                drive it from the keyboard, see below
    tools/crsf_send.py --bad-crc                    spoil every second frame: outputs must not react
    tools/crsf_send.py --duration 3                 stop after 3 s: watch the failsafe kick in
    tools/crsf_send.py --dry-run                    print the frames instead of sending them

Interactive keys (frames keep flowing while you type):
    a / d  or  left / right     steer  -/+ one step
    s / w  or  down / up        throttle -/+ one step
    A D S W                     ten steps
    c or space                  both to centre
    1 .. 9                      steer to -100 % .. +100 % in eight steps (5 is centre)
    q or Ctrl+C                 quit, which is a failsafe test

Ctrl+C stops it; that too is a failsafe test.
Needs pyserial: sudo apt install python3-serial   (or pip install pyserial)
"""

import argparse
import glob
import os
import pathlib
import select
import sys
import termios
import time
import tty

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "tb" / "model"))
import crsf  # noqa: E402


def find_port():
    ports = sorted(glob.glob("/dev/ttyUSB*")) + sorted(glob.glob("/dev/ttyACM*"))
    if not ports:
        sys.exit("no /dev/ttyUSB* or /dev/ttyACM*: is the board's mini-USB plugged into this PC?")
    return ports[0]


def to_crsf(value, in_us):
    v = crsf.crsf_from_us(value) if in_us else int(value)
    if not 0 <= v <= 2047:
        sys.exit(f"channel value {value} out of range")
    return v


def clamp(v):
    return max(crsf.CH_MIN, min(crsf.CH_MAX, v))


def apply_key(key, steer, throttle, step):
    """One keystroke to new (steer, throttle, quit). Arrow keys arrive as ESC [ A/B/C/D."""
    big = 10 * step
    moves = {
        "a": (-step, 0), "d": (step, 0), "s": (0, -step), "w": (0, step),
        "A": (-big, 0), "D": (big, 0), "S": (0, -big), "W": (0, big),
        "\x1b[D": (-step, 0), "\x1b[C": (step, 0), "\x1b[B": (0, -step), "\x1b[A": (0, step),
    }
    if key in moves:
        ds, dt = moves[key]
        return clamp(steer + ds), clamp(throttle + dt), False
    if key in ("c", " "):
        return crsf.CH_MID, crsf.CH_MID, False
    if key in "123456789" and key:
        span = crsf.CH_MAX - crsf.CH_MIN
        return round(crsf.CH_MIN + span * (int(key) - 1) / 8), throttle, False
    if key in ("q", "\x03"):
        return steer, throttle, True
    return steer, throttle, False


def read_keys():
    """Keys waiting on stdin, possibly none. Read from the raw descriptor:
    Python's stdin buffer would swallow the tail of an escape sequence.
    An arrow key is ESC [ X and is returned as one key."""
    fd = sys.stdin.fileno()
    if not select.select([fd], [], [], 0)[0]:
        return []
    data = os.read(fd, 64)
    keys = []
    while data:
        if data[:1] == b"\x1b" and len(data) >= 3:
            keys.append(data[:3].decode(errors="replace"))
            data = data[3:]
        else:
            keys.append(data[:1].decode(errors="replace"))
            data = data[1:]
    return keys


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", help="serial port, default: first /dev/ttyUSB*")
    ap.add_argument("--baud", type=int, default=420000)
    ap.add_argument("--rate", type=float, default=250, help="frames per second, default 250")
    ap.add_argument("--steer", type=float, default=992, help="channel 0")
    ap.add_argument("--throttle", type=float, default=992, help="channel 1")
    ap.add_argument("--us", action="store_true", help="values are microseconds, not CRSF units")
    ap.add_argument("--sweep", type=float, metavar="SECONDS", help="sweep steer end to end and back with this period")
    ap.add_argument("--interactive", "-i", action="store_true", help="change the values from the keyboard while running")
    ap.add_argument("--step", type=int, default=16, help="interactive step in CRSF units, default 16 (10 us)")
    ap.add_argument("--bad-crc", action="store_true", help="spoil the CRC of every second frame")
    ap.add_argument("--duration", type=float, help="seconds to run, default: until Ctrl+C")
    ap.add_argument("--dry-run", action="store_true", help="print frames as hex instead of sending")
    args = ap.parse_args()

    steer = to_crsf(args.steer, args.us)
    throttle = to_crsf(args.throttle, args.us)
    if args.interactive and args.sweep:
        sys.exit("--interactive and --sweep do not mix")
    if args.interactive and not sys.stdin.isatty():
        sys.exit("--interactive needs a terminal on stdin")

    if args.dry_run:
        port = None
        name = "stdout"
    else:
        try:
            import serial
        except ImportError:
            sys.exit("pyserial missing: sudo apt install python3-serial  (or pip install pyserial)")
        name = args.port or find_port()
        try:
            port = serial.Serial(name, args.baud, timeout=0)
        except serial.SerialException as e:
            sys.exit(f"cannot open {name}: {e}\n"
                     "permission denied usually means: sudo usermod -aG dialout $USER, then log in again")

    period = 1.0 / args.rate
    print(f"{name} @ {args.baud}: {args.rate:g} frames/s, steer {steer} ({crsf.us_from_crsf(steer):.1f} us), "
          f"throttle {throttle} ({crsf.us_from_crsf(throttle):.1f} us)"
          + (f", steer sweep {args.sweep:g} s" if args.sweep else "")
          + (", every second CRC spoiled" if args.bad_crc else ""))

    def status(values):
        return (f"steer {values[0]:4d} ({crsf.us_from_crsf(values[0]):6.1f} us)  "
                f"throttle {values[1]:4d} ({crsf.us_from_crsf(values[1]):6.1f} us)")

    channels = [crsf.CH_MID] * crsf.CH_COUNT
    sent = 0
    t0 = time.monotonic()
    next_t = t0
    last_report = t0
    tty_state = None
    if args.interactive:
        tty_state = termios.tcgetattr(sys.stdin)
        tty.setcbreak(sys.stdin.fileno())       # keys arrive at once, Ctrl+C still works
        print("a/d steer, w/s throttle, A/D/W/S x10, c centre, 1..9 steer presets, q quit")
    try:
        while True:
            now = time.monotonic()
            if args.duration is not None and now - t0 >= args.duration:
                break
            if args.interactive:
                quit_now = False
                keys = read_keys()
                for key in keys:
                    steer, throttle, quit_now = apply_key(key, steer, throttle, args.step)
                    if quit_now:
                        break
                if quit_now:
                    break
                if keys:
                    print(f"\r{status((steer, throttle))}   ", end="", flush=True)
            if args.sweep:
                # triangle between CH_MIN and CH_MAX
                phase = ((now - t0) / args.sweep) % 1.0
                tri = 2 * phase if phase < 0.5 else 2 * (1 - phase)
                channels[0] = round(crsf.CH_MIN + tri * (crsf.CH_MAX - crsf.CH_MIN))
            else:
                channels[0] = steer
            channels[1] = throttle

            frame = bytearray(crsf.rc_frame(channels))
            if args.bad_crc and sent % 2 == 1:
                frame[-1] ^= 0xFF

            if port is None:
                print(frame.hex(" "))
            else:
                port.write(frame)
            sent += 1

            if now - last_report >= 1.0 and port is not None and not args.interactive:
                print(f"\r{sent} frames, {status(channels)}   ", end="", flush=True)
                last_report = now

            next_t += period
            delay = next_t - time.monotonic()
            if delay > 0:
                time.sleep(delay)
            else:
                next_t = time.monotonic()      # fell behind, do not burst
    except KeyboardInterrupt:
        pass
    finally:
        if tty_state is not None:
            termios.tcsetattr(sys.stdin, termios.TCSADRAIN, tty_state)
        if port is not None:
            port.close()
        print(f"\n{sent} frames sent, stopped: the board should fail safe in about 0.5 s")


if __name__ == "__main__":
    main()
