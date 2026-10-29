<%@ Control Language="VB" ClassName="backup_data_riwayat_control" %>

<%-- 
=============================================================================================
MODUL RIWAYAT & AUDIT TRAIL PROSES (riwayat.ascx)
Menyajikan daftar catatan lengkap seluruh pekerjaan (Backup, Restore, Ekspor) yang telah
selesai dijalankan, baik yang berstatus Berhasil, Gagal, maupun Dibatalkan. Dilengkapi
mekanisme penyaringan dinamis dan pagination server-side yang sangat hemat memori.
=============================================================================================
--%>
<!-- #INCLUDE file="con_backup.ascx" -->
<!-- #INCLUDE file="table_helpers.ascx" -->

<script runat="server">
    ' Ukuran halaman pagination (10 baris per halaman untuk performa rendering optimal)
    Private Const HistoryPageSize As Integer = 10
Private Property HistoryPageIndex As Long
 Get
  Return If(ViewState("HistoryPageIndex") Is Nothing,0L,Convert.ToInt64(ViewState("HistoryPageIndex")))
 End Get
 Set(value As Long)
  ViewState("HistoryPageIndex")=Math.Max(0L,value)
 End Set
End Property

Protected Sub Page_Load(sender As Object,e As EventArgs)
 RequireBackupStaff()
 Response.Cache.SetCacheability(HttpCacheability.NoCache)
 Response.Cache.SetNoStore()
 Response.Cache.SetExpires(DateTime.UtcNow.AddYears(-1))
 If Not IsPostBack Then
  ApplyHistoryFilterFromQuery()
  LoadHistory()
 End If
End Sub

Private Sub ApplyHistoryFilterFromQuery()
 Dim operation=If(Request.QueryString("operation"),"").Trim().ToUpperInvariant(),status=If(Request.QueryString("status"),"").Trim().ToUpperInvariant()
 If ddlHistoryOperation.Items.FindByValue(operation) IsNot Nothing Then ddlHistoryOperation.SelectedValue=operation
 If ddlHistoryStatus.Items.FindByValue(status) IsNot Nothing Then ddlHistoryStatus.SelectedValue=status
End Sub

Protected Sub btnApplyHistoryFilter_Click(sender As Object,e As EventArgs)
 HistoryPageIndex=0
 LoadHistory()
End Sub

Private Function HistoryWhereSql() As String
 Dim filters As New System.Collections.Generic.List(Of String)()
 filters.Add("j.Status NOT IN ('WAITING','CLAIMED','TRANSFERRING')")
 If ddlHistoryOperation.SelectedValue<>"" Then filters.Add("j.OperationType=@OperationType")
 Select Case ddlHistoryStatus.SelectedValue
  Case "SUCCESS":filters.Add("j.Status='SUCCESS'")
  Case "FAILED":filters.Add("j.Status='FAILED' AND ISNULL(j.ErrorMessage,'') NOT LIKE '[[]CANCELLED]%'")
  Case "CANCELLED":filters.Add("j.Status='FAILED' AND ISNULL(j.ErrorMessage,'') LIKE '[[]CANCELLED]%'")
 End Select
 Return " WHERE " & String.Join(" AND ",filters.ToArray())
