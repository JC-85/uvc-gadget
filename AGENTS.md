# Stream Buffer / Host FPS Issue – Working Notes

## Current status
- Branch: `fix-stream-buffer` (pushed).
- Gadget now copies V4L2 MJPEG into UVC MMAP buffers, stamps monotonic timestamps/sequence based on negotiated interval, and drops MJPEG frames missing markers or under 60 KB.
- Advertised UVC frame intervals are limited to 15 fps (mjpeg/yuyv arrays + config script) to keep hosts off 2 fps.
- Current configfs on device still shows `dwFrameInterval=5000000` and refuses rewrites (busy). UDC now reads empty after attempted unbind/rebind; device node missing until rebind happens on the device.
- Latest run (`run.sh` → `test-logs/linux-20251225-0010xx.log` / `test-logs/ffmpeg_output.log`):
  - Gadget side streams stable ~95–100 KB MJPEG buffers with monotonic timestamps.
  - Windows dshow still reports 2 fps; ffmpeg log shows “non monotonically increasing dts” and MJPEG decode errors (bad VLC/EOI before SOF).
  - Timeout exit (expected); no gadget-side errors.

## Open issues
- Host appears to ignore negotiated 15 fps and sticks to 2 fps, causing repeated DTS warnings on ffmpeg.
- Host receives MJPEG packets that ffmpeg flags as corrupt despite marker checks and size floor on gadget side.

## Next steps
1) Repair gadget config on the device: rebind UDC and rewrite configfs intervals to 666666 (may require tearing down/recreating the UVC function); run multi-gadget.sh as root once the gadget is unbound.
2) Validate host timestamps: confirm UVC header PTS/delta via host capture (Wireshark or Windows-side logging) to ensure monotonic timestamps are delivered.
3) Compare payload integrity: capture sample MJPEG payload from gadget side and host side to see where corruption is introduced; tighten validation if corruption originates before USB.

### Milestones
- 2025-12-25: Added monotonic timestamp stamping (including initial MMAP QBUF), defaulted advertised intervals to 15fps preference, and dropped MJPEG frames under 60 KB. Host still reports 2 fps; ffmpeg DTS warnings persist. Continued work needed on enforcing interval and validating host-side PTS/data.
- 2025-12-25: Clamped PROBE/COMMIT dwFrameInterval to the nearest supported interval and rewrite SET_CUR data so GET_CUR echoes the clamped value; intervals remain sorted fastest-to-slowest. Deployed; host still advertising 2 fps in latest runs and ffmpeg reports DTS/decode errors. Next: verify clamp takes effect on host (GET_CUR/host view), capture host PTS, and compare MJPEG payloads.
- 2025-12-25: Tightened descriptor intervals to 15/30 fps only (removed 1 fps option) to discourage low-fps negotiation. Deployed and retested; host still shows 2 fps and ffmpeg errors persist.
- 2025-12-25: Limited config script to 15 fps only and added PROBE logging of max frame/payload. Attempted to overwrite configfs intervals via run.sh, but dwFrameInterval remains 5000000 (EBUSY) and UDC ended up unbound; need on-device rebind/teardown to apply new intervals.

## Recent commits
- `2782f92` Drop undersized MJPEG frames to avoid decode errors.
- `82618b3` Default to 15fps intervals in UVC descriptors.
- `3bb5820` Stamp initial UVC MMAP buffers with monotonic timestamps.
- `73c058f` Stabilize UVC timestamps and drop tiny MJPEG frames.
