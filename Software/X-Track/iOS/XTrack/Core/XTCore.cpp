/*
 * X-TRACK iOS port - LVGL glue: display, input devices, file system and app lifecycle.
 *
 * The original 240x240 UI is rendered unchanged (LV_COLOR_DEPTH 16, same lv_conf.h as
 * the hardware build) and converted to a 32-bit framebuffer that the iOS view shows.
 */
#include "XTCore.h"
#include "lv_fs_ios.h"

#include "lvgl/lvgl.h"
#include "App.h"
#include "Common/HAL/HAL.h"
#include "Common/DataProc/DataProc.h"

#include <chrono>
#include <stdlib.h>
#include <string.h>

/*Set in lv_conf.h as `LV_TICK_CUSTOM_SYS_TIME_EXPR`*/
extern "C" uint32_t custom_tick_get(void)
{
    using namespace std::chrono;
    static const steady_clock::time_point start = steady_clock::now();
    return (uint32_t)duration_cast<milliseconds>(steady_clock::now() - start).count();
}

/* Implemented in HAL_iOS.cpp */
namespace HAL
{
bool Encoder_IsEnabled();
}

/* ---------------- Display ---------------- */

static uint32_t s_framebuffer[XT_SCREEN_WIDTH * XT_SCREEN_HEIGHT];
static bool s_framebufferDirty = true;
static bool s_initialized = false;

static void disp_flush(lv_disp_drv_t* disp_drv, const lv_area_t* area, lv_color_t* color_p)
{
    const int32_t w = lv_area_get_width(area);

    for (int32_t y = area->y1; y <= area->y2; y++)
    {
        if (y < 0 || y >= XT_SCREEN_HEIGHT)
        {
            color_p += w;
            continue;
        }

        uint32_t* dst = &s_framebuffer[y * XT_SCREEN_WIDTH];
        for (int32_t x = area->x1; x <= area->x2; x++)
        {
            if (x >= 0 && x < XT_SCREEN_WIDTH)
            {
                /* lv_color_to32 handles RGB565 + LV_COLOR_16_SWAP => 0xAARRGGBB */
                dst[x] = lv_color_to32(*color_p) | 0xFF000000u;
            }
            color_p++;
        }
    }

    s_framebufferDirty = true;
    lv_disp_flush_ready(disp_drv);
}

/* ---------------- Input: touch ---------------- */

static struct
{
    int16_t x;
    int16_t y;
    bool pressed;
    bool pressLatch; /* a tap that began and ended between two reads */
} s_touch;

static void touch_read(lv_indev_drv_t* drv, lv_indev_data_t* data)
{
    data->point.x = s_touch.x;
    data->point.y = s_touch.y;
    data->state = (s_touch.pressed || s_touch.pressLatch) ? LV_INDEV_STATE_PRESSED : LV_INDEV_STATE_RELEASED;
    s_touch.pressLatch = false;
}

/* ---------------- Input: encoder (Camera Control) ---------------- */

static struct
{
    int32_t diff;
    bool pressed;
    bool pressLatch; /* a click that began and ended between two reads */
} s_encoder;

static void encoder_read(lv_indev_drv_t* drv, lv_indev_data_t* data)
{
    static bool lastState = false;

    data->enc_diff = (int16_t)LV_CLAMP(-100, s_encoder.diff, 100);
    s_encoder.diff = 0;

    bool isPush = s_encoder.pressed || s_encoder.pressLatch;
    s_encoder.pressLatch = false;

    data->state = isPush ? LV_INDEV_STATE_PRESSED : LV_INDEV_STATE_RELEASED;

    /* Same feedback tone as the hardware encoder (USER/lv_port/lv_port_indev.cpp) */
    if (isPush != lastState)
    {
        HAL::Buzz_Tone(isPush ? 500 : 700, 20);
        lastState = isPush;
    }
}