End Function

    ' =========================================================================================
    ' PEMUATAN DATA RIWAYAT (SERVER-SIDE PAGINATION DENGAN OFFSET FETCH)
    ' Mengambil data menggunakan query efisien SQL Server 'OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY'
    ' agar pembacaan tabel tetap cepat dan ringan walaupun riwayat telah mencapai puluhan ribu baris.
    ' =========================================================================================
    Private Sub LoadHistory()
        Dim data As New DataTable()
        Try
            litHistoryMessage.Text = ""
            cnsr.Open()
            Dim totalRows As Long
            
            ' 1. Hitung total baris yang cocok dengan kriteria filter aktif
            Using countCommand As New SqlCommand("SELECT COUNT_BIG(*) FROM dbo.BackupTransferJob j" & HistoryWhereSql(), cnsr)
                AddHistoryParameters(countCommand)
                totalRows = Convert.ToInt64(countCommand.ExecuteScalar())
            End Using
            
            Dim lastPage = If(totalRows = 0, 0L, (totalRows - 1) \ HistoryPageSize)
            HistoryPageIndex = Math.Min(HistoryPageIndex, lastPage)
            ViewState("HistoryLastPage") = lastPage
            
            ' 2. Ambil hanya baris yang dibutuhkan pada halaman saat ini
            Dim historySql = "SELECT j.JobId,j.OperationType,j.TriggerSource,j.CutoffThAkdk,j.StudentNim,j.RestoreThAkdkList,j.SelectedTables,j.Status,j.ProcessedStudents,j.CreatedAt,j.CompletedAt,j.ProgressMessage,j.ResultMessage,j.ErrorMessage,j.TotalStudents,(SELECT COUNT(*) FROM dbo.BackupTransferJobStudent s WHERE s.JobId=j.JobId) TrackedStudents FROM dbo.BackupTransferJob j" & HistoryWhereSql() & " ORDER BY j.CreatedAt DESC,j.JobId DESC OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY"
  Using cmd As New SqlCommand(historySql,cnsr)
   AddHistoryParameters(cmd)
   cmd.Parameters.Add("@Offset",SqlDbType.BigInt).Value=HistoryPageIndex*HistoryPageSize
   cmd.Parameters.Add("@PageSize",SqlDbType.Int).Value=HistoryPageSize
   Using ad As New SqlDataAdapter(cmd):ad.Fill(data):End Using
  End Using
  pnlHistoryPager.Visible=(lastPage>0)
  lblHistoryPage.Text=(HistoryPageIndex+1).ToString("N0") & " / " & (lastPage+1).ToString("N0")
  lblHistoryPage.ToolTip=totalRows.ToString("N0") & " proses"
  btnHistoryFirst.Enabled=(HistoryPageIndex>0):btnHistoryPrevious.Enabled=(HistoryPageIndex>0)
  btnHistoryNext.Enabled=(HistoryPageIndex<lastPage):btnHistoryLast.Enabled=(HistoryPageIndex<lastPage)
  Dim inventoryByYear=LoadInventoryPeriodsByYear()
  data.Columns.Add("OperationLabel",GetType(String))
  data.Columns.Add("DetailLabel",GetType(String))
  For Each row As DataRow In data.Rows
   Dim operation=row("OperationType").ToString().Trim().ToUpperInvariant()
   Dim status=row("Status").ToString().Trim().ToUpperInvariant()
   row("OperationLabel")=GetOperationTargetLabel(row,operation,inventoryByYear)
   Dim progress=If(row.IsNull("ProgressMessage"),"",row("ProgressMessage").ToString()),result=If(row.IsNull("ResultMessage"),"",row("ResultMessage").ToString()),failure=If(row.IsNull("ErrorMessage"),"",row("ErrorMessage").ToString())
   Dim detail=If(status="SUCCESS",result,If(status="FAILED",failure,progress))
   Dim processed=Convert.ToInt32(row("ProcessedStudents"))
   row("DetailLabel")=CleanProgressDetail(detail,operation,status,processed)
  Next
  gvProcessHistory.DataSource=data:gvProcessHistory.DataBind()
 Catch ex As Exception
  pnlHistoryPager.Visible=False
  litHistoryMessage.Text="<div class='alert alert-danger'><strong>Gagal memuat riwayat.</strong> " & Server.HtmlEncode(BackupErrorMessage(ex)) & "</div>"
 Finally
  tutupsr()
 End Try
End Sub


Private Function LoadInventoryPeriodsByYear() As System.Collections.Generic.Dictionary(Of String,System.Collections.Generic.HashSet(Of String))
 Dim result As New System.Collections.Generic.Dictionary(Of String,System.Collections.Generic.HashSet(Of String))(StringComparer.OrdinalIgnoreCase)
 Using cmd As New SqlCommand("SELECT DISTINCT RTRIM(p.ThAkdk) ThAkdk FROM dbo.BackupAgentPeriodInventory p JOIN dbo.BackupAgentNode a ON a.AgentId=p.AgentId WHERE a.IsPrimary=1 AND a.IsEnabled=1",cnsr)
  If cnsr.State=ConnectionState.Closed Then cnsr.Open()
  Using rd=cmd.ExecuteReader()
   While rd.Read()
    Dim ta=rd("ThAkdk").ToString().Trim()
    If ta.Length>=4 Then
     Dim year=ta.Substring(0,4)
     If Not result.ContainsKey(year) Then result(year)=New System.Collections.Generic.HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
     result(year).Add(ta)
    End If
   End While
  End Using
 End Using
 Return result
End Function



