<%@ Control Language="VB" ClassName="backup_data_riwayat_control" %>
<!-- #INCLUDE file="con_backup.ascx" -->
<!-- #INCLUDE file="table_helpers.ascx" -->

<script runat="server">
Private Const HistoryPageSize As Integer=10
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

Private Sub LoadHistory()
 Dim data As New DataTable()
 Try
  litHistoryMessage.Text=""
  cnsr.Open()
  Dim totalRows As Long
  Using countCommand As New SqlCommand("SELECT COUNT_BIG(*) FROM dbo.BackupTransferJob j" & HistoryWhereSql(),cnsr)
   AddHistoryParameters(countCommand)
   totalRows=Convert.ToInt64(countCommand.ExecuteScalar())
  End Using
  Dim lastPage=If(totalRows=0,0L,(totalRows-1) \ HistoryPageSize)
  HistoryPageIndex=Math.Min(HistoryPageIndex,lastPage)
  ViewState("HistoryLastPage")=lastPage
  Dim historySql="SELECT j.JobId,j.OperationType,j.TriggerSource,j.CutoffThAkdk,j.StudentNim,j.RestoreThAkdkList,j.SelectedTables,j.Status,j.ProcessedStudents,j.CreatedAt,j.CompletedAt,j.ProgressMessage,j.ResultMessage,j.ErrorMessage,j.TotalStudents,j.VerificationStatus,j.VerificationSummary,j.VerifiedAt,(SELECT COUNT(*) FROM dbo.BackupTransferJobStudent s WHERE s.JobId=j.JobId) TrackedStudents FROM dbo.BackupTransferJob j" & HistoryWhereSql() & " ORDER BY j.CreatedAt DESC,j.JobId DESC OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY"
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
  data.Columns.Add("StatusLabel",GetType(String))
  data.Columns.Add("ProgressLabel",GetType(String))
  data.Columns.Add("TableLabel",GetType(String))
  data.Columns.Add("DetailLabel",GetType(String))
  data.Columns.Add("VerificationBadgeHtml",GetType(String))
  data.Columns.Add("CanResync",GetType(Boolean))
  For Each row As DataRow In data.Rows
   Dim operation=row("OperationType").ToString().Trim().ToUpperInvariant()
   Dim status=row("Status").ToString().Trim().ToUpperInvariant()
   row("OperationLabel")=GetOperationTargetLabel(row,operation,inventoryByYear)
   row("TableLabel")=BackupTableLabels(row("SelectedTables").ToString())
   Dim progress=If(row.IsNull("ProgressMessage"),"",row("ProgressMessage").ToString()),result=If(row.IsNull("ResultMessage"),"",row("ResultMessage").ToString()),failure=If(row.IsNull("ErrorMessage"),"",row("ErrorMessage").ToString())
   Dim detail=If(status="SUCCESS",result,If(status="FAILED",failure,progress))
   row("StatusLabel")=If(status="FAILED" AndAlso failure.StartsWith("[CANCELLED]",StringComparison.OrdinalIgnoreCase),"Dibatalkan",TransferStatusText(status))
   Dim processed=Convert.ToInt32(row("ProcessedStudents")),tracked=Convert.ToInt32(row("TrackedStudents")),storedTotal=If(row.IsNull("TotalStudents"),-1,Convert.ToInt32(row("TotalStudents"))),total=GetProgressTotal(storedTotal,tracked,operation,status,processed)
   row("ProgressLabel")=String.Format("{0:N0}",processed) & "/" & If(total>=0,String.Format("{0:N0}",total),"-")
   row("DetailLabel")=CleanProgressDetail(detail,operation,status,processed)
   Dim vStatus=If(row.IsNull("VerificationStatus"),"UNVERIFIED",row("VerificationStatus").ToString().Trim().ToUpperInvariant())
   Dim vSummary=If(row.IsNull("VerificationSummary"),"",row("VerificationSummary").ToString().Trim())
   Dim isBackup=operation.Equals("BACKUP",StringComparison.OrdinalIgnoreCase)
   Dim isSuccess=status.Equals("SUCCESS",StringComparison.OrdinalIgnoreCase)
   row("CanResync")=(isBackup AndAlso isSuccess AndAlso vStatus="MISMATCH")
   If isBackup AndAlso isSuccess Then
    If vStatus="VERIFIED" Then
     row("VerificationBadgeHtml")="<span class='label label-success' title='" & Server.HtmlEncode(vSummary) & "'><i class='fa fa-check' aria-hidden='true'></i> 100% Cocok</span>"
    ElseIf vStatus="MISMATCH" Then
     row("VerificationBadgeHtml")="<span class='label label-warning' title='" & Server.HtmlEncode(vSummary) & "'><i class='fa fa-exclamation-triangle' aria-hidden='true'></i> Selisih</span>"
    Else
     row("VerificationBadgeHtml")="<span class='label label-default' title='Belum diverifikasi'><i class='fa fa-clock-o' aria-hidden='true'></i> Belum diverifikasi</span>"
    End If
   Else
    row("VerificationBadgeHtml")="<span class='text-muted'>-</span>"
   End If
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

