"""Bounded, read-only Windows Graphics Capture. Never injects game input.

Requires: windows-capture, opencv-python, pywin32. Repeated encoded frames are
explicitly logged; encoded FPS alone does not prove fresh game frames.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--window", required=True, help="Exact existing window title")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--seconds", required=True, type=float)
    args = parser.parse_args()
    if not 1 <= args.seconds <= 160:
        parser.error("Capture must be between 1 and 160 seconds")
    if args.output.exists():
        parser.error("Output must be a new folder")
    import cv2
    import win32gui
    from windows_capture import WindowsCapture

    candidates = []
    win32gui.EnumWindows(lambda handle, _: candidates.append(handle)
                        if win32gui.GetWindowText(handle) == args.window else None, None)
    if len(candidates) != 1:
        raise RuntimeError(f"Expected one exact window, found {len(candidates)}")
    args.output.mkdir(parents=True, exist_ok=False)
    started = time.monotonic()
    started_utc = datetime.now(timezone.utc).isoformat()
    writer, size, encoded, callbacks = None, None, 0, 0
    errors, times = [], []
    closed = False
    frame_log = (args.output / "frames.jsonl").open("w", encoding="utf-8")
    capture = WindowsCapture(cursor_capture=False, draw_border=False,
                             minimum_update_interval=60, window_name=args.window)

    @capture.event
    def on_frame_arrived(frame, control):
        nonlocal writer, size, encoded, callbacks
        try:
            elapsed = time.monotonic() - started
            bgr = cv2.cvtColor(frame.frame_buffer, cv2.COLOR_BGRA2BGR)
            if writer is None:
                size = (frame.width, frame.height)
                writer = cv2.VideoWriter(str(args.output / "game.mp4"),
                                         cv2.VideoWriter_fourcc(*"mp4v"), 15, size)
                if not writer.isOpened():
                    raise RuntimeError("Video encoder unavailable")
                cv2.imwrite(str(args.output / "first.png"), bgr)
            if size != (frame.width, frame.height):
                raise RuntimeError("Window resized during capture")
            callbacks += 1
            times.append(elapsed)
            before = encoded
            while encoded < int(elapsed * 15) + 1:
                writer.write(bgr)
                encoded += 1
            frame_log.write(json.dumps({"utc": datetime.now(timezone.utc).isoformat(),
                "elapsed": elapsed, "encoded_frames": encoded,
                "duplicates_for_timing": max(0, encoded - before - 1),
                "capture_timespan": frame.timespan}) + "\n")
            frame_log.flush()
            if elapsed >= args.seconds:
                control.stop()
        except Exception as error:
            errors.append(str(error))
            control.stop()

    @capture.event
    def on_closed():
        nonlocal closed
        closed = True

    control = capture.start_free_threaded()
    try:
        while not control.is_finished() and time.monotonic() - started < args.seconds + 10:
            time.sleep(0.1)
    finally:
        if not control.is_finished():
            control.stop()
        control.wait()
        if writer:
            writer.release()
        frame_log.close()
    last_frame = times[-1] if times else 0
    max_gap = max([times[0]] + [b-a for a,b in zip(times, times[1:])]) if times else None
    if closed and last_frame < args.seconds - 0.5:
        errors.append("Window closed before capture duration")
    if last_frame < args.seconds - 0.5:
        errors.append("Capture ended early or frames stopped arriving")
    if max_gap is None or max_gap > 2:
        errors.append("Fresh capture frame gap exceeds two seconds")
    result = {"started_utc": started_utc, "window": args.window, "size": size,
        "requested_seconds": args.seconds, "last_frame_seconds": last_frame,
        "encoded_frames": encoded, "fresh_callbacks": callbacks,
        "max_callback_gap": max_gap, "errors": errors,
        "capture_ok": encoded > 0 and not errors, "visual_pass": False,
        "scope": "Read-only window capture; review video before claiming animation success"}
    (args.output / "capture.json").write_text(json.dumps(result, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(result))
    return 0 if result["capture_ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