Private Function CleanProgressDetail(detail As String,operation As String,status As String,processed As Integer) As String
 Dim cleaned=System.Text.RegularExpressions.Regex.Replace(BackupFriendlyText(detail),"^\[TOTAL:\d+\]\s*","")
 cleaned=System.Text.RegularExpressions.Regex.Replace(cleaned,"(?i)\bMenunggu\s+laptop(?:\s+backup)?\b","Menunggu Database Backup")
 If status="SUCCESS" AndAlso operation="BACKUP" Then
  Return processed.ToString("N0") & " Data Mahasiswa Berhasil Dibackup"
 End If
 If status="SUCCESS" AndAlso operation="RESTORE" Then
  Dim restoredMessage=processed.ToString("N0") & " Data Mahasiswa Berhasil Dipulihkan"
  Dim skippedMatch=System.Text.RegularExpressions.Regex.Match(cleaned,"(?<count>\d+)\s+Data Mahasiswa Dilewati Karena Seluruh Baris Sudah Tersedia",System.Text.RegularExpressions.RegexOptions.IgnoreCase)
  If skippedMatch.Success Then
   Dim skipped As Integer
   If Integer.TryParse(skippedMatch.Groups("count").Value,skipped) AndAlso skipped>0 Then Return restoredMessage & vbLf & skipped.ToString("N0") & " Data Mahasiswa Dilewati Karena Seluruh Baris Sudah Tersedia"
  End If
  Return restoredMessage
 End If
 If operation="BACKUP" AndAlso (cleaned.StartsWith("Menyalin batch backup",StringComparison.OrdinalIgnoreCase) OrElse cleaned.StartsWith("Mengonfirmasi batch backup",StringComparison.OrdinalIgnoreCase) OrElse cleaned.StartsWith("Proses Backup",StringComparison.OrdinalIgnoreCase)) Then
  Return "Proses Backup"
 End If
 If operation="RESTORE" AndAlso (cleaned.StartsWith("Menyiapkan pemulihan",StringComparison.OrdinalIgnoreCase) OrElse cleaned.StartsWith("Mengirim batch pemulihan",StringComparison.OrdinalIgnoreCase) OrElse cleaned.StartsWith("Menyelesaikan pemulihan",StringComparison.OrdinalIgnoreCase) OrElse cleaned.StartsWith("Proses Pemulihan",StringComparison.OrdinalIgnoreCase)) Then
  Return "Proses Pemulihan"
 End If
 Return If(String.IsNullOrWhiteSpace(cleaned),"-",cleaned)
End Function



Private Sub AddHistoryParameters(cmd As SqlCommand)
 If ddlHistoryOperation.SelectedValue<>"" Then cmd.Parameters.Add("@OperationType",SqlDbType.VarChar,10).Value=ddlHistoryOperation.SelectedValue
End Sub

Protected Sub HistoryPage_Command(sender As Object,e As CommandEventArgs)
 Dim lastPage=If(ViewState("HistoryLastPage") Is Nothing,0L,Convert.ToInt64(ViewState("HistoryLastPage")))
 Select Case Convert.ToString(e.CommandArgument)
  Case "first":HistoryPageIndex=0
  Case "previous":HistoryPageIndex-=1
  Case "next":HistoryPageIndex=Math.Min(lastPage,HistoryPageIndex+1)
  Case "last":HistoryPageIndex=lastPage
  Case Else:Return
 End Select
 LoadHistory()
End Sub

