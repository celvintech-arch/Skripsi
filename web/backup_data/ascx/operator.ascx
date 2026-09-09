<%@ Control Language="VB" ClassName="backup_data_operator_control" %>
<!-- #INCLUDE file="con_backup.ascx" -->

<script runat="server">
Protected Sub Page_Load(sender As Object,e As EventArgs)
 RequireBackupStaff()
 If Not IsPostBack Then LoadOperators()
End Sub

Private Function CurrentOperatorId() As String
 Return BackupRequestedBy().Trim()
End Function

Private Function ValidUserId(value As String) As Boolean
 Return value.Length>=3 AndAlso value.Length<=50 AndAlso System.Text.RegularExpressions.Regex.IsMatch(value,"^[0-9A-Za-z._-]+$")
End Function

Private Function ValidRole(value As String) As Boolean
 Return value="STAFF_BACKUP" OrElse value="MANAGER_BACKUP"
End Function

Private Sub LoadOperators()
 Dim data As New DataTable()
 Try
  Using cmd As New SqlCommand("SELECT UserId,AccessRole,IsEnabled,CreatedAt,UpdatedAt FROM dbo.BackupOperatorAccess ORDER BY IsEnabled DESC,UserId",cnsr)
   Using ad As New SqlDataAdapter(cmd):ad.Fill(data):End Using
  End Using
  gvOperators.DataSource=data:gvOperators.DataBind()
  lblOperatorCount.Text=data.Rows.Count.ToString("N0") & " pengguna terdaftar"
 Catch ex As Exception
  ShowOperatorAlert("danger","Gagal memuat operator",ex.Message)
 Finally:tutupsr():End Try
End Sub

Protected Sub btnAddOperator_Click(sender As Object,e As EventArgs)
 Try
  Dim userId=txtOperatorId.Text.Trim()
  If Not ValidUserId(userId) Then Throw New ApplicationException("ID Lintar harus 3-50 karakter dan hanya boleh berisi huruf, angka, titik, garis bawah, atau tanda minus.")
  Dim accessRole=ddlOperatorRole.SelectedValue.Trim().ToUpperInvariant()
  If Not ValidRole(accessRole) Then Throw New ApplicationException("Peran pengguna tidak valid.")
  SetOperatorAccess(userId,accessRole,True)
  txtOperatorId.Text=""
  ShowOperatorAlert("success","Pengguna tersimpan","ID " & userId & " terdaftar sebagai " & RoleText(accessRole) & ".")
 Catch ex As Exception
  ShowOperatorAlert("danger","Gagal menyimpan operator",ex.Message)
 Finally:tutupsr():End Try
 LoadOperators()
End Sub

Protected Sub gvOperators_RowCommand(sender As Object,e As GridViewCommandEventArgs)
 If e.CommandName<>"ToggleOperator" AndAlso e.CommandName<>"SetOperatorRole" Then Return
 Try
  Dim parts=e.CommandArgument.ToString().Split("|"c)
  If parts.Length<3 Then Throw New ApplicationException("Parameter perubahan pengguna tidak lengkap.")
  Dim userId=parts(0).Trim(),accessRole=parts(1).Trim().ToUpperInvariant(),enable=(parts(2)="1")
  If Not ValidUserId(userId) OrElse Not ValidRole(accessRole) Then Throw New ApplicationException("Parameter pengguna tidak valid.")
  If e.CommandName="ToggleOperator" Then
   If Not enable AndAlso String.Equals(userId,CurrentOperatorId(),StringComparison.OrdinalIgnoreCase) Then Throw New ApplicationException("Akun yang sedang digunakan tidak dapat dinonaktifkan sendiri.")
   SetOperatorAccess(userId,accessRole,enable)
   ShowOperatorAlert("success","Akses diperbarui","Pengguna " & userId & If(enable," sudah diaktifkan."," sudah dinonaktifkan."))
  Else
   If accessRole="MANAGER_BACKUP" AndAlso String.Equals(userId,CurrentOperatorId(),StringComparison.OrdinalIgnoreCase) Then Throw New ApplicationException("Staf yang sedang login tidak dapat mengubah dirinya sendiri menjadi Manager.")
   SetOperatorAccess(userId,accessRole,enable)
   ShowOperatorAlert("success","Peran diperbarui","Pengguna " & userId & " sekarang menjadi " & RoleText(accessRole) & ".")
  End If
 Catch ex As Exception
  ShowOperatorAlert("danger","Gagal memperbarui operator",ex.Message)
 Finally:tutupsr():End Try
 LoadOperators()
