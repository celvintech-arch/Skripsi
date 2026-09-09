<%@ Control Language="VB" ClassName="backup_data_riwayat_control" %>
<!-- #INCLUDE file="con_backup.ascx" -->

<script runat="server">
Protected Sub Page_Load(sender As Object,e As EventArgs)
 RequireBackupStaff()
 Response.Cache.SetCacheability(HttpCacheability.NoCache)
 Response.Cache.SetNoStore()
 Response.Cache.SetExpires(DateTime.UtcNow.AddYears(-1))
 If Not IsPostBack Then LoadHistory()
End Sub

Private Sub LoadHistory()
 Dim data As New DataTable()
 litHistoryRefresh.Text=""
 Try
   Dim historySql="SELECT j.JobId,j.OperationType,j.TriggerSource,j.CutoffThAkdk,j.StudentNim,j.RestoreThAkdkList,j.SelectedTables,j.Status,j.ProcessedStudents,j.CreatedAt,j.CompletedAt,j.ProgressMessage,j.ResultMessage,j.ErrorMessage,j.TotalStudents,(SELECT COUNT(*) FROM dbo.BackupTransferJobStudent s WHERE s.JobId=j.JobId) TrackedStudents FROM dbo.BackupTransferJob j ORDER BY j.CreatedAt DESC"
  Using cmd As New SqlCommand(historySql,cnsr)
   Using ad As New SqlDataAdapter(cmd):ad.Fill(data):End Using
  End Using
  Dim inventoryByYear=LoadInventoryPeriodsByYear()
  data.Columns.Add("OperationLabel",GetType(String))
  data.Columns.Add("StatusLabel",GetType(String))
  data.Columns.Add("ProgressLabel",GetType(String))
  data.Columns.Add("TableLabel",GetType(String))
  data.Columns.Add("DetailLabel",GetType(String))
  For Each row As DataRow In data.Rows
   Dim operation=row("OperationType").ToString().Trim().ToUpperInvariant()
   Dim status=row("Status").ToString().Trim().ToUpperInvariant()
   row("OperationLabel")=GetOperationTargetLabel(row,operation,inventoryByYear)
   row("TableLabel")=GetTableLabel(row("SelectedTables").ToString())
   Dim progress=If(row.IsNull("ProgressMessage"),"",row("ProgressMessage").ToString()),result=If(row.IsNull("ResultMessage"),"",row("ResultMessage").ToString()),failure=If(row.IsNull("ErrorMessage"),"",row("ErrorMessage").ToString())
   Dim detail=If(status="SUCCESS",result,If(status="FAILED",failure,progress))
   row("StatusLabel")=If(status="FAILED" AndAlso failure.StartsWith("[CANCELLED]",StringComparison.OrdinalIgnoreCase),"Dibatalkan",TransferStatusText(status))
   Dim processed=Convert.ToInt32(row("ProcessedStudents")),tracked=Convert.ToInt32(row("TrackedStudents")),storedTotal=If(row.IsNull("TotalStudents"),-1,Convert.ToInt32(row("TotalStudents"))),total=GetProgressTotal(storedTotal,tracked,operation,status,processed)
   row("ProgressLabel")=String.Format("{0:N0}",processed) & "/" & If(total>=0,String.Format("{0:N0}",total),"-")
   row("DetailLabel")=CleanProgressDetail(detail,operation,status,processed)
  Next
  Dim activeData=data.Clone(),completedData=data.Clone()
  For Each row As DataRow In data.Rows
   If IsActiveTransferStatus(row("Status").ToString()) Then activeData.ImportRow(row) Else completedData.ImportRow(row)
  Next
  gvActiveProcesses.DataSource=activeData:gvActiveProcesses.DataBind()
  gvProcessHistory.DataSource=completedData:gvProcessHistory.DataBind()
  If activeData.Rows.Count>0 Then litHistoryRefresh.Text="<script>(function(){window.backupHistoryAction=function(button,message){if(button.getAttribute('data-backup-confirmed')==='1'){button.removeAttribute('data-backup-confirmed');if(window.backupHistoryPollTimer)window.clearTimeout(window.backupHistoryPollTimer);button.setAttribute('data-submitting','1');button.classList.add('backup-action-submitting');return true;}if(button.getAttribute('data-submitting')==='1')return false;return window.backupConfirm(button,message,{title:'Batalkan proses?',confirmText:'Ya, batalkan'});};window.backupHistoryPollTimer=window.setTimeout(function(){window.location.replace('index.aspx?tab=riwayat&poll=' + Date.now());},10000);})();</" & "script>"
 Catch ex As Exception
  litHistoryMessage.Text="<div class='alert alert-danger'><strong>Gagal memuat riwayat.</strong> " & Server.HtmlEncode(ex.Message) & "</div>"
 Finally
  tutupsr()
 End Try
End Sub

