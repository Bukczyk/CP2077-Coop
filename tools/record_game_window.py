"""Bounded, read-only Windows Graphics Capture. Never injects game input.

Requires: windows-capture, PyAV, opencv-python, pywin32. NVENC keeps compression
off the CPU. Variable-frame-rate timestamps preserve real gaps without creating
duplicate frames inside the capture callback. Fresh cadence is still reported.
"""
import argparse
from datetime import datetime, timezone
from fractions import Fraction
import json
from pathlib import Path
import statistics
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--window", required=True, help="Exact existing window title")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--seconds", required=True, type=float)
    parser.add_argument("--fps", type=int, choices=(15,30,60), default=60,
                        help="Requested capture/encoding rate; fresh callbacks are reported separately")
    parser.add_argument("--encoder", choices=("h264_nvenc","libx264"), default="h264_nvenc")
    args = parser.parse_args()
    if not 1 <= args.seconds <= 160:
        parser.error("Capture must be between 1 and 160 seconds")
    if args.output.exists():
        parser.error("Output must be a new folder")
    import cv2
    import av
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
    cv2.setNumThreads(1)
    writer, stream, size, encoded, callbacks = None, None, None, 0, 0
    first_elapsed, first_utc, last_pts = None, None, -1
    errors, times = [], []
    closed = False
    frame_log = (args.output / "frames.jsonl").open("w", encoding="utf-8")
    interval_ms = max(1, 1000 // args.fps)
    capture = WindowsCapture(cursor_capture=False, draw_border=False,
                             minimum_update_interval=interval_ms, window_hwnd=candidates[0])

    @capture.event
    def on_frame_arrived(frame, control):
        nonlocal writer, stream, size, encoded, callbacks, first_elapsed, first_utc, last_pts
        try:
            elapsed = time.monotonic() - started
            if writer is None:
                size = (frame.width, frame.height)
                first_elapsed, first_utc = elapsed, datetime.now(timezone.utc).isoformat()
                writer = av.open(str(args.output / "game.mp4"),"w")
                stream = writer.add_stream(args.encoder,rate=args.fps)
                stream.width,stream.height = size
                stream.codec_context.max_b_frames = 0
                stream.pix_fmt = "bgra" if args.encoder=="h264_nvenc" else "yuv420p"
                stream.options = ({"preset":"p1","tune":"ull","rc":"vbr","cq":"20"}
                    if args.encoder=="h264_nvenc" else {"preset":"ultrafast","crf":"20"})
                cv2.imwrite(str(args.output / "first.png"), frame.frame_buffer)
            if size != (frame.width, frame.height):
                raise RuntimeError("Window resized during capture")
            callbacks += 1
            times.append(elapsed)
            # H.264's encoder clock uses the requested frame interval. Drop a
            # callback in the same interval instead of inventing a later PTS.
            # Longer gaps remain gaps in the MP4, not CPU-heavy catch-up loops.
            pts = round((elapsed-first_elapsed)*args.fps)
            submitted = pts>last_pts
            if submitted:
                picture = av.VideoFrame.from_ndarray(frame.frame_buffer,format="bgra")
                picture.pts, picture.time_base = pts,Fraction(1,args.fps)
                for packet in stream.encode(picture):writer.mux(packet)
                encoded += 1
                last_pts = pts
            frame_log.write(json.dumps({"utc": datetime.now(timezone.utc).isoformat(),
                "elapsed": elapsed, "encoded_frames": encoded,
                "duplicates_for_timing": 0,"encoded_this_callback":submitted,
                "video_pts":pts,"video_time_base":"1/"+str(args.fps),
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
            try:
                if stream:
                    for packet in stream.encode():writer.mux(packet)
                writer.close()
            except Exception as error:errors.append("Encoder finalization: "+str(error))
        frame_log.close()
    last_frame = times[-1] if times else 0
    max_gap = max([times[0]] + [b-a for a,b in zip(times, times[1:])]) if times else None
    gaps = sorted(b-a for a,b in zip(times,times[1:]))
    if closed and last_frame < args.seconds - 0.5:
        errors.append("Window closed before capture duration")
    if last_frame < args.seconds - 0.5:
        errors.append("Capture ended early or frames stopped arriving")
    if max_gap is None or max_gap > 2:
        errors.append("Fresh capture frame gap exceeds two seconds")
    result = {"started_utc": started_utc, "window": args.window, "size": size,
        "video_started_utc":first_utc,"first_frame_elapsed":first_elapsed,
        "encoder":args.encoder,"timing":"variable frame rate, no synthetic duplicates",
        "requested_seconds": args.seconds, "last_frame_seconds": last_frame,
        "encoded_frames": encoded, "fresh_callbacks": callbacks,
        "requested_fps": args.fps, "minimum_update_interval_ms": interval_ms,
        "mean_fresh_callback_fps": (len(times)-1)/(times[-1]-times[0]) if len(times)>1 else None,
        "median_callback_gap": statistics.median(gaps) if gaps else None,
        "p95_callback_gap": gaps[min(len(gaps)-1,int(len(gaps)*0.95))] if gaps else None,
        "max_callback_gap": max_gap, "errors": errors,
        "capture_ok": encoded > 0 and not errors, "visual_pass": False,
        "scope": "Read-only window capture; review video before claiming animation success"}
    (args.output / "capture.json").write_text(json.dumps(result, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(result))
    return 0 if result["capture_ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
