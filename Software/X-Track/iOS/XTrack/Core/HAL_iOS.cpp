/*
 * X-TRACK iOS port - HAL implementation.
 *
 * Sensor data is pushed in by the iOS platform layer (CoreLocation, CoreMotion,
 * UIDevice battery) through the XTCore_Set* functions; the X-TRACK application
 * reads it through the unchanged HAL interface (USER/App/Common/HAL/HAL.h).
 */
#include "XTCore.h"
#include "Common/HAL/HAL.h"
#include "Utils/TonePlayer/TonePlayer.h"
#include "Config/Config.h"
#include "lvgl/lvgl.h"

#include <math.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>

#include "Common/Music/MusicCode.h"

namespace HAL
{
bool Encoder_IsEnabled();
}

/* ---------------- State shared with the platform layer ---------------- */

static HAL::GPS_Info_t s_gpsInfo;
static int64_t s_gpsUtcMs = 0;

static HAL::Power_Info_t s_powerInfo = { 3700, 100, false };

static HAL::IMU_Info_t s_imuInfo;
static bool s_imuUpdated = false;
static HAL::CommitFunc_t s_imuCommit = nullptr;
static void* s_imuUserData = nullptr;

static HAL::MAG_Info_t s_magInfo;
static bool s_magUpdated = false;
static HAL::CommitFunc_t s_magCommit = nullptr;
static void* s_magUserData = nullptr;

static float s_storageSizeMB = 0.0f;
static HAL::SD_CallbackFunction_t s_sdCallback = nullptr;

static bool s_encoderEnable = true;
static bool s_buzzEnable = true;

static TonePlayer s_player;

extern "C" void XTCore_SetGPSFix(const XTCore_GPSFix_t* fix)
{
    s_gpsInfo.isVaild = fix->valid;
    if (fix->valid)
    {
        s_gpsInfo.longitude = fix->longitude;
        s_gpsInfo.latitude = fix->latitude;
        s_gpsInfo.altitude = fix->altitude;
        if (fix->course >= 0.0f)
        {
            s_gpsInfo.course = fix->course;
        }
        s_gpsInfo.speed = fix->speed < 0.0f ? 0.0f : fix->speed;
        s_gpsUtcMs = fix->utcTimestampMs;
    }
    else
    {
        s_gpsInfo.speed = 0.0f;
    }
    s_gpsInfo.satellites = fix->valid ? fix->satellites : 0;
}

extern "C" void XTCore_SetPower(uint8_t usagePercent, bool isCharging)
{
    if (usagePercent > 100)
    {
        usagePercent = 100;
    }
    s_powerInfo.usage = usagePercent;
    s_powerInfo.isCharging = isCharging;
    /* Approximate Li-ion voltage for the "battery" info page */
    s_powerInfo.voltage = (uint16_t)(3300 + usagePercent * 9);
}

extern "C" void XTCore_SetIMU(int16_t ax, int16_t ay, int16_t az, int16_t gx, int16_t gy, int16_t gz)
{
    s_imuInfo.ax = ax;
    s_imuInfo.ay = ay;
    s_imuInfo.az = az;
    s_imuInfo.gx = gx;
    s_imuInfo.gy = gy;
    s_imuInfo.gz = gz;
    s_imuUpdated = true;
}

extern "C" void XTCore_SetSteps(int32_t steps)
{
    s_imuInfo.steps = (int16_t)(steps % 10000);
    s_imuUpdated = true;
}

extern "C" void XTCore_SetMAG(int16_t x, int16_t y, int16_t z)
{
    s_magInfo.x = x;
    s_magInfo.y = y;
    s_magInfo.z = z;
    s_magUpdated = true;
}

extern "C" void XTCore_SetStorageSizeMB(float totalMB)
{
    s_storageSizeMB = totalMB;
}

/* ---------------- HAL ---------------- */

