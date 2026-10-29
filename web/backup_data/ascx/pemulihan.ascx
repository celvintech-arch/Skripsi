<%@ Control Language="VB" ClassName="backup_data_pemulihan_control" %>
<!-- #INCLUDE file="con_backup.ascx" -->
<!-- #INCLUDE file="table_helpers.ascx" -->
<%@ Import Namespace="System.Collections.Generic" %>

<script runat="server">
Protected CurrentRestoreSection As String="ta"
Protected LookupPending As Boolean=False
Protected BackupServiceReady As Boolean=False
Private CurrentBackupService As BackupServiceState

Protected ReadOnly Property CurrentLiveDbName As String
    Get
        Dim builder As New SqlConnectionStringBuilder(connstringLive)
        Return builder.InitialCatalog
    End Get
End Property

Protected ReadOnly Property CurrentBackupDbName As String
    Get
        Return CurrentLiveDbName & "_backup"
    End Get
End Property

Protected ReadOnly Property CurrentAgentName As String
    Get
        If CurrentBackupService IsNot Nothing AndAlso Not String.IsNullOrWhiteSpace(CurrentBackupService.AgentName) AndAlso CurrentBackupService.AgentName <> "-" Then
            Return CurrentBackupService.AgentName
        End If
        Return "Laptop Backup"
    End Get
End Property
Protected Sub Page_Load(sender As Object,e As EventArgs)
 RequireBackupStaff()
 LoadBackupConnectionStatus()
 Dim requested=If(Request.QueryString("section"),"").Trim().ToLowerInvariant()
 If requested="nim" Then CurrentRestoreSection="nim"
 If Not IsPostBack Then
  If CurrentRestoreSection="ta" Then
   PopulateRestorePeriods()
  Else
   PopulateStudentRestoreYears()
   If String.Equals(Request.QueryString("lookup"),"1",StringComparison.Ordinal) AndAlso Session("BackupStudentLookupId") IsNot Nothing Then
    LoadBackedUpStudents()
   Else
    Session.Remove("BackupStudentLookupId")
    ShowEmptyRestoreNimState()
   End If
  End If
 End If
End Sub
Private Sub LoadBackupConnectionStatus()
 litBackupConnectionStatus.Text=""
 Try
  CurrentBackupService=ReadBackupServiceState()
  BackupServiceReady=CurrentBackupService.IsReady
  litBackupConnectionStatus.Text=BackupServiceAlertHtml(CurrentBackupService,"Pemulihan data")
 Catch ex As Exception
  CurrentBackupService=New BackupServiceState()
  ShowBackupConnectionWarning("Status Database Backup tidak dapat diperiksa.",BackupErrorMessage(ex),"danger")
 Finally
  tutupsr()
 End Try
 btnRestorePeriods.Enabled=BackupServiceReady
 btnSearchBackupNim.Enabled=BackupServiceReady
End Sub

Private Sub ShowBackupConnectionWarning(title As String,message As String,kind As String)
 litBackupConnectionStatus.Text &= "<div class='alert alert-" & kind & " backup-connection-alert' role='alert'><div class='backup-connection-alert-icon' aria-hidden='true'><svg viewBox='0 0 24 24' focusable='false'><path d='M12 3.25L22 20.5H2L12 3.25Z' fill='currentColor'/><path d='M12 8.2V14.1' stroke='white' stroke-width='2.2' stroke-linecap='round'/><circle cx='12' cy='17.25' r='1.2' fill='white'/></svg></div><div><strong>" & Server.HtmlEncode(title) & "</strong><div>" & Server.HtmlEncode(message) & "</div></div></div>"
End Sub


Private Sub PopulateStudentRestoreYears()
 ddlStudentRestoreYear.Items.Clear():ddlStudentRestoreYear.Items.Add(New ListItem("- Pilih Tahun Akademik -",""))
 Using cmd As New SqlCommand("SELECT DISTINCT LEFT(RTRIM(p.ThAkdk),4) Tahun FROM dbo.BackupAgentPeriodInventory p JOIN dbo.BackupAgentNode a ON a.AgentId=p.AgentId WHERE a.IsPrimary=1 AND a.IsEnabled=1 AND p.ThAkdk LIKE '[0-9][0-9][0-9][0-9][0-9]' ORDER BY Tahun DESC",cnsr)
  Try
   cnsr.Open():Using rd=cmd.ExecuteReader():While rd.Read():Dim year=rd("Tahun").ToString():ddlStudentRestoreYear.Items.Add(New ListItem(year,year)):End While:End Using
  Finally:tutupsr():End Try
 End Using
End Sub

Private Sub ShowEmptyRestoreNimState()
 gvBackedUpStudents.PageIndex=0
 gvBackedUpStudents.EmptyDataText="Pilih Tahun Akademik terlebih dahulu."
 gvBackedUpStudents.DataSource=New DataTable()
 gvBackedUpStudents.DataBind()
 lblStudentSearchInfo.Text=""
