# Stream Buffer / Host FPS Issue – Working Notes

## Current status
- Branch: `fix-stream-buffer` (pushed).
- Standalone dummy mode forces MMAP IO, uses a tracked 1280x720 MJPEG sample (`test-logs/sample_720p.mjpeg`), paces timestamps, advertises the sample size, and queues 8 buffers; first payload dumped to `/tmp/uvc_dump.jpeg` is valid. Sample updated to a realistic ~46 KB frame.
- Latest runs still show every UVC buffer returned with `V4L2_BUF_FLAG_ERROR`; kernel logs spam “VS request completed with status -61 (ECONNRESET)” and host ffmpeg fails to decode (I/O error, “No JPEG data found”).

## Open issues
- UVC stream still failing: all dequeued buffers come back with ERROR, kernel logs show VS requests ending with -61 (ECONNRESET), and host ffmpeg can’t decode any frames.
- Need to determine why the host resets requests: payload layout/headers vs. size negotiation vs. endpoint configuration.

## Next steps
1) Capture more detail around the ERROR returns (-61) from g_uvc (usbmon or verbose kernel logging) to understand why the host resets VS requests.
2) Verify what payload size/headers the gadget is sending (confirm bytesused honored, consider adding optional UVC header construction if needed).
3) Once ERROR is resolved, re-run ffmpeg and confirm sustained ≥15 fps for 10s with the sample MJPEG source.

### Milestones
- 2025-12-25: Added monotonic timestamp stamping (including initial MMAP QBUF), defaulted advertised intervals to 15fps preference, and dropped MJPEG frames under 60 KB. Host still reports 2 fps; ffmpeg DTS warnings persist. Continued work needed on enforcing interval and validating host-side PTS/data.
- 2025-12-25: Clamped PROBE/COMMIT dwFrameInterval to the nearest supported interval and rewrite SET_CUR data so GET_CUR echoes the clamped value; intervals remain sorted fastest-to-slowest. Deployed; host still advertising 2 fps in latest runs and ffmpeg reports DTS/decode errors. Next: verify clamp takes effect on host (GET_CUR/host view), capture host PTS, and compare MJPEG payloads.
- 2025-12-25: Tightened descriptor intervals to 15/30 fps only (removed 1 fps option) to discourage low-fps negotiation. Deployed and retested; host still shows 2 fps and ffmpeg errors persist.
- 2025-12-25: Limited config script to 15 fps only and added PROBE logging of max frame/payload. Attempted to overwrite configfs intervals via run.sh, but dwFrameInterval remains 5000000 (EBUSY) and UDC ended up unbound; need on-device rebind/teardown to apply new intervals.
- 2025-12-25: Added teardown-gadget.sh and wired piwebcam/run.sh to teardown-then-setup and assert multi-gadget intervals match 666666 before streaming. Device-side configfs still stuck at 5000000 until teardown is executed on-device.
- 2025-12-25: Fixed config rebuild pipeline: reboot + teardown + multi-gadget now binds UDC, applies 666666 intervals, and uvc-gadget opens successfully (host stream still pending host-side ffmpeg).
- 2025-12-25: Fixed dummy/MMAP segfault by honoring standalone IO choice; added tracked 1280x720 sample MJPEG, timestamp pacing, and buffer dump. Current blocker: UVC buffers returned with ERROR/-61 and host still can’t decode.
- 2025-12-25: Advertise actual sample MJPEG size in standalone and bumped dummy buffers to 8; kernel still reports VS -61 and host decoding fails.

## Recent commits
- `2782f92` Drop undersized MJPEG frames to avoid decode errors.
- `82618b3` Default to 15fps intervals in UVC descriptors.
- `3bb5820` Stamp initial UVC MMAP buffers with monotonic timestamps.
- `73c058f` Stabilize UVC timestamps and drop tiny MJPEG frames.