void HAL::HAL_Init()
{
    s_gpsInfo.longitude = CONFIG_GPS_LONGITUDE_DEFAULT;
    s_gpsInfo.latitude = CONFIG_GPS_LATITUDE_DEFAULT;
    s_gpsInfo.isVaild = false;
    s_gpsInfo.satellites = 0;

    Buzz_init();
    Audio_Init();
    SD_Init();

    if (s_sdCallback)
    {
        s_sdCallback(true);
    }
}

void HAL::HAL_Update()
{
    Audio_Update();

    /* Same 1 s sensor update period as the hardware (USER/HAL/HAL.cpp) */
    static uint32_t lastSensorTick = 0;
    if (lv_tick_elaps(lastSensorTick) >= 1000)
    {
        lastSensorTick = lv_tick_get();
        IMU_Update();
        MAG_Update();
    }
}

/* Clock */
void HAL::Clock_Init()
{
}

void HAL::Clock_GetInfo(Clock_Info_t* info)
{
    struct timeval tv;
    gettimeofday(&tv, nullptr);
    struct tm t;
    time_t sec = tv.tv_sec;
    localtime_r(&sec, &t);

    info->year = t.tm_year + 1900;
    info->month = t.tm_mon + 1;
    info->day = t.tm_mday;
    info->week = t.tm_wday;
    info->hour = t.tm_hour;
    info->minute = t.tm_min;
    info->second = t.tm_sec;
    info->millisecond = (uint16_t)(tv.tv_usec / 1000);
}

void HAL::Clock_SetInfo(const Clock_Info_t* info)
{
    /* iOS keeps its own network/GPS synchronized clock. */
    LV_LOG_USER(
        "Clock calibrate request ignored: %04d-%02d-%02d %02d:%02d:%02d",
        info->year, info->month, info->day,
        info->hour, info->minute, info->second
    );
}

/* GPS */
void HAL::GPS_Init()
{
}

void HAL::GPS_Update()
{
}

bool HAL::GPS_GetInfo(GPS_Info_t* info)
{
    /* GPS clock is UTC (X-TRACK converts it with the configured time zone) */
    int64_t ms = s_gpsUtcMs;
    if (!s_gpsInfo.isVaild || ms <= 0)
    {
        struct timeval tv;
        gettimeofday(&tv, nullptr);
        ms = (int64_t)tv.tv_sec * 1000 + tv.tv_usec / 1000;
    }

    time_t sec = (time_t)(ms / 1000);
    struct tm t;
    gmtime_r(&sec, &t);
    s_gpsInfo.clock.year = t.tm_year + 1900;
    s_gpsInfo.clock.month = t.tm_mon + 1;
    s_gpsInfo.clock.day = t.tm_mday;
    s_gpsInfo.clock.week = t.tm_wday;
    s_gpsInfo.clock.hour = t.tm_hour;
    s_gpsInfo.clock.minute = t.tm_min;
    s_gpsInfo.clock.second = t.tm_sec;
    s_gpsInfo.clock.millisecond = (uint16_t)(ms % 1000);

    *info = s_gpsInfo;
    return s_gpsInfo.isVaild;
}

bool HAL::GPS_LocationIsValid()
{
    return s_gpsInfo.isVaild;
}

double HAL::GPS_GetDistanceOffset(GPS_Info_t* info, double preLong, double preLat)
{
    /* Great-circle distance in meters (same formula as TinyGPS++ distanceBetween) */
    const double DEG_TO_RAD = 0.017453292519943295769236907684886;
    double lat1 = info->latitude, long1 = info->longitude;
    double lat2 = preLat, long2 = preLong;

    double delta = (long1 - long2) * DEG_TO_RAD;
    double sdlong = sin(delta);
    double cdlong = cos(delta);
    lat1 *= DEG_TO_RAD;
    lat2 *= DEG_TO_RAD;
    double slat1 = sin(lat1);
    double clat1 = cos(lat1);
    double slat2 = sin(lat2);
    double clat2 = cos(lat2);
    delta = (clat1 * slat2) - (slat1 * clat2 * cdlong);
    delta = delta * delta;
    delta += (clat2 * sdlong) * (clat2 * sdlong);
    delta = sqrt(delta);
    double denom = (slat1 * slat2) + (clat1 * clat2 * cdlong);
    delta = atan2(delta, denom);
    return delta * 6372795;
}