End Sub

Private Function CreateLookup(queryType As String,keyword As String,year As String) As Guid
 Using cmd As New SqlCommand("dbo.sp_CreateBackupLookupRequest",cnsr)
  cmd.CommandType=CommandType.StoredProcedure
  cmd.Parameters.Add("@QueryType",SqlDbType.VarChar,10).Value=queryType
  cmd.Parameters.Add("@SearchKeyword",SqlDbType.NVarChar,100).Value=If(String.IsNullOrWhiteSpace(keyword),CObj(DBNull.Value),keyword.Trim())
  cmd.Parameters.Add("@FilterYear",SqlDbType.Char,4).Value=If(String.IsNullOrWhiteSpace(year),CObj(DBNull.Value),year.Trim())
  cmd.Parameters.Add("@RequestedBy",SqlDbType.VarChar,50).Value=BackupRequestedBy()
  cnsr.Open():Using rd=cmd.ExecuteReader():If rd.Read() Then Return CType(rd("LookupId"),Guid)
  End Using
 End Using
 Throw New ApplicationException("Permintaan pencarian backup tidak menghasilkan ID.")
End Function

Private Function ReadLookup(id As Guid,ByRef status As String,ByRef resultJson As String,ByRef failure As String,ByRef keyword As String,ByRef year As String) As Boolean
 Using cmd As New SqlCommand("dbo.sp_GetBackupLookupRequest",cnsr)
  cmd.CommandType=CommandType.StoredProcedure:cmd.Parameters.Add("@LookupId",SqlDbType.UniqueIdentifier).Value=id
  cnsr.Open():Using rd=cmd.ExecuteReader()
   If Not rd.Read() Then Return False
   status=rd("Status").ToString():resultJson=If(rd.IsDBNull(rd.GetOrdinal("ResultJson")),"",rd("ResultJson").ToString()):failure=If(rd.IsDBNull(rd.GetOrdinal("ErrorMessage")),"",rd("ErrorMessage").ToString()):keyword=If(rd.IsDBNull(rd.GetOrdinal("SearchKeyword")),"",rd("SearchKeyword").ToString()):year=If(rd.IsDBNull(rd.GetOrdinal("FilterYear")),"",rd("FilterYear").ToString())
   Return True
  End Using
 End Using
End Function

Private Sub RegisterLookupRefresh()
 ScriptManager.RegisterStartupScript(Me,Me.GetType(),"RefreshBackupLookup","scheduleBackupLookupRefresh('index.aspx?tab=pemulihan&section=" & CurrentRestoreSection & "&lookup=1');",True)
End Sub

Private Sub LoadBackedUpStudents()
 Dim data As New DataTable():data.Columns.Add("Nim1",GetType(String)):data.Columns.Add("Nama",GetType(String)):data.Columns.Add("ThAkdk",GetType(String))
 Try
  Dim lookupId As Guid
  If Session("BackupStudentLookupId") Is Nothing OrElse Not Guid.TryParse(Convert.ToString(Session("BackupStudentLookupId")),lookupId) Then ShowEmptyRestoreNimState():Return
  tutupsr()
  Dim status As String="",json As String="",failure As String="",keyword As String="",year As String=""

  If Not ReadLookup(lookupId,status,json,failure,keyword,year) Then
   Session.Remove("BackupStudentLookupId")
   lblStudentSearchInfo.Text="Pencarian backup sudah kedaluwarsa. Silakan cari kembali."
   Return
  End If

  tutupsr()
  If ddlStudentRestoreYear.Items.FindByValue(year) IsNot Nothing Then ddlStudentRestoreYear.SelectedValue=year
  txtSearchBackupNim.Text=keyword

  If status="WAITING" OrElse status="CLAIMED" Then
   LookupPending=True
   gvBackedUpStudents.EmptyDataText="<div class='text-center text-muted' style='padding: 24px 10px;' role='status' aria-live='polite'><i class='fa fa-spinner fa-spin fa-2x' style='color: #0369a1;' aria-hidden='true'></i><div style='margin-top: 10px; font-size: 14px; font-weight: 600; color: #0369a1;'>Sedang mengambil data mahasiswa dari Laptop Backup...</div><div style='font-size: 12px; color: #64748b; margin-top: 4px;'>Daftar mahasiswa akan dimuat secara otomatis.</div></div>"
   gvBackedUpStudents.DataSource=data
   gvBackedUpStudents.DataBind()
   lblStudentSearchInfo.Text=""
   RegisterLookupRefresh()
   Return
  End If

  If status="FAILED" Then
   ShowAlert("error","Pencarian backup gagal",If(String.IsNullOrWhiteSpace(failure),"Terjadi kesalahan saat mencari data pada Laptop Backup.",failure))
   gvBackedUpStudents.EmptyDataText="Pencarian gagal: " & Server.HtmlEncode(failure)
   gvBackedUpStudents.DataSource=data
   gvBackedUpStudents.DataBind()
   lblStudentSearchInfo.Text=""
   Return
  End If

  Dim root=TryCast((New System.Web.Script.Serialization.JavaScriptSerializer()).DeserializeObject(json),System.Collections.Generic.Dictionary(Of String,Object))
  Dim students=If(root IsNot Nothing AndAlso root.ContainsKey("students"),TryCast(root("students"),System.Collections.IList),Nothing)
  If students IsNot Nothing Then
   For Each item In students
    Dim row=TryCast(item,System.Collections.Generic.Dictionary(Of String,Object))
    If row IsNot Nothing Then data.Rows.Add(Convert.ToString(row("nim1")),Convert.ToString(row("nama")),Convert.ToString(row("thAkdk")))
   Next
  End If
  gvBackedUpStudents.EmptyDataText="Data mahasiswa tidak ditemukan pada pencarian/tahun ini."
  gvBackedUpStudents.DataSource=data:gvBackedUpStudents.DataBind()
  lblStudentSearchInfo.Text=If(data.Rows.Count=0,"Data tidak ditemukan.","Ditemukan " & data.Rows.Count.ToString("N0") & " data mahasiswa pada Database Backup.")
 Catch ex As Exception
  gvBackedUpStudents.DataSource=Nothing:gvBackedUpStudents.DataBind():lblStudentSearchInfo.Text="Database Backup tidak dapat dibaca: " & Server.HtmlEncode(BackupErrorMessage(ex))
 Finally:tutupsr():End Try