Private Function GetTargetLabel(row As DataRow,operation As String,inventoryByYear As System.Collections.Generic.Dictionary(Of String,System.Collections.Generic.HashSet(Of String))) As String
 If operation="BACKUP" Then
  If Not row.IsNull("StudentNim") AndAlso Not String.IsNullOrWhiteSpace(row("StudentNim").ToString()) Then Return "NIM: " & row("StudentNim").ToString().Trim()
  If Not row.IsNull("RestoreThAkdkList") Then
   Dim backupTarget=row("RestoreThAkdkList").ToString().Trim()
   If backupTarget.StartsWith("SINGLE:",StringComparison.OrdinalIgnoreCase) Then Return "TA " & backupTarget.Substring(7)
   If backupTarget.StartsWith("RANGE:",StringComparison.OrdinalIgnoreCase) Then Return "TA " & backupTarget.Substring(6).Replace("-"," sampai ")
   If backupTarget.StartsWith("UP_TO:",StringComparison.OrdinalIgnoreCase) Then Return "TA " & backupTarget.Substring(6) & " dan sebelumnya"
  End If
  Return If(row.IsNull("CutoffThAkdk"),"-","TA " & row("CutoffThAkdk").ToString().Trim() & " dan sebelumnya")
 End If
 If operation="EXPORT" Then Return "Database Backup"
 If Not row.IsNull("StudentNim") AndAlso Not String.IsNullOrWhiteSpace(row("StudentNim").ToString()) Then Return "NIM: " & row("StudentNim").ToString().Trim()
 If row.IsNull("RestoreThAkdkList") Then Return "-"
 Dim raw=row("RestoreThAkdkList").ToString(),selected As New System.Collections.Generic.HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
 For Each value As String In raw.Split(","c)
  Dim ta=value.Trim()
  If ta<>"" Then selected.Add(ta)
 Next
 If selected.Count=0 Then Return "-"
 Dim allInventory As New System.Collections.Generic.HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
 For Each periods As System.Collections.Generic.HashSet(Of String) In inventoryByYear.Values
  allInventory.UnionWith(periods)
 Next
 If allInventory.Count>0 AndAlso selected.SetEquals(allInventory) Then Return "Semua Tahun"
 Dim selectedYears As New System.Collections.Generic.HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
 For Each ta As String In selected
  If ta.Length>=4 Then selectedYears.Add(ta.Substring(0,4))
 Next
 If selected.Count>0 Then
  Dim year As String="",sameYear As Boolean=True
  For Each ta As String In selected
   If ta.Length<4 Then sameYear=False : Exit For
   If year="" Then
    year=ta.Substring(0,4)
   ElseIf ta.Substring(0,4)<>year Then
    sameYear=False : Exit For
   End If
  Next
  If sameYear AndAlso inventoryByYear.ContainsKey(year) AndAlso selected.SetEquals(inventoryByYear(year)) Then Return year
 End If
 Dim values(selected.Count-1) As String:selected.CopyTo(values):Array.Sort(values,StringComparer.OrdinalIgnoreCase)
 If selectedYears.Count>1 Then
  Dim years(selectedYears.Count-1) As String:selectedYears.CopyTo(years):Array.Sort(years,StringComparer.OrdinalIgnoreCase)
  Return years(0) & "-" & years(years.Length-1) & " (" & selected.Count.ToString() & " TA)"
 End If
 Return "TA: " & String.Join(", ",values)
End Function

Private Function GetOperationTargetLabel(row As DataRow,operation As String,inventoryByYear As System.Collections.Generic.Dictionary(Of String,System.Collections.Generic.HashSet(Of String))) As String
 Dim scheduled=Not row.IsNull("TriggerSource") AndAlso (row("TriggerSource").ToString().Trim().Equals("SCHEDULE",StringComparison.OrdinalIgnoreCase) OrElse row("TriggerSource").ToString().Trim().Equals("SCHEDULED",StringComparison.OrdinalIgnoreCase))
 If operation="EXPORT" Then Return "Ekspor Database Backup"
 If operation="BACKUP" AndAlso scheduled AndAlso Not row.IsNull("CutoffThAkdk") Then
  Dim scheduledTa=row("CutoffThAkdk").ToString().Trim()
  If scheduledTa.Length>=4 Then Return "Backup Terjadwal Tahun " & scheduledTa.Substring(0,4)
 End If
 Dim title As String
 If operation="BACKUP" Then
  title="Backup" & If(scheduled," Terjadwal","")
 ElseIf operation="RESTORE" Then
  title="Pemulihan" & If(scheduled," Terjadwal","")
 Else
  title=operation
 End If
 Dim target=GetTargetLabel(row,operation,inventoryByYear).Trim()
 If target="" OrElse target="-" OrElse target.Equals("Database Backup",StringComparison.OrdinalIgnoreCase) Then Return title
 If target.StartsWith("NIM:",StringComparison.OrdinalIgnoreCase) Then target="NIM " & target.Substring(4).Trim()
 If target.StartsWith("TA: ",StringComparison.OrdinalIgnoreCase) Then
  target="Tahun Akademik " & target.Substring(4).Trim()
 ElseIf target.StartsWith("TA ",StringComparison.OrdinalIgnoreCase) Then
  target="Tahun Akademik " & target.Substring(3).Trim()
 ElseIf System.Text.RegularExpressions.Regex.IsMatch(target,"^\d{4}$") Then
  target="Tahun " & target
 ElseIf System.Text.RegularExpressions.Regex.IsMatch(target,"^\d{4}[^\d]+\d{4}") Then
  target="Tahun " & target
 End If
 Return title & " " & target