End Sub

Private Sub SetOperatorAccess(userId As String,accessRole As String,isEnabled As Boolean)
 Using cmd As New SqlCommand("dbo.sp_SetBackupOperatorAccess",cnsr)
  cmd.CommandType=CommandType.StoredProcedure
  cmd.Parameters.Add("@UserId",SqlDbType.NVarChar,50).Value=userId
  cmd.Parameters.Add("@AccessRole",SqlDbType.VarChar,30).Value=accessRole
  cmd.Parameters.Add("@IsEnabled",SqlDbType.Bit).Value=isEnabled
  cnsr.Open():cmd.ExecuteNonQuery()
 End Using
End Sub

Private Sub ShowOperatorAlert(css As String,title As String,message As String)
 litOperatorAlert.Text="<div class='alert alert-" & css & "'><strong>" & Server.HtmlEncode(title) & "</strong><br />" & Server.HtmlEncode(message) & "</div>"
End Sub

Protected Function StatusText(value As Object) As String
 Return If(Convert.ToBoolean(value),"Aktif","Nonaktif")
End Function

Protected Function StatusClass(value As Object) As String
 Return If(Convert.ToBoolean(value),"label label-success","label label-default")
End Function

Protected Function NormalizedRole(value As Object) As String
 Dim roleValue=If(value Is Nothing,"",value.ToString().Trim().ToUpperInvariant())
 Return If(roleValue="MANAGER_BACKUP","MANAGER_BACKUP","STAFF_BACKUP")
End Function

Protected Function RoleText(value As Object) As String
 Return If(NormalizedRole(value)="MANAGER_BACKUP","Manager","Staf")
End Function
</script>