End Sub

Protected Sub btnSearchBackupNim_Click(sender As Object,e As EventArgs)
 gvBackedUpStudents.PageIndex=0
 If String.IsNullOrWhiteSpace(ddlStudentRestoreYear.SelectedValue) Then
  Session.Remove("BackupStudentLookupId")
  ShowEmptyRestoreNimState()
  ShowAlert("warning","Tahun Akademik belum dipilih","Pilih Tahun Akademik terlebih dahulu sebelum mencari mahasiswa.")
 Else
  Session.Remove("BackupStudentLookupId")
  Try
   Dim id=CreateLookup("SEARCH",txtSearchBackupNim.Text.Trim(),ddlStudentRestoreYear.SelectedValue):Session("BackupStudentLookupId")=id.ToString()
  Catch ex As Exception:ShowAlert("error","Pencarian gagal dibuat",BackupErrorMessage(ex))
  Finally:tutupsr():End Try
  LoadBackedUpStudents()
 End If
End Sub

Protected Sub ddlStudentRestoreYear_SelectedIndexChanged(sender As Object,e As EventArgs)
 gvBackedUpStudents.PageIndex=0
 If String.IsNullOrWhiteSpace(ddlStudentRestoreYear.SelectedValue) Then
  Session.Remove("BackupStudentLookupId")
  ShowEmptyRestoreNimState()
 Else
  Session.Remove("BackupStudentLookupId")
  Try
   Dim id=CreateLookup("SEARCH",txtSearchBackupNim.Text.Trim(),ddlStudentRestoreYear.SelectedValue):Session("BackupStudentLookupId")=id.ToString()
  Catch ex As Exception:ShowAlert("error","Filter gagal dibuat",BackupErrorMessage(ex))
  Finally:tutupsr():End Try
  LoadBackedUpStudents()
 End If
End Sub

Protected Sub gvBackedUpStudents_PageIndexChanging(sender As Object,e As GridViewPageEventArgs)
 gvBackedUpStudents.PageIndex=e.NewPageIndex
 LoadBackedUpStudents()
End Sub

Protected Sub gvBackedUpStudents_RowCommand(sender As Object,e As GridViewCommandEventArgs)
 If e.CommandName<>"RestoreStudent" Then Return
 Dim success As Boolean = False
 Try
  Dim nim=e.CommandArgument.ToString().Trim()
  If Not System.Text.RegularExpressions.Regex.IsMatch(nim,"^[0-9]{9}$") Then Throw New ApplicationException("NIM hasil pencarian tidak valid.")
  CreateRestoreJob(nim,Nothing,1,SelectedTables(cblRestoreNimTables,True))
  success = True
 Catch ex As Exception
  ShowAlert("error","Pemulihan gagal",BackupErrorMessage(ex))
 Finally:tutupsr():End Try
 If success Then
  Response.Redirect("index.aspx?tab=dashboard&ref=restore", False)
  Context.ApplicationInstance.CompleteRequest()
  Return
 End If
 LoadBackedUpStudents()
End Sub