static void lv_port_init()
{
    /* Display */
    static lv_color_t drawBuf[XT_SCREEN_WIDTH * XT_SCREEN_HEIGHT];
    static lv_disp_draw_buf_t dispBuf;
    lv_disp_draw_buf_init(&dispBuf, drawBuf, nullptr, XT_SCREEN_WIDTH * XT_SCREEN_HEIGHT);

    static lv_disp_drv_t dispDrv;
    lv_disp_drv_init(&dispDrv);
    dispDrv.hor_res = XT_SCREEN_WIDTH;
    dispDrv.ver_res = XT_SCREEN_HEIGHT;
    dispDrv.flush_cb = disp_flush;
    dispDrv.draw_buf = &dispBuf;
    lv_disp_drv_register(&dispDrv);

    lv_group_t* group = lv_group_create();
    lv_group_set_default(group);

    /* Touch screen */
    static lv_indev_drv_t touchDrv;
    lv_indev_drv_init(&touchDrv);
    touchDrv.type = LV_INDEV_TYPE_POINTER;
    touchDrv.read_cb = touch_read;
    lv_indev_drv_register(&touchDrv);

    /* Encoder, driven by the iPhone Camera Control button */
    static lv_indev_drv_t encDrv;
    lv_indev_drv_init(&encDrv);
    encDrv.type = LV_INDEV_TYPE_ENCODER;
    encDrv.read_cb = encoder_read;
    lv_indev_t* encIndev = lv_indev_drv_register(&encDrv);
    lv_indev_set_group(encIndev, group);
}

/* ---------------- Public API ---------------- */

extern "C" void XTCore_Init(const char* rootPath)
{
    if (s_initialized)
    {
        return;
    }

    lv_init();
    lv_fs_ios_init(rootPath);
    lv_port_init();

    HAL::HAL_Init();
    App_Init();

    s_initialized = true;
}

extern "C" void XTCore_Tick(void)
{
    if (!s_initialized)
    {
        return;
    }
    lv_timer_handler();
    HAL::HAL_Update();
}

extern "C" void XTCore_Save(void)
{
    if (!s_initialized)
    {
        return;
    }

    DataProc::SysConfig_Info_t sysConfig;
    DATA_PROC_INIT_STRUCT(sysConfig);
    sysConfig.cmd = DataProc::SYSCONFIG_CMD_SAVE;
    DataProc::Center()->AccountMain.Notify("SysConfig", &sysConfig, sizeof(sysConfig));

    DataProc::Storage_Info_t storage;
    DATA_PROC_INIT_STRUCT(storage);
    storage.cmd = DataProc::STORAGE_CMD_SAVE;
    DataProc::Center()->AccountMain.Notify("Storage", &storage, sizeof(storage));
}

extern "C" bool XTCore_FetchFramebuffer(const uint32_t** pixels)
{
    *pixels = s_framebuffer;
    bool dirty = s_framebufferDirty;
    s_framebufferDirty = false;
    return dirty;
}

extern "C" void XTCore_TouchInput(int16_t x, int16_t y, bool pressed)
{
    s_touch.x = LV_CLAMP(0, x, XT_SCREEN_WIDTH - 1);
    s_touch.y = LV_CLAMP(0, y, XT_SCREEN_HEIGHT - 1);
    if (pressed && !s_touch.pressed)
    {
        s_touch.pressLatch = true;
    }
    s_touch.pressed = pressed;
}

extern "C" void XTCore_EncoderAddDiff(int32_t diff)
{
    if (!HAL::Encoder_IsEnabled())
    {
        return;
    }
    s_encoder.diff += diff;
}

extern "C" void XTCore_EncoderSetPressed(bool pressed)
{
    if (pressed && !HAL::Encoder_IsEnabled())
    {
        return;
    }
    if (pressed && !s_encoder.pressed)
    {
        s_encoder.pressLatch = true;
    }
    s_encoder.pressed = pressed;
}