End Function


Protected Function GetHistoryOperationBadge(opObj As Object) As String
    Dim op = If(opObj Is Nothing, "", opObj.ToString().Trim().ToUpperInvariant())
    Select Case op
        Case "BACKUP": Return "<span class='label label-success' style='font-size: 10px; padding: 3px 7px; border-radius: 4px; display: inline-flex; align-items: center; gap: 4px;'><i class='fa fa-database'></i> Backup</span>"
        Case "RESTORE": Return "<span class='label label-info' style='font-size: 10px; padding: 3px 7px; border-radius: 4px; display: inline-flex; align-items: center; gap: 4px;'><i class='fa fa-undo'></i> Pemulihan</span>"
        Case "EXPORT": Return "<span class='label label-default' style='font-size: 10px; padding: 3px 7px; border-radius: 4px; background-color: #475569; color: #fff; display: inline-flex; align-items: center; gap: 4px;'><i class='fa fa-file-archive-o'></i> Ekspor</span>"
        Case Else: Return "<span class='label label-default' style='font-size: 10px; padding: 3px 7px;'>" & Server.HtmlEncode(op) & "</span>"
    End Select
End Function

Protected Function GetOperationCleanTarget(labelObj As Object, opObj As Object) As String
    Dim label = If(labelObj Is Nothing, "", labelObj.ToString().Trim())
    Dim op = If(opObj Is Nothing, "", opObj.ToString().Trim().ToUpperInvariant())
    If op = "BACKUP" Then
        If label.StartsWith("Backup ", StringComparison.OrdinalIgnoreCase) Then label = label.Substring(7).Trim()
    ElseIf op = "RESTORE" Then
        If label.StartsWith("Pemulihan ", StringComparison.OrdinalIgnoreCase) Then label = label.Substring(10).Trim()
    ElseIf op = "EXPORT" Then
        If label.StartsWith("Ekspor ", StringComparison.OrdinalIgnoreCase) Then label = label.Substring(7).Trim()
    End If
    Return If(String.IsNullOrWhiteSpace(label), "-", label)
End Function

Protected Function GetHistoryStatusBadge(statusObj As Object, errorObj As Object) As String
    Dim status = If(statusObj Is Nothing, "", statusObj.ToString().Trim().ToUpperInvariant())
    Dim err = If(errorObj Is Nothing, "", errorObj.ToString())
    If status = "FAILED" AndAlso err.StartsWith("[CANCELLED]", StringComparison.OrdinalIgnoreCase) Then
        Return "<span class='label label-default' style='font-size: 11px; padding: 4px 8px; border-radius: 4px; background-color: #64748b; color: #fff; display: inline-flex; align-items: center; gap: 4px;'><i class='fa fa-ban'></i> Dibatalkan</span>"
    End If
    Select Case status
        Case "SUCCESS": Return "<span class='label label-success' style='font-size: 11px; padding: 4px 8px; border-radius: 4px; display: inline-flex; align-items: center; gap: 4px;'><i class='fa fa-check'></i> Berhasil</span>"
        Case "FAILED": Return "<span class='label label-danger' style='font-size: 11px; padding: 4px 8px; border-radius: 4px; display: inline-flex; align-items: center; gap: 4px;'><i class='fa fa-times'></i> Gagal</span>"
        Case "WAITING": Return "<span class='label label-warning' style='font-size: 11px; padding: 4px 8px; border-radius: 4px; display: inline-flex; align-items: center; gap: 4px;'><i class='fa fa-clock-o'></i> Menunggu</span>"
        Case "CLAIMED", "TRANSFERRING": Return "<span class='label label-primary' style='font-size: 11px; padding: 4px 8px; border-radius: 4px; display: inline-flex; align-items: center; gap: 4px;'><i class='fa fa-refresh fa-spin'></i> Diproses</span>"
        Case Else: Return "<span class='label label-default' style='font-size: 11px; padding: 4px 8px;'>" & Server.HtmlEncode(status) & "</span>"
    End Select
End Function