Private Function GetTableLabel(value As String) As String
 Dim labels As New System.Collections.Generic.List(Of String)()
 For Each name In value.Split(","c)
  Select Case name.Trim().ToLowerInvariant()
   Case "tbio01":labels.Add("Biodata")
   Case "treg":labels.Add("Registrasi")
   Case "tkrs06":labels.Add("KRS")
   Case "t_absensi14":labels.Add("Absensi")
  End Select
 Next
 Return If(labels.Count=0,"-",String.Join(", ",labels.ToArray()))
End Function

Private Function LoadInventoryPeriodsByYear() As System.Collections.Generic.Dictionary(Of String,System.Collections.Generic.HashSet(Of String))
 Dim result As New System.Collections.Generic.Dictionary(Of String,System.Collections.Generic.HashSet(Of String))(StringComparer.OrdinalIgnoreCase)
 Using cmd As New SqlCommand("SELECT DISTINCT RTRIM(p.ThAkdk) ThAkdk FROM dbo.BackupAgentPeriodInventory p JOIN dbo.BackupAgentNode a ON a.AgentName=p.AgentName WHERE a.IsPrimary=1 AND a.IsEnabled=1",cnsr)
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
 Dim cleaned=System.Text.RegularExpressions.Regex.Replace(detail,"^\[TOTAL:\d+\]\s*","")
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
 If operation="BACKUP" AndAlso (cleaned.StartsWith("Menyalin batch backup",StringComparison.OrdinalIgnoreCase) OrElse cleaned.StartsWith("Mengonfirmasi batch backup",StringComparison.OrdinalIgnoreCase) OrElse cleaned.StartsWith("Proses Backup",StringComparison.OrdinalIgnoreCase) OrElse cleaned.StartsWith("Proses Backup",StringComparison.OrdinalIgnoreCase)) Then
  Return "Proses Backup"
 End If
 If operation="RESTORE" AndAlso (cleaned.StartsWith("Menyiapkan pemulihan",StringComparison.OrdinalIgnoreCase) OrElse cleaned.StartsWith("Mengirim batch pemulihan",StringComparison.OrdinalIgnoreCase) OrElse cleaned.StartsWith("Menyelesaikan pemulihan",StringComparison.OrdinalIgnoreCase) OrElse cleaned.StartsWith("Proses Pemulihan",StringComparison.OrdinalIgnoreCase)) Then
  Return "Proses Pemulihan"
 End If
 Return If(String.IsNullOrWhiteSpace(cleaned),"-",cleaned)
End Function


Protected Function CanCancel(value As Object,operationValue As Object) As Boolean
 Dim status=If(value Is Nothing,"",value.ToString().Trim().ToUpperInvariant())
 Dim operation=If(operationValue Is Nothing,"",operationValue.ToString().Trim().ToUpperInvariant())
 If operation="EXPORT" Then Return status="WAITING"
 Return status="WAITING" OrElse status="CLAIMED" OrElse status="TRANSFERRING"
End Function

Private Function IsActiveTransferStatus(value As String) As Boolean
 Dim status=If(value Is Nothing,"",value.Trim().ToUpperInvariant())
 Return status="WAITING" OrElse status="CLAIMED" OrElse status="TRANSFERRING"
End Function

Protected Sub gvProcessHistory_PageIndexChanging(sender As Object,e As GridViewPageEventArgs)
 gvProcessHistory.PageIndex=e.NewPageIndex
 LoadHistory()
End Sub

