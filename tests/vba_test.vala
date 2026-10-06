using Singularity.Apps.Spreadsheet;

void same (string what, string got, string expected) {
    if (got != expected) {
        stderr.printf ("FAIL %s: expected [%s] got [%s]\n", what, expected, got);
        Test.fail ();
    }
}

string show (Sheet s, string addr) {
    int r, c;
    bool a, b;
    Address.parse_cell (addr, out r, out c, out a, out b);
    return s.value_at (r, c).display ();
}

string bytes_text (uint8[] b) {
    var sb = new StringBuilder ();
    foreach (uint8 x in b) sb.append_c ((char) x);
    return sb.str;
}

void test_decompress () {
    uint8[] c1 = { 0x01, 0x19, 0xB0, 0x00, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x00, 0x69, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E, 0x6F, 0x70, 0x00, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x2E };
    same ("literal chunk", bytes_text (VbaProject.decompress (c1)), "abcdefghijklmnopqrstuv.");
    uint8[] c3 = { 0x01, 0x03, 0xB0, 0x02, 0x61, 0x0B, 0x00 };
    same ("run", bytes_text (VbaProject.decompress (c3)), "aaaaaaaaaaaaaaa");
}

Document run_vba (string src, string entry, ScriptHost host) {
    var doc = new Document ();
    var runner = new ScriptRunner (doc, host);
    try {
        runner.run_lenient (src, entry);
    } catch (ScriptError e) {
        stderr.printf ("FAIL %s: %s\n", entry, e.message);
        Test.fail ();
    }
    doc.book.recalculate ();
    return doc;
}

