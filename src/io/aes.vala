namespace Singularity.Apps.Spreadsheet {

    public class Aes {
        private static uint8[]? sbox;
        private static uint8[]? inv;
        private uint8[] round_keys;
        private int rounds;

        private static uint8 xtime (uint8 x) {
            return (uint8) (((x << 1) ^ (((x >> 7) & 1) * 0x1b)) & 0xff);
        }

        private static uint8 mul (uint8 a, uint8 b) {
            uint8 r = 0;
            uint8 x = a;
            uint8 y = b;
            while (y != 0) {
                if ((y & 1) != 0) r ^= x;
                x = xtime (x);
                y >>= 1;
            }
            return r;
        }

        private static void init_tables () {
            if (sbox != null) return;
            var s = new uint8[256];
            var si = new uint8[256];
            uint8 p = 1, q = 1;
            do {
                p = (uint8) (p ^ ((p << 1) & 0xff) ^ (((p & 0x80) != 0) ? 0x1b : 0));
                q ^= (uint8) ((q << 1) & 0xff);
                q ^= (uint8) ((q << 2) & 0xff);
                q ^= (uint8) ((q << 4) & 0xff);
                if ((q & 0x80) != 0) q ^= 0x09;
                uint8 x = (uint8) (q ^ rotl (q, 1) ^ rotl (q, 2) ^ rotl (q, 3) ^ rotl (q, 4) ^ 0x63);
                s[p] = x;
                si[x] = p;
            } while (p != 1);
            s[0] = 0x63;
            si[0x63] = 0;
            sbox = s;
            inv = si;
        }

        private static uint8 rotl (uint8 x, int n) {
            return (uint8) (((x << n) | (x >> (8 - n))) & 0xff);
        }

        public Aes (uint8[] key) {
            init_tables ();
            int nk = key.length / 4;
            rounds = nk + 6;
            int total = 4 * (rounds + 1);
            round_keys = new uint8[total * 4];
            for (int i = 0; i < key.length; i++) round_keys[i] = key[i];
            uint8 rcon = 1;
            var t = new uint8[4];
            for (int i = nk; i < total; i++) {
                for (int j = 0; j < 4; j++) t[j] = round_keys[(i - 1) * 4 + j];
                if (i % nk == 0) {
                    uint8 tmp = t[0];
                    t[0] = (uint8) (sbox[t[1]] ^ rcon);
                    t[1] = sbox[t[2]];
                    t[2] = sbox[t[3]];
                    t[3] = sbox[tmp];
                    rcon = xtime (rcon);
                } else if (nk > 6 && i % nk == 4) {
                    for (int j = 0; j < 4; j++) t[j] = sbox[t[j]];
                }
                for (int j = 0; j < 4; j++) round_keys[i * 4 + j] = (uint8) (round_keys[(i - nk) * 4 + j] ^ t[j]);
            }
        }

        private void add_round_key (uint8[] st, int round) {
            for (int i = 0; i < 16; i++) st[i] ^= round_keys[round * 16 + i];
        }

        public void encrypt_block (uint8[] st) {
            add_round_key (st, 0);
            var tmp = new uint8[16];
            for (int round = 1; round <= rounds; round++) {
                for (int i = 0; i < 16; i++) st[i] = sbox[st[i]];
                for (int c = 0; c < 4; c++) for (int r = 0; r < 4; r++) tmp[c * 4 + r] = st[((c + r) % 4) * 4 + r];
                for (int i = 0; i < 16; i++) st[i] = tmp[i];
                if (round != rounds) {
                    for (int c = 0; c < 4; c++) {
                        uint8 a0 = st[c * 4], a1 = st[c * 4 + 1], a2 = st[c * 4 + 2], a3 = st[c * 4 + 3];
                        st[c * 4] = (uint8) (xtime (a0) ^ xtime (a1) ^ a1 ^ a2 ^ a3);
                        st[c * 4 + 1] = (uint8) (a0 ^ xtime (a1) ^ xtime (a2) ^ a2 ^ a3);
                        st[c * 4 + 2] = (uint8) (a0 ^ a1 ^ xtime (a2) ^ xtime (a3) ^ a3);
                        st[c * 4 + 3] = (uint8) (xtime (a0) ^ a0 ^ a1 ^ a2 ^ xtime (a3));
                    }
                }
                add_round_key (st, round);
            }
        }

        public void decrypt_block (uint8[] st) {
            add_round_key (st, rounds);
            var tmp = new uint8[16];
            for (int round = rounds - 1; round >= 0; round--) {
                for (int c = 0; c < 4; c++) for (int r = 0; r < 4; r++) tmp[((c + r) % 4) * 4 + r] = st[c * 4 + r];
                for (int i = 0; i < 16; i++) st[i] = inv[tmp[i]];
                add_round_key (st, round);
                if (round != 0) {
                    for (int c = 0; c < 4; c++) {
                        uint8 a0 = st[c * 4], a1 = st[c * 4 + 1], a2 = st[c * 4 + 2], a3 = st[c * 4 + 3];
                        st[c * 4] = (uint8) (mul (a0, 14) ^ mul (a1, 11) ^ mul (a2, 13) ^ mul (a3, 9));
                        st[c * 4 + 1] = (uint8) (mul (a0, 9) ^ mul (a1, 14) ^ mul (a2, 11) ^ mul (a3, 13));
                        st[c * 4 + 2] = (uint8) (mul (a0, 13) ^ mul (a1, 9) ^ mul (a2, 14) ^ mul (a3, 11));
                        st[c * 4 + 3] = (uint8) (mul (a0, 11) ^ mul (a1, 13) ^ mul (a2, 9) ^ mul (a3, 14));
                    }
                }
            }
        }

        public uint8[] cbc_encrypt (uint8[] iv, uint8[] data) {
            int n = (data.length + 15) / 16 * 16;
            var out_b = new uint8[n];
            var prev = new uint8[16];
            for (int i = 0; i < 16; i++) prev[i] = i < iv.length ? iv[i] : 0;
            var blk = new uint8[16];
            for (int off = 0; off < n; off += 16) {
                for (int i = 0; i < 16; i++) blk[i] = (uint8) ((off + i < data.length ? data[off + i] : 0) ^ prev[i]);
                encrypt_block (blk);
                for (int i = 0; i < 16; i++) {
                    out_b[off + i] = blk[i];
                    prev[i] = blk[i];
                }
            }
            return out_b;
        }

        public uint8[] cbc_decrypt (uint8[] iv, uint8[] data) {
            int n = data.length / 16 * 16;
            var out_b = new uint8[n];
            var prev = new uint8[16];
            for (int i = 0; i < 16; i++) prev[i] = i < iv.length ? iv[i] : 0;
            var blk = new uint8[16];
            for (int off = 0; off < n; off += 16) {
                for (int i = 0; i < 16; i++) blk[i] = data[off + i];
                decrypt_block (blk);
                for (int i = 0; i < 16; i++) {
                    out_b[off + i] = (uint8) (blk[i] ^ prev[i]);
                    prev[i] = data[off + i];
                }
            }
            return out_b;
        }

        public uint8[] ecb_decrypt (uint8[] data) {
            int n = data.length / 16 * 16;
            var out_b = new uint8[n];
            var blk = new uint8[16];
            for (int off = 0; off < n; off += 16) {
                for (int i = 0; i < 16; i++) blk[i] = data[off + i];
                decrypt_block (blk);
                for (int i = 0; i < 16; i++) out_b[off + i] = blk[i];
            }
            return out_b;
        }

        public uint8[] ecb_encrypt (uint8[] data) {
            int n = (data.length + 15) / 16 * 16;
            var out_b = new uint8[n];
            var blk = new uint8[16];
            for (int off = 0; off < n; off += 16) {
                for (int i = 0; i < 16; i++) blk[i] = off + i < data.length ? data[off + i] : 0;
                encrypt_block (blk);
                for (int i = 0; i < 16; i++) out_b[off + i] = blk[i];
            }
            return out_b;
        }
    }
}
