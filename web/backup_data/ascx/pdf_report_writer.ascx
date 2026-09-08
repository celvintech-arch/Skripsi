<%@ Import Namespace="System.Collections.Generic" %>
<%@ Import Namespace="System.Data" %>
<%@ Import Namespace="System.Globalization" %>
<%@ Import Namespace="System.IO" %>
<%@ Import Namespace="System.Text" %>

<script runat="server">
Private NotInheritable Class BackupSummaryPdfWriter
    Private Const PageWidth As Double = 842
    Private Const PageHeight As Double = 595
    Private Const Margin As Double = 36
    Private Shared ReadOnly Invariant As CultureInfo = CultureInfo.InvariantCulture

    Private Class PdfPage
        Public ReadOnly Content As New StringBuilder()
        Public Y As Double
    End Class

    Private Sub New()
    End Sub

    Public Shared Function Create(ByVal reportPeriod As String,
                                  ByVal filterDescription As String,
                                  ByVal summaryItems As IList(Of KeyValuePair(Of String, String)),
                                  ByVal jobs As DataTable,
                                  ByVal inventory As DataTable) As Byte()
        Dim pages As New List(Of PdfPage)()
        Dim page As PdfPage = AddPage(pages, "Laporan Backup Data", reportPeriod)

        WriteText(page, Margin, page.Y, 9, "Filter: " & filterDescription, False, 125)
        page.Y -= 24
        DrawSummaryCards(page, summaryItems)
        page.Y -= 12

        WriteText(page, Margin, page.Y, 12, "Detail Proses", True, 80)
        page.Y -= 18
        DrawJobHeader(page)
        For Each row As DataRow In jobs.Rows
            If page.Y < 62 Then
                page = AddPage(pages, "Laporan Backup Data - Detail Proses", reportPeriod)
                DrawJobHeader(page)
            End If
            DrawJobRow(page, row)
        Next

        page = AddPage(pages, "Laporan Backup Data - Inventaris", reportPeriod)
        DrawInventoryHeader(page)
        For Each row As DataRow In inventory.Rows
            If page.Y < 62 Then
                page = AddPage(pages, "Laporan Backup Data - Inventaris", reportPeriod)
                DrawInventoryHeader(page)
            End If
            DrawInventoryRow(page, row)
        Next

        If inventory.Rows.Count = 0 Then
            WriteText(page, Margin + 6, page.Y - 13, 8, "Inventaris belum tersedia untuk filter yang dipilih.", False, 110)
            page.Y -= 20
        End If

        For i As Integer = 0 To pages.Count - 1
            WriteText(pages(i), Margin, 23, 8, "LINTAR - PUSDATIN UNTAR", False, 50)
            WriteText(pages(i), PageWidth - 105, 23, 8, "Halaman " & (i + 1).ToString() & " / " & pages.Count.ToString(), False, 30)
        Next
        Return BuildDocument(pages)
    End Function

    Private Shared Function AddPage(ByVal pages As List(Of PdfPage), ByVal title As String, ByVal period As String) As PdfPage
        Dim page As New PdfPage()
        page.Y = PageHeight - Margin
        pages.Add(page)
        WriteText(page, Margin, page.Y, 16, title, True, 95)
        WriteText(page, PageWidth - 225, page.Y, 9, "Periode: " & period, False, 48)
        page.Y -= 18
        DrawLine(page, Margin, page.Y, PageWidth - Margin, page.Y, 0.6)
        page.Y -= 18
        Return page
    End Function

    Private Shared Sub DrawSummaryCards(ByVal page As PdfPage, ByVal items As IList(Of KeyValuePair(Of String, String)))
        Dim cardWidth As Double = 184
        Dim cardHeight As Double = 44
        Dim gap As Double = 11
        For i As Integer = 0 To items.Count - 1
            Dim column As Integer = i Mod 4
            Dim row As Integer = i \ 4
            Dim x As Double = Margin + column * (cardWidth + gap)
            Dim y As Double = page.Y - row * (cardHeight + 8)
            FillRectangle(page, x, y - cardHeight, cardWidth, cardHeight, 0.96)
            StrokeRectangle(page, x, y - cardHeight, cardWidth, cardHeight, 0.75)
            WriteText(page, x + 8, y - 14, 7, items(i).Key.ToUpperInvariant(), True, 30)
            WriteText(page, x + 8, y - 33, 13, items(i).Value, True, 24)
        Next
        Dim rows As Integer = CInt(Math.Ceiling(items.Count / 4.0))
        page.Y -= rows * (cardHeight + 8)
    End Sub

    Private Shared Sub DrawJobHeader(ByVal page As PdfPage)
        Dim labels() As String = {"Dibuat", "Operasi", "Cakupan", "Tabel", "Status", "Diproses", "Durasi", "Pengguna"}
        Dim widths() As Double = {85, 55, 105, 160, 70, 60, 65, 120}
        DrawTableRow(page, labels, widths, True)
    End Sub

    Private Shared Sub DrawJobRow(ByVal page As PdfPage, ByVal row As DataRow)
        Dim values() As String = {
            FormatDate(row("CreatedAt")),
            Value(row, "OperationLabel"),
            Value(row, "ScopeLabel"),
            Value(row, "TableLabel"),
            Value(row, "StatusLabel"),
            FormatNumber(row("ProcessedStudents")),
            Value(row, "DurationLabel"),
            Value(row, "RequestedBy")
        }
        Dim widths() As Double = {85, 55, 105, 160, 70, 60, 65, 120}
        DrawTableRow(page, values, widths, False)
    End Sub

    Private Shared Sub DrawInventoryHeader(ByVal page As PdfPage)
        Dim labels() As String = {"Tahun Akademik", "Mahasiswa Backup", "Mahasiswa Periode Terakhir", "Sinkronisasi Terakhir"}
        Dim widths() As Double = {150, 170, 190, 210}
        DrawTableRow(page, labels, widths, True)
    End Sub

    Private Shared Sub DrawInventoryRow(ByVal page As PdfPage, ByVal row As DataRow)
        Dim values() As String = {
            Value(row, "ThAkdk"),
            FormatNumber(row("BackupStudents")),
            FormatNumber(row("LatestStudentCount")),
            FormatDate(row("UpdatedAt"))
        }
        Dim widths() As Double = {150, 170, 190, 210}
        DrawTableRow(page, values, widths, False)
    End Sub

    Private Shared Sub DrawTableRow(ByVal page As PdfPage, ByVal values() As String, ByVal widths() As Double, ByVal isHeader As Boolean)
        Const rowHeight As Double = 19
        Dim x As Double = Margin
        If isHeader Then FillRectangle(page, Margin, page.Y - rowHeight, Sum(widths), rowHeight, 0.9)
        For i As Integer = 0 To values.Length - 1
            StrokeRectangle(page, x, page.Y - rowHeight, widths(i), rowHeight, 0.8)
            Dim maxChars As Integer = Math.Max(4, CInt(Math.Floor((widths(i) - 8) / If(isHeader, 4.7, 4.3))))
            WriteText(page, x + 4, page.Y - 13, If(isHeader, 8, 7.5), values(i), isHeader, maxChars)
            x += widths(i)
        Next
        page.Y -= rowHeight
    End Sub

    Private Shared Function Sum(ByVal values() As Double) As Double
        Dim result As Double = 0
        For Each value As Double In values
            result += value
        Next
        Return result
    End Function

    Private Shared Function Value(ByVal row As DataRow, ByVal columnName As String) As String
        If Not row.Table.Columns.Contains(columnName) OrElse row.IsNull(columnName) Then Return "-"
        Return row(columnName).ToString().Trim()
    End Function

    Private Shared Function FormatDate(ByVal value As Object) As String
        If value Is Nothing OrElse Convert.IsDBNull(value) Then Return "-"
        Return Convert.ToDateTime(value).ToString("dd MMM yyyy HH:mm", CultureInfo.GetCultureInfo("id-ID"))
    End Function

    Private Shared Function FormatNumber(ByVal value As Object) As String
        If value Is Nothing OrElse Convert.IsDBNull(value) Then Return "0"
        Return Convert.ToInt64(value).ToString("N0", CultureInfo.GetCultureInfo("id-ID"))
    End Function

    Private Shared Sub WriteText(ByVal page As PdfPage, ByVal x As Double, ByVal y As Double, ByVal size As Double, ByVal value As String, ByVal bold As Boolean, ByVal maxChars As Integer)
        Dim text As String = AsciiText(value, maxChars)
        page.Content.Append("BT /").Append(If(bold, "F2", "F1")).Append(" ").Append(Number(size)).Append(" Tf ")
        page.Content.Append(Number(x)).Append(" ").Append(Number(y)).Append(" Td (").Append(PdfEscape(text)).Append(") Tj ET").Append(ControlChars.Lf)
    End Sub

    Private Shared Sub DrawLine(ByVal page As PdfPage, ByVal x1 As Double, ByVal y1 As Double, ByVal x2 As Double, ByVal y2 As Double, ByVal gray As Double)
        page.Content.Append(Number(gray)).Append(" G ").Append(Number(x1)).Append(" ").Append(Number(y1)).Append(" m ").Append(Number(x2)).Append(" ").Append(Number(y2)).Append(" l S").Append(ControlChars.Lf)
    End Sub

    Private Shared Sub StrokeRectangle(ByVal page As PdfPage, ByVal x As Double, ByVal y As Double, ByVal width As Double, ByVal height As Double, ByVal gray As Double)
        page.Content.Append(Number(gray)).Append(" G ").Append(Number(x)).Append(" ").Append(Number(y)).Append(" ").Append(Number(width)).Append(" ").Append(Number(height)).Append(" re S").Append(ControlChars.Lf)
    End Sub

    Private Shared Sub FillRectangle(ByVal page As PdfPage, ByVal x As Double, ByVal y As Double, ByVal width As Double, ByVal height As Double, ByVal gray As Double)
        page.Content.Append(Number(gray)).Append(" g ").Append(Number(x)).Append(" ").Append(Number(y)).Append(" ").Append(Number(width)).Append(" ").Append(Number(height)).Append(" re f 0 g").Append(ControlChars.Lf)
    End Sub

    Private Shared Function Number(ByVal value As Double) As String
        Return value.ToString("0.##", Invariant)
    End Function

    Private Shared Function AsciiText(ByVal value As String, ByVal maxChars As Integer) As String
        If String.IsNullOrEmpty(value) Then Return "-"
        Dim normalized As String = value.Normalize(NormalizationForm.FormD)
        Dim result As New StringBuilder()
        For Each character As Char In normalized
            If CharUnicodeInfo.GetUnicodeCategory(character) = UnicodeCategory.NonSpacingMark Then Continue For
            Dim code As Integer = AscW(character)
            If code >= 32 AndAlso code <= 126 Then
                result.Append(character)
            ElseIf character = ChrW(&H2013) OrElse character = ChrW(&H2014) OrElse character = ChrW(&H2011) Then
                result.Append("-")
            Else
                result.Append("?")
            End If
        Next
        Dim text As String = result.ToString()
        If text.Length > maxChars Then text = text.Substring(0, Math.Max(1, maxChars - 3)) & "..."
        Return text
    End Function

    Private Shared Function PdfEscape(ByVal value As String) As String
        Return value.Replace("\", "\\").Replace("(", "\(").Replace(")", "\)").Replace(ControlChars.Cr, " ").Replace(ControlChars.Lf, " ")
    End Function

    Private Shared Function BuildDocument(ByVal pages As IList(Of PdfPage)) As Byte()
        Dim objectCount As Integer = 4 + pages.Count * 2
        Dim objects As Byte()() = New Byte(objectCount)() {}
        objects(1) = Bytes("<< /Type /Catalog /Pages 2 0 R >>")
        objects(3) = Bytes("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
        objects(4) = Bytes("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")

        Dim kids As New StringBuilder()
        For i As Integer = 0 To pages.Count - 1
            Dim contentId As Integer = 5 + i * 2
            Dim pageId As Integer = contentId + 1
            kids.Append(pageId).Append(" 0 R ")
            Dim contentBytes As Byte() = Bytes("q" & ControlChars.Lf & "0 g 0 G" & ControlChars.Lf & pages(i).Content.ToString() & "Q" & ControlChars.Lf)
            objects(contentId) = Combine(Bytes("<< /Length " & contentBytes.Length.ToString(Invariant) & " >>" & ControlChars.Lf & "stream" & ControlChars.Lf), contentBytes, Bytes("endstream"))
            objects(pageId) = Bytes("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 " & Number(PageWidth) & " " & Number(PageHeight) & "] /Resources << /ProcSet [/PDF /Text] /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents " & contentId.ToString(Invariant) & " 0 R >>")
        Next
        objects(2) = Bytes("<< /Type /Pages /Count " & pages.Count.ToString(Invariant) & " /Kids [" & kids.ToString() & "] >>")

        Using output As New MemoryStream()
            Write(output, Bytes("%PDF-1.4" & ControlChars.Lf & "%" & ChrW(226) & ChrW(227) & ChrW(207) & ChrW(211) & ControlChars.Lf))
            Dim offsets(objectCount) As Long
            For i As Integer = 1 To objectCount
                offsets(i) = output.Position
                Write(output, Bytes(i.ToString(Invariant) & " 0 obj" & ControlChars.Lf))
                Write(output, objects(i))
                Write(output, Bytes(ControlChars.Lf & "endobj" & ControlChars.Lf))
            Next
            Dim xrefOffset As Long = output.Position
            Write(output, Bytes("xref" & ControlChars.Lf & "0 " & (objectCount + 1).ToString(Invariant) & ControlChars.Lf))
            Write(output, Bytes("0000000000 65535 f " & ControlChars.Lf))
            For i As Integer = 1 To objectCount
                Write(output, Bytes(offsets(i).ToString("0000000000", Invariant) & " 00000 n " & ControlChars.Lf))
            Next
            Write(output, Bytes("trailer" & ControlChars.Lf & "<< /Size " & (objectCount + 1).ToString(Invariant) & " /Root 1 0 R >>" & ControlChars.Lf & "startxref" & ControlChars.Lf & xrefOffset.ToString(Invariant) & ControlChars.Lf & "%%EOF"))
            Return output.ToArray()
        End Using
    End Function

    Private Shared Function Bytes(ByVal value As String) As Byte()
        Return Encoding.GetEncoding(1252).GetBytes(value)
    End Function

    Private Shared Function Combine(ByVal first As Byte(), ByVal second As Byte(), ByVal third As Byte()) As Byte()
        Using stream As New MemoryStream()
            Write(stream, first)
            Write(stream, second)
            Write(stream, third)
            Return stream.ToArray()
        End Using
    End Function

    Private Shared Sub Write(ByVal stream As Stream, ByVal value As Byte())
        stream.Write(value, 0, value.Length)
    End Sub
End Class
</script>
