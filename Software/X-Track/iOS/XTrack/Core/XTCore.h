/*
 * X-TRACK iOS port - C interface between the iOS platform layer (Objective-C++)
 * and the portable LVGL/X-TRACK core (C/C++).
 *
 * All XTCore_* functions must be called on the main thread.
 */
#ifndef XT_CORE_H
#define XT_CORE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define XT_SCREEN_WIDTH   240
#define XT_SCREEN_HEIGHT  240

/* ---------- Lifecycle (platform -> core) ---------- */

/* rootPath: writable directory used as the virtual "SD card" root ("/") */
void XTCore_Init(const char* rootPath);
/* Run LVGL timers + HAL updates. Call once per display frame. */
void XTCore_Tick(void);
/* Persist settings / sport data / stop recording (app goes to background or terminates). */
void XTCore_Save(void);

/* Framebuffer: XT_SCREEN_WIDTH * XT_SCREEN_HEIGHT pixels, 32-bit BGRA little-endian
 * (CGBitmap: kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst).
 * Returns true if the framebuffer changed since the previous call. */
bool XTCore_FetchFramebuffer(const uint32_t** pixels);

/* ---------- Input (platform -> core) ---------- */

/* Touch in LVGL screen coordinates (0..239) */
void XTCore_TouchInput(int16_t x, int16_t y, bool pressed);
/* Rotary encoder emulation (Camera Control slide => diff, press => push) */
void XTCore_EncoderAddDiff(int32_t diff);
void XTCore_EncoderSetPressed(bool pressed);

/* ---------- Sensors (platform -> core) ---------- */

typedef struct
{
    bool     valid;
    double   longitude;
    double   latitude;
    float    altitude;   /* m */
    float    course;     /* deg, 0 = north */
    float    speed;      /* km/h */
    int16_t  satellites; /* estimated from accuracy */
    int64_t  utcTimestampMs;
} XTCore_GPSFix_t;

void XTCore_SetGPSFix(const XTCore_GPSFix_t* fix);
void XTCore_SetPower(uint8_t usagePercent, bool isCharging);
void XTCore_SetIMU(int16_t ax, int16_t ay, int16_t az, int16_t gx, int16_t gy, int16_t gz);
void XTCore_SetSteps(int32_t steps);
void XTCore_SetMAG(int16_t x, int16_t y, int16_t z);
void XTCore_SetStorageSizeMB(float totalMB);

/* ---------- Platform services (core -> platform, implemented in Obj-C++) ---------- */

/* Play a square-ish tone. freq == 0 => stop. durationMs < 0 => until next call. */
void XTPlatform_Tone(uint32_t freq, int32_t durationMs);

#ifdef __cplusplus
}
#endif

#endif