void test_language () {
    string src = """
Option Explicit
Private Const RATE As Double = 0.1
Private total As Long

Private Type Point
    x As Long
End Type

Public Function AddTax(ByVal amount As Double, Optional ByVal pct As Double = 0.2) As Double
    AddTax = amount * (1 + pct)
End Function

Private Sub Twice(ByRef n As Long)
    n = n * 2
End Sub

Sub Main()
    Dim i As Long, s As String, arr(1 To 3) As Integer, dyn() As Variant
    For i = 1 To 3
        arr(i) = i * 10
    Next i
    ReDim dyn(0 To 1)
    dyn(0) = "a"
    ReDim Preserve dyn(0 To 2)
    dyn(2) = "c"
    With ActiveSheet
        .Range("A1").Value = arr(1) + arr(2) + arr(3)
        .Range("A2").Value = UBound(arr) & LBound(arr) & UBound(dyn)
        .Cells(3, 1).Value = dyn(0) & dyn(2)
    End With
    Dim n As Long
    n = 21
    Twice n
    Range("A4").Value = n
    Range("A5").Value = AddTax(100)
    Range("A6").Value = AddTax(100, pct:=0.5)
    Dim k As Integer
    k = 2.5
    Range("A7").Value = k
    Select Case n
        Case 1 To 10
            s = "low"
        Case Is > 40
            s = "high"
        Case Else
            s = "mid"
    End Select
    Range("A8").Value = s
    Dim c As New Collection
    c.Add "x"
    c.Add "y", "key"
    Range("A9").Value = c.Count & c("key") & c(1)
    Dim d As Object
    Set d = CreateObject("Scripting.Dictionary")
    d("one") = 1
    d.Add "two", 2
    Range("A10").Value = d("one") + d("two") & "|" & d.Exists("two") & "|" & Join(d.Keys, ",")
    Range("A11").Value = "x" & Format(1234.5, "#,##0.00")
    Range("A12").Value = Left("Spreadsheet", 5) & Mid("abcdef", 2, 3) & UCase(Right("xyz", 1)) & InStr("hello", "l") & Replace("a-b-c", "-", "+")
    Range("A13").Value = "x" & Year(DateSerial(2024, 2, 29)) & "-" & Month(DateAdd("m", 1, DateSerial(2024, 1, 31))) & "-" & Day(DateAdd("m", 1, DateSerial(2024, 1, 31)))
    Range("A14").Value = DateDiff("d", #1/1/2024#, #3/1/2024#)
    Range("A15").Value = Application.WorksheetFunction.Sum(Range("A1"), 5)
    Range("A16").Value = RATE * 10
    Dim parts
    parts = Split("a,b,c", ",")
    Range("A17").Value = UBound(parts) & parts(1)
    Range("A18").Value = IIf(n > 1, "yes", "no") & CStr(CInt(3.5)) & CStr(CInt(4.5)) & (7 \ 2) & (7 Mod 3)
    Range("A19").Value = TypeName(c) & TypeName(1.5) & TypeName("s") & VarType(True)
    Dim hit As Boolean
    hit = "Banana" Like "B*n?na"
    Range("A20").Value = hit
End Sub

Sub Errors()
    On Error GoTo Handler
    Dim x As Long
    x = 1 / 0
    Range("B1").Value = "not reached"
    Exit Sub
Handler:
    Range("B4").Value = "caught " & Err.Number & " " & Err.Description
    Resume Next
End Sub

Sub Errors2()
    On Error Resume Next
    Err.Raise 1234, , "custom"
    Range("B2").Value = Err.Number & " " & Err.Description
    Err.Clear
    Range("B3").Value = Err.Number
    On Error GoTo 0
End Sub

Sub Loops()
    Dim i As Long, total As Long
    i = 0
    Do While i < 5
        i = i + 1
        If i = 2 Then GoTo Skip
        total = total + i
Skip:
    Loop
    Range("C1").Value = total
    Do
        i = i - 1
    Loop Until i <= 0
    Range("C2").Value = i
    Dim cell As Range
    Range("D1:D3").Value = 2
    For Each cell In Range("D1:D3")
        cell.Offset(0, 1).Value = cell.Value * 3
    Next cell
    Range("C3").FormulaR1C1 = "=SUM(R1C4:R3C5)"
    Range("C4").Formula = "=SUM(D1:E3)"
    Range("F1:F3").Formula = "=D1+E1"
    Range("C5").Value = "x" & Range("C3").FormulaR1C1 & "|" & Range("F3").Formula
End Sub
""";
    var host = new ScriptHost ();
    var doc = run_vba (src, "Main", host);
    var s = doc.book.sheets[0];
    same ("array sum", show (s, "A1"), "60");
    same ("bounds", show (s, "A2"), "312");
    same ("redim preserve", show (s, "A3"), "ac");
    same ("byref", show (s, "A4"), "42");
    same ("optional", show (s, "A5"), "120");
    same ("named arg", show (s, "A6"), "150");
    same ("integer rounding", show (s, "A7"), "2");
    same ("select case", show (s, "A8"), "high");
    same ("collection", show (s, "A9"), "2yx");
    same ("dictionary", show (s, "A10"), "3|True|one,two");
    same ("format", show (s, "A11"), "x1,234.50");
    same ("strings", show (s, "A12"), "SpreabcdZ3a+b+c");
    same ("dates", show (s, "A13"), "x2024-2-29");
    same ("datediff", show (s, "A14"), "60");
    same ("worksheetfunction", show (s, "A15"), "65");
    same ("const", show (s, "A16"), "1");
    same ("split", show (s, "A17"), "2b");
    same ("misc", show (s, "A18"), "yes4431");
    same ("typename", show (s, "A19"), "CollectionDoubleString11");
    same ("like", show (s, "A20"), "TRUE");
    doc = run_vba (src, "Errors", host);
    s = doc.book.sheets[0];
    same ("resume next after handler", show (s, "B1"), "not reached");
    same ("on error goto", show (s, "B4"), "caught 11 division by zero");
    doc = run_vba (src, "Errors2", host);
    s = doc.book.sheets[0];
    same ("err raise", show (s, "B2"), "1234 custom");
    same ("err clear", show (s, "B3"), "0");
    doc = run_vba (src, "Loops", host);
    s = doc.book.sheets[0];
    same ("goto in loop", show (s, "C1"), "13");
    same ("loop until", show (s, "C2"), "0");
    same ("for each offset", show (s, "E2"), "6");
    same ("r1c1 formula", show (s, "C3"), "24");
    same ("a1 formula", show (s, "C4"), "24");
    same ("relative fill", show (s, "F3"), "8");
    same ("formula text", show (s, "C5"), "x=SUM(R1C4:R3C5)|=D3+E3");
}

