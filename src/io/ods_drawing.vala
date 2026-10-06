namespace Singularity.Apps.Spreadsheet {

    public class OdsDrawing {
        private const double PX_CM = 37.795;

        private static string esc (string s) {
            return Ods.esc (s);
        }

        private static string cm (double v) {
            return Value.fixed (v, 3) + "cm";
        }

        public static string odf_ref (Workbook book, Sheet own, string excel_ref) {
            if (excel_ref == "") return "";
            var a = ChartResolve.area_of_ref (book, own, excel_ref);
            if (a == null) return "";
            if (a.sheet == null) a.sheet = own;
            return Ods.plain_range (a);
        }

        public static string excel_ref (string odf) {
            string t = odf.strip ();
            if (t == "") return "";
            int sp = -1;
            bool q = false;
            for (int i = 0; i < t.length; i++) {
                if (t[i] == '\'') q = !q;
                else if (t[i] == ' ' && !q) {
                    sp = i;
                    break;
                }
            }
            if (sp > 0) t = t.substring (0, sp);
            string[] parts = {};
            int start = 0;
            q = false;
            for (int i = 0; i < t.length; i++) {
                if (t[i] == '\'') q = !q;
                else if (t[i] == ':' && !q) {
                    parts += t.substring (start, i - start);
                    start = i + 1;
                }
            }
            parts += t.substring (start);
            string sheet = "";
            string[] cells = {};
            foreach (string p in parts) {
                int dot = -1;
                q = false;
                for (int i = 0; i < p.length; i++) {
                    if (p[i] == '\'') q = !q;
                    else if (p[i] == '.' && !q) dot = i;
                }
                string sh = dot >= 0 ? p.substring (0, dot) : "";
                string cell = dot >= 0 ? p.substring (dot + 1) : p;
                if (sh.has_prefix ("$")) sh = sh.substring (1);
                if (sh.has_prefix ("'") && sh.has_suffix ("'") && sh.length >= 2) sh = sh.substring (1, sh.length - 2).replace ("''", "'");
                if (sh != "" && sheet == "") sheet = sh;
                cells += cell.replace ("$", "");
            }
            if (cells.length == 0 || cells[0] == "") return "";
            int r, c;
            bool a1, a2;
            if (!Address.parse_cell (cells[0], out r, out c, out a1, out a2)) return "";
            string result = (sheet != "" ? Address.quote_sheet (sheet) + "!" : "") + Address.cell (r, c, true, true);
            if (cells.length > 1 && cells[1] != cells[0]) {
                int r2, c2;
                if (Address.parse_cell (cells[1], out r2, out c2, out a1, out a2)) result += ":" + Address.cell (r2, c2, true, true);
            }
            return result;
        }

        private static void to_odf_refs (Workbook book, Sheet own, Singularity.Charts.ChartSpec spec) {
            foreach (var s in spec.series) {
                s.name_ref = odf_ref (book, own, s.name_ref);
                s.values_ref = odf_ref (book, own, s.values_ref);
                s.categories_ref = odf_ref (book, own, s.categories_ref);
                s.x_ref = odf_ref (book, own, s.x_ref);
                s.sizes_ref = odf_ref (book, own, s.sizes_ref);
            }
        }

        private static string graphic_style (OdsOut o, Drawing d) {
            string name = "gr%d".printf (o.next ());
            var sb = new StringBuilder ("<style:style style:name=\"%s\" style:family=\"graphic\"><style:graphic-properties".printf (name));
            if (d.fill != "" && d.kind != DrawingKind.LINE && d.kind != DrawingKind.ARROW) sb.append (" draw:fill=\"solid\" draw:fill-color=\"%s\"".printf (d.fill));
            else sb.append (" draw:fill=\"none\"");
            if (d.opacity < 1) sb.append (" draw:opacity=\"%d%%\"".printf ((int) Math.round (d.opacity * 100)));
            if (d.stroke != "" && d.stroke_width > 0) sb.append (" draw:stroke=\"solid\" svg:stroke-color=\"%s\" svg:stroke-width=\"%s\"".printf (d.stroke, cm (d.stroke_width / PX_CM)));
            else sb.append (" draw:stroke=\"none\"");
            if (d.kind == DrawingKind.ARROW) sb.append (" draw:marker-end=\"Arrow\" draw:marker-end-width=\"%s\"".printf (cm (0.2 + d.stroke_width * 0.05)));
            if (d.kind == DrawingKind.TEXT_BOX) sb.append (" draw:textarea-vertical-align=\"top\" draw:auto-grow-height=\"false\"");
            else sb.append (" draw:textarea-horizontal-align=\"center\" draw:textarea-vertical-align=\"middle\"");
            sb.append ("/><style:text-properties fo:color=\"%s\" fo:font-size=\"%spt\"/></style:style>".printf (d.text_color.length == 7 ? d.text_color : "#000000", Value.format_number_general_full (d.font_size)));
            o.auto_styles.append (sb.str);
            return name;
        }

        private static string paragraphs (string text) {
            var sb = new StringBuilder ();
            foreach (string line in text.split ("\n")) sb.append ("<text:p>%s</text:p>".printf (esc (line)));
            return sb.str;
        }

        public static void write (OdsOut o) {
            var book = o.book;
            bool marker = false;
            int obj = 0;
            foreach (var s in book.sheets) {
                write_sparklines (o, s);
                if (s.charts.size == 0 && s.drawings.size == 0) continue;
                var sb = new StringBuilder ("<table:shapes>");
                int z = 0;
                foreach (var ch in s.charts) {
                    var spec = ChartResolve.resolve (book, s, ch);
                    to_odf_refs (book, s, spec);
                    double ax = SheetGeometry.to_abs_x (s, ch.x), ay = SheetGeometry.to_abs_y (s, ch.y);
                    double wcm = ch.width / Xlsx.COL_SCALE / PX_CM, hcm = ch.height / Xlsx.ROW_SCALE / PX_CM;
                    string content = Singularity.Charts.OdfChart.write_content (spec, wcm, hcm);
                    obj++;
                    string oname = "Object %d".printf (obj);
                    string frame = "<draw:frame draw:z-index=\"%d\" draw:name=\"%s\" svg:x=\"%s\" svg:y=\"%s\" svg:width=\"%s\" svg:height=\"%s\">".printf (
                        z++, esc (ch.name != "" ? ch.name : oname), cm (ax / Xlsx.COL_SCALE / PX_CM), cm (ay / Xlsx.ROW_SCALE / PX_CM), cm (wcm), cm (hcm));
                    string notify = "";
                    foreach (var ser in spec.series) if (ser.values_ref != "") notify += (notify != "" ? " " : "") + ser.values_ref;
                    if (o.flat) {
                        string inner = content;
                        int decl = inner.index_of ("?>");
                        if (decl >= 0) inner = inner.substring (decl + 2).strip ();
                        inner = inner.replace ("<office:document-content ", "<office:document office:mimetype=\"%s\" ".printf (Singularity.Charts.OdfChart.MEDIA_TYPE)).replace ("</office:document-content>", "</office:document>");
                        sb.append (frame + "<draw:object draw:notify-on-update-of-ranges=\"%s\">%s</draw:object>%s</draw:frame>".printf (esc (notify), inner, desc (ch.alt_text)));
                    } else {
                        o.files[oname + "/content.xml"] = new Bytes (content.data);
                        o.files[oname + "/styles.xml"] = new Bytes (Singularity.Charts.OdfChart.write_styles ().data);
                        o.manifest.append ("<manifest:file-entry manifest:full-path=\"%s/\" manifest:version=\"1.3\" manifest:media-type=\"%s\"/><manifest:file-entry manifest:full-path=\"%s/content.xml\" manifest:media-type=\"text/xml\"/><manifest:file-entry manifest:full-path=\"%s/styles.xml\" manifest:media-type=\"text/xml\"/>".printf (
                            esc (oname), Singularity.Charts.OdfChart.MEDIA_TYPE, esc (oname), esc (oname)));
                        sb.append (frame + "<draw:object draw:notify-on-update-of-ranges=\"%s\" xlink:href=\"./%s\" xlink:type=\"simple\" xlink:show=\"embed\" xlink:actuate=\"onLoad\"/>%s</draw:frame>".printf (esc (notify), esc (oname), desc (ch.alt_text)));
                    }
                }
                double ox = SheetGeometry.to_abs_x (s, 0), oy = SheetGeometry.to_abs_y (s, 0);
                foreach (var d in s.drawings) {
                    if (d.kind == DrawingKind.ARROW) marker = true;
                    foreach (var c in d.children) if (c.kind == DrawingKind.ARROW) marker = true;
                    write_drawing (o, sb, d, ox, oy, 1, 1, ref z);
                }
                sb.append ("</table:shapes>");
                o.put_table_start (s, sb.str);
            }
            if (marker) o.common_styles.append ("<draw:marker draw:name=\"Arrow\" svg:viewBox=\"0 0 20 30\" svg:d=\"M10 0l-10 30h20z\"/>");
        }

        private static string desc (string alt) {
            return alt != "" ? "<svg:desc>%s</svg:desc>".printf (esc (alt)) : "";
        }

        private static void write_drawing (OdsOut o, StringBuilder sb, Drawing d, double ox, double oy, double sx, double sy, ref int z) {
            double apx = ox + d.x * sx, apy = oy + d.y * sy;
            double wpx = d.width * sx, hpx = d.height * sy;
            if (d.kind == DrawingKind.GROUP) {
                double fw = d.frame_w > 0 ? d.frame_w : d.width, fh = d.frame_h > 0 ? d.frame_h : d.height;
                sb.append ("<draw:g%s>".printf (d.name != "" ? " draw:name=\"%s\"".printf (esc (d.name)) : ""));
                sb.append (desc (d.alt_text));
                foreach (var c in d.children) write_drawing (o, sb, c, apx, apy, fw > 0 ? wpx / fw : 1, fh > 0 ? hpx / fh : 1, ref z);
                sb.append ("</draw:g>");
                return;
            }
            double ax = apx / Xlsx.COL_SCALE / PX_CM, ay = apy / Xlsx.ROW_SCALE / PX_CM;
            double wcm = wpx / Xlsx.COL_SCALE / PX_CM, hcm = hpx / Xlsx.ROW_SCALE / PX_CM;
            string geo = "svg:x=\"%s\" svg:y=\"%s\" svg:width=\"%s\" svg:height=\"%s\"".printf (cm (ax), cm (ay), cm (wcm), cm (hcm));
            string nm = d.name != "" ? " draw:name=\"%s\"".printf (esc (d.name)) : "";
            string dsc = desc (d.alt_text);
            switch (d.kind) {
                case DrawingKind.IMAGE:
                    if (d.image == null) break;
                    string path = "Pictures/image%d.%s".printf (o.next (), Drawing.ext_of (d.mime));
                    if (o.flat) {
                        sb.append ("<draw:frame draw:z-index=\"%d\"%s %s><draw:image><office:binary-data>%s</office:binary-data></draw:image>%s</draw:frame>".printf (z++, nm, geo, Base64.encode (d.image.get_data ()), dsc));
                    } else {
                        o.add_file (path, d.image, d.mime);
                        sb.append ("<draw:frame draw:z-index=\"%d\"%s %s><draw:image xlink:href=\"%s\" xlink:type=\"simple\" xlink:show=\"embed\" xlink:actuate=\"onLoad\"/>%s</draw:frame>".printf (z++, nm, geo, path, dsc));
                    }
                    break;
                case DrawingKind.LINE:
                case DrawingKind.ARROW:
                    double x1 = d.flip_h ? ax + wcm : ax, x2 = d.flip_h ? ax : ax + wcm;
                    double y1 = d.flip_v ? ay + hcm : ay, y2 = d.flip_v ? ay : ay + hcm;
                    sb.append ("<draw:line draw:z-index=\"%d\"%s draw:style-name=\"%s\" svg:x1=\"%s\" svg:y1=\"%s\" svg:x2=\"%s\" svg:y2=\"%s\">%s<text:p/></draw:line>".printf (
                        z++, nm, graphic_style (o, d), cm (x1), cm (y1), cm (x2), cm (y2), dsc));
                    break;
                case DrawingKind.ELLIPSE:
                    sb.append ("<draw:ellipse draw:z-index=\"%d\"%s draw:style-name=\"%s\" %s>%s%s</draw:ellipse>".printf (z++, nm, graphic_style (o, d), geo, dsc, paragraphs (d.text)));
                    break;
                case DrawingKind.TEXT_BOX:
                    sb.append ("<draw:frame draw:z-index=\"%d\"%s draw:style-name=\"%s\" %s><draw:text-box>%s</draw:text-box>%s</draw:frame>".printf (z++, nm, graphic_style (o, d), geo, paragraphs (d.text), dsc));
                    break;
                default:
                    string radius = d.kind == DrawingKind.ROUNDED ? " draw:corner-radius=\"%s\"".printf (cm (double.min (wcm, hcm) * 0.16)) : "";
                    sb.append ("<draw:rect draw:z-index=\"%d\"%s draw:style-name=\"%s\" %s%s>%s%s</draw:rect>".printf (z++, nm, graphic_style (o, d), geo, radius, dsc, paragraphs (d.text)));
                    break;
            }
        }

        private static void write_sparklines (OdsOut o, Sheet s) {
            if (s.sparklines.size == 0) return;
            var sb = new StringBuilder ("<calcext:sparkline-groups>");
            int gi = 0;
            foreach (var g in s.sparklines) {
                if (g.items.size == 0) continue;
                gi++;
                sb.append ("<calcext:sparkline-group calcext:id=\"{%08X-0000-4000-8000-%012d}\" calcext:type=\"%s\" calcext:line-width=\"%spt\" calcext:display-empty-cells-as=\"gap\"".printf (
                    (uint) s.name.hash (), gi, g.kind.to_id (), Value.format_number_general_full (g.line_weight)));
                if (g.markers) sb.append (" calcext:markers=\"true\"");
                if (g.high) sb.append (" calcext:high=\"true\"");
                if (g.low) sb.append (" calcext:low=\"true\"");
                if (g.first) sb.append (" calcext:first=\"true\"");
                if (g.last) sb.append (" calcext:last=\"true\"");
                if (g.negative) sb.append (" calcext:negative=\"true\"");
                sb.append (" calcext:color-series=\"%s\" calcext:color-negative=\"%s\" calcext:color-axis=\"#000000\" calcext:color-markers=\"%s\" calcext:color-first=\"%s\" calcext:color-last=\"%s\" calcext:color-high=\"%s\" calcext:color-low=\"%s\"><calcext:sparklines>".printf (
                    g.color, g.negative_color, g.marker_color, g.marker_color, g.marker_color, g.high_color, g.low_color));
                foreach (var it in g.items) {
                    string src = odf_ref (o.book, s, it.source.has_prefix ("=") ? it.source.substring (1) : it.source);
                    sb.append ("<calcext:sparkline calcext:cell-address=\"%s\" calcext:data-range=\"%s\"/>".printf (esc (Ods.plain_range (new Area.cell (s, it.row, it.col))), esc (src)));
                }
                sb.append ("</calcext:sparklines></calcext:sparkline-group>");
            }
            sb.append ("</calcext:sparkline-groups>");
            o.put_table_end (s, sb.str);
        }

        private static double length_px (string v) {
            string t = v.strip ();
            if (t.has_suffix ("cm")) return double.parse (t.substring (0, t.length - 2)) * PX_CM;
            if (t.has_suffix ("mm")) return double.parse (t.substring (0, t.length - 2)) * PX_CM / 10;
            if (t.has_suffix ("in")) return double.parse (t.substring (0, t.length - 2)) * 96;
            if (t.has_suffix ("pt")) return double.parse (t.substring (0, t.length - 2)) * 96 / 72;
            if (t.has_suffix ("pc")) return double.parse (t.substring (0, t.length - 2)) * 16;
            return double.parse (t);
        }

        private static string a (Xml.Node* n, string name) {
            for (Xml.Attr* p = n->properties; p != null; p = p->next) {
                if (p->name == name) return p->children != null ? p->children->content : "";
            }
            return "";
        }

        private static string desc_of (Xml.Node* n) {
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE && c->name == "desc") return c->get_content ().strip ();
            }
            return "";
        }

        private static void place (Sheet s, Xml.Node* n, out double x, out double y, out double w, out double h) {
            x = SheetGeometry.from_abs_x (s, length_px (a (n, "x")) * Xlsx.COL_SCALE);
            y = SheetGeometry.from_abs_y (s, length_px (a (n, "y")) * Xlsx.ROW_SCALE);
            w = length_px (a (n, "width")) * Xlsx.COL_SCALE;
            h = length_px (a (n, "height")) * Xlsx.ROW_SCALE;
        }

        private static string node_text (Xml.Node* n) {
            string[] lines = {};
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == "p") lines += c->get_content ();
                else if (c->name == "text-box") return node_text (c);
            }
            return string.joinv ("\n", lines);
        }

        private static Gee.HashMap<string, Xml.Node*> graphic_styles (OdsIn inp) {
            var map = new Gee.HashMap<string, Xml.Node*> ();
            foreach (var e in inp.style_nodes.entries) map[e.key] = e.value;
            if (inp.content != null) {
                for (Xml.Node* c = inp.content->children; c != null; c = c->next) {
                    if (c->type != Xml.ElementType.ELEMENT_NODE || c->name != "automatic-styles") continue;
                    for (Xml.Node* st = c->children; st != null; st = st->next) {
                        if (st->type == Xml.ElementType.ELEMENT_NODE && st->name == "style") map[a (st, "name")] = st;
                    }
                }
            }
            return map;
        }

        private static void apply_style (Drawing d, Xml.Node* st) {
            if (st == null) return;
            for (Xml.Node* c = st->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == "graphic-properties") {
                    string fill = a (c, "fill");
                    if (fill == "none") d.fill = "";
                    string fc = a (c, "fill-color");
                    if (fc.length == 7 && fill != "none") d.fill = fc.down ();
                    string stroke = a (c, "stroke");
                    if (stroke == "none") d.stroke = "";
                    string sc = a (c, "stroke-color");
                    if (sc.length == 7 && stroke != "none") d.stroke = sc.down ();
                    string sw = a (c, "stroke-width");
                    if (sw != "") d.stroke_width = double.max (length_px (sw), 0.5);
                    if (a (c, "marker-end") != "" && d.kind == DrawingKind.LINE) d.kind = DrawingKind.ARROW;
                    string op = a (c, "opacity");
                    if (op.has_suffix ("%")) d.opacity = double.parse (op.substring (0, op.length - 1)) / 100.0;
                } else if (c->name == "text-properties") {
                    string col = a (c, "color");
                    if (col.length == 7) d.text_color = col.down ();
                    string fs = a (c, "font-size");
                    if (fs.has_suffix ("pt")) d.font_size = double.parse (fs.substring (0, fs.length - 2));
                }
            }
        }

        private static string? object_xml (OdsIn inp, Xml.Node* obj) {
            string href = a (obj, "href");
            if (href != "" && inp.zip != null) {
                string p = href.has_prefix ("./") ? href.substring (2) : href;
                try {
                    return inp.zip.read_text (p + "/content.xml");
                } catch (Error e) {
                    return null;
                }
            }
            for (Xml.Node* c = obj->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                var buf = new Xml.Buffer ();
                buf.node_dump (c->doc, c, 0, 0);
                return buf.content ();
            }
            return null;
        }

        private static Bytes? image_bytes (OdsIn inp, Xml.Node* img) {
            string href = a (img, "href");
            if (href != "" && inp.zip != null) {
                try {
                    var data = inp.zip.read (href.has_prefix ("./") ? href.substring (2) : href);
                    return data != null ? new Bytes (data) : null;
                } catch (Error e) {
                    return null;
                }
            }
            for (Xml.Node* c = img->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE && c->name == "binary-data") return new Bytes (Base64.decode (c->get_content ().strip ()));
            }
            return null;
        }

        private static void read_shape_node (OdsIn inp, Sheet s, Xml.Node* n, Gee.HashMap<string, Xml.Node*> styles, Gee.ArrayList<Drawing> target) {
            double x, y, w, h;
            switch (n->name) {
                case "g":
                    var g = new Drawing (DrawingKind.GROUP);
                    g.fill = "";
                    g.stroke = "";
                    g.name = a (n, "name");
                    g.alt_text = desc_of (n);
                    g.diagram = Diagrams.kind_from_name (g.name);
                    for (Xml.Node* c = n->children; c != null; c = c->next) {
                        if (c->type == Xml.ElementType.ELEMENT_NODE) read_shape_node (inp, s, c, styles, g.children);
                    }
                    if (g.children.size == 0) break;
                    double x1 = double.INFINITY, y1 = double.INFINITY, x2 = -double.INFINITY, y2 = -double.INFINITY;
                    foreach (var c in g.children) {
                        x1 = double.min (x1, c.x);
                        y1 = double.min (y1, c.y);
                        x2 = double.max (x2, c.x + c.width);
                        y2 = double.max (y2, c.y + c.height);
                    }
                    foreach (var c in g.children) {
                        c.x -= x1;
                        c.y -= y1;
                    }
                    g.x = x1;
                    g.y = y1;
                    g.width = g.frame_w = x2 - x1;
                    g.height = g.frame_h = y2 - y1;
                    target.add (g);
                    break;
                case "frame":
                    place (s, n, out x, out y, out w, out h);
                    for (Xml.Node* c = n->children; c != null; c = c->next) {
                        if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                        if (c->name == "object") {
                            string? xml = object_xml (inp, c);
                            if (xml == null) break;
                            var spec = Singularity.Charts.OdfChart.read_content (xml);
                            if (spec == null) break;
                            foreach (var ser in spec.series) {
                                ser.name_ref = excel_ref (ser.name_ref);
                                ser.values_ref = excel_ref (ser.values_ref);
                                ser.categories_ref = excel_ref (ser.categories_ref);
                                ser.x_ref = excel_ref (ser.x_ref);
                                ser.sizes_ref = excel_ref (ser.sizes_ref);
                            }
                            var chart = new Chart (new Area (s, 0, 0, 0, 0));
                            chart.title = spec.title;
                            spec.title = "";
                            chart.style = spec;
                            chart.kind = Chart.kind_of_spec (spec);
                            chart.name = a (n, "name");
                            chart.x = x;
                            chart.y = y;
                            chart.width = w;
                            chart.height = h;
                            ChartResolve.adopt_source (inp.book, s, chart);
                            chart.explicit_series = true;
                            chart.alt_text = desc_of (n);
                            s.charts.add (chart);
                            break;
                        }
                        if (c->name == "image") {
                            var bytes = image_bytes (inp, c);
                            if (bytes == null) break;
                            var d = new Drawing (DrawingKind.IMAGE);
                            d.image = bytes;
                            d.mime = Drawing.mime_of (bytes.get_data ());
                            d.name = a (n, "name");
                            d.x = x;
                            d.y = y;
                            d.width = w;
                            d.height = h;
                            d.alt_text = desc_of (n);
                            target.add (d);
                            break;
                        }
                        if (c->name == "text-box") {
                            var d = new Drawing (DrawingKind.TEXT_BOX);
                            apply_style (d, styles[a (n, "style-name")]);
                            d.text = node_text (c);
                            d.name = a (n, "name");
                            d.x = x;
                            d.y = y;
                            d.width = w;
                            d.height = h;
                            d.alt_text = desc_of (n);
                            target.add (d);
                            break;
                        }
                    }
                    break;
                case "rect":
                case "ellipse":
                case "custom-shape":
                    place (s, n, out x, out y, out w, out h);
                    DrawingKind k = n->name == "ellipse" ? DrawingKind.ELLIPSE : (a (n, "corner-radius") != "" ? DrawingKind.ROUNDED : DrawingKind.RECTANGLE);
                    if (n->name == "custom-shape") {
                        for (Xml.Node* c = n->children; c != null; c = c->next) {
                            if (c->type != Xml.ElementType.ELEMENT_NODE || c->name != "enhanced-geometry") continue;
                            string t = a (c, "type");
                            if (t == "ellipse" || t == "circle") k = DrawingKind.ELLIPSE;
                            else if (t.has_prefix ("round")) k = DrawingKind.ROUNDED;
                        }
                    }
                    var d = new Drawing (k);
                    apply_style (d, styles[a (n, "style-name")]);
                    d.text = node_text (n).strip ();
                    d.name = a (n, "name");
                    d.x = x;
                    d.y = y;
                    d.width = w;
                    d.height = h;
                    d.alt_text = desc_of (n);
                    target.add (d);
                    break;
                case "line":
                    double x1 = length_px (a (n, "x1")) * Xlsx.COL_SCALE, y1 = length_px (a (n, "y1")) * Xlsx.ROW_SCALE;
                    double x2 = length_px (a (n, "x2")) * Xlsx.COL_SCALE, y2 = length_px (a (n, "y2")) * Xlsx.ROW_SCALE;
                    var d = new Drawing (DrawingKind.LINE);
                    apply_style (d, styles[a (n, "style-name")]);
                    d.x = SheetGeometry.from_abs_x (s, double.min (x1, x2));
                    d.y = SheetGeometry.from_abs_y (s, double.min (y1, y2));
                    d.width = Math.fabs (x2 - x1);
                    d.height = Math.fabs (y2 - y1);
                    d.flip_h = x2 < x1;
                    d.flip_v = y2 < y1;
                    d.name = a (n, "name");
                    d.alt_text = desc_of (n);
                    target.add (d);
                    break;
            }
        }

        private static void walk (OdsIn inp, Sheet s, Xml.Node* n, Gee.HashMap<string, Xml.Node*> styles) {
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                switch (c->name) {
                    case "frame":
                    case "rect":
                    case "ellipse":
                    case "custom-shape":
                    case "line":
                    case "g":
                        read_shape_node (inp, s, c, styles, s.drawings);
                        break;
                    case "sparkline-groups":
                        read_sparklines (s, c);
                        break;
                    case "table-row":
                    case "table-rows":
                    case "table-row-group":
                    case "table-header-rows":
                    case "table-cell":
                    case "shapes":
                        walk (inp, s, c, styles);
                        break;
                }
            }
        }

        public static void read (OdsIn inp) {
            var styles = graphic_styles (inp);
            for (int i = 0; i < inp.tables.size && i < inp.book.sheets.size; i++) {
                walk (inp, inp.book.sheets[i], inp.tables[i], styles);
            }
        }

        private static void read_sparklines (Sheet s, Xml.Node* groups) {
            for (Xml.Node* gn = groups->children; gn != null; gn = gn->next) {
                if (gn->type != Xml.ElementType.ELEMENT_NODE || gn->name != "sparkline-group") continue;
                var g = new SparklineGroup ();
                g.kind = SparklineKind.from_id (a (gn, "type"));
                g.markers = a (gn, "markers") == "true";
                g.high = a (gn, "high") == "true";
                g.low = a (gn, "low") == "true";
                g.first = a (gn, "first") == "true";
                g.last = a (gn, "last") == "true";
                g.negative = a (gn, "negative") == "true";
                string lw = a (gn, "line-width");
                if (lw.has_suffix ("pt")) g.line_weight = double.parse (lw.substring (0, lw.length - 2));
                if (a (gn, "color-series").length == 7) g.color = a (gn, "color-series").down ();
                if (a (gn, "color-negative").length == 7) g.negative_color = a (gn, "color-negative").down ();
                if (a (gn, "color-markers").length == 7) g.marker_color = a (gn, "color-markers").down ();
                if (a (gn, "color-high").length == 7) g.high_color = a (gn, "color-high").down ();
                if (a (gn, "color-low").length == 7) g.low_color = a (gn, "color-low").down ();
                for (Xml.Node* sl = gn->children; sl != null; sl = sl->next) {
                    if (sl->type != Xml.ElementType.ELEMENT_NODE || sl->name != "sparklines") continue;
                    for (Xml.Node* it = sl->children; it != null; it = it->next) {
                        if (it->type != Xml.ElementType.ELEMENT_NODE) continue;
                        string cell = excel_ref (a (it, "cell-address"));
                        string src = excel_ref (a (it, "data-range"));
                        if (cell == "" || src == "") continue;
                        int bang = cell.last_index_of ("!");
                        string addr = (bang >= 0 ? cell.substring (bang + 1) : cell).replace ("$", "");
                        int r, c;
                        bool a1, a2;
                        if (!Address.parse_cell (addr, out r, out c, out a1, out a2)) continue;
                        g.items.add (new Sparkline (r, c, src));
                    }
                }
                if (g.items.size > 0) s.sparklines.add (g);
            }
        }
    }
}