Private Function GetProgressTotal(storedTotal As Integer,tracked As Integer,operation As String,status As String,processed As Integer) As Integer
 If storedTotal>=0 Then Return storedTotal
 If operation="BACKUP" Then Return tracked
 If operation="RESTORE" AndAlso status="SUCCESS" Then Return processed
 Return -1
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

Protected Sub gvProcessHistory_RowCommand(sender As Object,e As GridViewCommandEventArgs)
 If e.CommandName="ResyncJob" Then
  Dim jobId As Guid
  If Guid.TryParse(Convert.ToString(e.CommandArgument),jobId) Then
   ResyncJob(jobId)
  End If
 End If
End Sub

Private Sub ResyncJob(jobId As Guid)
 Try
  Dim cutoffTa As String="",startTa As String="",mode As String="UP_TO",tables As String="",studentNim As String=""
  Using cmd As New SqlCommand("SELECT CutoffThAkdk,StudentNim,RestoreThAkdkList,SelectedTables FROM dbo.BackupTransferJob WHERE JobId=@JobId AND OperationType='BACKUP'",cnsr)
   cmd.Parameters.Add("@JobId",SqlDbType.UniqueIdentifier).Value=jobId
   If cnsr.State=ConnectionState.Closed Then cnsr.Open()
   Using rd=cmd.ExecuteReader()
    If Not rd.Read() Then Throw New ApplicationException("Job backup tidak ditemukan.")
    cutoffTa=If(rd.IsDBNull(0),"",rd(0).ToString().Trim())
    studentNim=If(rd.IsDBNull(1),"",rd(1).ToString().Trim())
    Dim scope=If(rd.IsDBNull(2),"",rd(2).ToString().Trim())
    tables=If(rd.IsDBNull(3),"tbio01,treg,tkrs06,t_absensi14",rd(3).ToString().Trim())
    If scope.StartsWith("SINGLE:",StringComparison.OrdinalIgnoreCase) Then
     mode="SINGLE":cutoffTa=scope.Substring(7).Trim()
    ElseIf scope.StartsWith("RANGE:",StringComparison.OrdinalIgnoreCase) Then
     mode="RANGE"
     Dim parts=scope.Substring(6).Split("-"c)
     If parts.Length=2 Then startTa=parts(0).Trim():cutoffTa=parts(1).Trim()
    ElseIf scope.StartsWith("UP_TO:",StringComparison.OrdinalIgnoreCase) Then
     mode="UP_TO":cutoffTa=scope.Substring(6).Trim()
    End If
   End Using
  End Using

  If Not String.IsNullOrWhiteSpace(studentNim) Then
   Using cmd As New SqlCommand("dbo.sp_CreateBackupNimTransferJob",cnsr)
    cmd.CommandType=CommandType.StoredProcedure
    cmd.Parameters.Add("@StudentNim",SqlDbType.Char,9).Value=studentNim
    cmd.Parameters.Add("@RequestedBy",SqlDbType.VarChar,50).Value=BackupRequestedBy()
    cmd.Parameters.Add("@SelectedTables",SqlDbType.VarChar,100).Value=tables
    If cnsr.State=ConnectionState.Closed Then cnsr.Open()
    cmd.ExecuteNonQuery()
   End Using
  Else
   Using cmd As New SqlCommand("dbo.sp_CreateBackupTransferJob",cnsr)
    cmd.CommandType=CommandType.StoredProcedure
    cmd.Parameters.Add("@CutoffThAkdk",SqlDbType.Char,5).Value=cutoffTa
    cmd.Parameters.Add("@RequestedBy",SqlDbType.VarChar,50).Value=BackupRequestedBy()
    cmd.Parameters.Add("@TriggerSource",SqlDbType.VarChar,10).Value="MANUAL"
    cmd.Parameters.Add("@SelectionMode",SqlDbType.VarChar,10).Value=mode
    cmd.Parameters.Add("@StartThAkdk",SqlDbType.Char,5).Value=If(mode="RANGE",CObj(startTa),DBNull.Value)
    cmd.Parameters.Add("@SelectedTables",SqlDbType.VarChar,100).Value=tables
    If cnsr.State=ConnectionState.Closed Then cnsr.Open()
    cmd.ExecuteNonQuery()
   End Using
  End If
  ShowHistoryAlert("success","Sinkronisasi Ulang Didaftarkan","Job sinkronisasi ulang berhasil dibuat dan akan diproses otomatis oleh Database Backup.")
 Catch ex As Exception
  ShowHistoryAlert("error","Gagal Mendaftarkan Sinkronisasi",BackupErrorMessage(ex))
 Finally
  tutupsr()
 End Try
 LoadHistory()