void test_object_model () {
    string src = """
Sub Model()
    Dim ws As Worksheet
    Set ws = Worksheets.Add(After:=Worksheets(Worksheets.Count))
    ws.Name = "Data"
    ws.Range("A1:A5").Value = Application.Transpose(Array(5, 3, 9, 1, 7))
    ws.Range("B1").Value = ws.Range("A1").End(xlDown).Row
    ws.Range("B2").Value = ws.Cells(ws.Rows.Count, 1).End(xlUp).Address
    ws.Range("B3").Value = ws.Range("A1:A5").Find(What:=9).Address(False, False)
    ws.Range("A1:A5").Sort Key1:=ws.Range("A1"), Order1:=xlAscending
    ws.Range("B4").Value = ws.Range("A1").Value & ws.Range("A5").Value
    ws.Range("C1").Resize(2, 2).Value = 1
    ws.Range("B5").Value = Application.WorksheetFunction.Sum(ws.Range("C1:D2"))
    ws.Range("A1:A5").Font.Bold = True
    ws.Range("A1").Interior.Color = RGB(255, 0, 0)
    ws.Range("B6").Value = ws.Range("A1").Font.Bold & "|" & ws.Range("A1").Interior.Color
    ws.Range("E1").Value = "hello"
    ws.Range("E1").Copy ws.Range("E2")
    ws.Range("E3").Value = ws.Range("E2").Value & Sheets.Count & ws.Index
    ActiveWorkbook.Names.Add Name:="Scores", RefersTo:=ws.Range("A1:A5")
    ws.Range("B7").Value = Application.WorksheetFunction.Max(Range("Scores"))
    ws.Rows(10).Hidden = True
    ws.Range("B8").Value = ws.Rows(10).Hidden
    ws.PageSetup.Orientation = xlLandscape
    ws.PageSetup.PrintArea = "$A$1:$B$8"
    ws.Range("B9").Value = Intersect(ws.Range("A1:C3"), ws.Range("B2:D4")).Address
    ws.Range("B10").Value = MsgBox("Continue?", vbYesNo + vbQuestion, "Ask")
End Sub

Sub Sandbox()
    Shell "rm -rf /"
End Sub

Sub Sandbox2()
    Open "/etc/passwd" For Input As #1
End Sub

Sub Sandbox3()
    ThisWorkbook.SaveAs "x.xlsx"
End Sub
""";
    var host = new ScriptHost ();
    host.answers.add (6);
    var doc = run_vba (src, "Model", host);
    var ws = doc.book.find_sheet ("Data");
    if (ws == null) {
        stderr.printf ("FAIL sheet not added\n");
        Test.fail ();
        return;
    }
    same ("end down", show (ws, "B1"), "5");
    same ("end up", show (ws, "B2"), "$A$5");
    same ("find", show (ws, "B3"), "A3");
    same ("sort", show (ws, "B4"), "19");
    same ("resize sum", show (ws, "B5"), "4");
    same ("font interior", show (ws, "B6"), "True|255");
    same ("copy", show (ws, "E3"), "hello22");
    same ("names", show (ws, "B7"), "9");
    same ("hidden", show (ws, "B8"), "TRUE");
    same ("intersect", show (ws, "B9"), "$B$2:$C$3");
    same ("msgbox yes", show (ws, "B10"), "6");
    same ("page setup", ws.page.landscape.to_string () + ws.page.print_area, "trueA1:B8");
    foreach (string sub in new string[] { "Sandbox", "Sandbox2", "Sandbox3" }) {
        var d2 = new Document ();
        var runner = new ScriptRunner (d2, new ScriptHost ());
        try {
            runner.run_lenient (src, sub);
            stderr.printf ("FAIL %s was not blocked\n", sub);
            Test.fail ();
        } catch (ScriptError e) {
            if (!e.message.contains ("not allowed")) {
                stderr.printf ("FAIL %s wrong error %s\n", sub, e.message);
                Test.fail ();
            }
        }
    }
}

void test_udf_and_trust () {
    var doc = new Document ();
    var s = doc.book.sheets[0];
    doc.book.scripts.module ("Module1").source = "Function Square(x)\n    Square = x * x\nEnd Function\nFunction Twice(r As Range)\n    Twice = Application.WorksheetFunction.Sum(r) * 2\nEnd Function\nFunction Bad()\n    Range(\"A1\").Value = 1\n    Bad = 2\nEnd Function\n";
    s.set_input (0, 1, "=Square(7)");
    s.set_input (1, 0, "3");
    s.set_input (2, 0, "4");
    s.set_input (1, 1, "=Twice(A2:A3)");
    s.set_input (2, 1, "=Bad()");
    doc.book.recalculate ();
    same ("udf disabled", show (s, "B1"), "#NAME?");
    try {
        doc.book.udf = new MacroUdf (doc);
    } catch (ScriptError e) {
        Test.fail ();
    }
    doc.book.recalculate ();
    same ("udf square", show (s, "B1"), "49");
    same ("udf range arg", show (s, "B2"), "14");
    same ("udf cannot write", show (s, "B3"), "#VALUE!");
}

void test_macro_file_roundtrip () {
    string p = Path.build_filename (Environment.get_tmp_dir (), "ss-vba-%d.xlsx".printf (Random.int_range (0, 1000000)));
    var book = new Workbook ();
    book.add_sheet ("S");
    book.scripts.module ("Module1").source = "Sub A()\nEnd Sub\n";
    try {
        XlsxWriter.save (book, p);
        var back = Xlsx.load (p);
        if (!back.scripts.from_file) {
            stderr.printf ("FAIL scripts from file not flagged\n");
            Test.fail ();
        }
    } catch (Error e) {
        Test.fail ();
    }
    FileUtils.remove (p);
}

int main (string[] args) {
    Test.init (ref args);
    LocaleInfo.set_c ();
    Test.add_func ("/vba/decompress", test_decompress);
    Test.add_func ("/vba/language", test_language);
    Test.add_func ("/vba/object-model", test_object_model);
    Test.add_func ("/vba/udf", test_udf_and_trust);
    Test.add_func ("/vba/file-flag", test_macro_file_roundtrip);
    return Test.run ();
}
