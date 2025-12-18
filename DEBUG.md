# Debug Output System

## Overview

The UVC gadget application includes a debug output system that can help diagnose streaming issues without impacting performance in the critical data path.

## Debug Macros

### DEBUG_PRINT
Basic debug print that can be compiled out.

```c
DEBUG_PRINT("Message: %s\n", message);
```

### DEBUG_PRINT_THROTTLED
Throttled debug print that only outputs every Nth call to avoid flooding logs in hot paths.

```c
DEBUG_PRINT_THROTTLED(counter_name, interval, "Message every %d calls\n", interval);
```

## Active Streaming Debug Output

The application includes throttled debug output at critical points:

1. **V4L2 Frame Capture** (every 30 frames):
   ```
   V4L2: Captured frame - buffer index=2, 153600 bytes [450 total]
   ```
   Shows when frames are being captured from the video source.

2. **UVC Data Transfer** (every 30 frames):
   ```
   UVC: Streaming active - queued buffer #123 (index=1, 153600 bytes) [450 total]
   ```
   Shows when data is being actively pushed to the UVC device (host).

## Compiling with Debug Output

### Debug Enabled (Default)
```bash
make
# or explicitly:
make DEBUG=1
```

This will include all debug output. Output appears every 30 frames to avoid overwhelming the logs while still providing visibility into streaming activity.

### Debug Disabled (Production)
To compile without any debug overhead:
```bash
make DEBUG=0
```

When compiled with `DEBUG=0`, all debug macros become no-ops and add zero runtime overhead.

### Makefile Options

The Makefile supports the following debug control:

- `make` - Build with debug enabled (default, DEBUG=1)
- `make DEBUG=1` - Build with debug enabled (explicit)
- `make DEBUG=0` - Build with debug disabled (production, no overhead)

The DEBUG flag controls whether the `-DDISABLE_DEBUG` compiler flag is added.

## Interpreting Debug Output

### Normal Operation
When streaming is working correctly, you should see both V4L2 and UVC messages appearing regularly:

```
V4L2: Captured frame - buffer index=0, 153600 bytes [30 total]
UVC: Streaming active - queued buffer #30 (index=0, 153600 bytes) [30 total]
V4L2: Captured frame - buffer index=1, 153600 bytes [60 total]
UVC: Streaming active - queued buffer #60 (index=1, 153600 bytes) [60 total]
```

### Troubleshooting

**No V4L2 messages:**
- Video capture device is not producing frames
- Check camera connection and V4L2 device configuration

**No UVC messages:**
- Data is not being sent to the host
- Could indicate USB disconnection or host not reading data
- Check for ERROR buffer messages

**V4L2 messages but no UVC messages:**
- Frames are being captured but not forwarded to UVC
- Could indicate buffer allocation issues or USB bandwidth problems
- Check buffer size in COMMIT message

**UVC messages but errors:**
- Data is being sent but host is rejecting it
- Check for "Buffer returned with ERROR" messages
- May indicate buffer size or frame rate mismatch

**ERROR Buffers (Enhanced Diagnostics):**

The first 5 buffers show detailed info:
```
UVC: Buffer #1: index=0, bytesused=15129, length=1843200
```

When ERROR occurs, you'll see:
```
UVC: ERROR buffer details: index=0, bytesused=15129, length=1843200, qbuf_count=1, dqbuf_count=1
```

Key indicators:
- **bytesused < length**: Normal - actual frame smaller than max buffer (good compression)
- **bytesused > length**: Problem - frame too large for buffer (shouldn't happen with our fix)
- **qbuf_count = dqbuf_count**: All buffers returned with ERROR (streaming failed)
- **ERROR on buffer #1**: Immediate failure, check COMMIT buffer size and USB mode (bulk vs iso)

## Throttling Interval

The default throttle interval is 30 frames. This means:
- At 30fps: Debug output every 1 second
- At 15fps: Debug output every 2 seconds
- At 1fps: Debug output every 30 seconds

This provides good visibility without impacting timing in the hot path or overwhelming logs during normal operation.

To change the interval, modify the second parameter in the `DEBUG_PRINT_THROTTLED` calls in `uvc-gadget.c`.

## Performance Impact

**With Debug Enabled:**
- Minimal overhead: One counter increment per frame
- One printf call every 30 frames
- Negligible impact on streaming performance

**With Debug Disabled:**
- Zero overhead: All debug code compiled out
- No function calls, no conditionals
- Identical performance to builds without debug system
