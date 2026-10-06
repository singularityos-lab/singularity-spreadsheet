namespace Singularity.Apps.Spreadsheet {

    public class CondXml {
        private static string esc (string s) {
            return XlsxWriter.esc (s);
        }

        public static string? rule (CondFormat cf, string head) {
            string first = Address.cell (cf.area.r1, cf.area.c1);
            string q = esc (cf.a.replace ("\"", "\"\""));
            switch (cf.kind) {
                case CondKind.GREATER_EQUAL:
                    return head + " type=\"cellIs\" operator=\"greaterThanOrEqual\"><formula>%s</formula></cfRule>".printf (esc (cf.a));
                case CondKind.LESS_EQUAL:
                    return head + " type=\"cellIs\" operator=\"lessThanOrEqual\"><formula>%s</formula></cfRule>".printf (esc (cf.a));
                case CondKind.NOT_BETWEEN:
                    return head + " type=\"cellIs\" operator=\"notBetween\"><formula>%s</formula><formula>%s</formula></cfRule>".printf (esc (cf.a), esc (cf.b));
                case CondKind.TEXT_BEGINS:
                    return head + " type=\"beginsWith\" operator=\"beginsWith\" text=\"%s\"><formula>LEFT(%s,LEN(\"%s\"))=\"%s\"</formula></cfRule>".printf (esc (cf.a), first, q, q);
                case CondKind.TEXT_ENDS:
                    return head + " type=\"endsWith\" operator=\"endsWith\" text=\"%s\"><formula>RIGHT(%s,LEN(\"%s\"))=\"%s\"</formula></cfRule>".printf (esc (cf.a), first, q, q);
                case CondKind.TEXT_NOT_CONTAINS:
                    return head + " type=\"notContainsText\" operator=\"notContains\" text=\"%s\"><formula>ISERROR(SEARCH(\"%s\",%s))</formula></cfRule>".printf (esc (cf.a), q, first);
                case CondKind.NO_BLANK:
                    return head + " type=\"notContainsBlanks\"><formula>LEN(TRIM(%s))&gt;0</formula></cfRule>".printf (first);
                case CondKind.NO_ERRORS:
                    return head + " type=\"notContainsErrors\"><formula>NOT(ISERROR(%s))</formula></cfRule>".printf (first);
                case CondKind.DATE_OCCURRING:
                    return head + " type=\"timePeriod\" timePeriod=\"%s\"><formula>FLOOR(%s,1)=TODAY()</formula></cfRule>".printf (cf.date_period, first);
                case CondKind.ICON_SET:
                    int n = CondIcons.count (cf.icon_set);
                    var sb = new StringBuilder (head + " type=\"iconSet\"><iconSet iconSet=\"%s\"%s%s>".printf (cf.icon_set, cf.show_value ? "" : " showValue=\"0\"", cf.icon_reverse ? " reverse=\"1\"" : ""));
                    for (int i = 0; i < n; i++) sb.append ("<cfvo type=\"percent\" val=\"%d\"/>".printf (i * 100 / n));
                    sb.append ("</iconSet></cfRule>");
                    return sb.str;
                default:
                    return null;
            }
        }

        public static CondFormat? read (Area area, Xml.Node* rule, string type, string op, Gee.ArrayList<string> formulas) {
            CondFormat? f = null;
            string? text = rule->get_prop ("text");
            switch (type) {
                case "beginsWith":
                    f = new CondFormat (area, CondKind.TEXT_BEGINS);
                    f.a = text ?? "";
                    break;
                case "endsWith":
                    f = new CondFormat (area, CondKind.TEXT_ENDS);
                    f.a = text ?? "";
                    break;
                case "notContainsText":
                    f = new CondFormat (area, CondKind.TEXT_NOT_CONTAINS);
                    f.a = text ?? "";
                    break;
                case "notContainsBlanks":
                    f = new CondFormat (area, CondKind.NO_BLANK);
                    break;
                case "notContainsErrors":
                    f = new CondFormat (area, CondKind.NO_ERRORS);
                    break;
                case "timePeriod":
                    f = new CondFormat (area, CondKind.DATE_OCCURRING);
                    f.date_period = rule->get_prop ("timePeriod") ?? "today";
                    break;
                case "iconSet":
                    f = new CondFormat (area, CondKind.ICON_SET);
                    for (Xml.Node* ch = rule->children; ch != null; ch = ch->next) {
                        if (ch->type != Xml.ElementType.ELEMENT_NODE || ch->name != "iconSet") continue;
                        f.icon_set = ch->get_prop ("iconSet") ?? "3TrafficLights1";
                        f.show_value = ch->get_prop ("showValue") != "0";
                        f.icon_reverse = ch->get_prop ("reverse") == "1";
                    }
                    break;
            }
            return f;
        }
    }
}
