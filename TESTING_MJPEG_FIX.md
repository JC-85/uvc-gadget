# Testing the MJPEG EOI Fix

## Problem Statement
When reading MJPEG frames from the FIFO with ffmpeg, users were experiencing:
```
[mjpeg @ 0x1b3b520] EOI missing, emulating
```

This error indicates incomplete MJPEG frames (missing End Of Image markers).

## Root Cause
The FIFO was opened with `O_NONBLOCK`, causing partial frames to be written when:
- The FIFO buffer filled up (EAGAIN/EWOULDBLOCK)
- The reader disconnected (EPIPE)
- Other write errors occurred

## Fix Applied
Modified the code to use **blocking I/O** for FIFO writes:
1. `tee_open_if_needed()` now clears the `O_NONBLOCK` flag after opening
2. `tee_writer_thread()` handles blocking writes with proper error handling
3. Each MJPEG frame is now written atomically or not at all

## How to Test

### Prerequisites
1. Raspberry Pi (or similar device) with UVC gadget support
2. V4L2 video capture device (e.g., `/dev/video0`)
3. FIFO for teeing the video stream
4. ffmpeg installed

### Setup Steps

1. **Build uvc-gadget:**
   ```bash
   cd /path/to/uvc-gadget
   make clean && make
   ```

2. **Create a FIFO:**
   ```bash
   mkfifo /tmp/video.fifo
   ```

3. **Start uvc-gadget with TEE enabled:**
   ```bash
   # For MJPEG at 720p
   sudo ./uvc-gadget -f 1 -r 0 -v /dev/video0 -T /tmp/video.fifo
   ```

4. **Read from the FIFO with ffmpeg (in another terminal):**
   ```bash
   ffmpeg -f mjpeg -i /tmp/video.fifo -f null -
   ```
   
   Or to save to file:
   ```bash
   ffmpeg -f mjpeg -i /tmp/video.fifo output.mp4
   ```

5. **Monitor for EOI errors:**
   - Watch the ffmpeg output for `EOI missing, emulating` messages
   - **Expected result:** No EOI errors should appear
   - Before the fix: EOI errors would appear frequently
   - After the fix: No EOI errors (frames are written atomically)

### Alternative Test with VLC

Instead of ffmpeg, you can use VLC to view the stream:
```bash
vlc /tmp/video.fifo
```

### Stress Testing

To verify robustness under various conditions:

1. **Test reader disconnect:**
   - Start ffmpeg reading from FIFO
   - Kill ffmpeg (Ctrl+C)
   - Start ffmpeg again
   - Verify no corruption in subsequent frames

2. **Test slow reader:**
   - Use a slow frame rate in ffmpeg
   - Monitor for dropped frames vs. corrupted frames
   - Frames should be dropped cleanly, not corrupted

3. **Test high frame rate:**
   - Use high frame rate video source
   - Monitor ring buffer status for drops
   - Verify no partial frames even under load

## Expected Behavior

### Before Fix
- Frequent `EOI missing, emulating` errors
- Corrupted MJPEG frames in output
- Video artifacts and glitches

### After Fix
- No `EOI missing, emulating` errors
- Clean MJPEG frames even under stress
- Possible frame drops (which is acceptable) but no corruption

## Troubleshooting

If you still see EOI errors after applying the fix:

1. **Verify the fix was compiled:**
   ```bash
   strings uvc-gadget | grep "blocking I/O should never return EAGAIN"
   ```
   This should return a match if the fix is present.

2. **Check FIFO is actually being used:**
   - Ensure you're using the `-T` option with uvc-gadget
   - Verify the FIFO exists: `ls -l /tmp/video.fifo`

3. **Check for other issues:**
   - Verify the V4L2 device is producing valid MJPEG
   - Test with a different video source
   - Check system logs for other errors

## Technical Details

The fix ensures atomic frame writes by:
- Opening FIFO with `O_NONBLOCK` initially (to avoid blocking on open if no reader)
- Clearing `O_NONBLOCK` flag immediately after opening using `fcntl()`
- Using blocking `write()` calls which will:
  - Complete fully (entire frame written)
  - Or fail with EPIPE if reader disconnects
  - Never return EAGAIN/EWOULDBLOCK (would indicate a bug)

This guarantees that ffmpeg always reads complete MJPEG frames with proper EOI markers.