<div class="backup-page backup-page-administration">
 <div class="backup-page-header">
  <span class="backup-page-eyebrow">Administrasi</span>
  <h1>Kelola Pengguna</h1>
 </div>
 <asp:Literal ID="litOperatorAlert" runat="server" />
 <div class="panel panel-default backup-u-014">
  <div class="panel-heading backup-u-042"><i class="fa fa-user-plus"></i> Daftarkan Pengguna</div>
  <div class="panel-body">
   <div class="row">
    <div class="col-md-5 col-sm-6"><label for="<%= txtOperatorId.ClientID %>">ID Lintar pengguna</label><asp:TextBox ID="txtOperatorId" runat="server" CssClass="form-control" MaxLength="50" placeholder="Contoh: 20014001" /></div>
    <div class="col-md-3 col-sm-3"><label for="<%= ddlOperatorRole.ClientID %>">Peran</label><asp:DropDownList ID="ddlOperatorRole" runat="server" CssClass="form-control"><asp:ListItem Value="STAFF_BACKUP">Staf</asp:ListItem><asp:ListItem Value="MANAGER_BACKUP">Manager</asp:ListItem></asp:DropDownList></div>
    <div class="col-md-3 col-sm-3 backup-u-075"><asp:Button ID="btnAddOperator" runat="server" Text="Daftarkan Pengguna" CssClass="btn btn-success btn-block" OnClick="btnAddOperator_Click" OnClientClick="return backupConfirm(this,'Daftarkan ID dan peran pengguna ini?',{title:'Konfirmasi pengguna',confirmText:'Ya, daftarkan',confirmColor:'#15803d'});" /></div>
   </div>
  </div>
 </div>
 <div class="panel panel-default backup-u-013">
  <div class="panel-heading backup-u-043"><span><i class="fa fa-list"></i> Daftar Pengguna</span><asp:Label ID="lblOperatorCount" runat="server" CssClass="text-muted" /></div>
  <div class="table-responsive">
   <asp:GridView ID="gvOperators" runat="server" AutoGenerateColumns="false" CssClass="table table-bordered table-hover backup-u-058 operator-table" GridLines="None" EmptyDataText="Belum ada operator terdaftar." OnRowCommand="gvOperators_RowCommand">
    <Columns>
     <asp:BoundField DataField="UserId" HeaderText="ID Lintar" />
     <asp:TemplateField HeaderText="Peran"><ItemTemplate><span class="label label-info"><%# RoleText(Eval("AccessRole")) %></span></ItemTemplate></asp:TemplateField>
     <asp:TemplateField HeaderText="Status" ItemStyle-HorizontalAlign="Center"><ItemTemplate><span class='<%# StatusClass(Eval("IsEnabled")) %>'><%# StatusText(Eval("IsEnabled")) %></span></ItemTemplate></asp:TemplateField>
     <asp:BoundField DataField="UpdatedAt" HeaderText="Terakhir Diubah" DataFormatString="{0:dd MMM yyyy HH:mm}" />
      <asp:TemplateField HeaderText="Aksi" ItemStyle-HorizontalAlign="Center"><ItemTemplate><div class="operator-actions"><asp:LinkButton ID="btnSetStaff" runat="server" CssClass="btn btn-default btn-sm operator-role-button" CommandName="SetOperatorRole" CommandArgument='<%# Eval("UserId").ToString() & "|STAFF_BACKUP|" & If(Convert.ToBoolean(Eval("IsEnabled")),"1","0") %>' ToolTip="Ubah menjadi Staf" OnClientClick="return backupConfirm(this,'Ubah peran pengguna menjadi Staf?',{title:'Konfirmasi perubahan peran'});"><i class="fa fa-user" aria-hidden="true"></i><span>Staf</span></asp:LinkButton><asp:LinkButton ID="btnSetManager" runat="server" CssClass="btn btn-default btn-sm operator-role-button" CommandName="SetOperatorRole" CommandArgument='<%# Eval("UserId").ToString() & "|MANAGER_BACKUP|" & If(Convert.ToBoolean(Eval("IsEnabled")),"1","0") %>' ToolTip="Ubah menjadi Manager" OnClientClick="return backupConfirm(this,'Ubah peran pengguna menjadi Manager?',{title:'Konfirmasi perubahan peran'});"><i class="fa fa-briefcase" aria-hidden="true"></i><span>Manager</span></asp:LinkButton><asp:LinkButton ID="btnToggleOperator" runat="server" CssClass='<%# If(Convert.ToBoolean(Eval("IsEnabled")),"btn btn-danger btn-sm operator-status-button","btn btn-success btn-sm operator-status-button") %>' CommandName="ToggleOperator" CommandArgument='<%# Eval("UserId").ToString() & "|" & NormalizedRole(Eval("AccessRole")) & "|" & If(Convert.ToBoolean(Eval("IsEnabled")),"0","1") %>' ToolTip='<%# If(Convert.ToBoolean(Eval("IsEnabled")),"Nonaktifkan pengguna","Aktifkan pengguna") %>' OnClientClick="return backupConfirm(this,'Ubah status akses pengguna ini?',{title:'Konfirmasi status akses'});"><i class='<%# If(Convert.ToBoolean(Eval("IsEnabled")),"fa fa-trash-o","fa fa-refresh") %>' aria-hidden="true"></i><span class="sr-only"><%# If(Convert.ToBoolean(Eval("IsEnabled")),"Nonaktifkan","Aktifkan") %></span></asp:LinkButton></div></ItemTemplate></asp:TemplateField>
    </Columns>
   </asp:GridView>
  </div>
 </div>
</div>