Private Sub PopulateRestorePeriods()
 ddlRestoreStartTa.Items.Clear():ddlRestoreStartTa.Items.Add(New ListItem("- Pilih TA awal -",""))
 ddlRestoreEndTa.Items.Clear():ddlRestoreEndTa.Items.Add(New ListItem("- Pilih TA -",""))
 Try
  Using cmd As New SqlCommand("SELECT p.ThAkdk, p.StudentCount, p.LiveStudentCount FROM dbo.BackupAgentPeriodInventory p JOIN dbo.BackupAgentNode a ON a.AgentId=p.AgentId WHERE a.IsPrimary=1 AND a.IsEnabled=1 AND p.StudentCount > 0 ORDER BY p.ThAkdk DESC", cnsr)
   cnsr.Open()
   Using rd = cmd.ExecuteReader()
    While rd.Read()
     Dim ta = rd("ThAkdk").ToString().Trim()
     Dim backupCount = Convert.ToInt32(rd("StudentCount"))
     Dim eligible = backupCount
     Dim startItem As New ListItem(ta, ta), endItem As New ListItem(ta, ta)
     For Each optionItem As ListItem In New ListItem(){startItem, endItem}
      optionItem.Attributes("data-eligible") = eligible.ToString()
      optionItem.Attributes("data-backup") = backupCount.ToString()
     Next
     ddlRestoreStartTa.Items.Add(startItem)
     ddlRestoreEndTa.Items.Add(endItem)
    End While
   End Using
  End Using
  If ddlRestoreEndTa.Items.Count <= 1 Then
   ShowBackupConnectionWarning("Belum ada Tahun Akademik pada Database Backup.", "Database Backup terhubung, tetapi inventaris masih kosong. Tunggu pembaruan data atau pastikan database backup berisi data.", "warning")
  End If
 Catch ex As Exception
  ShowBackupConnectionWarning("Daftar Tahun Akademik tidak dapat dimuat.", BackupErrorMessage(ex), "warning")
 Finally
  tutupsr()
 End Try
End Sub

Private Function GetSelectedRestorePeriods() As System.Collections.Generic.List(Of String)
 Dim periods As New System.Collections.Generic.List(Of String)()
 Dim mode=ddlRestoreScope.SelectedValue,startTa=ddlRestoreStartTa.SelectedValue,endTa=ddlRestoreEndTa.SelectedValue
 If mode<>"SINGLE" AndAlso mode<>"RANGE" Then Throw New ApplicationException("Cakupan pemulihan tidak valid.")
 If endTa="" Then Throw New ApplicationException("Pilih Tahun Akademik.")
 If mode="RANGE" AndAlso startTa="" Then Throw New ApplicationException("Pilih TA awal rentang.")
 If mode="RANGE" AndAlso String.CompareOrdinal(startTa,endTa)>=0 Then Throw New ApplicationException("TA akhir harus lebih besar dari TA awal.")
 For Each item As ListItem In ddlRestoreEndTa.Items
  Dim ta=item.Value
  If ta<>"" AndAlso ((mode="SINGLE" AndAlso ta=endTa) OrElse (mode="RANGE" AndAlso String.CompareOrdinal(ta,startTa)>=0 AndAlso String.CompareOrdinal(ta,endTa)<=0)) Then periods.Add(ta)
 Next
 Return periods
End Function

Private Function GetSelectedRestoreStudentTotal() As Integer
 Dim total As Integer=0,selected=GetSelectedRestorePeriods()
 For Each item As ListItem In ddlRestoreEndTa.Items
  Dim count As Integer
  If selected.Contains(item.Value) AndAlso Integer.TryParse(item.Attributes("data-eligible"),count) Then total+=count
 Next
 Return total
End Function

Protected Sub btnRestorePeriods_Click(sender As Object,e As EventArgs)
 Dim success As Boolean = False
 Try
  Dim periods=GetSelectedRestorePeriods()
  If periods.Count=0 Then Throw New ApplicationException("Pilih minimal satu Tahun Akademik.")
  CreateRestoreJob(Nothing,String.Join(",",periods.ToArray()),GetSelectedRestoreStudentTotal(),SelectedTables(cblRestorePeriodTables,True))
  success = True
 Catch ex As Exception
  ShowAlert("error","Pemulihan gagal",BackupErrorMessage(ex))
 Finally
  tutupsr()
 End Try
 If success Then
  Response.Redirect("index.aspx?tab=dashboard&ref=restore", False)
  Context.ApplicationInstance.CompleteRequest()
  Return
 End If
 PopulateRestorePeriods()
End Sub

Private Sub CreateRestoreJob(nim As String,periods As String,expectedStudents As Integer,selectedTablesCsv As String)
 EnsureBackupServiceReady(CurrentBackupService,"Pemulihan")
 Using cmd As New SqlCommand("dbo.sp_CreateRestoreTransferJob",cnsr)
  cmd.CommandType=CommandType.StoredProcedure
  cmd.Parameters.Add("@StudentNim",SqlDbType.Char,9).Value=If(String.IsNullOrWhiteSpace(nim),CObj(DBNull.Value),nim)
  cmd.Parameters.Add("@ThAkdkList",SqlDbType.NVarChar,-1).Value=If(String.IsNullOrWhiteSpace(periods),CObj(DBNull.Value),periods)
  cmd.Parameters.Add("@RequestedBy",SqlDbType.VarChar,50).Value=BackupRequestedBy()
  cmd.Parameters.Add("@ExpectedStudents",SqlDbType.Int).Value=Math.Max(0,expectedStudents)
  cmd.Parameters.Add("@SelectedTables",SqlDbType.VarChar,100).Value=selectedTablesCsv
  cnsr.Open()
  Dim jobId=Convert.ToString(cmd.ExecuteScalar())
  ShowAlert("success","Permintaan masuk antrean","Proses " & jobId & " akan dijalankan oleh Database Backup utama. Salinan backup tetap disimpan.")
 End Using
