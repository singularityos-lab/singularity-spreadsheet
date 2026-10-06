namespace Singularity.Apps.Spreadsheet {

    public class XlsxDrawing {
        private const string REL_DRAWING = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing";
        private const string REL_IMAGE = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image";
        private const string CT_DRAWING = "application/vnd.openxmlformats-officedocument.drawing+xml";
        private const string NS_XDR = "http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing";
        private const string NS_A = "http://schemas.openxmlformats.org/drawingml/2006/main";
        private const string NS_R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
        private const string NS_C = "http://schemas.openxmlformats.org/drawingml/2006/chart";
        private const string SPARK_URI = "{05C60535-1F16-4fd2-B633-F4F36F0B64E0}";
        private const double EMU = 9525;

        private static string esc (string s) {
            return XlsxWriter.esc (s);
        }

        private static string hexv (string color) {
            return color.length == 7 ? color.substring (1).up () : "000000";
        }

        private static string anchor_point (string tag, Sheet s, double abs_x, double abs_y) {
            int col, row;
            double ox, oy;
            SheetGeometry.locate_col (s, abs_x, out col, out ox);
            SheetGeometry.locate_row (s, abs_y, out row, out oy);
            int64 cx = (int64) Math.round (ox / Xlsx.COL_SCALE * EMU);
            int64 cy = (int64) Math.round (oy / Xlsx.ROW_SCALE * EMU);
            return "<xdr:%s><xdr:col>%d</xdr:col><xdr:colOff>%s</xdr:colOff><xdr:row>%d</xdr:row><xdr:rowOff>%s</xdr:rowOff></xdr:%s>".printf (tag, col, cx.to_string (), row, cy.to_string (), tag);
        }

        private static string anchor_open (Sheet s, double x, double y, double w, double h) {
            double ax = SheetGeometry.to_abs_x (s, x), ay = SheetGeometry.to_abs_y (s, y);
            return "<xdr:twoCellAnchor editAs=\"oneCell\">" + anchor_point ("from", s, ax, ay) + anchor_point ("to", s, ax + w, ay + h);
        }

        private static string xfrm (double w, double h, bool flip_h = false, bool flip_v = false) {
            int64 cx = (int64) Math.round (w / Xlsx.COL_SCALE * EMU);
            int64 cy = (int64) Math.round (h / Xlsx.ROW_SCALE * EMU);
            return "<a:xfrm%s%s><a:off x=\"0\" y=\"0\"/><a:ext cx=\"%s\" cy=\"%s\"/></a:xfrm>".printf (flip_h ? " flipH=\"1\"" : "", flip_v ? " flipV=\"1\"" : "", cx.to_string (), cy.to_string ());
        }

        private static string prst (DrawingKind k) {
            switch (k) {
                case DrawingKind.ROUNDED: return "roundRect";
                case DrawingKind.ELLIPSE: return "ellipse";
                case DrawingKind.LINE: case DrawingKind.ARROW: return "straightConnector1";
                default: return "rect";
            }
        }

        private static string descr (string alt) {
            return alt != "" ? " descr=\"%s\"".printf (esc (alt)) : "";
        }

        private static string child_xfrm (Drawing d) {
            int64 x = (int64) Math.round (d.x / Xlsx.COL_SCALE * EMU), y = (int64) Math.round (d.y / Xlsx.ROW_SCALE * EMU);
            int64 cx = (int64) Math.round (d.width / Xlsx.COL_SCALE * EMU), cy = (int64) Math.round (d.height / Xlsx.ROW_SCALE * EMU);
            return "<a:xfrm%s%s><a:off x=\"%s\" y=\"%s\"/><a:ext cx=\"%s\" cy=\"%s\"/></a:xfrm>".printf (d.flip_h ? " flipH=\"1\"" : "", d.flip_v ? " flipV=\"1\"" : "", x.to_string (), y.to_string (), cx.to_string (), cy.to_string ());
        }

        private static string group_xml (Sheet s, Drawing g, ref int id) {
            double ax = SheetGeometry.to_abs_x (s, g.x), ay = SheetGeometry.to_abs_y (s, g.y);
            double fw = g.frame_w > 0 ? g.frame_w : g.width, fh = g.frame_h > 0 ? g.frame_h : g.height;
            int64 ox = (int64) Math.round (ax / Xlsx.COL_SCALE * EMU), oy = (int64) Math.round (ay / Xlsx.ROW_SCALE * EMU);
            int64 cx = (int64) Math.round (g.width / Xlsx.COL_SCALE * EMU), cy = (int64) Math.round (g.height / Xlsx.ROW_SCALE * EMU);
            int64 fx = (int64) Math.round (fw / Xlsx.COL_SCALE * EMU), fy = (int64) Math.round (fh / Xlsx.ROW_SCALE * EMU);
            string name = g.name != "" ? g.name : "Group %d".printf (id);
            var sb = new StringBuilder ("<xdr:grpSp><xdr:nvGrpSpPr><xdr:cNvPr id=\"%d\" name=\"%s\"%s/><xdr:cNvGrpSpPr/></xdr:nvGrpSpPr>".printf (id++, esc (name), descr (g.alt_text)));
            sb.append ("<xdr:grpSpPr><a:xfrm><a:off x=\"%s\" y=\"%s\"/><a:ext cx=\"%s\" cy=\"%s\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"%s\" cy=\"%s\"/></a:xfrm></xdr:grpSpPr>".printf (
                ox.to_string (), oy.to_string (), cx.to_string (), cy.to_string (), fx.to_string (), fy.to_string ()));
            foreach (var c in g.children) {
                if (c.kind == DrawingKind.GROUP) sb.append (group_xml (s, c, ref id));
                else if (c.kind != DrawingKind.IMAGE) sb.append (shape_xml (c, id++, child_xfrm (c)));
            }
            sb.append ("</xdr:grpSp>");
            return sb.str;
        }

        private static string solid (string color, double opacity) {
            if (opacity >= 1) return "<a:solidFill><a:srgbClr val=\"%s\"/></a:solidFill>".printf (hexv (color));
            return "<a:solidFill><a:srgbClr val=\"%s\"><a:alpha val=\"%d\"/></a:srgbClr></a:solidFill>".printf (hexv (color), (int) (opacity * 100000));
        }

        private static string shape_xml (Drawing d, int id, string? xf = null) {
            string name = d.name != "" ? d.name : "%s %d".printf (d.kind == DrawingKind.TEXT_BOX ? "TextBox" : "Shape", id);
            string fill = d.fill != "" ? solid (d.fill, d.opacity) : "<a:noFill/>";
            string ln = d.stroke != "" && d.stroke_width > 0 ? "<a:ln w=\"%d\"><a:solidFill><a:srgbClr val=\"%s\"/></a:solidFill>%s</a:ln>".printf ((int) (d.stroke_width * 9525), hexv (d.stroke), d.kind == DrawingKind.ARROW ? "<a:tailEnd type=\"triangle\"/>" : "") : "<a:ln><a:noFill/></a:ln>";
            if (d.kind == DrawingKind.LINE || d.kind == DrawingKind.ARROW) {
                return "<xdr:cxnSp macro=\"\"><xdr:nvCxnSpPr><xdr:cNvPr id=\"%d\" name=\"%s\"%s/><xdr:cNvCxnSpPr/></xdr:nvCxnSpPr><xdr:spPr>%s<a:prstGeom prst=\"straightConnector1\"><a:avLst/></a:prstGeom>%s</xdr:spPr></xdr:cxnSp>".printf (
                    id, esc (name), descr (d.alt_text), xf ?? xfrm (d.width, d.height, d.flip_h, d.flip_v), ln);
            }
            var sb = new StringBuilder ("<xdr:sp macro=\"\" textlink=\"\"><xdr:nvSpPr><xdr:cNvPr id=\"%d\" name=\"%s\"%s/><xdr:cNvSpPr%s/></xdr:nvSpPr>".printf (id, esc (name), descr (d.alt_text), d.kind == DrawingKind.TEXT_BOX ? " txBox=\"1\"" : ""));
            sb.append ("<xdr:spPr>%s<a:prstGeom prst=\"%s\"><a:avLst/></a:prstGeom>%s%s</xdr:spPr>".printf (xf ?? xfrm (d.width, d.height), prst (d.kind), fill, ln));
            sb.append ("<xdr:txBody><a:bodyPr vertOverflow=\"clip\" horzOverflow=\"clip\" rtlCol=\"0\" anchor=\"%s\"/><a:lstStyle/>".printf (d.kind == DrawingKind.TEXT_BOX ? "t" : "ctr"));
            foreach (string line in d.text.split ("\n")) {
                sb.append ("<a:p><a:pPr algn=\"%s\"/>".printf (d.kind == DrawingKind.TEXT_BOX ? "l" : "ctr"));
                if (line != "") sb.append ("<a:r><a:rPr lang=\"en-US\" sz=\"%d\"><a:solidFill><a:srgbClr val=\"%s\"/></a:solidFill></a:rPr><a:t>%s</a:t></a:r>".printf ((int) (d.font_size * 100), hexv (d.text_color), esc (line)));
                sb.append ("</a:p>");
            }
            sb.append ("</xdr:txBody></xdr:sp>");
            return sb.str;
        }

        public static void write_sheet (XlsxSheetPart part) {
            var s = part.sheet;
            write_sparklines (part);
            if (s.charts.size == 0 && s.drawings.size == 0) return;
            var w = part.writer;
            int n = w.next_number ();
            string dpath = "xl/drawings/drawing%d.xml".printf (n);
            var rels = new StringBuilder ();
            int rid = 1;
            var sb = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n");
            sb.append ("<xdr:wsDr xmlns:xdr=\"%s\" xmlns:a=\"%s\" xmlns:r=\"%s\">".printf (NS_XDR, NS_A, NS_R));
            int id = 2;
            foreach (var ch in s.charts) {
                var spec = ChartResolve.resolve (w.book, s, ch);
                bool extended;
                string xml = Singularity.Charts.DrawingML.write_any (spec, out extended);
                int cn = w.next_number ();
                string cpath = extended ? "xl/charts/chartEx%d.xml".printf (cn) : "xl/charts/chart%d.xml".printf (cn);
                w.add_text_part (cpath, xml, extended ? Singularity.Charts.DrawingML.CHARTEX_CONTENT_TYPE : Singularity.Charts.DrawingML.CHART_CONTENT_TYPE);
                string r = "rId%d".printf (rid++);
                rels.append ("<Relationship Id=\"%s\" Type=\"%s\" Target=\"../charts/%s\"/>".printf (r, extended ? Singularity.Charts.DrawingML.CHARTEX_REL_TYPE : Singularity.Charts.DrawingML.CHART_REL_TYPE, Path.get_basename (cpath)));
                string name = ch.name != "" ? ch.name : "Chart %d".printf (id - 1);
                string frame = "<xdr:graphicFrame macro=\"\"><xdr:nvGraphicFramePr><xdr:cNvPr id=\"%d\" name=\"%s\"%s/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr><xdr:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/></xdr:xfrm><a:graphic>".printf (id++, esc (name), descr (ch.alt_text));
                sb.append (anchor_open (s, ch.x, ch.y, ch.width, ch.height));
                if (extended) {
                    bool funnel = spec.kind == Singularity.Charts.ChartType.FUNNEL;
                    string req = funnel ? "cx2" : "cx1";
                    string req_ns = funnel ? "http://schemas.microsoft.com/office/drawing/2015/10/21/chartex" : "http://schemas.microsoft.com/office/drawing/2015/9/8/chartex";
                    sb.append ("<mc:AlternateContent xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\"><mc:Choice xmlns:%s=\"%s\" Requires=\"%s\">".printf (req, req_ns, req));
                    sb.append (frame + "<a:graphicData uri=\"%s\"><cx:chart xmlns:cx=\"%s\" r:id=\"%s\"/></a:graphicData></a:graphic></xdr:graphicFrame>".printf (Singularity.Charts.DrawingML.NS_CX, Singularity.Charts.DrawingML.NS_CX, r));
                    sb.append ("</mc:Choice><mc:Fallback><xdr:sp macro=\"\" textlink=\"\"><xdr:nvSpPr><xdr:cNvPr id=\"%d\" name=\"%s\"/><xdr:cNvSpPr><a:spLocks noTextEdit=\"1\"/></xdr:cNvSpPr></xdr:nvSpPr><xdr:spPr>%s<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:solidFill><a:prstClr val=\"white\"/></a:solidFill><a:ln w=\"1\"><a:solidFill><a:prstClr val=\"green\"/></a:solidFill></a:ln></xdr:spPr><xdr:txBody><a:bodyPr vertOverflow=\"clip\" horzOverflow=\"clip\"/><a:lstStyle/><a:p><a:r><a:rPr lang=\"en-US\" sz=\"1100\"/><a:t>%s</a:t></a:r></a:p></xdr:txBody></xdr:sp></mc:Fallback></mc:AlternateContent>".printf (
                        id++, esc (name), xfrm (ch.width, ch.height), esc (_("This chart needs a newer version of Excel."))));
                } else {
                    sb.append (frame + "<a:graphicData uri=\"%s\"><c:chart xmlns:c=\"%s\" r:id=\"%s\"/></a:graphicData></a:graphic></xdr:graphicFrame>".printf (NS_C, NS_C, r));
                }
                sb.append ("<xdr:clientData/></xdr:twoCellAnchor>");
            }
            foreach (var d in s.drawings) {
                sb.append (anchor_open (s, d.x, d.y, d.width, d.height));
                if (d.kind == DrawingKind.IMAGE && d.image != null) {
                    string ext = Drawing.ext_of (d.mime);
                    string mpath = "xl/media/image%d.%s".printf (w.next_number (), ext);
                    w.add_binary_part (mpath, d.image, null);
                    w.defaults[ext] = d.mime;
                    string r = "rId%d".printf (rid++);
                    rels.append ("<Relationship Id=\"%s\" Type=\"%s\" Target=\"../media/%s\"/>".printf (r, REL_IMAGE, Path.get_basename (mpath)));
                    string name = d.name != "" ? d.name : "Picture %d".printf (id - 1);
                    sb.append ("<xdr:pic><xdr:nvPicPr><xdr:cNvPr id=\"%d\" name=\"%s\"%s/><xdr:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></xdr:cNvPicPr></xdr:nvPicPr><xdr:blipFill><a:blip r:embed=\"%s\"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill><xdr:spPr>%s<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic>".printf (
                        id++, esc (name), descr (d.alt_text), r, xfrm (d.width, d.height)));
                } else if (d.kind == DrawingKind.GROUP) {
                    sb.append (group_xml (s, d, ref id));
                } else {
                    sb.append (shape_xml (d, id++));
                }
                sb.append ("<xdr:clientData/></xdr:twoCellAnchor>");
            }
            sb.append ("</xdr:wsDr>");
            w.add_text_part (dpath, sb.str, CT_DRAWING);
            if (rels.len > 0) w.add_text_part ("xl/drawings/_rels/drawing%d.xml.rels".printf (n), "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" + rels.str + "</Relationships>", null);
            string did = part.add_rel (REL_DRAWING, "../drawings/drawing%d.xml".printf (n));
            part.put ("drawing", "<drawing r:id=\"%s\"/>".printf (did));
        }

        private static string argb (string c) {
            return "FF" + hexv (c);
        }

        private static void write_sparklines (XlsxSheetPart part) {
            var s = part.sheet;
            if (s.sparklines.size == 0) return;
            var sb = new StringBuilder ("<ext uri=\"%s\" xmlns:x14=\"http://schemas.microsoft.com/office/spreadsheetml/2009/9/main\"><x14:sparklineGroups xmlns:xm=\"http://schemas.microsoft.com/office/excel/2006/main\">".printf (SPARK_URI));
            foreach (var g in s.sparklines) {
                if (g.items.size == 0) continue;
                sb.append ("<x14:sparklineGroup");
                if (g.kind != SparklineKind.LINE) sb.append (" type=\"%s\"".printf (g.kind.to_id ()));
                sb.append (" displayEmptyCellsAs=\"gap\"");
                if (g.markers) sb.append (" markers=\"1\"");
                if (g.high) sb.append (" high=\"1\"");
                if (g.low) sb.append (" low=\"1\"");
                if (g.first) sb.append (" first=\"1\"");
                if (g.last) sb.append (" last=\"1\"");
                if (g.negative) sb.append (" negative=\"1\"");
                if (g.line_weight != 0.75) sb.append (" lineWeight=\"%s\"".printf (Value.format_number_general_full (g.line_weight)));
                sb.append (">");
                sb.append ("<x14:colorSeries rgb=\"%s\"/><x14:colorNegative rgb=\"%s\"/><x14:colorAxis rgb=\"FF000000\"/><x14:colorMarkers rgb=\"%s\"/><x14:colorFirst rgb=\"%s\"/><x14:colorLast rgb=\"%s\"/><x14:colorHigh rgb=\"%s\"/><x14:colorLow rgb=\"%s\"/>".printf (
                    argb (g.color), argb (g.negative_color), argb (g.marker_color), argb (g.marker_color), argb (g.marker_color), argb (g.high_color), argb (g.low_color)));
                sb.append ("<x14:sparklines>");
                foreach (var it in g.items) {
                    string src = it.source.has_prefix ("=") ? it.source.substring (1) : it.source;
                    if (!src.contains ("!")) src = Address.quote_sheet (s.name) + "!" + src;
                    sb.append ("<x14:sparkline><xm:f>%s</xm:f><xm:sqref>%s</xm:sqref></x14:sparkline>".printf (esc (src), Address.cell (it.row, it.col)));
                }
                sb.append ("</x14:sparklines></x14:sparklineGroup>");
            }
            sb.append ("</x14:sparklineGroups></ext>");
            part.put ("extLst", sb.str);
        }

        private static double emu_px_x (string v) {
            return double.parse (v) / EMU * Xlsx.COL_SCALE;
        }

        private static double emu_px_y (string v) {
            return double.parse (v) / EMU * Xlsx.ROW_SCALE;
        }

        private static bool point (Singularity.Charts.XmlElement? p, Sheet s, out double ax, out double ay) {
            ax = ay = 0;
            if (p == null) return false;
            var col = p.child ("col");
            var row = p.child ("row");
            if (col == null || row == null) return false;
            ax = SheetGeometry.col_pos (s, int.parse (col.text)) + emu_px_x (p.child ("colOff") != null ? p.child ("colOff").text : "0");
            ay = SheetGeometry.row_pos (s, int.parse (row.text)) + emu_px_y (p.child ("rowOff") != null ? p.child ("rowOff").text : "0");
            return true;
        }

        private static bool anchor_box (Singularity.Charts.XmlElement anchor, Sheet s, out double x, out double y, out double w, out double h) {
            x = y = 0;
            w = 480;
            h = 300;
            double ax, ay;
            if (anchor.local == "absoluteAnchor") {
                var pos = anchor.child ("pos");
                var ext = anchor.child ("ext");
                if (pos == null) return false;
                ax = emu_px_x (pos.attr ("x"));
                ay = emu_px_y (pos.attr ("y"));
                if (ext != null) {
                    w = emu_px_x (ext.attr ("cx"));
                    h = emu_px_y (ext.attr ("cy"));
                }
            } else {
                if (!point (anchor.child ("from"), s, out ax, out ay)) return false;
                if (anchor.local == "twoCellAnchor") {
                    double bx, by;
                    if (point (anchor.child ("to"), s, out bx, out by)) {
                        w = double.max (bx - ax, 4);
                        h = double.max (by - ay, 4);
                    }
                } else {
                    var ext = anchor.child ("ext");
                    if (ext != null) {
                        w = emu_px_x (ext.attr ("cx"));
                        h = emu_px_y (ext.attr ("cy"));
                    }
                }
            }
            x = SheetGeometry.from_abs_x (s, ax);
            y = SheetGeometry.from_abs_y (s, ay);
            return true;
        }

        private static Gee.HashMap<string, string> read_rels (ZipReader zip, string path) {
            var map = new Gee.HashMap<string, string> ();
            string dir = Path.get_dirname (path);
            string rel = dir + "/_rels/" + Path.get_basename (path) + ".rels";
            try {
                string? text = zip.read_text (rel);
                if (text == null) return map;
                var root = Singularity.Charts.XmlElement.parse (text);
                if (root == null) return map;
                foreach (var r in root.children) {
                    string t = r.attr ("Target");
                    if (r.attr ("TargetMode") == "External") continue;
                    map[r.attr ("Id")] = Xlsx.resolve (dir, t);
                }
            } catch (Error e) {
            }
            return map;
        }

        private static string color_hex (Singularity.Charts.XmlElement? e) {
            if (e == null) return "";
            var c = e.find ("srgbClr");
            if (c != null && c.attr ("val").length == 6) return "#" + c.attr ("val").down ();
            return "";
        }

        private static Drawing? read_shape (Singularity.Charts.XmlElement sp) {
            var sppr = sp.child ("spPr");
            string geom = "rect";
            if (sppr != null) {
                var pg = sppr.child ("prstGeom");
                if (pg != null) geom = pg.attr ("prst", "rect");
            }
            bool txbox = false;
            var nv = sp.child ("nvSpPr");
            if (nv != null && nv.child ("cNvSpPr") != null) txbox = nv.child ("cNvSpPr").attr ("txBox") == "1";
            DrawingKind k;
            if (sp.local == "cxnSp" || geom == "line" || geom == "straightConnector1") k = DrawingKind.LINE;
            else if (txbox) k = DrawingKind.TEXT_BOX;
            else if (geom == "ellipse") k = DrawingKind.ELLIPSE;
            else if (geom == "roundRect") k = DrawingKind.ROUNDED;
            else k = DrawingKind.RECTANGLE;
            var d = new Drawing (k);
            if (sppr != null) {
                var xf = sppr.child ("xfrm");
                if (xf != null) {
                    d.flip_h = xf.attr ("flipH") == "1";
                    d.flip_v = xf.attr ("flipV") == "1";
                }
                if (sppr.child ("noFill") != null) d.fill = "";
                else if (sppr.child ("solidFill") != null) {
                    d.fill = color_hex (sppr.child ("solidFill"));
                    var alpha = sppr.child ("solidFill").find ("alpha");
                    if (alpha != null) d.opacity = double.parse (alpha.attr ("val", "100000")) / 100000.0;
                }
                var ln = sppr.child ("ln");
                if (ln != null) {
                    if (ln.child ("noFill") != null) d.stroke = "";
                    else if (ln.child ("solidFill") != null) d.stroke = color_hex (ln.child ("solidFill"));
                    if (ln.attr ("w") != "") d.stroke_width = double.parse (ln.attr ("w")) / 9525.0;
                    var tail = ln.child ("tailEnd");
                    var head = ln.child ("headEnd");
                    if (k == DrawingKind.LINE && ((tail != null && tail.attr ("type", "none") != "none") || (head != null && head.attr ("type", "none") != "none"))) {
                        d.kind = DrawingKind.ARROW;
                        if (tail == null || tail.attr ("type", "none") == "none") {
                            d.flip_h = !d.flip_h;
                            d.flip_v = !d.flip_v;
                        }
                    }
                }
            }
            var tb = sp.child ("txBody");
            if (tb != null) {
                string[] lines = {};
                foreach (var p in tb.all ("p")) {
                    var ts = new Gee.ArrayList<Singularity.Charts.XmlElement> ();
                    p.find_all ("t", ts);
                    var sb = new StringBuilder ();
                    foreach (var t in ts) sb.append (t.text);
                    lines += sb.str;
                }
                d.text = string.joinv ("\n", lines).strip ();
                var rpr = tb.find ("rPr");
                if (rpr != null) {
                    if (rpr.attr ("sz") != "") d.font_size = double.parse (rpr.attr ("sz")) / 100.0;
                    string tc = color_hex (rpr.child ("solidFill"));
                    if (tc != "") d.text_color = tc;
                }
            }
            var pr = sp.find ("cNvPr");
            if (pr != null) {
                d.name = pr.attr ("name");
                d.alt_text = pr.attr ("descr");
            }
            return d;
        }

        private static double num_attr (Singularity.Charts.XmlElement? e, string a) {
            return e != null ? double.parse (e.attr (a, "0")) : 0;
        }

        private static Drawing read_group (Singularity.Charts.XmlElement grp) {
            var g = new Drawing (DrawingKind.GROUP);
            g.fill = "";
            g.stroke = "";
            var gpr = grp.child ("grpSpPr");
            var xf = gpr != null ? gpr.child ("xfrm") : null;
            double chx = num_attr (xf != null ? xf.child ("chOff") : null, "x");
            double chy = num_attr (xf != null ? xf.child ("chOff") : null, "y");
            double chw = num_attr (xf != null ? xf.child ("chExt") : null, "cx");
            double chh = num_attr (xf != null ? xf.child ("chExt") : null, "cy");
            g.frame_w = chw / EMU * Xlsx.COL_SCALE;
            g.frame_h = chh / EMU * Xlsx.ROW_SCALE;
            var pr = grp.find ("cNvPr");
            if (pr != null) {
                g.name = pr.attr ("name");
                g.alt_text = pr.attr ("descr");
                g.diagram = Diagrams.kind_from_name (g.name);
            }
            foreach (var c in grp.children) {
                Drawing? child = null;
                Singularity.Charts.XmlElement? cxf = null;
                if (c.local == "sp" || c.local == "cxnSp") {
                    child = read_shape (c);
                    var sppr = c.child ("spPr");
                    cxf = sppr != null ? sppr.child ("xfrm") : null;
                } else if (c.local == "grpSp") {
                    child = read_group (c);
                    var gp = c.child ("grpSpPr");
                    cxf = gp != null ? gp.child ("xfrm") : null;
                }
                if (child == null) continue;
                if (cxf != null) {
                    child.x = (num_attr (cxf.child ("off"), "x") - chx) / EMU * Xlsx.COL_SCALE;
                    child.y = (num_attr (cxf.child ("off"), "y") - chy) / EMU * Xlsx.ROW_SCALE;
                    child.width = num_attr (cxf.child ("ext"), "cx") / EMU * Xlsx.COL_SCALE;
                    child.height = num_attr (cxf.child ("ext"), "cy") / EMU * Xlsx.ROW_SCALE;
                }
                g.children.add (child);
            }
            return g;
        }

        public static void read_sheet (XlsxSheetIn sin) {
            try {
                read_drawing (sin);
                read_sparklines (sin);
            } catch (Error e) {
            }
        }

        private static void read_drawing (XlsxSheetIn sin) throws Error {
            string? target = sin.target_of_type ("/drawing");
            if (target == null) return;
            var zip = sin.reader.zip;
            string? text = zip.read_text (target);
            if (text == null) return;
            var root = Singularity.Charts.XmlElement.parse (text);
            if (root == null) return;
            var rels = read_rels (zip, target);
            var s = sin.sheet;
            foreach (var anchor in root.children) {
                if (anchor.local != "twoCellAnchor" && anchor.local != "oneCellAnchor" && anchor.local != "absoluteAnchor") continue;
                double x, y, w, h;
                if (!anchor_box (anchor, s, out x, out y, out w, out h)) continue;
                Singularity.Charts.XmlElement? content = null;
                foreach (var c in anchor.children) {
                    if (c.local == "graphicFrame" || c.local == "pic" || c.local == "sp" || c.local == "cxnSp" || c.local == "grpSp") {
                        content = c;
                        break;
                    }
                    if (c.local == "AlternateContent") {
                        var choice = c.child ("Choice");
                        if (choice != null && choice.children.size > 0) {
                            content = choice.children[0];
                            break;
                        }
                    }
                }
                if (content == null) continue;
                if (content.local == "graphicFrame") {
                    var gd = content.find ("graphicData");
                    if (gd == null) continue;
                    Singularity.Charts.XmlElement? cref = null;
                    foreach (var gc in gd.children) if (gc.local == "chart") cref = gc;
                    if (cref == null) continue;
                    string rid = cref.attr ("id");
                    if (!rels.has_key (rid)) continue;
                    string? cxml = zip.read_text (rels[rid]);
                    if (cxml == null) continue;
                    var spec = Singularity.Charts.DrawingML.read_chart (cxml);
                    if (spec == null) continue;
                    var chart = new Chart (new Area (s, 0, 0, 0, 0));
                    chart.title = spec.title;
                    spec.title = "";
                    chart.style = spec;
                    chart.kind = Chart.kind_of_spec (spec);
                    chart.x = x;
                    chart.y = y;
                    chart.width = w;
                    chart.height = h;
                    var nv = content.find ("cNvPr");
                    if (nv != null) {
                        chart.name = nv.attr ("name");
                        chart.alt_text = nv.attr ("descr");
                    }
                    chart.explicit_series = true;
                    ChartResolve.adopt_source (sin.reader.book, s, chart);
                    chart.explicit_series = true;
                    s.charts.add (chart);
                } else if (content.local == "pic") {
                    var blip = content.find ("blip");
                    if (blip == null) continue;
                    string rid = blip.attr ("embed");
                    if (!rels.has_key (rid)) continue;
                    var data = zip.read (rels[rid]);
                    if (data == null) continue;
                    var d = new Drawing (DrawingKind.IMAGE);
                    d.image = new Bytes (data);
                    d.mime = Drawing.mime_of (data);
                    d.x = x;
                    d.y = y;
                    d.width = w;
                    d.height = h;
                    var nv = content.find ("cNvPr");
                    if (nv != null) {
                        d.name = nv.attr ("name");
                        d.alt_text = nv.attr ("descr");
                    }
                    s.drawings.add (d);
                } else if (content.local == "sp" || content.local == "cxnSp") {
                    var d = read_shape (content);
                    if (d == null) continue;
                    d.x = x;
                    d.y = y;
                    d.width = w;
                    d.height = h;
                    s.drawings.add (d);
                } else if (content.local == "grpSp") {
                    var gd = read_group (content);
                    gd.x = x;
                    gd.y = y;
                    gd.width = w;
                    gd.height = h;
                    s.drawings.add (gd);
                }
            }
        }

        private static string rgb_of (Xml.Node* n) {
            if (n == null) return "";
            string v = Xlsx.attr (n, "rgb");
            if (v.length == 8) return "#" + v.substring (2).down ();
            if (v.length == 6) return "#" + v.down ();
            return "";
        }

        private static Xml.Node* named (Xml.Node* parent, string name) {
            if (parent == null) return null;
            for (Xml.Node* c = parent->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE && c->name == name) return c;
            }
            return null;
        }

        private static void read_sparklines (XlsxSheetIn sin) {
            var ext_list = named (sin.root, "extLst");
            if (ext_list == null) return;
            for (Xml.Node* ext = ext_list->children; ext != null; ext = ext->next) {
                if (ext->type != Xml.ElementType.ELEMENT_NODE) continue;
                var groups = named (ext, "sparklineGroups");
                if (groups == null) continue;
                for (Xml.Node* gn = groups->children; gn != null; gn = gn->next) {
                    if (gn->type != Xml.ElementType.ELEMENT_NODE || gn->name != "sparklineGroup") continue;
                    var g = new SparklineGroup ();
                    g.kind = SparklineKind.from_id (Xlsx.attr (gn, "type", "line"));
                    g.markers = Xlsx.attr (gn, "markers") == "1";
                    g.high = Xlsx.attr (gn, "high") == "1";
                    g.low = Xlsx.attr (gn, "low") == "1";
                    g.first = Xlsx.attr (gn, "first") == "1";
                    g.last = Xlsx.attr (gn, "last") == "1";
                    g.negative = Xlsx.attr (gn, "negative") == "1";
                    if (Xlsx.attr (gn, "lineWeight") != "") g.line_weight = double.parse (Xlsx.attr (gn, "lineWeight"));
                    else g.line_weight = 0.75;
                    string c = rgb_of (named (gn, "colorSeries"));
                    if (c != "") g.color = c;
                    c = rgb_of (named (gn, "colorNegative"));
                    if (c != "") g.negative_color = c;
                    c = rgb_of (named (gn, "colorMarkers"));
                    if (c != "") g.marker_color = c;
                    c = rgb_of (named (gn, "colorHigh"));
                    if (c != "") g.high_color = c;
                    c = rgb_of (named (gn, "colorLow"));
                    if (c != "") g.low_color = c;
                    var items = named (gn, "sparklines");
                    for (Xml.Node* it = items != null ? items->children : null; it != null; it = it->next) {
                        if (it->type != Xml.ElementType.ELEMENT_NODE) continue;
                        string f = Xlsx.text_of (named (it, "f")).strip ();
                        string sq = Xlsx.text_of (named (it, "sqref")).strip ();
                        int r, col;
                        bool a1, a2;
                        if (!Address.parse_cell (sq, out r, out col, out a1, out a2)) continue;
                        g.items.add (new Sparkline (r, col, f));
                    }
                    if (g.items.size > 0) sin.sheet.sparklines.add (g);
                }
            }
        }
    }
}