Protected Sub gvActiveProcesses_RowCommand(sender As Object,e As GridViewCommandEventArgs)
 If e.CommandName<>"CancelJob" Then Return
 Dim jobId As Guid
 If Not Guid.TryParse(Convert.ToString(e.CommandArgument),jobId) Then Return
 Try
  Using cn As New SqlConnection(connstringLive),cmd As New SqlCommand("UPDATE dbo.BackupTransferJob SET Status='FAILED',CompletedAt=SYSDATETIME(),LeaseExpiresAt=NULL,ProgressMessage=NULL,ResultMessage=NULL,ErrorMessage=@message WHERE JobId=@job AND Status IN('WAITING','CLAIMED','TRANSFERRING') AND (OperationType<>'EXPORT' OR Status='WAITING')",cn)
   cmd.Parameters.Add("@job",SqlDbType.UniqueIdentifier).Value=jobId
   cmd.Parameters.Add("@message",SqlDbType.NVarChar,2000).Value="[CANCELLED] Dibatalkan oleh " & BackupRequestedBy() & "."
   cn.Open()
   If cmd.ExecuteNonQuery()=1 Then litHistoryMessage.Text="<div class='alert alert-success'><strong>Proses dibatalkan.</strong> Tahap yang belum dijalankan dihentikan; perubahan yang sudah tersimpan tidak dibatalkan.</div>" Else litHistoryMessage.Text="<div class='alert alert-warning'>Proses sudah selesai atau sebelumnya telah dibatalkan.</div>"
  End Using
 Catch ex As Exception
  litHistoryMessage.Text="<div class='alert alert-danger'><strong>Pembatalan gagal.</strong> " & Server.HtmlEncode(ex.Message) & "</div>"
 End Try
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
 <div class="panel history-card">
  <div class="panel-heading"><i class="fa fa-spinner fa-spin"></i> Proses Sedang Berjalan</div>
  <div class="table-responsive">
   <asp:GridView ID="gvActiveProcesses" runat="server" AutoGenerateColumns="false" CssClass="table table-striped table-hover history-table" EmptyDataText="Tidak ada proses yang sedang berjalan." GridLines="None" OnRowCommand="gvActiveProcesses_RowCommand">
    <Columns>
     <asp:BoundField DataField="CreatedAt" HeaderText="Dibuat" DataFormatString="{0:dd MMM yyyy HH:mm}" ItemStyle-Width="115px" HeaderStyle-Width="115px" />
     <asp:BoundField DataField="OperationLabel" HeaderText="Operasi" ItemStyle-Width="270px" HeaderStyle-Width="270px" />
     <asp:BoundField DataField="TableLabel" HeaderText="Tabel" ItemStyle-Width="210px" HeaderStyle-Width="210px" />
     <asp:BoundField DataField="StatusLabel" HeaderText="Status" ItemStyle-CssClass="history-status" ItemStyle-Width="105px" HeaderStyle-Width="105px" />
     <asp:BoundField DataField="ProgressLabel" HeaderText="Diproses" ItemStyle-HorizontalAlign="Right" ItemStyle-Width="95px" HeaderStyle-Width="95px" />
     <asp:BoundField DataField="DetailLabel" HeaderText="Keterangan" NullDisplayText="-" ItemStyle-CssClass="history-note" />
     <asp:TemplateField HeaderText="Aksi" ItemStyle-Width="115px" HeaderStyle-Width="115px" ItemStyle-CssClass="history-action-cell" ItemStyle-HorizontalAlign="Center" HeaderStyle-HorizontalAlign="Center">
      <ItemTemplate>
       <div class="history-actions">
       <asp:LinkButton ID="btnCancelJob" runat="server" Text="Batalkan" CssClass="btn btn-warning btn-xs history-text-btn" CommandName="CancelJob" CommandArgument='<%# Eval("JobId") %>' Visible='<%# CanCancel(Eval("Status"),Eval("OperationType")) %>' OnClientClick="return backupHistoryAction(this,'Batalkan proses ini? Perubahan yang sudah tersimpan tidak dapat dibatalkan.');" />
       </div>
      </ItemTemplate>
     </asp:TemplateField>
    </Columns>
   </asp:GridView>
  </div>
 </div>
 <div class="panel history-card">
  <div class="panel-heading"><i class="fa fa-history"></i> Riwayat Proses Selesai</div>
  <div class="table-responsive">
   <asp:GridView ID="gvProcessHistory" runat="server" AutoGenerateColumns="false" AllowPaging="true" PageSize="10" PagerSettings-Mode="NumericFirstLast" PagerSettings-FirstPageText="Awal" PagerSettings-LastPageText="Akhir" PagerStyle-CssClass="customPager" PagerStyle-HorizontalAlign="Center" CssClass="table table-striped table-hover history-table" EmptyDataText="Belum ada riwayat proses selesai." GridLines="None" OnPageIndexChanging="gvProcessHistory_PageIndexChanging">
    <Columns>
     <asp:BoundField DataField="CreatedAt" HeaderText="Dibuat" DataFormatString="{0:dd MMM yyyy HH:mm}" ItemStyle-Width="115px" HeaderStyle-Width="115px" />
     <asp:BoundField DataField="OperationLabel" HeaderText="Operasi" ItemStyle-Width="270px" HeaderStyle-Width="270px" />
     <asp:BoundField DataField="TableLabel" HeaderText="Tabel" ItemStyle-Width="210px" HeaderStyle-Width="210px" />
     <asp:BoundField DataField="StatusLabel" HeaderText="Status" ItemStyle-CssClass="history-status" ItemStyle-Width="105px" HeaderStyle-Width="105px" />
     <asp:BoundField DataField="ProgressLabel" HeaderText="Diproses" ItemStyle-HorizontalAlign="Right" ItemStyle-Width="95px" HeaderStyle-Width="95px" />
     <asp:BoundField DataField="CompletedAt" HeaderText="Selesai" DataFormatString="{0:dd MMM yyyy HH:mm}" NullDisplayText="-" ItemStyle-Width="115px" HeaderStyle-Width="115px" />
     <asp:BoundField DataField="DetailLabel" HeaderText="Keterangan" NullDisplayText="-" ItemStyle-CssClass="history-note" />
    </Columns>
   </asp:GridView>
  </div>
 </div>
 <asp:Literal ID="litHistoryRefresh" runat="server" />
</div>
