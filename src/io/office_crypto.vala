namespace Singularity.Apps.Spreadsheet {

    public errordomain CryptoError {
        PASSWORD_REQUIRED,
        WRONG_PASSWORD,
        UNSUPPORTED
    }

    public class CfbNode {
        public string name;
        public bool storage;
        public uint8[] data = {};
        public Gee.ArrayList<CfbNode> children = new Gee.ArrayList<CfbNode> ();
        public int id;
        public int left = -1;
        public int right = -1;
        public int child = -1;
        public uint32 start;

        public CfbNode (string name, bool storage) {
            this.name = name;
            this.storage = storage;
        }

        public CfbNode add_stream (string n, uint8[] d) {
            var c = new CfbNode (n, false);
            c.data = d;
            children.add (c);
            return c;
        }

        public CfbNode add_storage (string n) {
            var c = new CfbNode (n, true);
            children.add (c);
            return c;
        }
    }

    public class CryptoCfbWriter {
        private const uint32 FREE = (uint32) 0xFFFFFFFFU;
        private const uint32 END = (uint32) 0xFFFFFFFEU;
        private const uint32 FATSECT = (uint32) 0xFFFFFFFDU;

        private static void put32 (ByteArray b, uint32 v) {
            b.append ({ (uint8) (v & 0xff), (uint8) ((v >> 8) & 0xff), (uint8) ((v >> 16) & 0xff), (uint8) ((v >> 24) & 0xff) });
        }

        private static void put16 (ByteArray b, uint16 v) {
            b.append ({ (uint8) (v & 0xff), (uint8) ((v >> 8) & 0xff) });
        }

        private static int compare (CfbNode a, CfbNode b) {
            int la = a.name.char_count (), lb = b.name.char_count ();
            if (la != lb) return la - lb;
            return strcmp (a.name.up (), b.name.up ());
        }

        private static int build_tree (Gee.List<CfbNode> sorted, int lo, int hi) {
            if (lo > hi) return -1;
            int mid = (lo + hi) / 2;
            var n = sorted[mid];
            n.left = build_tree (sorted, lo, mid - 1);
            n.right = build_tree (sorted, mid + 1, hi);
            return n.id;
        }

        private static void number (CfbNode n, Gee.ArrayList<CfbNode> all) {
            n.id = all.size;
            all.add (n);
            foreach (var c in n.children) number (c, all);
        }

        private static void link (CfbNode n) {
            if (n.children.size == 0) return;
            var sorted = new Gee.ArrayList<CfbNode> ();
            sorted.add_all (n.children);
            sorted.sort ((a, b) => compare (a, b));
            n.child = build_tree (sorted, 0, sorted.size - 1);
            foreach (var c in n.children) link (c);
        }

        private static uint32 add_chain (Gee.ArrayList<Bytes> sectors, Gee.ArrayList<uint32> fat, uint8[] d) {
            if (d.length == 0) return END;
            uint32 first = (uint32) sectors.size;
            int count = (d.length + 511) / 512;
            for (int i = 0; i < count; i++) {
                var s = new uint8[512];
                int len = int.min (512, d.length - i * 512);
                Memory.copy (s, (uint8*) d + i * 512, len);
                sectors.add (new Bytes (s));
                fat.add (i == count - 1 ? END : first + i + 1);
            }
            return first;
        }

        public static uint8[] build (CfbNode root) {
            var all = new Gee.ArrayList<CfbNode> ();
            number (root, all);
            link (root);
            var mini = new ByteArray ();
            var minifat = new Gee.ArrayList<uint32> ();
            var big = new Gee.ArrayList<CfbNode> ();
            foreach (var n in all) {
                if (n.storage || n == root) continue;
                if (n.data.length >= 4096) {
                    big.add (n);
                    continue;
                }
                if (n.data.length == 0) {
                    n.start = END;
                    continue;
                }
                uint32 first = (uint32) (mini.len / 64);
                int count = (n.data.length + 63) / 64;
                mini.append (n.data);
                while (mini.len % 64 != 0) mini.append ({ 0 });
                for (int i = 0; i < count; i++) minifat.add (i == count - 1 ? END : first + i + 1);
                n.start = first;
            }
            var sectors = new Gee.ArrayList<Bytes> ();
            var fat = new Gee.ArrayList<uint32> ();
            foreach (var n in big) n.start = add_chain (sectors, fat, n.data);
            root.start = add_chain (sectors, fat, mini.data);
            var mf = new ByteArray ();
            foreach (uint32 v in minifat) put32 (mf, v);
            while (mf.len % 512 != 0) put32 (mf, FREE);
            uint32 minifat_start = minifat.size > 0 ? add_chain (sectors, fat, mf.data) : END;
            int minifat_sectors = (int) (mf.len / 512);
            var dir = new ByteArray ();
            foreach (var n in all) {
                var name = new uint8[64];
                int k = 0;
                unichar c;
                int i = 0;
                while (n.name.get_next_char (ref i, out c) && k < 62) {
                    name[k++] = (uint8) (c & 0xff);
                    name[k++] = (uint8) ((c >> 8) & 0xff);
                }
                dir.append (name);
                put16 (dir, (uint16) (k + 2));
                dir.append ({ (uint8) (n == root ? 5 : (n.storage ? 1 : 2)), 1 });
                put32 (dir, (uint32) n.left);
                put32 (dir, (uint32) n.right);
                put32 (dir, (uint32) n.child);
                for (int z = 0; z < 16 + 4 + 16; z++) dir.append ({ 0 });
                put32 (dir, n.storage && n != root ? 0 : n.start);
                put32 (dir, n.storage && n != root ? 0 : (n == root ? mini.len : n.data.length));
                put32 (dir, 0);
            }
            while (dir.len % 512 != 0) {
                var empty = new uint8[128];
                dir.append (empty[0:64]);
                put16 (dir, 0);
                dir.append ({ 0, 0 });
                put32 (dir, FREE);
                put32 (dir, FREE);
                put32 (dir, FREE);
                for (int z = 0; z < 36 + 12; z++) dir.append ({ 0 });
            }
            uint32 dir_start = add_chain (sectors, fat, dir.data);
            int data_sectors = sectors.size;
            int fat_count = 1;
            while ((data_sectors + fat_count) > fat_count * 128) fat_count++;
            uint32 fat_first = (uint32) data_sectors;
            for (int i = 0; i < fat_count; i++) fat.add (FATSECT);
            var fatb = new ByteArray ();
            foreach (uint32 v in fat) put32 (fatb, v);
            while (fatb.len < fat_count * 512) put32 (fatb, FREE);
            var head = new ByteArray ();
            head.append ({ 0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1 });
            for (int z = 0; z < 16; z++) head.append ({ 0 });
            put16 (head, 0x3E);
            put16 (head, 3);
            put16 (head, 0xFFFE);
            put16 (head, 9);
            put16 (head, 6);
            for (int z = 0; z < 6; z++) head.append ({ 0 });
            put32 (head, 0);
            put32 (head, (uint32) fat_count);
            put32 (head, dir_start);
            put32 (head, 0);
            put32 (head, 4096);
            put32 (head, minifat_start);
            put32 (head, (uint32) minifat_sectors);
            put32 (head, END);
            put32 (head, 0);
            for (int i = 0; i < 109; i++) put32 (head, i < fat_count ? fat_first + i : FREE);
            var out_b = new ByteArray ();
            out_b.append (head.data);
            foreach (var s in sectors) out_b.append (s.get_data ());
            out_b.append (fatb.data);
            return out_b.steal ();
        }
    }

    public class OfficeCrypto {
        private const uint8[] BLOCK_VERIFIER_INPUT = { 0xfe, 0xa7, 0xd2, 0x76, 0x3b, 0x4b, 0x9e, 0x79 };
        private const uint8[] BLOCK_VERIFIER_VALUE = { 0xd7, 0xaa, 0x0f, 0x6d, 0x30, 0x61, 0x34, 0x4e };
        private const uint8[] BLOCK_KEY_VALUE = { 0x14, 0x6e, 0x0b, 0xe7, 0xab, 0xac, 0xd0, 0xd6 };
        private const uint8[] BLOCK_HMAC_KEY = { 0x5f, 0xb2, 0xad, 0x01, 0x0c, 0xb9, 0xe1, 0xf6 };
        private const uint8[] BLOCK_HMAC_VALUE = { 0xa0, 0x67, 0x7f, 0x02, 0xb2, 0x2c, 0x84, 0x33 };

        public static bool is_encrypted (uint8[] data) {
            if (!Cfb.sniff (data)) return false;
            try {
                var c = new Cfb (data);
                return c.streams.has_key ("EncryptionInfo") && c.streams.has_key ("EncryptedPackage");
            } catch (XlsError e) {
                return false;
            }
        }

        public static bool is_encrypted_file (string path) {
            try {
                uint8[] data;
                FileUtils.get_data (path, out data);
                return is_encrypted (data);
            } catch (Error e) {
                return false;
            }
        }

        private static uint8[] concat (uint8[] a, uint8[] b) {
            var r = new uint8[a.length + b.length];
            Memory.copy (r, a, a.length);
            Memory.copy ((uint8*) r + a.length, b, b.length);
            return r;
        }

        private static ChecksumType hash_type (string name) {
            switch (name.up ().replace ("-", "")) {
                case "SHA1": return ChecksumType.SHA1;
                case "SHA256": return ChecksumType.SHA256;
                case "SHA384": return ChecksumType.SHA384;
                default: return ChecksumType.SHA512;
            }
        }

        private static uint8[] hash (ChecksumType t, uint8[] d) {
            var ck = new Checksum (t);
            ck.update (d, d.length);
            size_t len = 64;
            var buf = new uint8[64];
            ck.get_digest (buf, ref len);
            buf.length = (int) len;
            return buf;
        }

        private static uint8[] le32 (uint32 v) {
            return { (uint8) (v & 0xff), (uint8) ((v >> 8) & 0xff), (uint8) ((v >> 16) & 0xff), (uint8) ((v >> 24) & 0xff) };
        }

        private static uint8[] fit (uint8[] d, int size, uint8 pad) {
            var r = new uint8[size];
            for (int i = 0; i < size; i++) r[i] = i < d.length ? d[i] : pad;
            return r;
        }

        private static uint8[] random_bytes (int n) {
            var r = new uint8[n];
            try {
                var s = File.new_for_path ("/dev/urandom").read ();
                size_t got;
                s.read_all (r, out got);
                s.close ();
                if (got == n) return r;
            } catch (Error e) {
            }
            for (int i = 0; i < n; i++) r[i] = (uint8) Random.int_range (0, 256);
            return r;
        }

        private static uint8[] agile_hash (ChecksumType t, string password, uint8[] salt, int spin) {
            var h = hash (t, concat (salt, PasswordHash.utf16le (password)));
            for (int i = 0; i < spin; i++) h = hash (t, concat (le32 (i), h));
            return h;
        }

        private static uint8[] agile_key (ChecksumType t, uint8[] h, uint8[] block, int bytes) {
            return fit (hash (t, concat (h, block)), bytes, 0x36);
        }

        private static uint8[] b64 (string s) {
            return (uint8[]) Base64.decode (s);
        }

        private static uint8[] hmac (ChecksumType t, uint8[] key, uint8[] data) {
            var h = new Hmac (t, key);
            h.update (data);
            size_t len = 64;
            var buf = new uint8[64];
            h.get_digest (buf, ref len);
            buf.length = (int) len;
            return buf;
        }

        public static uint8[] decrypt (uint8[] file, string password) throws Error {
            var cfb = new Cfb (file);
            var info = cfb.streams["EncryptionInfo"];
            var pkg = cfb.streams["EncryptedPackage"];
            if (info == null || pkg == null) throw new CryptoError.UNSUPPORTED ("not an encrypted package");
            unowned uint8[] id = info.get_data ();
            unowned uint8[] pd = pkg.get_data ();
            int major = id[0] | (id[1] << 8);
            int minor = id[2] | (id[3] << 8);
            uint64 size = 0;
            for (int i = 7; i >= 0; i--) size = (size << 8) | pd[i];
            if (major == 4 && minor == 4) return decrypt_agile (id, pd, size, password);
            if ((major == 3 || major == 4) && minor == 2) return decrypt_standard (id, pd, size, password);
            throw new CryptoError.UNSUPPORTED ("unsupported encryption version %d.%d", major, minor);
        }

        private static uint8[] decrypt_agile (uint8[] info, uint8[] pkg, uint64 size, string password) throws Error {
            string xml = (string) info[8:info.length];
            xml = xml.substring (0, int.min (xml.length, info.length - 8));
            var doc = Xml.Parser.read_memory (xml, xml.length, null, null, Xml.ParserOption.NONET);
            if (doc == null) throw new CryptoError.UNSUPPORTED ("bad encryption info");
            Xml.Node* key_data = null;
            Xml.Node* enc_key = null;
            find (doc->get_root_element (), ref key_data, ref enc_key);
            if (key_data == null || enc_key == null) {
                delete doc;
                throw new CryptoError.UNSUPPORTED ("only password encryption is supported");
            }
            var kd_salt = b64 (key_data->get_prop ("saltValue"));
            var kd_hash = hash_type (key_data->get_prop ("hashAlgorithm"));
            int kd_bits = int.parse (key_data->get_prop ("keyBits"));
            var pw_salt = b64 (enc_key->get_prop ("saltValue"));
            var pw_hash = hash_type (enc_key->get_prop ("hashAlgorithm"));
            int pw_bits = int.parse (enc_key->get_prop ("keyBits"));
            int spin = int.parse (enc_key->get_prop ("spinCount"));
            var ev_in = b64 (enc_key->get_prop ("encryptedVerifierHashInput"));
            var ev_val = b64 (enc_key->get_prop ("encryptedVerifierHashValue"));
            var ek_val = b64 (enc_key->get_prop ("encryptedKeyValue"));
            delete doc;
            var h = agile_hash (pw_hash, password, pw_salt, spin);
            var vin = new Aes (agile_key (pw_hash, h, BLOCK_VERIFIER_INPUT, pw_bits / 8)).cbc_decrypt (pw_salt, ev_in);
            var vval = new Aes (agile_key (pw_hash, h, BLOCK_VERIFIER_VALUE, pw_bits / 8)).cbc_decrypt (pw_salt, ev_val);
            var vh = hash (pw_hash, vin[0:16]);
            for (int i = 0; i < vh.length; i++) {
                if (i >= vval.length || vh[i] != vval[i]) throw new CryptoError.WRONG_PASSWORD ("wrong password");
            }
            var secret = new Aes (agile_key (pw_hash, h, BLOCK_KEY_VALUE, pw_bits / 8)).cbc_decrypt (pw_salt, ek_val);
            secret = secret[0:kd_bits / 8];
            var aes = new Aes (secret);
            var out_b = new ByteArray ();
            int seg = 0;
            for (int off = 8; off < pkg.length; off += 4096) {
                int len = int.min (4096, pkg.length - off);
                var iv = fit (hash (kd_hash, concat (kd_salt, le32 (seg))), 16, 0);
                out_b.append (aes.cbc_decrypt (iv, pkg[off:off + len]));
                seg++;
            }
            if (out_b.len > size) out_b.set_size ((uint) size);
            return out_b.steal ();
        }

        private static void find (Xml.Node* n, ref Xml.Node* key_data, ref Xml.Node* enc_key) {
            for (Xml.Node* c = n; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == "keyData") key_data = c;
                if (c->name == "encryptedKey" && c->get_prop ("encryptedKeyValue") != null) enc_key = c;
                if (c->children != null) find (c->children, ref key_data, ref enc_key);
            }
        }

        private static uint8[] decrypt_standard (uint8[] info, uint8[] pkg, uint64 size, string password) throws Error {
            int p = 8;
            uint32 header_size = info[p] | (info[p + 1] << 8) | (info[p + 2] << 16) | (info[p + 3] << 24);
            p += 4;
            int key_bits = info[p + 16] | (info[p + 17] << 8);
            p += (int) header_size;
            int salt_size = info[p] | (info[p + 1] << 8);
            p += 4;
            var salt = info[p:p + salt_size];
            p += salt_size;
            var enc_verifier = info[p:p + 16];
            p += 16;
            p += 4;
            var enc_hash = info[p:p + 32];
            var h = hash (ChecksumType.SHA1, concat (salt, PasswordHash.utf16le (password)));
            for (int i = 0; i < 50000; i++) h = hash (ChecksumType.SHA1, concat (le32 (i), h));
            h = hash (ChecksumType.SHA1, concat (h, le32 (0)));
            var buf1 = new uint8[64];
            var buf2 = new uint8[64];
            for (int i = 0; i < 64; i++) {
                buf1[i] = (uint8) (0x36 ^ (i < h.length ? h[i] : 0));
                buf2[i] = (uint8) (0x5c ^ (i < h.length ? h[i] : 0));
            }
            var key = concat (hash (ChecksumType.SHA1, buf1), hash (ChecksumType.SHA1, buf2))[0:key_bits / 8];
            var aes = new Aes (key);
            var verifier = aes.ecb_decrypt (enc_verifier);
            var vhash = aes.ecb_decrypt (enc_hash);
            var check = hash (ChecksumType.SHA1, verifier);
            for (int i = 0; i < 20; i++) if (check[i] != vhash[i]) throw new CryptoError.WRONG_PASSWORD ("wrong password");
            var out_b = aes.ecb_decrypt (pkg[8:pkg.length]);
            if (out_b.length > size) out_b.length = (int) size;
            return out_b;
        }

        private static uint8[] lp_unicode (string s) {
            var b = new ByteArray ();
            var u = PasswordHash.utf16le (s);
            b.append (le32 ((uint32) u.length));
            b.append (u);
            while (b.len % 4 != 0) b.append ({ 0 });
            return b.steal ();
        }

        private static uint8[] version_stream () {
            var b = new ByteArray ();
            b.append (lp_unicode ("Microsoft.Container.DataSpaces"));
            for (int i = 0; i < 3; i++) b.append ({ 1, 0, 0, 0 });
            return b.steal ();
        }

        private static uint8[] data_space_map () {
            var entry = new ByteArray ();
            entry.append (le32 (1));
            entry.append (le32 (0));
            entry.append (lp_unicode ("EncryptedPackage"));
            entry.append (lp_unicode ("StrongEncryptionDataSpace"));
            var b = new ByteArray ();
            b.append (le32 (8));
            b.append (le32 (1));
            b.append (le32 (entry.len + 4));
            b.append (entry.data);
            return b.steal ();
        }

        private static uint8[] data_space_info () {
            var b = new ByteArray ();
            b.append (le32 (8));
            b.append (le32 (1));
            b.append (lp_unicode ("StrongEncryptionTransform"));
            return b.steal ();
        }

        private static uint8[] primary () {
            var id = lp_unicode ("{FF9A3F03-56EF-4613-BDD5-5A41C1D07246}");
            var b = new ByteArray ();
            b.append (le32 ((uint32) (8 + id.length + 20)));
            b.append (le32 (1));
            b.append (id);
            b.append (lp_unicode ("Microsoft.Container.EncryptionTransform"));
            for (int i = 0; i < 3; i++) b.append ({ 1, 0, 0, 0 });
            b.append (le32 (7));
            b.append ("AES 128".data);
            b.append ({ 0 });
            b.append (le32 (16));
            b.append (le32 (0));
            b.append (le32 (4));
            return b.steal ();
        }

        public static uint8[] encrypt (uint8[] package, string password) {
            var t = ChecksumType.SHA512;
            int spin = 100000;
            var kd_salt = random_bytes (16);
            var pw_salt = random_bytes (16);
            var secret = random_bytes (32);
            var verifier = random_bytes (16);
            var h = agile_hash (t, password, pw_salt, spin);
            var ev_in = new Aes (agile_key (t, h, BLOCK_VERIFIER_INPUT, 32)).cbc_encrypt (pw_salt, verifier);
            var ev_val = new Aes (agile_key (t, h, BLOCK_VERIFIER_VALUE, 32)).cbc_encrypt (pw_salt, hash (t, verifier));
            var ek_val = new Aes (agile_key (t, h, BLOCK_KEY_VALUE, 32)).cbc_encrypt (pw_salt, secret);
            var aes = new Aes (secret);
            var pkg = new ByteArray ();
            uint64 size = package.length;
            for (int i = 0; i < 8; i++) pkg.append ({ (uint8) ((size >> (8 * i)) & 0xff) });
            int seg = 0;
            for (int off = 0; off < package.length; off += 4096) {
                int len = int.min (4096, package.length - off);
                var iv = fit (hash (t, concat (kd_salt, le32 (seg))), 16, 0);
                pkg.append (aes.cbc_encrypt (iv, package[off:off + len]));
                seg++;
            }
            var hmac_key = random_bytes (64);
            var iv_hk = fit (hash (t, concat (kd_salt, BLOCK_HMAC_KEY)), 16, 0);
            var enc_hmac_key = aes.cbc_encrypt (iv_hk, hmac_key);
            var hv = hmac (t, hmac_key, pkg.data);
            var iv_hv = fit (hash (t, concat (kd_salt, BLOCK_HMAC_VALUE)), 16, 0);
            var enc_hmac_value = aes.cbc_encrypt (iv_hv, hv);
            string xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n<encryption xmlns=\"http://schemas.microsoft.com/office/2006/encryption\" xmlns:p=\"http://schemas.microsoft.com/office/2006/keyEncryptor/password\" xmlns:c=\"http://schemas.microsoft.com/office/2006/keyEncryptor/certificate\">"
                + "<keyData saltSize=\"16\" blockSize=\"16\" keyBits=\"256\" hashSize=\"64\" cipherAlgorithm=\"AES\" cipherChaining=\"ChainingModeCBC\" hashAlgorithm=\"SHA512\" saltValue=\"%s\"/>".printf (Base64.encode (kd_salt))
                + "<dataIntegrity encryptedHmacKey=\"%s\" encryptedHmacValue=\"%s\"/>".printf (Base64.encode (enc_hmac_key), Base64.encode (enc_hmac_value))
                + "<keyEncryptors><keyEncryptor uri=\"http://schemas.microsoft.com/office/2006/keyEncryptor/password\"><p:encryptedKey spinCount=\"%d\" saltSize=\"16\" blockSize=\"16\" keyBits=\"256\" hashSize=\"64\" cipherAlgorithm=\"AES\" cipherChaining=\"ChainingModeCBC\" hashAlgorithm=\"SHA512\" saltValue=\"%s\" encryptedVerifierHashInput=\"%s\" encryptedVerifierHashValue=\"%s\" encryptedKeyValue=\"%s\"/></keyEncryptor></keyEncryptors></encryption>".printf (
                    spin, Base64.encode (pw_salt), Base64.encode (ev_in), Base64.encode (ev_val), Base64.encode (ek_val));
            var info = new ByteArray ();
            info.append ({ 4, 0, 4, 0, 0x40, 0, 0, 0 });
            info.append (xml.data);
            var root = new CfbNode ("Root Entry", true);
            root.add_stream ("EncryptionInfo", info.data);
            root.add_stream ("EncryptedPackage", pkg.data);
            var ds = root.add_storage ("\x06" + "DataSpaces");
            ds.add_stream ("Version", version_stream ());
            ds.add_stream ("DataSpaceMap", data_space_map ());
            ds.add_storage ("DataSpaceInfo").add_stream ("StrongEncryptionDataSpace", data_space_info ());
            ds.add_storage ("TransformInfo").add_storage ("StrongEncryptionTransform").add_stream ("\x06" + "Primary", primary ());
            return CryptoCfbWriter.build (root);
        }
    }
}