End Sub

Private Sub ShowAlert(kind As String,title As String,message As String)
 message=BackupFriendlyText(message)
 Dim css=If(kind="error","danger",kind)
 Dim historyLink=If(kind="success"," <a class='alert-link backup-history-link' href='index.aspx?tab=riwayat'>Lihat Riwayat Proses <i class='fa fa-arrow-right'></i></a>","")
 litAlertRestore.Text="<div class='alert alert-" & css & "'><strong>" & Server.HtmlEncode(title) & "</strong><br />" & Server.HtmlEncode(message) & historyLink & "</div>"
End Sub
</script>
<script type="text/javascript">
var backupLookupRefreshTimer=null;
var backupLookupRefreshUrl=null;
var backupLookupRefreshDelay=2000;
var backupLookupIsFetching=false;

function cancelBackupLookupRefresh(stopPolling){
 if(backupLookupRefreshTimer!==null){window.clearTimeout(backupLookupRefreshTimer);backupLookupRefreshTimer=null;}
 if(stopPolling===true){backupLookupRefreshUrl=null;}
}

function armBackupLookupRefresh(){
 if(!backupLookupRefreshUrl||backupLookupIsFetching){return;}
 if(backupLookupRefreshTimer!==null){window.clearTimeout(backupLookupRefreshTimer);backupLookupRefreshTimer=null;}
 backupLookupRefreshTimer=window.setTimeout(function(){
  backupLookupRefreshTimer=null;
  if(!backupLookupRefreshUrl||backupLookupIsFetching){return;}
  backupLookupIsFetching=true;
  var checkUrl=backupLookupRefreshUrl+'&poll='+Date.now();
  fetch(checkUrl,{credentials:'same-origin',cache:'no-store',headers:{'X-Requested-With':'BackupLookupPoll'}})
   .then(function(response){if(!response.ok){throw new Error('Status HTTP '+response.status);}return response.text();})
   .then(function(html){
    backupLookupIsFetching=false;
    if(!backupLookupRefreshUrl){return;}
    if(html.indexOf('id="backupLookupPending" data-pending="1"')>=0){
     armBackupLookupRefresh();
     return;
    }
    sessionStorage.setItem('restore_scroll_pos', window.scrollY || window.pageYOffset);
    window.location.replace(checkUrl);
   })
   .catch(function(){
    backupLookupIsFetching=false;
    if(backupLookupRefreshUrl){
     armBackupLookupRefresh();
    }
   });
 },backupLookupRefreshDelay);
}

function scheduleBackupLookupRefresh(url){
 cancelBackupLookupRefresh(false);
 backupLookupRefreshUrl=url;
 armBackupLookupRefresh();
}