End Sub

Private Sub ShowHistoryAlert(kind As String,title As String,msg As String)
 msg=BackupFriendlyText(msg)
 Dim alertType As String=If(kind="error","danger",kind)
 litHistoryMessage.Text="<div class='alert alert-" & alertType & "'><strong>" & Server.HtmlEncode(title) & "</strong> " & Server.HtmlEncode(msg) & "</div>"
 Dim safeTitle As String=HttpUtility.JavaScriptStringEncode(title,True)
 Dim safeMessage As String=HttpUtility.JavaScriptStringEncode(msg,True)
 Dim swalIcon As String=If(kind="error","error",kind)
 Dim confirmColor As String=If(kind="success","#00a65a","#dd4b39")
 Dim script As String="if (typeof Swal !== 'undefined') { Swal.fire({title: " & safeTitle & ", text: " & safeMessage & ", icon: '" & swalIcon & "', confirmButtonText: 'OK', confirmButtonColor: '" & confirmColor & "', width: '480px'}); }"
 ScriptManager.RegisterStartupScript(Me,Me.GetType(),"HistoryAlert_" & Guid.NewGuid().ToString("N"),script,True)
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
Private Function TransferStatusText(value As String) As String
 Select Case value
  Case "WAITING":Return "Menunggu Database Backup"
  Case "CLAIMED","TRANSFERRING":Return "Diproses"
  Case "SUCCESS":Return "Berhasil"
  Case "FAILED":Return "Gagal"
  Case Else:Return value
 End Select
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
   <asp:GridView ID="gvProcessHistory" runat="server" AutoGenerateColumns="false" AllowPaging="false" CssClass="table table-striped table-hover history-table" EmptyDataText="Belum ada riwayat proses selesai." GridLines="None" OnRowCommand="gvProcessHistory_RowCommand">
    <Columns>
     <asp:BoundField DataField="CreatedAt" HeaderText="Dibuat" DataFormatString="{0:dd MMM yyyy HH:mm}" ItemStyle-Width="115px" HeaderStyle-Width="115px" />
     <asp:BoundField DataField="OperationLabel" HeaderText="Operasi" ItemStyle-Width="250px" HeaderStyle-Width="250px" />
     <asp:BoundField DataField="TableLabel" HeaderText="Tabel" ItemStyle-Width="190px" HeaderStyle-Width="190px" />
     <asp:BoundField DataField="StatusLabel" HeaderText="Status" ItemStyle-CssClass="history-status" ItemStyle-Width="95px" HeaderStyle-Width="95px" />
     <asp:BoundField DataField="ProgressLabel" HeaderText="Diproses" ItemStyle-HorizontalAlign="Right" ItemStyle-Width="90px" HeaderStyle-Width="90px" />
     <asp:TemplateField HeaderText="Verifikasi" ItemStyle-Width="140px" HeaderStyle-Width="140px">
      <ItemTemplate>
       <%# Eval("VerificationBadgeHtml") %>
       <asp:LinkButton ID="btnResync" runat="server" CssClass="btn btn-xs btn-danger" CommandName="ResyncJob" CommandArgument='<%# Eval("JobId") %>' Visible='<%# Eval("CanResync") %>' ToolTip="Sinkronkan ulang data untuk cakupan ini" OnClientClick="return backupConfirm(this, 'Jalankan sinkronisasi ulang untuk cakupan data ini sekarang? Hanya data tahun/cakupan ini yang akan disinkronkan kembali.', {title: 'Konfirmasi Sinkronisasi Ulang', confirmText: 'Ya, Sinkronkan'});"><i class="fa fa-refresh"></i> Sinkronkan</asp:LinkButton>
      </ItemTemplate>
     </asp:TemplateField>
     <asp:BoundField DataField="CompletedAt" HeaderText="Selesai" DataFormatString="{0:dd MMM yyyy HH:mm}" NullDisplayText="-" ItemStyle-Width="115px" HeaderStyle-Width="115px" />
     <asp:BoundField DataField="DetailLabel" HeaderText="Keterangan" NullDisplayText="-" ItemStyle-CssClass="history-note" />
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
