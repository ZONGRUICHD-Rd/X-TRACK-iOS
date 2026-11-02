/*
 * X-TRACK iOS port - buzzer emulation (XTPlatform_Tone).
 * Generates a soft square wave, like the passive buzzer on the original hardware.
 * Uses the "ambient" audio session: mixes with music and respects the silent switch.
 */
#import <AVFoundation/AVFoundation.h>
#include "XTCore.h"
#include <atomic>
#include <math.h>

static AVAudioEngine* s_engine = nil;
static AVAudioSourceNode* s_source = nil;
static double s_sampleRate = 44100.0;

/* Main thread publishes a new tone request, the render thread picks it up
 * when the generation counter changes and then owns the countdown. */
static std::atomic<uint32_t> s_reqFreq(0);
static std::atomic<int64_t> s_reqSamples(-1); /* -1 = endless */
static std::atomic<uint32_t> s_reqGen(0);

static bool Tone_EnsureEngine(void)
{
    if (s_engine && s_engine.isRunning)
    {
        return true;
    }

    if (!s_engine)
    {
        AVAudioSession* session = AVAudioSession.sharedInstance;
        [session setCategory:AVAudioSessionCategoryAmbient
                 withOptions:AVAudioSessionCategoryOptionMixWithOthers
                       error:nil];
        [session setActive:YES error:nil];

        s_engine = [AVAudioEngine new];
        AVAudioFormat* outFormat = [s_engine.outputNode inputFormatForBus:0];
        s_sampleRate = outFormat.sampleRate > 0 ? outFormat.sampleRate : 44100.0;
        AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:s_sampleRate channels:1];

        s_source = [[AVAudioSourceNode alloc]
            initWithFormat:format
               renderBlock:^OSStatus(BOOL* isSilence, const AudioTimeStamp* timestamp, AVAudioFrameCount frameCount,
                                     AudioBufferList* outputData) {
                   static uint32_t gen = 0;
                   static uint32_t freq = 0;
                   static int64_t left = 0;
                   static double phase = 0.0;

                   uint32_t newGen = s_reqGen.load(std::memory_order_acquire);
                   if (newGen != gen)
                   {
                       gen = newGen;
                       freq = s_reqFreq.load(std::memory_order_relaxed);
                       left = s_reqSamples.load(std::memory_order_relaxed);
                   }

                   float* out = (float*)outputData->mBuffers[0].mData;
                   const double sr = s_sampleRate;
                   bool silent = true;

                   for (AVAudioFrameCount i = 0; i < frameCount; i++)
                   {
                       float v = 0.0f;
                       if (freq > 0 && left != 0)
                       {
                           phase += (double)freq / sr;
                           phase -= floor(phase);
                           /* Slightly rounded square wave, like a passive buzzer */
                           v = (float)(tanh(sin(2.0 * M_PI * phase) * 4.0) * 0.12);
                           silent = false;
                           if (left > 0)
                           {
                               left--;
                           }
                       }
                       out[i] = v;
                   }

                   *isSilence = silent;
                   return noErr;
               }];

        [s_engine attachNode:s_source];
        [s_engine connect:s_source to:s_engine.mainMixerNode format:format];
    }

    NSError* error = nil;
    if (![s_engine startAndReturnError:&error])
    {
        NSLog(@"[Tone] audio engine start failed: %@", error);
        return false;
    }
    return true;
}

extern "C" void XTPlatform_Tone(uint32_t freq, int32_t durationMs)
{
    if (freq == 0)
    {
        s_reqFreq.store(0, std::memory_order_relaxed);
        s_reqSamples.store(0, std::memory_order_relaxed);
        s_reqGen.fetch_add(1, std::memory_order_release);
        return;
    }

    if (!Tone_EnsureEngine())
    {
        return;
    }

    int64_t samples = durationMs < 0 ? -1 : (int64_t)(s_sampleRate * durationMs / 1000.0);
    if (samples == 0)
    {
        samples = 1;
    }
    s_reqFreq.store(freq, std::memory_order_relaxed);
    s_reqSamples.store(samples, std::memory_order_relaxed);
    s_reqGen.fetch_add(1, std::memory_order_release);
}