/* Power */
void HAL::Power_Init()
{
}

void HAL::Power_GetInfo(Power_Info_t* info)
{
    *info = s_powerInfo;
}

void HAL::Power_SetEventCallback(Power_CallbackFunction_t callback)
{
}

/* IMU */
bool HAL::IMU_Init()
{
    return true;
}

void HAL::IMU_SetCommitCallback(CommitFunc_t func, void* userData)
{
    s_imuCommit = func;
    s_imuUserData = userData;
}

void HAL::IMU_Update()
{
    if (s_imuUpdated && s_imuCommit)
    {
        IMU_Info_t imu = s_imuInfo;
        s_imuCommit(&imu, s_imuUserData);
        s_imuUpdated = false;
    }
}

/* MAG */
bool HAL::MAG_Init()
{
    return true;
}

void HAL::MAG_SetCommitCallback(CommitFunc_t func, void* userData)
{
    s_magCommit = func;
    s_magUserData = userData;
}

void HAL::MAG_Update()
{
    if (s_magUpdated && s_magCommit)
    {
        MAG_Info_t mag = s_magInfo;
        s_magCommit(&mag, s_magUserData);
        s_magUpdated = false;
    }
}

/* Storage: the app's Documents folder plays the role of the SD card */
bool HAL::SD_Init()
{
    return true;
}

void HAL::SD_Update()
{
}

bool HAL::SD_GetReady()
{
    return true;
}

float HAL::SD_GetCardSizeMB()
{
    return s_storageSizeMB;
}

const char* HAL::SD_GetTypeName()
{
    return "iOS";
}

void HAL::SD_SetEventCallback(SD_CallbackFunction_t callback)
{
    s_sdCallback = callback;
}

/* Encoder: fed by the Camera Control button through XTCore_Encoder* */
void HAL::Encoder_Init()
{
}

void HAL::Encoder_Update()
{
}

int32_t HAL::Encoder_GetDiff()
{
    return 0;
}

bool HAL::Encoder_GetIsPush()
{
    return false;
}

void HAL::Encoder_SetEnable(bool en)
{
    s_encoderEnable = en;
}

bool HAL::Encoder_IsEnabled()
{
    return s_encoderEnable;
}

/* Buzzer */
void HAL::Buzz_init()
{
}

void HAL::Buzz_SetEnable(bool en)
{
    s_buzzEnable = en;
    if (!en)
    {
        XTPlatform_Tone(0, 0);
    }
}

void HAL::Buzz_Tone(uint32_t freq, int32_t duration)
{
    if (!s_buzzEnable)
    {
        return;
    }
    XTPlatform_Tone(freq, duration);
}

/* Audio */
void HAL::Audio_Init()
{
    s_player.SetCallback([](uint32_t freq, uint16_t volume)
    {
        HAL::Buzz_Tone(freq);
    });
}

void HAL::Audio_Update()
{
    s_player.Update(lv_tick_get());
}

bool HAL::Audio_PlayMusic(const char* name)
{
    bool retval = false;
    for (size_t i = 0; i < sizeof(MusicList) / sizeof(MusicList[0]); i++)
    {
        if (strcmp(name, MusicList[i].name) == 0)
        {
            s_player.Play(MusicList[i].mc, MusicList[i].length);
            retval = true;
            break;
        }
    }
    return retval;
}

/* Unused on iOS but declared in HAL.h */
void HAL::Memory_DumpInfo()
{
}