document.addEventListener('visibilitychange',function(){
 if(!document.hidden&&backupLookupRefreshUrl&&!backupLookupIsFetching){
  armBackupLookupRefresh();
 }
});
window.addEventListener('beforeunload',function(){cancelBackupLookupRefresh(true);});
var savedRestoreScroll = sessionStorage.getItem('restore_scroll_pos');
if (savedRestoreScroll !== null) {
    sessionStorage.removeItem('restore_scroll_pos');
    window.scrollTo({ top: parseInt(savedRestoreScroll, 10), behavior: 'smooth' });
}
function restoreNumber(value){return (parseInt(value||"0",10)||0).toLocaleString("id-ID");}
function restoreScopeIncluded(mode,start,end,ta){return(mode==="SINGLE"&&ta===end)||(mode==="RANGE"&&start&&end&&ta>=start&&ta<=end);}
function applyRestoreScope(){
 var mode=$("#<%= ddlRestoreScope.ClientID %>").val(),$start=$("#<%= ddlRestoreStartTa.ClientID %>"),$end=$("#<%= ddlRestoreEndTa.ClientID %>");
 var start=$start.val()||"",end=$end.val()||"",range=mode==="RANGE";
 $("#restoreStartTaGroup").toggleClass("backup-u-029", !range);
 $("#restoreEndTaLabel").text(range?"TA akhir:":"Tahun Akademik:");
 $end.prop("disabled",range&&!start);
 $end.find("option").each(function(){var ta=this.value;var invalid=!!(range&&start&&ta&&ta<=start);$(this).prop("disabled",invalid).prop("hidden",invalid);});
 if(range&&start&&end&&end<=start){$end.val("");end="";}
  var ready=!!end&&(!range||!!start),eligible=0;
  if(ready){$end.find("option").each(function(){var ta=this.value;if(ta&&restoreScopeIncluded(mode,start,end,ta)){eligible+=parseInt($(this).attr("data-eligible")||"0",10)||0;}});}
 $("#restoreSummaryEligible").text(restoreNumber(eligible));
 $("#restoreSummaryPeriod").text(!ready?"-":(mode==="RANGE"?start+" sampai "+end:end));
 $("#restoreScopeSummary").toggleClass("backup-u-029", !ready);
}
function resetRestoreScope(){$("#<%= ddlRestoreStartTa.ClientID %>").val("");$("#<%= ddlRestoreEndTa.ClientID %>").val("");applyRestoreScope();}
function confirmRestorePeriods(button){
 var mode=$("#<%= ddlRestoreScope.ClientID %>").val(),start=$("#<%= ddlRestoreStartTa.ClientID %>").val(),end=$("#<%= ddlRestoreEndTa.ClientID %>").val();
 if(mode==="RANGE"&&!start){return backupNotice("Pilih TA awal terlebih dahulu.");}
 if(!end){return backupNotice(mode==="RANGE"?"Pilih TA akhir.":"Pilih Tahun Akademik.");}
 if(mode==="RANGE"&&end<=start){return backupNotice("TA akhir harus lebih besar dari TA awal.");}
 return backupConfirm(button,"Pulihkan data sesuai cakupan Tahun Akademik yang dipilih? Salinan pada database backup tetap disimpan dan konflik pada database aktif akan dilewati.",{title:"Konfirmasi pemulihan",confirmText:"Ya, pulihkan"});
}
$(document).ready(applyRestoreScope);
</script>

