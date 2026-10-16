<%@ Control Language="VB" ClassName="backup_data_ekspor_control" %>
<!-- #INCLUDE file="con_backup.ascx" -->

<script runat="server">
Protected Sub Page_Load(sender As Object,e As EventArgs)
 RequireBackupStaff()
 Response.Cache.SetCacheability(HttpCacheability.NoCache):Response.Cache.SetNoStore()
 If Not IsPostBack Then LoadExports()
 btnCreateExport.Enabled=False
 Try
  btnCreateExport.Enabled=ReadBackupServiceState().IsReady
 Catch ex As Exception
  System.Diagnostics.Trace.TraceError("Backup Data export service status: {0}",ex)
 End Try
End Sub

Protected Sub btnCreateExport_Click(sender As Object,e As EventArgs)
 Try
  EnsureBackupServiceReady(ReadBackupServiceState(),"Ekspor database")
  Using cmd As New SqlCommand("dbo.sp_CreateBackupExportJob",cnsr)
   cmd.CommandType=CommandType.StoredProcedure
   cmd.Parameters.Add("@RequestedBy",SqlDbType.VarChar,50).Value=BackupRequestedBy()
   cnsr.Open()
   Dim jobId=Convert.ToString(cmd.ExecuteScalar())
   ShowAlert("success","Permintaan ekspor dibuat","Proses " & jobId & " menunggu layanan Database Backup.")
  End Using
 Catch ex As Exception
  ShowAlert("danger","Ekspor gagal dibuat",BackupErrorMessage(ex))
 Finally:tutupsr():End Try
 LoadExports()
End Sub

Private Sub LoadExports()
 Dim data As New DataTable()
 litLastExportStatus.Text="Belum ada ekspor":litLastExportFile.Text="-":litLastExportSize.Text="-":litLastExportVerification.Text="-":litLastExportCompleted.Text="-"
 Try
  Using cmd As New SqlCommand("SELECT TOP(20) JobId,Status,CreatedAt,CompletedAt,ProgressMessage,ResultMessage,ErrorMessage FROM dbo.BackupTransferJob WHERE OperationType='EXPORT' ORDER BY CreatedAt DESC",cnsr)
   Using ad As New SqlDataAdapter(cmd):ad.Fill(data):End Using
  End Using
  If data.Rows.Count>0 Then
   Dim latest=data.Rows(0)
   Dim status=latest("Status").ToString().Trim().ToUpperInvariant(),messageColumn=If(status="SUCCESS","ResultMessage",If(status="FAILED","ErrorMessage","ProgressMessage"))
   Dim detail=If(latest.IsNull(messageColumn),"",latest(messageColumn).ToString())
   litLastExportStatus.Text=Server.HtmlEncode(StatusText(status))
   litLastExportFile.Text=Server.HtmlEncode(MetadataValue(detail,"File lokal:\s*(?<value>[^|]+)"))
   litLastExportSize.Text=Server.HtmlEncode(MetadataValue(detail,"Ukuran:\s*(?<value>[^|]+)"))
   litLastExportVerification.Text=Server.HtmlEncode(If(detail.IndexOf("RESTORE VERIFYONLY berhasil",StringComparison.OrdinalIgnoreCase)>=0,"Terverifikasi",If(status="SUCCESS","Belum tersedia",StatusText(status))))
   litLastExportCompleted.Text=If(latest.IsNull("CompletedAt"),"Belum selesai",Convert.ToDateTime(latest("CompletedAt")).ToString("dd MMM yyyy HH:mm"))
  End If
  If data.Select("Status='WAITING' OR Status='CLAIMED' OR Status='TRANSFERRING'").Length>0 Then litExportRefresh.Text="<script>window.setTimeout(function(){window.location.replace('index.aspx?tab=ekspor&poll='+Date.now());},10000);</" & "script>"
 Catch ex As Exception
  ShowAlert("danger","Gagal memuat riwayat ekspor",BackupErrorMessage(ex))
 Finally:tutupsr():End Try
End Sub

Private Function MetadataValue(message As String,pattern As String) As String
 If String.IsNullOrWhiteSpace(message) Then Return "-"
 Dim match=System.Text.RegularExpressions.Regex.Match(message,pattern,System.Text.RegularExpressions.RegexOptions.IgnoreCase)
 Return If(match.Success,match.Groups("value").Value.Trim(),"-")
End Function

Private Function StatusText(value As String) As String
 Select Case value.Trim().ToUpperInvariant()
  Case "WAITING":Return "Menunggu Database Backup"
  Case "CLAIMED","TRANSFERRING":Return "Diproses"
  Case "SUCCESS":Return "Berhasil"
  Case "FAILED":Return "Gagal"
  Case Else:Return value
 End Select
End Function

Private Sub ShowAlert(css As String,title As String,message As String)
 litExportAlert.Text="<div class='alert alert-" & css & "'><strong>" & Server.HtmlEncode(title) & "</strong><br />" & Server.HtmlEncode(message) & "</div>"
End Sub
</script>

<div class="backup-page backup-page-operation">
 <div class="backup-page-header">
  <span class="backup-page-eyebrow">Operasional</span>
  <h1>Ekspor Database</h1>
 </div>
 <asp:Literal ID="litExportAlert" runat="server" />
 <div class="panel panel-default export-action-panel">
  <div class="panel-heading backup-u-042"><i class="fa fa-database"></i> File Database Backup Terakhir</div>
  <div class="panel-body">
   <div class="export-latest-card">
    <div><span>Status</span><strong><asp:Literal ID="litLastExportStatus" runat="server" /></strong></div>
    <div><span>Nama file</span><strong><asp:Literal ID="litLastExportFile" runat="server" /></strong></div>
    <div><span>Ukuran</span><strong><asp:Literal ID="litLastExportSize" runat="server" /></strong></div>
    <div><span>Verifikasi</span><strong><asp:Literal ID="litLastExportVerification" runat="server" /></strong></div>
    <div><span>Selesai</span><strong><asp:Literal ID="litLastExportCompleted" runat="server" /></strong></div>
   </div>
   <div class="export-action-buttons">
    <asp:Button ID="btnCreateExport" runat="server" Text="Buat File .BAK" CssClass="btn btn-primary" OnClick="btnCreateExport_Click" OnClientClick="return backupConfirm(this,'Buat file .bak dari Database Backup sekarang?',{title:'Konfirmasi ekspor database',confirmText:'Ya, buat file .BAK',confirmColor:'#A01626'});" />
    <a class="btn btn-default" href="index.aspx?tab=riwayat&amp;operation=EXPORT"><i class="fa fa-history"></i> Lihat Riwayat Ekspor</a>
   </div>
  </div>
 </div>
 <asp:Literal ID="litExportRefresh" runat="server" />
</div>
