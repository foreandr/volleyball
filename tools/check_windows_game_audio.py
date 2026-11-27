"""Measure a live hitting demo through Windows Core Audio and WASAPI loopback.
Requires pycaw and PyAudioWPatch. Run while the normal Windows build is playing.
"""
from ctypes import POINTER, c_float, c_uint
from comtypes import COMMETHOD, GUID, HRESULT, IUnknown

import array
import math
import time

import pyaudiowpatch as pa
from pycaw.api.endpointvolume import IAudioMeterInformation
from pycaw.pycaw import AudioUtilities


class IChannelAudioVolume(IUnknown):
    _iid_ = GUID("{1C158861-B533-4B30-B1CF-E853E51C59B8}")
    _methods_ = [
        COMMETHOD([], HRESULT, "GetChannelCount", (["out"], POINTER(c_uint), "count")),
        COMMETHOD([], HRESULT, "SetChannelVolume", (["in"], c_uint, "channel"),
                  (["in"], c_float, "gain"), (["in"], POINTER(GUID), "context")),
        COMMETHOD([], HRESULT, "GetChannelVolume", (["in"], c_uint, "channel"),
                  (["out"], POINTER(c_float), "gain")),
    ]


def measure(seconds=25):
    session = next(s for s in AudioUtilities.GetAllSessions()
                   if s.State == 1 and s.Process and s.Process.name() == "VolleyballPractice.exe")
    channels = session._ctl.QueryInterface(IChannelAudioVolume)
    gains = [channels.GetChannelVolume(i) for i in range(channels.GetChannelCount())]
    print("Windows game channel gains:", gains)
    if max(gains, default=0.) < .001:
        print("Game channel levels are below -60 dB in Windows.")
        return False
    meter = session._ctl.QueryInterface(IAudioMeterInformation)
    print("Game mute:", session.SimpleAudioVolume.GetMute(),
          "game volume:", session.SimpleAudioVolume.GetMasterVolume())
    with pa.PyAudio() as audio:
        endpoint = audio.get_default_wasapi_loopback()
        rate = int(endpoint["defaultSampleRate"])
        with audio.open(format=pa.paFloat32, channels=endpoint["maxInputChannels"],
                        rate=rate, input=True, input_device_index=endpoint["index"],
                        frames_per_buffer=1024) as stream:
            peak = concurrent_peak = output_peak = 0.
            active_blocks = 0
            until = time.monotonic() + seconds
            while time.monotonic() < until:
                samples = array.array("f", stream.read(1024, exception_on_overflow=False))
                block_peak = max(abs(v) for v in samples)
                level = meter.GetPeakValue()
                peak = max(peak, level)
                output_peak = max(output_peak, block_peak)
                if level > .002:
                    active_blocks += 1
                    concurrent_peak = max(concurrent_peak, block_peak)
    print(endpoint["name"], "game peak", round(peak, 4),
          "endpoint peak", round(output_peak, 4), "concurrent peak", round(concurrent_peak, 4),
          "active blocks", active_blocks)
    return active_blocks > 0 and concurrent_peak > .001 and math.isfinite(output_peak)


if __name__ == "__main__":
    raise SystemExit(0 if measure() else 1)
