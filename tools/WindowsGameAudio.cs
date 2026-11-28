using System;
using System.Runtime.InteropServices;

// Windows Core Audio interfaces. Unused methods retain their native vtable slots.
namespace VolleyballAudio {
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    class DeviceEnumerator {}

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IDevices {
        void EnumAudioEndpoints(int flow, uint state, out ICollection devices);
    }
    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ICollection {
        void GetCount(out uint count);
        void Item(uint index, out IDevice device);
    }
    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IDevice {
        void Activate(ref Guid iid, uint context, IntPtr parameters,
            [MarshalAs(UnmanagedType.IUnknown)] out object instance);
    }
    [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IManager {
        void GetAudioSessionControl(); void GetSimpleAudioVolume();
        void GetSessionEnumerator(out ISessions sessions);
    }
    [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ISessions {
        void GetCount(out int count);
        void GetSession(int index, [MarshalAs(UnmanagedType.IUnknown)] out object session);
    }
    [ComImport, Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ISession {
        void GetState(out int state);
        void GetDisplayName(); void SetDisplayName(); void GetIconPath(); void SetIconPath();
        void GetGroupingParam(); void SetGroupingParam(); void RegisterAudioSessionNotification();
        void UnregisterAudioSessionNotification(); void GetSessionIdentifier(); void GetSessionInstanceIdentifier();
        void GetProcessId(out uint pid);
    }
    [ComImport, Guid("1C158861-B533-4B30-B1CF-E853E51C59B8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IChannels {
        void GetChannelCount(out uint count);
        void SetChannelVolume(uint channel, float level, IntPtr context);
        void GetChannelVolume(uint channel, out float level);
    }
    public static class SessionRepair {
        public static int Main(string[] args) {
            uint pid;
            if (args.Length != 1 || !uint.TryParse(args[0], out pid)) return 2;
            for (int i = 0; i < 40; i++) {
                try { if (Check(pid)) return 0; } catch (COMException) {}
                System.Threading.Thread.Sleep(250);
            }
            return 1;
        }

        public static bool Check(uint pid) {
            ICollection devices;
            ((IDevices)new DeviceEnumerator()).EnumAudioEndpoints(0, 1, out devices);
            uint count;
            devices.GetCount(out count);
            for (uint n = 0; n < count; n++) {
                IDevice device;
                devices.Item(n, out device);
                Guid iid = typeof(IManager).GUID;
                object manager;
                try { device.Activate(ref iid, 23, IntPtr.Zero, out manager); }
                catch (COMException) { continue; }
                ISessions sessions;
                ((IManager)manager).GetSessionEnumerator(out sessions);
                int length;
                sessions.GetCount(out length);
                for (int i = 0; i < length; i++) {
                    object item;
                    sessions.GetSession(i, out item);
                    ISession session = (ISession)item;
                    uint owner;
                    int state;
                    session.GetProcessId(out owner);
                    session.GetState(out state);
                    if (owner != pid || state != 1) continue;
                    IChannels channels = (IChannels)item;
                    uint total;
                    channels.GetChannelCount(out total);
                    if (total != 2) return true;
                    // Only repair the specific symmetric -72 dB fault observed in this game.
                    for (uint c = 0; c < total; c++) {
                        float gain;
                        channels.GetChannelVolume(c, out gain);
                        if (Math.Abs(gain - 0.0002511886f) > 0.000001f) return true;
                    }
                    for (uint c = 0; c < total; c++) channels.SetChannelVolume(c, 1f, IntPtr.Zero);
                    return true;
                }
            }
            return false;
        }
    }
}
