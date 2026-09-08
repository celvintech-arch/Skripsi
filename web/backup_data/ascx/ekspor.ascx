<%@ Control Language="VB" ClassName="backup_data_ekspor_control" %>
<!-- #INCLUDE file="con_backup.ascx" -->

<script runat="server">
Protected Sub Page_Load(sender As Object,e As EventArgs)
 RequireBackupStaff()
 Response.Cache.SetCacheability(HttpCacheability.NoCache):Response.Cache.SetNoStore()
 If Not IsPostBack Then LoadExports()
End Sub

Protected Sub btnCreateExport_Click(sender As Object,e As EventArgs)
 Try
  Using cmd As New SqlCommand("dbo.sp_CreateBackupExportJob",cnsr)
   cmd.CommandType=CommandType.StoredProcedure
   cmd.Parameters.Add("@RequestedBy",SqlDbType.VarChar,50).Value=BackupRequestedBy()
   cnsr.Open()
   Dim jobId=Convert.ToString(cmd.ExecuteScalar())
   ShowAlert("success","Permintaan ekspor dibuat","Proses " & jobId & " menunggu layanan Database Backup.")
  End Using
 Catch ex As Exception
  ShowAlert("danger","Ekspor gagal dibuat",ex.Message)
 Finally:tutupsr():End Try
 LoadExports()
End Sub

Private Sub LoadExports()
 Dim data As New DataTable()
 Try
  Using cmd As New SqlCommand("SELECT TOP(20) JobId,Status,CreatedAt,CompletedAt,ProgressMessage,ResultMessage,ErrorMessage FROM dbo.BackupTransferJob WHERE OperationType='EXPORT' ORDER BY CreatedAt DESC",cnsr)
   Using ad As New SqlDataAdapter(cmd):ad.Fill(data):End Using
  End Using
  data.Columns.Add("StatusLabel",GetType(String)):data.Columns.Add("DetailLabel",GetType(String))
  For Each row As DataRow In data.Rows
   row("StatusLabel")=StatusText(row("Status").ToString())
   Dim status=row("Status").ToString().Trim().ToUpperInvariant(),messageColumn=If(status="SUCCESS","ResultMessage",If(status="FAILED","ErrorMessage","ProgressMessage"))
   row("DetailLabel")=If(row.IsNull(messageColumn) OrElse String.IsNullOrWhiteSpace(row(messageColumn).ToString()),"-",row(messageColumn).ToString())
  Next
  gvExports.DataSource=data:gvExports.DataBind()
  If data.Select("Status='WAITING' OR Status='CLAIMED' OR Status='TRANSFERRING'").Length>0 Then litExportRefresh.Text="<script>window.setTimeout(function(){window.location.replace('index.aspx?tab=ekspor&poll='+Date.now());},10000);</" & "script>"
 Catch ex As Exception
  ShowAlert("danger","Gagal memuat riwayat ekspor",ex.Message)
 Finally:tutupsr():End Try
End Sub

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
 <div class="panel panel-default backup-u-014">
  <div class="panel-heading backup-u-042"><i class="fa fa-database"></i> Buat File Database</div>
  <div class="panel-body">
   <p>Ekspor membuat file <strong>.bak</strong> pada folder lokal server Database Backup. File diperiksa menggunakan checksum, RESTORE VERIFYONLY, dan SHA-256.</p>
   <asp:Button ID="btnCreateExport" runat="server" Text="Buat Backup .BAK" CssClass="btn btn-success" OnClick="btnCreateExport_Click" OnClientClick="return backupConfirm(this,'Buat file .bak dari Database Backup sekarang?',{title:'Konfirmasi ekspor database',confirmText:'Ya, buat file .BAK',confirmColor:'#15803d'});" />
  </div>
 </div>
 <div class="panel panel-default backup-u-013">
  <div class="panel-heading backup-u-042"><i class="fa fa-history"></i> Riwayat Ekspor</div>
  <div class="table-responsive">
   <asp:GridView ID="gvExports" runat="server" AutoGenerateColumns="false" CssClass="table table-bordered table-hover backup-u-058" GridLines="None" EmptyDataText="Belum ada ekspor database.">
    <Columns>
     <asp:BoundField DataField="CreatedAt" HeaderText="Dibuat" DataFormatString="{0:dd MMM yyyy HH:mm}" />
     <asp:BoundField DataField="StatusLabel" HeaderText="Status" />
     <asp:BoundField DataField="CompletedAt" HeaderText="Selesai" DataFormatString="{0:dd MMM yyyy HH:mm}" NullDisplayText="-" />
     <asp:BoundField DataField="DetailLabel" HeaderText="File dan Verifikasi" />
    </Columns>
   </asp:GridView>
  </div>
 </div>
 <asp:Literal ID="litExportRefresh" runat="server" />
</div>
