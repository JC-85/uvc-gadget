# Testing the USB Connection Fix

## Problem Statement
When connecting to the UVC device on the host machine, the gadget would:
```
UVC: 2 buffers allocated.
V4L2: Starting video stream.
UVC: Starting video stream.
UVC: Possible USB shutdown requested from Host, seen during VIDIOC_DQBUF
UVC: Possible USB shutdown requested from Host, seen during VIDIOC_DQBUF
select timeout
UVC: Stopping video stream.
```

This caused the UVC gadget to exit prematurely, preventing successful USB webcam operation.

## Root Cause
The issue occurred due to two problems:

1. **False Shutdown Detection:** The code was treating `V4L2_BUF_FLAG_ERROR` on dequeued buffers as a definitive USB shutdown signal. However, error-flagged buffers can occur during normal operation (e.g., during stream startup, host pausing, or when TEE mode is active and a USB host connects).

2. **Aggressive Timeout Handling:** The main loop would exit whenever `select()` timed out (after 2 seconds of inactivity), even during normal operation. This was too aggressive for a UVC gadget that should remain running and ready for connections.

## Fix Applied

### 1. Improved Error Buffer Handling
Modified `uvc_video_process()` to:
- Skip re-queuing buffers with ERROR flags but continue processing
- Not set `uvc_shutdown_requested` flag for error buffers
- Rely on actual disconnect events (UVC_EVENT_DISCONNECT, ENODEV) for shutdown detection

### 2. Fixed Select Timeout Behavior
Modified the main loop to:
- Continue operation on timeout during normal operation
- Only exit on timeout if `uvc_shutdown_requested` flag is set
- Allow the gadget to stay running and wait for new events

## How to Test

### Prerequisites
1. Device with UVC gadget support (e.g., Raspberry Pi with OTG)
2. V4L2 video capture device (e.g., `/dev/video0`)
3. Host computer with USB connection
4. Optional: FIFO for TEE mode testing

### Setup Steps

1. **Build uvc-gadget with the fix:**
   ```bash
   cd /path/to/uvc-gadget
   make clean && make
   ```

2. **Set up USB gadget configuration** (if not already done):
   ```bash
   # This varies by platform - consult your device's documentation
   # Example for Raspberry Pi:
   sudo modprobe libcomposite
   # Run multi-gadget.sh or configure manually
   ```

3. **Start uvc-gadget in normal mode:**
   ```bash
   # For MJPEG at 720p
   sudo ./uvc-gadget -f 1 -r 0 -v /dev/video0 -u /dev/video1
   ```

4. **Connect the host computer via USB**

5. **On the host, open the webcam:**
   - Linux: `vlc v4l2:///dev/video0` or `cheese`
   - Windows: Open Camera app or VLC
   - macOS: Open Photo Booth or QuickTime Player

### Test with TEE Mode (Original Issue Scenario)

If you're using TEE mode (the scenario where the issue was most prominent):

1. **Create a FIFO:**
   ```bash
   mkfifo /tmp/video.fifo
   ```

2. **Start uvc-gadget with TEE enabled:**
   ```bash
   sudo ./uvc-gadget -f 1 -r 0 -v /dev/video0 -u /dev/video1 -T /tmp/video.fifo
   ```

3. **Optionally start a reader (in another terminal):**
   ```bash
   ffmpeg -f mjpeg -i /tmp/video.fifo -f null -
   ```

4. **Connect the host computer via USB and open webcam**

## Expected Behavior

### Before Fix
- uvc-gadget would start normally
- When host connects, buffers get marked with ERROR flags
- Program would print "Possible USB shutdown requested" messages
- After 2 seconds, "select timeout" would occur
- Program would exit with "UVC: Stopping video stream"
- Host would see device disconnect

### After Fix
- uvc-gadget starts normally
- When host connects, any error buffers are handled gracefully
- Program prints "Buffer returned with error flag, skipping re-queue" (if applicable)
- Program continues running and processing
- Host successfully connects and receives video stream
- Program only exits on real shutdown events (user SIGINT, actual USB disconnect, etc.)

## Verification Tests

### Test 1: Basic Connection
1. Start uvc-gadget
2. Connect host
3. **Expected:** Host sees working webcam, no premature exit
4. **Success criteria:** Video streams continuously without disconnection

### Test 2: Reconnection Test
1. Start uvc-gadget
2. Connect host
3. Disconnect host
4. Wait 5 seconds
5. Reconnect host
6. **Expected:** uvc-gadget continues running, reconnects successfully
7. **Success criteria:** Multiple connect/disconnect cycles work without restarting uvc-gadget

### Test 3: TEE Mode with USB Connection
1. Create FIFO and start uvc-gadget with `-T /tmp/video.fifo`
2. Start ffmpeg reading from FIFO
3. Connect USB host
4. **Expected:** Both FIFO and USB streams work simultaneously
5. **Success criteria:** No "shutdown requested" messages, both streams continue

### Test 4: Idle Timeout Test
1. Start uvc-gadget
2. Wait 5 seconds (longer than select timeout)
3. Connect host
4. **Expected:** uvc-gadget continues running despite idle period
5. **Success criteria:** Connection succeeds after idle period

### Test 5: Real Shutdown Detection
1. Start uvc-gadget with USB connected and streaming
2. Physically disconnect USB cable
3. **Expected:** uvc-gadget detects real disconnect and stops streaming
4. **Success criteria:** Clean shutdown with "UVC_EVENT_DISCONNECT" or similar message

## Troubleshooting

### Issue: Still seeing premature exit
- Verify you compiled the latest version: `git log --oneline | head -3`
- Check for any additional error messages in output
- Ensure V4L2 device is working: `v4l2-ctl -d /dev/video0 --list-formats`

### Issue: No video stream on host
- This fix only addresses premature exit issues
- Check USB gadget configuration
- Verify UVC gadget module is loaded
- Check host recognizes device: `lsusb` (Linux) or Device Manager (Windows)

### Issue: "Buffer returned with error flag" messages
- These are informational and normal during stream startup
- They should not cause shutdown
- If they persist continuously, check V4L2 device health

## Technical Details

The fix distinguishes between:

1. **Transient buffer errors** (handled gracefully):
   - `V4L2_BUF_FLAG_ERROR` on buffers
   - Temporary timing issues
   - Stream startup conditions
   - TEE mode + USB host interaction

2. **Actual shutdown events** (still trigger proper shutdown):
   - `UVC_EVENT_DISCONNECT` from USB host
   - `ENODEV` errors on ioctl operations
   - `UVC_EVENT_STREAMOFF` events
   - User interrupts (Ctrl+C)

This ensures the gadget is robust during normal operation while still responding appropriately to real disconnect events.