<div class="backup-page backup-page-operation">
    <div class="backup-page-header">
        <span class="backup-page-eyebrow">Operasional</span>
        <h1>Pemulihan Data</h1>
    </div>
 <asp:Literal ID="litBackupConnectionStatus" runat="server" />
 <asp:Literal ID="litAlertRestore" runat="server" />
 <span class="backup-u-029" id="backupLookupPending" data-pending="<%= If(LookupPending,"1","0") %>"></span>

 <ul class="nav nav-tabs backup-u-064">
  <li class="<%= If(CurrentRestoreSection="ta","active","") %>"><a href="index.aspx?tab=pemulihan&amp;section=ta"><i class="fa fa-calendar backup-u-068"></i>Pemulihan Tahun Akademik</a></li>
  <li class="<%= If(CurrentRestoreSection="nim","active","") %>"><a href="index.aspx?tab=pemulihan&amp;section=nim"><i class="fa fa-user backup-u-068"></i>Pemulihan per NIM</a></li>
 </ul>

 <div class="tab-content">
  <div class="tab-pane <%= If(CurrentRestoreSection="nim","active","") %>" id="subtab-restore-nim">
   <div class="panel restore-card">
    <div class="panel-heading"><i class="fa fa-user"></i> Pemulihan per NIM</div>
    <div class="panel-body">
     <!-- ALUR PEMULIHAN DATA -->
     <div class="panel panel-default" style="border-left: 4px solid #0369a1; background: #f8fafc; margin-bottom: 18px; box-shadow: 0 1px 3px rgba(0,0,0,0.05);">
         <div class="panel-body" style="padding: 14px 18px;">
             <div style="display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap;">
                 <div style="flex: 1; min-width: 180px;">
                     <div style="font-size: 11px; font-weight: 600; text-transform: uppercase; color: #64748b; letter-spacing: 0.5px;">
                         <i class="fa fa-laptop text-info"></i> Asal Data
                     </div>
                     <div style="font-size: 16px; font-weight: bold; color: #0369a1; margin-top: 3px;">
                         Laptop Backup
                     </div>
                 </div>
                 <div style="text-align: center; padding: 0 24px;">
                     <div style="color: #0369a1; font-size: 24px; line-height: 1;">
                         <i class="fa fa-arrow-right"></i>
                     </div>
                 </div>
                 <div style="flex: 1; min-width: 180px;">
                     <div style="font-size: 11px; font-weight: 600; text-transform: uppercase; color: #64748b; letter-spacing: 0.5px;">
                         <i class="fa fa-database text-primary"></i> Tujuan Pemulihan
                     </div>
                     <div style="font-size: 16px; font-weight: bold; color: #1e293b; margin-top: 3px;">
                         Server Lintar
                     </div>
                 </div>
             </div>
         </div>
     </div>
     <p class="backup-mode-help"><i class="fa fa-info-circle"></i>Gunakan menu ini untuk memulihkan data satu mahasiswa tertentu. Baris yang sudah ada pada database aktif tidak akan ditimpa.</p>
     <div class="row backup-u-062">
      <div class="col-md-3 col-sm-4"><label for="<%= ddlStudentRestoreYear.ClientID %>">Filter tahun</label><asp:DropDownList ID="ddlStudentRestoreYear" runat="server" CssClass="form-control" AutoPostBack="true" OnSelectedIndexChanged="ddlStudentRestoreYear_SelectedIndexChanged" aria-label="Filter berdasarkan tahun akademik" /></div>
      <div class="col-md-5 col-sm-5"><label for="<%= txtSearchBackupNim.ClientID %>">Cari mahasiswa</label><asp:TextBox ID="txtSearchBackupNim" runat="server" CssClass="form-control" MaxLength="100" placeholder="Masukkan NIM atau nama mahasiswa" aria-label="Cari mahasiswa berdasarkan NIM atau nama" /></div>
      <div class="col-md-2 col-sm-3 backup-u-075"><asp:LinkButton ID="btnSearchBackupNim" runat="server" CssClass="btn btn-primary btn-block" OnClick="btnSearchBackupNim_Click" aria-label="Cari data mahasiswa"><i class="fa fa-search" aria-hidden="true"></i> Cari</asp:LinkButton></div>
     </div>
     <div class="well backup-u-010">
      <label>Tabel yang dipulihkan:</label>
      <asp:CheckBoxList ID="cblRestoreNimTables" runat="server" RepeatDirection="Horizontal" RepeatLayout="Flow" CssClass="backup-table-options">
       <asp:ListItem Value="tbio01" Text=" Biodata · wajib" Selected="True" Enabled="False" />
       <asp:ListItem Value="treg" Text=" Registrasi" Selected="True" />
       <asp:ListItem Value="tkrs06" Text=" KRS" Selected="True" />
       <asp:ListItem Value="t_absensi14" Text=" Absensi" Selected="True" />
      </asp:CheckBoxList>
      <p class="help-block">Biodata otomatis disertakan jika tabel lain dipilih. Baris aktif yang sudah ada tetap dilewati.</p>
     </div>
     <div class="table-responsive backup-u-065">
      <asp:GridView ID="gvBackedUpStudents" runat="server" AutoGenerateColumns="false" CssClass="table table-bordered table-hover restore-period-table" EmptyDataText="Data NIM backup tidak ditemukan." AllowPaging="true" PageSize="10" PagerSettings-Mode="NumericFirstLast" PagerSettings-FirstPageText="Awal" PagerSettings-LastPageText="Akhir" PagerStyle-CssClass="customPager" PagerStyle-HorizontalAlign="Center" OnPageIndexChanging="gvBackedUpStudents_PageIndexChanging" OnRowCommand="gvBackedUpStudents_RowCommand">
       <Columns>
        <asp:BoundField DataField="Nim1" HeaderText="NIM" />
        <asp:BoundField DataField="Nama" HeaderText="Nama Mahasiswa" />
        <asp:BoundField DataField="ThAkdk" HeaderText="TA Terakhir" />
        <asp:TemplateField HeaderText="Aksi" ItemStyle-HorizontalAlign="Center"><ItemTemplate><asp:Button ID="btnRestoreStudent" runat="server" Text="Pulihkan" CssClass="btn btn-xs btn-success" Enabled='<%# BackupServiceReady %>' CommandName="RestoreStudent" CommandArgument='<%# Eval("Nim1") %>' aria-label='<%# "Pulihkan data mahasiswa " & Eval("Nama") & " NIM " & Eval("Nim1") %>' OnClientClick="return backupConfirm(this,'Pulihkan mahasiswa ini? Salinan backup tetap disimpan; data aktif yang sudah ada tidak akan ditimpa.',{title:'Konfirmasi pemulihan',confirmText:'Ya, pulihkan',confirmColor:'#15803d'});" /></ItemTemplate></asp:TemplateField>
       </Columns>
      </asp:GridView>
     </div>
     <asp:Label ID="lblStudentSearchInfo" runat="server" CssClass="text-muted" />
    </div>
   </div>
  </div>

  <div class="tab-pane <%= If(CurrentRestoreSection="ta","active","") %>" id="subtab-restore-period">
   <div class="panel restore-card">
    <div class="panel-heading"><i class="fa fa-calendar"></i> Pemulihan Tahun Akademik</div>
    <div class="panel-body">
     <!-- ALUR PEMULIHAN DATA -->
     <div class="panel panel-default" style="border-left: 4px solid #0369a1; background: #f8fafc; margin-bottom: 18px; box-shadow: 0 1px 3px rgba(0,0,0,0.05);">
         <div class="panel-body" style="padding: 14px 18px;">
             <div style="display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap;">
                 <div style="flex: 1; min-width: 180px;">
                     <div style="font-size: 11px; font-weight: 600; text-transform: uppercase; color: #64748b; letter-spacing: 0.5px;">
                         <i class="fa fa-laptop text-info"></i> Asal Data
                     </div>
                     <div style="font-size: 16px; font-weight: bold; color: #0369a1; margin-top: 3px;">
                         Laptop Backup
                     </div>
                 </div>
                 <div style="text-align: center; padding: 0 24px;">
                     <div style="color: #0369a1; font-size: 24px; line-height: 1;">
                         <i class="fa fa-arrow-right"></i>
                     </div>
                 </div>
                 <div style="flex: 1; min-width: 180px;">
                     <div style="font-size: 11px; font-weight: 600; text-transform: uppercase; color: #64748b; letter-spacing: 0.5px;">
                         <i class="fa fa-database text-primary"></i> Tujuan Pemulihan
                     </div>
                     <div style="font-size: 16px; font-weight: bold; color: #1e293b; margin-top: 3px;">
                         Server Lintar
                     </div>
                 </div>
             </div>
         </div>
     </div>
     <p class="backup-mode-help"><i class="fa fa-info-circle"></i>Gunakan menu ini untuk memulihkan banyak mahasiswa berdasarkan satu atau beberapa Tahun Akademik. Data aktif yang sudah ada akan dilewati dan tidak ditimpa.</p>
     <div class="row backup-u-061">
      <div class="col-md-4"><label for="<%= ddlRestoreScope.ClientID %>">Cakupan pemulihan</label><asp:DropDownList ID="ddlRestoreScope" runat="server" CssClass="form-control" onchange="resetRestoreScope()"><asp:ListItem Value="SINGLE">1 Tahun Akademik</asp:ListItem><asp:ListItem Value="RANGE">Rentang Tahun Akademik</asp:ListItem></asp:DropDownList></div>
      <div class="col-md-4 backup-u-029" id="restoreStartTaGroup"><label for="<%= ddlRestoreStartTa.ClientID %>">TA awal:</label><asp:DropDownList ID="ddlRestoreStartTa" runat="server" CssClass="form-control" onchange="applyRestoreScope()" /></div>
      <div class="col-md-4"><label id="restoreEndTaLabel" for="<%= ddlRestoreEndTa.ClientID %>">Tahun Akademik:</label><asp:DropDownList ID="ddlRestoreEndTa" runat="server" CssClass="form-control" onchange="applyRestoreScope()" /></div>
     </div>
      <div class="well backup-u-010">
       <label>Tabel yang dipulihkan:</label>
       <asp:CheckBoxList ID="cblRestorePeriodTables" runat="server" RepeatDirection="Horizontal" RepeatLayout="Flow" CssClass="backup-table-options">
        <asp:ListItem Value="tbio01" Text=" Biodata · wajib" Selected="True" Enabled="False" />
        <asp:ListItem Value="treg" Text=" Registrasi" Selected="True" />
        <asp:ListItem Value="tkrs06" Text=" KRS" Selected="True" />
        <asp:ListItem Value="t_absensi14" Text=" Absensi" Selected="True" />
       </asp:CheckBoxList>
       <p class="help-block">Minimal satu tabel akademik dipilih; Biodata otomatis disertakan.</p>
      </div>
      <div id="restoreScopeSummary" class="row scope-summary backup-u-029">
        <div class="col-md-4"><div class="scope-summary-card active-card"><div class="scope-summary-icon"><svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path fill="currentColor" d="M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8Zm0 2c-4.42 0-8 2.24-8 5v1h16v-1c0-2.76-3.58-5-8-5Z" /></svg></div><div class="scope-summary-content"><span>Konflik Data Aktif</span><strong>Lewati Baris</strong></div></div></div>
        <div class="col-md-4"><div class="scope-summary-card inactive-card"><div class="scope-summary-icon"><svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path fill="currentColor" d="M7.5 10H14a5 5 0 0 1 0 10h-2v-2h2a3 3 0 0 1 0-6H7.5l3 3L9 16.5 3.5 11 9 5.5 10.5 7l-3 3Z" /></svg></div><div class="scope-summary-content"><span>Akumulasi Mahasiswa per TA</span><strong id="restoreSummaryEligible">0</strong></div></div></div>
       <div class="col-md-4"><div class="scope-summary-card period-card"><div class="scope-summary-icon"><svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path fill="currentColor" d="M7 2h2v3h6V2h2v3h3v17H4V5h3V2Zm11 8H6v10h12V10ZM6 7v1h12V7H6Z" /></svg></div><div class="scope-summary-content"><span>Cakupan Tahun Akademik</span><strong id="restoreSummaryPeriod">-</strong></div></div></div>
      </div>
     <div class="backup-u-076"><asp:Button ID="btnRestorePeriods" runat="server" Text="Masukkan Antrean Pemulihan" CssClass="btn btn-success" aria-label="Masukkan proses pemulihan ke dalam antrean" OnClick="btnRestorePeriods_Click" OnClientClick="return confirmRestorePeriods(this);" /></div>
    </div>
   </div>
  </div>
 </div>
</div>
