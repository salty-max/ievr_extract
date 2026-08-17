$code = @'
using System;
using System.Text;
using System.Collections.Generic;

public static class Cri3 {
    public static uint[] Table;
    static int[] invHigh;
    static Cri3() {
        Table = new uint[256];
        for (int i = 0; i < 256; i++) {
            uint crc = (uint)i;
            for (int j = 0; j < 8; j++)
                crc = ((crc & 1) != 0) ? ((crc >> 1) ^ 0xEDB88320u) : (crc >> 1);
            Table[i] = crc;
        }
        invHigh = new int[256];
        for (int i = 0; i < 256; i++) invHigh[Table[i] >> 24] = i;
    }

    public static byte[] ComputeKey(string name) {
        uint crc = 0xFFFFFFFFu;
        foreach (byte b in Encoding.UTF8.GetBytes(name)) {
            uint idx = (crc ^ b) & 0xFF;
            crc = (crc >> 8) ^ Table[idx];
        }
        return BitConverter.GetBytes(~crc);
    }

    public static uint UpdateCrcState(uint seed, byte[] keys) {
        uint crc = ~seed;
        for (int i = 0; i < 4; i++) {
            byte idx = (byte)((crc & 0xFF) ^ keys[i]);
            crc = (crc >> 8) ^ Table[idx];
        }
        return ~crc;
    }

    public static uint KeyStreamU32(uint crc) {
        uint final = 0;
        for (int lane = 0; lane < 4; lane++) {
            int s = lane << 1;
            uint r8 = (crc >> (s + 8)) & 3;
            r8 = (r8 | (((crc >> s) & 0xFF) << 2)) & 0xFF;
            r8 = ((r8 << 2) & 0xFF) | ((crc >> (s + 16)) & 3);
            r8 = ((r8 << 2) & 0xFF) | ((crc >> (s + 24)) & 3);
            final |= r8 << (lane * 8);
        }
        return final;
    }

    public static uint CrcFromKeyStream(uint ks) {
        uint crc = 0;
        for (int lane = 0; lane < 4; lane++) {
            int s = lane << 1;
            uint b = (ks >> (lane * 8)) & 0xFF;
            crc |= ((b >> 6) & 1) << s;
            crc |= ((b >> 7) & 1) << (s + 1);
            crc |= ((b >> 4) & 1) << (s + 8);
            crc |= ((b >> 5) & 1) << (s + 9);
            crc |= ((b >> 2) & 1) << (s + 16);
            crc |= ((b >> 3) & 1) << (s + 17);
            crc |= ((b >> 0) & 1) << (s + 24);
            crc |= ((b >> 1) & 1) << (s + 25);
        }
        return crc;
    }

    public static List<byte[]> RecoverKeys(uint seed, uint targetState) {
        var results = new List<byte[]>();
        uint c4 = ~targetState;
        uint start = ~seed;

        var mid = new Dictionary<uint, List<int>>();
        for (int k0 = 0; k0 < 256; k0++) {
            byte i0 = (byte)((start & 0xFF) ^ (uint)k0);
            uint c1 = (start >> 8) ^ Table[i0];
            for (int k1 = 0; k1 < 256; k1++) {
                byte i1 = (byte)((c1 & 0xFF) ^ (uint)k1);
                uint c2 = (c1 >> 8) ^ Table[i1];
                List<int> lst;
                if (!mid.TryGetValue(c2, out lst)) { lst = new List<int>(); mid[c2] = lst; }
                lst.Add((k0 << 8) | k1);
            }
        }

        int idx3 = invHigh[c4 >> 24];
        uint c3hi = c4 ^ Table[idx3];
        for (int c3low = 0; c3low < 256; c3low++) {
            uint c3 = (c3hi << 8) | (uint)c3low;
            int idx2 = invHigh[c3 >> 24];
            uint c2hi = c3 ^ Table[idx2];
            for (int c2low = 0; c2low < 256; c2low++) {
                uint c2 = (c2hi << 8) | (uint)c2low;
                List<int> lst;
                if (mid.TryGetValue(c2, out lst)) {
                    byte k2 = (byte)((uint)idx2 ^ (c2 & 0xFF));
                    byte k3 = (byte)((uint)idx3 ^ (c3 & 0xFF));
                    foreach (int pair in lst) {
                        var cand = new byte[] { (byte)(pair >> 8), (byte)(pair & 0xFF), k2, k3 };
                        if (UpdateCrcState(seed, cand) == targetState) results.Add(cand);
                    }
                }
            }
        }
        return results;
    }

    public static byte[] DecryptRange(byte[] data, long start, int len, byte[] keys) {
        var outb = new byte[len];
        for (int i = 0; i < len; i += 4) {
            uint pos = (uint)(start + i);
            uint ks = KeyStreamU32(UpdateCrcState(pos, keys));
            for (int j = 0; j < 4 && i + j < len; j++)
                outb[i + j] = (byte)(data[start + i + j] ^ (byte)(ks >> (8 * j)));
        }
        return outb;
    }
}

public static class Drag {
    public class Hit {
        public long Offset;
        public byte[] Key;
        public double Score;
        public string Sample;
    }

    static uint LE(byte[] d, long o) {
        return (uint)(d[o] | (d[o+1] << 8) | (d[o+2] << 16) | (d[o+3] << 24));
    }

    public static double Score(byte[] dec) {
        int printable = 0;
        foreach (byte x in dec) if ((x >= 32 && x < 127) || x == 0) printable++;
        return (double)printable / dec.Length;
    }

    public static string Ascii(byte[] d, int len) {
        var sb = new StringBuilder();
        for (int i = 0; i < len && i < d.Length; i++)
            sb.Append((d[i] >= 32 && d[i] < 127) ? (char)d[i] : '.');
        return sb.ToString();
    }

    public static List<Hit> Run(byte[] data, long from, long to, uint crib, long probeOff, int probeLen, double minScore) {
        var hits = new List<Hit>();
        for (long o = from; o + 4 <= to; o += 4) {
            uint ks = LE(data, o) ^ crib;
            uint state = Cri3.CrcFromKeyStream(ks);
            var keys = Cri3.RecoverKeys((uint)o, state);
            foreach (var k in keys) {
                var dec = Cri3.DecryptRange(data, probeOff, probeLen, k);
                double s = Score(dec);
                if (s >= minScore)
                    hits.Add(new Hit { Offset = o, Key = k, Score = s, Sample = Ascii(dec, 160) });
            }
        }
        return hits;
    }
}
'@
if (-not ([System.Management.Automation.PSTypeName]'Cri3').Type) {
    Add-Type -TypeDefinition $code -Language CSharp
}
