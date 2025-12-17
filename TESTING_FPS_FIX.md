# Testing the Frame Rate Fix

## Problem Statement
When connecting to the UVC gadget stream from a host PC using FFmpeg as a dshow device, users were only getting 2fps at 720p instead of the expected 15 or 30 fps.

## Root Cause
The frame interval negotiation logic in `uvc_events_process_data()` had a bug where it would select incorrect frame intervals when the host requested a specific frame rate.

**Buggy Code:**
```c
while (interval[0] < ctrl->dwFrameInterval && interval[1])
    ++interval;
```

This logic would advance too far through the intervals array when the host requested a frame interval that wasn't exactly in the list.

**Example of the Bug:**
- Available intervals: `{333333 (30fps), 666666 (15fps), 10000000 (1fps)}`
- If host requests `5000000` (2fps):
  - Loop would advance past 333333, 666666, and stop at 10000000
  - Result: Device selects 1fps instead of the faster 15fps ❌

## Fix Applied
Changed the interval selection logic to:
```c
while (interval[1] && (interval[1] <= ctrl->dwFrameInterval))
    ++interval;
```

This new logic:
- Selects the **largest supported interval that is ≤ requested**
- Prefers **faster frame rates** (smaller intervals) when ambiguous
- Follows UVC specification guidelines for interval negotiation

**Example with Fix:**
- Available intervals: `{333333 (30fps), 666666 (15fps), 10000000 (1fps)}`
- If host requests `5000000` (2fps):
  - Loop advances from 333333 to 666666 (since 10000000 > 5000000)
  - Result: Device selects 15fps ✓

## Additional Improvements
Added diagnostic output to help debug frame rate negotiation:
```
Host requested: 1280x720 interval=5000000 (2.00 fps)
COMMIT: 1280x720 interval=666666 (100ns) fps=15.00
```

## How to Test

### Prerequisites
1. Raspberry Pi (or similar device) with UVC gadget support
2. V4L2 video capture device (e.g., `/dev/video0`)
3. Host computer with FFmpeg installed
4. USB cable to connect Pi to host

### Setup Steps

1. **Build uvc-gadget with the fix:**
   ```bash
   cd /path/to/uvc-gadget
   make clean && make
   ```

2. **On the Raspberry Pi, configure the UVC gadget:**
   ```bash
   # Load the configfs-based gadget (if not already done)
   sudo ./multi-gadget.sh
   ```

3. **Start uvc-gadget:**
   ```bash
   # For MJPEG at 720p
   sudo ./uvc-gadget -f 1 -r 0 -v /dev/video0 -u /dev/video1
   
   # Add -T /tmp/video.fifo if you also want to tee the stream locally
   ```

4. **On the host PC, connect via USB and test with FFmpeg:**

   **On Windows:**
   ```cmd
   # List available devices
   ffmpeg -list_devices true -f dshow -i dummy
   
   # Stream from the UVC gadget (replace with your device name)
   ffmpeg -f dshow -i video="Pi Webcam" -f null -
   ```
   
   **On Linux:**
   ```bash
   # Find the video device
   v4l2-ctl --list-devices
   
   # Stream from the UVC gadget
   ffmpeg -f v4l2 -i /dev/videoX -f null -
   ```
   
   **On macOS:**
   ```bash
   # List available devices
   ffmpeg -f avfoundation -list_devices true -i ""
   
   # Stream from the UVC gadget
   ffmpeg -f avfoundation -i "0" -f null -
   ```

5. **Monitor the output:**
   - On the Raspberry Pi terminal, you should see:
     ```
     Host requested: 1280x720 interval=XXXXXX (X.XX fps)
     COMMIT: 1280x720 interval=333333 (100ns) fps=30.00
     ```
     or
     ```
     COMMIT: 1280x720 interval=666666 (100ns) fps=15.00
     ```
   
   - On the host PC, FFmpeg should report the frame rate:
     ```
     Stream #0:0: Video: mjpeg, yuvj422p, 1280x720, 30 fps, 30 tbr, 1000k tbn
     ```

### Expected Results

#### Before the Fix
- UVC gadget would select 1fps when host requested anything between 15fps and 1fps
- FFmpeg would show ~1-2 fps in the stream info
- Video would be extremely choppy

#### After the Fix
- UVC gadget selects appropriate frame rate (15fps or 30fps)
- FFmpeg shows 15fps or 30fps in the stream info
- Video streams smoothly at the negotiated frame rate

### Verification Test Cases

Run the unit test to verify the logic:
```bash
gcc -o /tmp/test_interval_logic /tmp/test_interval_logic.c
/tmp/test_interval_logic
```

Expected output shows NEW logic correctly selects faster frame rates:
```
Test 4: Host requests 5000000 (2fps, between 15 and 1)
OLD: Requested 5000000 (2.00 fps) -> Selected 10000000 (1.00 fps)
NEW: Requested 5000000 (2.00 fps) -> Selected 666666 (15.00 fps)
```

### Troubleshooting

1. **Still getting low frame rates:**
   - Check the diagnostic output on the Pi to see what interval is being committed
   - Verify the V4L2 capture device can actually provide frames at the requested rate
   - Check if the USB connection supports the required bandwidth (use High Speed or Super Speed)

2. **No diagnostic output:**
   - Remove the `-q` (quiet mode) flag if you're using it
   - Check that the UVC gadget device is properly connected

3. **FFmpeg reports different frame rate:**
   - Some hosts may override the negotiated frame rate
   - Check the actual COMMIT message in the Pi's terminal output
   - Verify the USB connection quality and bandwidth

## Technical Details

### Frame Interval Format
Frame intervals are specified in units of 100 nanoseconds:
- `333333` = 33.3333 ms = 30 fps
- `666666` = 66.6666 ms = 15 fps
- `10000000` = 1000 ms = 1 fps

### UVC Negotiation Process
1. Host sends `GET_MIN`, `GET_MAX`, `GET_DEF` to query supported formats
2. Host sends `SET_CUR(PROBE)` with desired parameters
3. Device responds with closest supported parameters
4. Host sends `GET_CUR(PROBE)` to read device response
5. Host sends `SET_CUR(COMMIT)` to finalize negotiation
6. Streaming begins with committed parameters

The fix ensures step 3 correctly selects frame intervals that prefer faster frame rates.

### Frame Interval Selection Algorithm
The intervals array is sorted in ascending order (fastest to slowest):
```c
unsigned int intervals[] = {333333, 666666, 10000000, 0};
```

The new algorithm:
1. Start at the fastest interval (smallest value)
2. Advance while the **next** interval is ≤ requested
3. Stop when advancing would exceed the requested interval
4. This selects the slowest acceptable frame rate (largest interval ≤ requested)

This ensures:
- Exact matches are selected when available
- Between-values requests prefer faster rates
- Device never promises faster rates than it can deliver