Protected Function FormatHistoryTables(raw As Object) As String
    Dim val = If(raw Is Nothing, "", raw.ToString().Trim())
    If String.IsNullOrWhiteSpace(val) Then Return "<span class='text-muted'>-</span>"
    Dim html As New System.Text.StringBuilder()
    For Each tbl In val.Split(","c)
        Select Case tbl.Trim().ToLowerInvariant()
            Case "tbio01": html.Append("<span class='label label-default' style='font-size: 10px; padding: 2px 6px; background: #f8fafc; color: #334155; border: 1px solid #cbd5e1; margin-right: 4px; margin-bottom: 2px; display: inline-block; font-weight: 500;'>Biodata</span>")
            Case "treg": html.Append("<span class='label label-default' style='font-size: 10px; padding: 2px 6px; background: #f8fafc; color: #334155; border: 1px solid #cbd5e1; margin-right: 4px; margin-bottom: 2px; display: inline-block; font-weight: 500;'>Registrasi</span>")
            Case "tkrs06": html.Append("<span class='label label-default' style='font-size: 10px; padding: 2px 6px; background: #f8fafc; color: #334155; border: 1px solid #cbd5e1; margin-right: 4px; margin-bottom: 2px; display: inline-block; font-weight: 500;'>KRS</span>")
            Case "t_absensi14": html.Append("<span class='label label-default' style='font-size: 10px; padding: 2px 6px; background: #f8fafc; color: #334155; border: 1px solid #cbd5e1; margin-right: 4px; margin-bottom: 2px; display: inline-block; font-weight: 500;'>Absensi</span>")
        End Select
    Next
    Return If(html.Length > 0, html.ToString(), "<span class='text-muted'>-</span>")
End Function

Protected Function FormatHistoryProgress(opObj As Object, processedObj As Object, totalObj As Object) As String
    Dim op = If(opObj Is Nothing, "", opObj.ToString().Trim().ToUpperInvariant())
    If op = "EXPORT" Then Return "<span class='text-muted' style='font-size: 14px;'>-</span>"
    
    Dim processed As Integer = If(processedObj IsNot Nothing AndAlso Not Convert.IsDBNull(processedObj), Convert.ToInt32(processedObj), 0)
    Dim total As Integer = If(totalObj IsNot Nothing AndAlso Not Convert.IsDBNull(totalObj), Convert.ToInt32(totalObj), -1)
    
    Dim totalText = If(total >= 0, total.ToString("N0"), processed.ToString("N0"))
    Return "<div class='text-center' style='white-space: nowrap;'><span style='font-weight: 700; color: #0f172a; font-size: 13px;'>" & processed.ToString("N0") & "</span><span style='color: #64748b; font-size: 12px;'> / " & totalText & "</span></div>"
End Function

Protected Function FormatHistoryDetail(detailObj As Object, statusObj As Object, opObj As Object) As String
    Dim detail = If(detailObj Is Nothing, "", detailObj.ToString())
    Dim status = If(statusObj Is Nothing, "", statusObj.ToString().Trim().ToUpperInvariant())
    Dim op = If(opObj Is Nothing, "", opObj.ToString().Trim().ToUpperInvariant())
    
    If op = "EXPORT" AndAlso (status = "SUCCESS" OrElse detail.Contains("RESTORE VERIFYONLY")) Then
        Dim fileMatch = System.Text.RegularExpressions.Regex.Match(detail, "File lokal:\s*(?<file>[^|]+)", System.Text.RegularExpressions.RegexOptions.IgnoreCase)
        Dim sizeMatch = System.Text.RegularExpressions.Regex.Match(detail, "Ukuran:\s*(?<size>[^|]+)", System.Text.RegularExpressions.RegexOptions.IgnoreCase)
        
        Dim fileName = If(fileMatch.Success, fileMatch.Groups("file").Value.Trim(), "")
        Dim sizeText = If(sizeMatch.Success, sizeMatch.Groups("size").Value.Trim(), "")
        
        Dim shortName = fileName
        If fileName.Length > 48 Then
            shortName = fileName.Substring(0, 24) & "..." & fileName.Substring(fileName.Length - 12)
        End If
        
        Dim html As New System.Text.StringBuilder()
        html.Append("<div style='line-height: 1.4;'>")
        html.Append("<div class='text-success' style='font-weight: 600; font-size: 12px;'><i class='fa fa-check-circle' style='margin-right: 4px;'></i>File .BAK Berhasil Diekspor & Terverifikasi</div>")
        
        If shortName <> "" OrElse sizeText <> "" Then
            html.Append("<div class='text-muted small' style='margin-top: 3px; display: flex; align-items: center; gap: 6px; flex-wrap: wrap;'>")
            If shortName <> "" Then
                html.Append("<span style='font-family: Consolas, monospace; font-size: 11px;' title='" & Server.HtmlEncode(fileName) & "'><i class='fa fa-file-archive-o text-muted'></i> " & Server.HtmlEncode(shortName) & "</span>")
            End If
            If sizeText <> "" Then
                html.Append("<span class='badge' style='background: #f1f5f9; color: #334155; border: 1px solid #cbd5e1; font-size: 10px; padding: 2px 6px; font-weight: 600;'><i class='fa fa-database'></i> " & Server.HtmlEncode(sizeText) & "</span>")
            End If
            html.Append("</div>")
        End If
        html.Append("</div>")
        Return html.ToString()
    End If
    
    If status = "SUCCESS" Then
        Return "<span class='text-success' style='font-weight: 500; font-size: 12px;'><i class='fa fa-check-circle' style='margin-right: 4px;'></i>" & Server.HtmlEncode(detail) & "</span>"
    ElseIf status = "FAILED" Then
        Return "<span class='text-danger' style='font-weight: 500; font-size: 12px;'><i class='fa fa-exclamation-triangle' style='margin-right: 4px;'></i>" & Server.HtmlEncode(detail) & "</span>"
    End If
    Return "<span class='text-muted' style='font-size: 12px;'>" & Server.HtmlEncode(detail) & "</span>"
End Function

</script>
<div class="backup-page backup-page-monitoring">
 <div class="backup-page-header">
  <span class="backup-page-eyebrow">Pemantauan</span>
  <h1>Riwayat Proses</h1>
 </div>
 <asp:Literal ID="litHistoryMessage" runat="server" />
 <div class="panel panel-default history-filter-panel">
  <div class="panel-heading"><i class="fa fa-filter"></i> Filter Riwayat</div>
  <div class="panel-body history-filter-grid">
   <div class="history-filter-field"><label for="<%= ddlHistoryOperation.ClientID %>">Jenis operasi</label><asp:DropDownList ID="ddlHistoryOperation" runat="server" CssClass="form-control"><asp:ListItem Value="">Semua</asp:ListItem><asp:ListItem Value="BACKUP">Backup</asp:ListItem><asp:ListItem Value="RESTORE">Pemulihan</asp:ListItem><asp:ListItem Value="EXPORT">Ekspor</asp:ListItem></asp:DropDownList></div>
   <div class="history-filter-field"><label for="<%= ddlHistoryStatus.ClientID %>">Status</label><asp:DropDownList ID="ddlHistoryStatus" runat="server" CssClass="form-control"><asp:ListItem Value="">Semua</asp:ListItem><asp:ListItem Value="SUCCESS">Berhasil</asp:ListItem><asp:ListItem Value="FAILED">Gagal</asp:ListItem><asp:ListItem Value="CANCELLED">Dibatalkan</asp:ListItem></asp:DropDownList></div>
   <div class="history-filter-action"><asp:Button ID="btnApplyHistoryFilter" runat="server" Text="Terapkan Filter" CssClass="btn btn-primary" OnClick="btnApplyHistoryFilter_Click" /></div>
  </div>
 </div>
 <div class="panel history-card">
  <div class="panel-heading"><i class="fa fa-history"></i> Riwayat Proses</div>
  <div class="table-responsive">
   <asp:GridView ID="gvProcessHistory" runat="server" AutoGenerateColumns="false" AllowPaging="false" CssClass="table table-hover history-table" EmptyDataText="Belum ada riwayat proses selesai." GridLines="None">
    <Columns>
     <asp:TemplateField HeaderText="Dibuat" HeaderStyle-Width="115px" HeaderStyle-CssClass="text-center" HeaderStyle-HorizontalAlign="Center" ItemStyle-CssClass="text-center history-nowrap" ItemStyle-HorizontalAlign="Center">
      <ItemTemplate>
       <div class="text-center" style="white-space: nowrap;">
        <div style="font-weight: 600; color: #1e293b; font-size: 12px;"><%# Eval("CreatedAt", "{0:dd MMM yyyy}") %></div>
        <div class="text-muted" style="font-size: 11px; margin-top: 1px;"><i class="fa fa-clock-o"></i> <%# Eval("CreatedAt", "{0:HH:mm}") %></div>
       </div>
      </ItemTemplate>
     </asp:TemplateField>

     <asp:TemplateField HeaderText="Operasi" HeaderStyle-Width="220px">
      <ItemTemplate>
       <div style="display: flex; flex-direction: column; align-items: flex-start; gap: 3px;">
        <div><%# GetHistoryOperationBadge(Eval("OperationType")) %></div>
        <div style="font-weight: 600; color: #1e293b; font-size: 13px; margin-top: 1px;"><%# GetOperationCleanTarget(Eval("OperationLabel"), Eval("OperationType")) %></div>
       </div>
      </ItemTemplate>
     </asp:TemplateField>

     <asp:TemplateField HeaderText="Tabel" HeaderStyle-Width="180px">
      <ItemTemplate>
       <div style="display: flex; flex-wrap: wrap; gap: 3px;">
        <%# FormatHistoryTables(Eval("SelectedTables")) %>
       </div>
      </ItemTemplate>
     </asp:TemplateField>

     <asp:TemplateField HeaderText="Status" HeaderStyle-Width="110px" HeaderStyle-CssClass="text-center" HeaderStyle-HorizontalAlign="Center" ItemStyle-CssClass="text-center" ItemStyle-HorizontalAlign="Center">
      <ItemTemplate>
       <div class="text-center">
        <%# GetHistoryStatusBadge(Eval("Status"), Eval("ErrorMessage")) %>
       </div>
      </ItemTemplate>
     </asp:TemplateField>

     <asp:TemplateField HeaderText="Diproses" HeaderStyle-Width="120px" HeaderStyle-CssClass="text-center" HeaderStyle-HorizontalAlign="Center" ItemStyle-CssClass="text-center history-nowrap" ItemStyle-HorizontalAlign="Center">
      <ItemTemplate>
       <%# FormatHistoryProgress(Eval("OperationType"), Eval("ProcessedStudents"), Eval("TotalStudents")) %>
      </ItemTemplate>
     </asp:TemplateField>

     <asp:TemplateField HeaderText="Selesai" HeaderStyle-Width="115px" HeaderStyle-CssClass="text-center" HeaderStyle-HorizontalAlign="Center" ItemStyle-CssClass="text-center history-nowrap" ItemStyle-HorizontalAlign="Center">
      <ItemTemplate>
       <%# If(Eval("CompletedAt") IsNot Nothing AndAlso Not Convert.IsDBNull(Eval("CompletedAt")), _
           "<div class='text-center' style='white-space: nowrap;'><div style='font-weight: 600; color: #1e293b; font-size: 12px;'>" & String.Format("{0:dd MMM yyyy}", Eval("CompletedAt")) & "</div><div class='text-muted' style='font-size: 11px; margin-top: 1px;'><i class='fa fa-clock-o'></i> " & String.Format("{0:HH:mm}", Eval("CompletedAt")) & "</div></div>", _
           "<span class='text-muted'>-</span>") %>
      </ItemTemplate>
     </asp:TemplateField>

     <asp:TemplateField HeaderText="Keterangan">
      <ItemTemplate>
       <%# FormatHistoryDetail(Eval("DetailLabel"), Eval("Status"), Eval("OperationType")) %>
      </ItemTemplate>
     </asp:TemplateField>
    </Columns>
   </asp:GridView>
   <asp:Panel ID="pnlHistoryPager" runat="server" CssClass="panel-footer history-pager" Visible="false">
    <asp:Button ID="btnHistoryFirst" runat="server" Text="«" CssClass="history-pager-button" CommandArgument="first" OnCommand="HistoryPage_Command" CausesValidation="false" ToolTip="Halaman pertama" aria-label="Halaman pertama" />
    <asp:Button ID="btnHistoryPrevious" runat="server" Text="‹" CssClass="history-pager-button" CommandArgument="previous" OnCommand="HistoryPage_Command" CausesValidation="false" ToolTip="Halaman sebelumnya" aria-label="Halaman sebelumnya" />
    <asp:Label ID="lblHistoryPage" runat="server" CssClass="history-pager-label" />
    <asp:Button ID="btnHistoryNext" runat="server" Text="›" CssClass="history-pager-button" CommandArgument="next" OnCommand="HistoryPage_Command" CausesValidation="false" ToolTip="Halaman berikutnya" aria-label="Halaman berikutnya" />
    <asp:Button ID="btnHistoryLast" runat="server" Text="»" CssClass="history-pager-button" CommandArgument="last" OnCommand="HistoryPage_Command" CausesValidation="false" ToolTip="Halaman terakhir" aria-label="Halaman terakhir" />
   </asp:Panel>
  </div>
 </div>
</div>
