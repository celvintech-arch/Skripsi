<%@ Control Language="VB" ClassName="backup_data_backup_v3_control" %>
<!-- #INCLUDE file="con_backup.ascx" -->
<%@ Import Namespace="System.Collections.Generic" %>

<script runat="server">
Protected CurrentBackupSection As String="otomatis"
Protected Sub Page_Load(sender As Object,e As EventArgs)
 RequireBackupStaff()
 Response.Cache.SetCacheability(HttpCacheability.NoCache)
 Response.Cache.SetNoStore()
 Response.Cache.SetExpires(DateTime.UtcNow.AddYears(-1))
 Dim requested=If(Request.QueryString("section"),"").Trim().ToLowerInvariant()
 If requested="tahun" Then CurrentBackupSection=requested
 If Not IsPostBack Then
  PopulateSourceDatabases()
  If CurrentBackupSection="otomatis" Then
   PopulateYears(ddlTahunJadwal,"- Pilih Tahun -")
   PopulateTAByYear(ddlBatasThAkdk,"- Pilih Detail Tahun Akademik -","")
   LoadConfig()
  Else
   PopulateBackupPeriods(ddlBackupStartTa,"- Pilih TA awal -")
   PopulateBackupPeriods(ddlBackupEndTa,"- Pilih TA -")
  End If
 End If
End Sub
Private Sub PopulateSourceDatabases()
 Dim builder As New SqlConnectionStringBuilder(cnsr.ConnectionString)
 Dim databaseName=builder.InitialCatalog
 ddlSourceDatabase.Items.Clear()
 ddlSourceDatabase.Items.Add(New ListItem(databaseName,databaseName))
 ddlSourceDatabase.Enabled=False
 ddlSourceDatabaseSchedule.Items.Clear()
 ddlSourceDatabaseSchedule.Items.Add(New ListItem(databaseName,databaseName))
 ddlSourceDatabaseSchedule.Enabled=False
End Sub
Private Sub ValidateSelectedSourceDatabase(selectedDatabase As String)
 Dim builder As New SqlConnectionStringBuilder(cnsr.ConnectionString)
 If Not String.Equals(selectedDatabase,builder.InitialCatalog,StringComparison.OrdinalIgnoreCase) Then Throw New ApplicationException("Database sumber belum terdaftar pada koneksi aplikasi.")
End Sub
Private Function SelectedTables(list As CheckBoxList,requireAcademic As Boolean) As String
 Dim chosen As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
 For Each item As ListItem In list.Items
  If item.Selected Then chosen.Add(item.Value)
 Next
 If chosen.Count=0 Then Throw New ApplicationException("Pilih minimal satu tabel.")
 If requireAcademic AndAlso Not chosen.Contains("treg") AndAlso Not chosen.Contains("tkrs06") AndAlso Not chosen.Contains("t_absensi14") Then Throw New ApplicationException("Pilih minimal satu tabel Registrasi, KRS, atau Absensi.")
 chosen.Add("tbio01")
 For Each item As ListItem In list.Items : item.Selected=chosen.Contains(item.Value) : Next
 Dim result As New List(Of String)()
 For Each name In New String(){"tbio01","treg","tkrs06","t_absensi14"} : If chosen.Contains(name) Then result.Add(name)
 Next
 Return String.Join(",",result.ToArray())
End Function
Private Sub ApplySelectedTables(list As CheckBoxList,value As String)
 Dim selected As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
 If String.IsNullOrWhiteSpace(value) Then value="tbio01,treg,tkrs06,t_absensi14"
 For Each name In value.Split(","c) : selected.Add(name.Trim()) : Next
 selected.Add("tbio01")
 For Each item As ListItem In list.Items : item.Selected=selected.Contains(item.Value) : Next
End Sub
Private Function SelectedTableLabels(value As String) As String
 Dim labels As New List(Of String)()
 For Each name In value.Split(","c)
  Select Case name.Trim().ToLowerInvariant()
   Case "tbio01":labels.Add("Biodata")
   Case "treg":labels.Add("Registrasi")
   Case "tkrs06":labels.Add("KRS")
   Case "t_absensi14":labels.Add("Absensi")
  End Select
 Next
 Return String.Join(", ",labels.ToArray())
End Function
Private Sub PopulateBackupPeriods(list As DropDownList,prompt As String)
 list.Items.Clear():list.Items.Add(New ListItem(prompt,""))
 Dim sql="SELECT LTRIM(RTRIM(r.th_akdk)) th_akdk,COUNT(DISTINCT r.nim1) StudentCount FROM dbo.treg r JOIN dbo.tbio01 b ON b.nim1=r.nim1 WHERE LTRIM(RTRIM(r.th_akdk)) LIKE '[0-9][0-9][0-9][0-9][0-9]' GROUP BY LTRIM(RTRIM(r.th_akdk)) ORDER BY th_akdk DESC"
 Using cmd As New SqlCommand(sql,cnsr)
  Try
    cnsr.Open():Using rd=cmd.ExecuteReader():While rd.Read():Dim ta=rd("th_akdk").ToString().Trim(),studentCount=Convert.ToInt32(rd("StudentCount")),optionItem As New ListItem(ta,ta):optionItem.Attributes("data-count")=studentCount.ToString():list.Items.Add(optionItem):End While:End Using
  Finally:tutupsr():End Try
 End Using
End Sub
Private Sub PopulateYears(list As DropDownList,prompt As String)
 list.Items.Clear():list.Items.Add(New ListItem(prompt,""))
 Dim sql="SELECT LEFT(LTRIM(RTRIM(r.th_akdk)),4) Tahun,COUNT(DISTINCT r.nim1) StudentCount FROM dbo.treg r JOIN dbo.tbio01 b ON b.nim1=r.nim1 WHERE LTRIM(RTRIM(r.th_akdk)) LIKE '[0-9][0-9][0-9][0-9][0-9]' GROUP BY LEFT(LTRIM(RTRIM(r.th_akdk)),4) ORDER BY Tahun DESC"
 Using cmd As New SqlCommand(sql,cnsr)
  Try
   cnsr.Open():Using rd=cmd.ExecuteReader():While rd.Read():Dim tahun=rd("Tahun").ToString().Trim(),studentCount=Convert.ToInt32(rd("StudentCount")):list.Items.Add(New ListItem(tahun & " - Total mahasiswa: " & studentCount.ToString("N0"),tahun)):End While:End Using
   Finally:tutupsr():End Try
 End Using
End Sub
Private Sub PopulateTAByYear(list As DropDownList,prompt As String,tahun As String)
 list.Items.Clear():list.Items.Add(New ListItem(prompt,""))
 If String.IsNullOrWhiteSpace(tahun) Then Exit Sub
 Dim sql=";WITH T AS(SELECT DISTINCT LTRIM(RTRIM(th_akdk)) th_akdk FROM dbo.treg WHERE LEFT(LTRIM(RTRIM(th_akdk)),4)=@tahun AND LTRIM(RTRIM(th_akdk)) LIKE '[0-9][0-9][0-9][0-9][0-9]') SELECT T.th_akdk,COUNT(DISTINCT r.nim1) StudentCount FROM T JOIN dbo.treg r ON LTRIM(RTRIM(r.th_akdk))<=T.th_akdk JOIN dbo.tbio01 b ON b.nim1=r.nim1 GROUP BY T.th_akdk ORDER BY T.th_akdk DESC"
 Using cmd As New SqlCommand(sql,cnsr)
  cmd.Parameters.Add("@tahun",SqlDbType.Char,4).Value=tahun
  Try
   cnsr.Open():Using rd=cmd.ExecuteReader():While rd.Read():Dim ta=rd("th_akdk").ToString().Trim(),studentCount=Convert.ToInt32(rd("StudentCount")):list.Items.Add(New ListItem(ta & " dan sebelumnya - Total mahasiswa: " & studentCount.ToString("N0"),ta)):End While:End Using
   Finally:tutupsr():End Try
  End Using
End Sub
Protected Sub ddlTahunJadwal_SelectedIndexChanged(sender As Object,e As EventArgs)
 PopulateTAByYear(ddlBatasThAkdk,"- Pilih detail Tahun Akademik -",ddlTahunJadwal.SelectedValue)
 ScriptManager.RegisterStartupScript(Me, Me.GetType(), "KeepScheduleTabAfterYear", "$(""a[href='#subtab-otomatis']"").tab('show');", True)
End Sub
Private Sub SetValue(list As DropDownList,value As String)
 If list.Items.FindByValue(value) IsNot Nothing Then list.SelectedValue=value
End Sub
Private Sub SetExecutionTime(value As String)
 If ddlJamEksekusi.Items.FindByValue(value) Is Nothing AndAlso value<>"" Then ddlJamEksekusi.Items.Add(New ListItem("Pukul " & value & " WIB",value))
 SetValue(ddlJamEksekusi,value)
End Sub
Private Sub LoadConfig()
 Dim savedTa As String="",savedTables As String="tbio01,treg,tkrs06,t_absensi14":Dim onOff As Boolean=False:Dim nextRun As Nullable(Of DateTime)=Nothing
 Using cmd As New SqlCommand("SELECT IsEnabled,Frequency,CONVERT(varchar(5),ExecutionTime,108) ExecutionTime,CutoffThAkdk,NextRunAt,SelectedTables FROM dbo.BackupJobConfiguration WHERE ConfigurationId=1",cnsr)
  Try
   cnsr.Open():Using rd=cmd.ExecuteReader():If rd.Read() Then
    onOff=CBool(rd("IsEnabled")):savedTa=rd("CutoffThAkdk").ToString().Trim():savedTables=rd("SelectedTables").ToString().Trim():chkJobToggleJS.Checked=onOff:hdnJobActive.Value=If(onOff,"1","0"):SetValue(ddlFrekuensi,rd("Frequency").ToString()):SetExecutionTime(rd("ExecutionTime").ToString()):If Not rd.IsDBNull(4) Then nextRun=CType(rd(4),DateTime)
   End If:End Using
  Finally:tutupsr():End Try
 End Using
 ApplySelectedTables(cblScheduleTables,savedTables)
 If savedTa.Length>=4 Then SetValue(ddlTahunJadwal,savedTa.Substring(0,4)):PopulateTAByYear(ddlBatasThAkdk,"- Pilih Detail Tahun Akademik -",ddlTahunJadwal.SelectedValue):SetValue(ddlBatasThAkdk,savedTa)
 Summary(onOff,nextRun)
End Sub
Private Sub Summary(onOff As Boolean,nextRun As Nullable(Of DateTime))
 lblSummaryScheduleStatus.Text=If(onOff,"ON","OFF")
 lblSummaryScheduleStatus.CssClass="label " & If(onOff,"label-success","label-default")
 pnlSummaryDetails.Visible=onOff
 If onOff Then
  litSummaryFrekuensi.Text=Server.HtmlEncode(ddlFrekuensi.SelectedItem.Text):litSummaryJam.Text=Server.HtmlEncode(ddlJamEksekusi.SelectedItem.Text):litSummaryTables.Text=Server.HtmlEncode(SelectedTableLabels(SelectedTables(cblScheduleTables,True))):litSummaryNextRun.Text=If(nextRun.HasValue,nextRun.Value.ToString("dd MMM yyyy HH:mm"),"Belum dijadwalkan")
  litSummaryCountdown.Text=If(nextRun.HasValue,"<span id='backupCountdown' data-next='" & nextRun.Value.ToString("yyyy-MM-ddTHH:mm:ss") & "'>Menghitung...</span>","-")
 End If
End Sub
Protected Sub btnSimpanJadwal_Click(sender As Object,e As EventArgs)
 Try
  ValidateSelectedSourceDatabase(ddlSourceDatabaseSchedule.SelectedValue)
  If ddlBatasThAkdk.SelectedValue="" Then Throw New ApplicationException("Pilih Tahun Akademik.")
  Dim selectedTableCsv=SelectedTables(cblScheduleTables,True)
  Using cmd As New SqlCommand("dbo.sp_SaveBackupJobConfiguration",cnsr)
   Dim nowTime As DateTime=DateTime.Now:Dim scheduledTime As TimeSpan=If(ddlJamEksekusi.SelectedValue="NEXT_1_MINUTE",nowTime.AddMinutes(1).TimeOfDay,TimeSpan.Parse(ddlJamEksekusi.SelectedValue))
   cmd.CommandType=CommandType.StoredProcedure:cmd.Parameters.Add("@IsEnabled",SqlDbType.Bit).Value=(hdnJobActive.Value="1"):cmd.Parameters.Add("@Frequency",SqlDbType.VarChar,10).Value=ddlFrekuensi.SelectedValue:cmd.Parameters.Add("@ExecutionTime",SqlDbType.Time).Value=scheduledTime:cmd.Parameters.Add("@CutoffThAkdk",SqlDbType.Char,5).Value=ddlBatasThAkdk.SelectedValue:cmd.Parameters.Add("@AdminUser",SqlDbType.VarChar,50).Value=BackupRequestedBy():cmd.Parameters.Add("@SelectedTables",SqlDbType.VarChar,100).Value=selectedTableCsv:cnsr.Open():cmd.ExecuteNonQuery()
  End Using:ShowAlert(litAlertSchedule,"success","Konfigurasi tersimpan","Konfigurasi penjadwalan tersimpan di database.")
 Catch ex As Exception:ShowAlert(litAlertSchedule,"error","Gagal menyimpan konfigurasi",ex.Message)
 Finally:tutupsr():End Try:LoadConfig()
End Sub
Protected Sub btnDisableSchedule_Click(sender As Object,e As EventArgs)
 hdnJobActive.Value="0"
 chkJobToggleJS.Checked=False
 btnSimpanJadwal_Click(sender,e)
End Sub
Protected Sub btnJalankanBackup_Click(sender As Object,e As EventArgs)
 Try
  ValidateSelectedSourceDatabase(ddlSourceDatabase.SelectedValue)
  Dim mode=ddlBackupScope.SelectedValue,startTa=ddlBackupStartTa.SelectedValue,endTa=ddlBackupEndTa.SelectedValue
  If mode<>"SINGLE" AndAlso mode<>"RANGE" Then Throw New ApplicationException("Cakupan backup tidak valid.")
  If endTa="" Then Throw New ApplicationException("Pilih Tahun Akademik.")
  If mode="RANGE" AndAlso startTa="" Then Throw New ApplicationException("Pilih TA awal rentang.")
  If mode="RANGE" AndAlso String.CompareOrdinal(startTa,endTa)>=0 Then Throw New ApplicationException("TA akhir harus lebih besar dari TA awal.")
  Dim selectedTableCsv=SelectedTables(cblBackupTables,True)
  Using cmd As New SqlCommand("dbo.sp_CreateBackupTransferJob",cnsr)
   cmd.CommandType=CommandType.StoredProcedure
   cmd.Parameters.Add("@CutoffThAkdk",SqlDbType.Char,5).Value=endTa
   cmd.Parameters.Add("@RequestedBy",SqlDbType.VarChar,50).Value=BackupRequestedBy()
   cmd.Parameters.Add("@TriggerSource",SqlDbType.VarChar,10).Value="MANUAL"
   cmd.Parameters.Add("@SelectionMode",SqlDbType.VarChar,10).Value=mode
   cmd.Parameters.Add("@StartThAkdk",SqlDbType.Char,5).Value=If(mode="RANGE",CObj(startTa),DBNull.Value)
   cmd.Parameters.Add("@SelectedTables",SqlDbType.VarChar,100).Value=selectedTableCsv
   cnsr.Open()
   Using rd=cmd.ExecuteReader()
    If Not rd.Read() Then Throw New ApplicationException("Pembuatan antrean tidak menghasilkan status.")
    Dim count=Convert.ToInt32(rd("CandidateStudents"))
    ShowAlert(litAlertBackup,"success","PERMINTAAN DITERIMA",If(count=0,"Tidak ada data yang perlu dibackup.",count.ToString("N0") & " mahasiswa masuk antrean Database Backup."))
   End Using
  End Using
 Catch ex As Exception
  ShowAlert(litAlertBackup,"error","Backup gagal",ex.Message)
 Finally
  tutupsr()
 End Try
End Sub
Private Sub ShowAlert(lit As Literal,kind As String,title As String,msg As String)
 Dim alertType As String = If(kind = "error", "danger", kind)
 If kind = "success" AndAlso Object.ReferenceEquals(lit, litAlertBackup) Then
  lit.Text = "<div class='alert alert-success backup-u-001'><div class='backup-u-036'><i class='fa fa-check-circle'></i> " & Server.HtmlEncode(title) & "</div><div class='backup-u-023'>" & Server.HtmlEncode(msg) & "</div></div>"
 Else
  lit.Text = "<div class='alert alert-" & alertType & "'><strong>" & Server.HtmlEncode(title) & "</strong> " & Server.HtmlEncode(msg) & "</div>"
 End If

 Dim safeTitle As String = title.Replace("'", "\'").Replace(vbCr, " ").Replace(vbLf, " ")
 Dim safeMessage As String = msg.Replace("'", "\'").Replace(vbCr, " ").Replace(vbLf, " ")
 Dim swalIcon As String = If(kind = "error", "error", kind)
 Dim confirmColor As String = If(kind = "success", "#00a65a", "#dd4b39")
 Dim script As String = "if (typeof Swal !== 'undefined') { Swal.fire({title: '" & safeTitle & "', text: '" & safeMessage & "', icon: '" & swalIcon & "', confirmButtonText: 'OK', confirmButtonColor: '" & confirmColor & "', width: '480px'}); }"
 If kind = "error" AndAlso Object.ReferenceEquals(lit, litAlertBackup) Then
  script &= " $(""a[href='#subtab-manual']"").tab('show');"
 End If
 ScriptManager.RegisterStartupScript(Me, Me.GetType(), "BackupAlert_" & Guid.NewGuid().ToString("N"), script, True)
End Sub
</script>

<script type="text/javascript">
    function backupNumber(value) { return (parseInt(value || "0", 10) || 0).toLocaleString("id-ID"); }
    function backupScopeIncluded(mode, start, end, ta) {
        return (mode === "SINGLE" && ta === end) || (mode === "RANGE" && start && end && ta >= start && ta <= end);
    }
    function toggleBackupScope() {
        var mode = $("#<%= ddlBackupScope.ClientID %>").val();
        var $start = $("#<%= ddlBackupStartTa.ClientID %>");
        var $end = $("#<%= ddlBackupEndTa.ClientID %>");
        var start = $start.val() || "", end = $end.val() || "";
        var range = mode === "RANGE";
        $("#backupStartTaGroup").toggleClass("backup-u-029", !range);
        $("#backupEndTaLabel").text(range ? "TA akhir:" : "Tahun Akademik:");
        $end.prop("disabled", range && !start);
        $end.find("option").each(function(){var ta=this.value;var invalid=!!(range&&start&&ta&&ta<=start);$(this).prop("disabled",invalid).prop("hidden",invalid);});
        if(range && start && end && end <= start){$end.val("");end="";}
        var ready = !!end && (!range || !!start), total = 0;
        if(ready){$end.find("option").each(function(){var ta=this.value;if(ta&&backupScopeIncluded(mode,start,end,ta)){total+=parseInt($(this).attr("data-count")||"0",10)||0;}});}
        $("#backupSummaryTotal").text(backupNumber(total));
        $("#backupSummaryPeriod").text(!ready?"-":(mode==="RANGE"?start+" sampai "+end:end));
        $("#backupScopeSummary").toggleClass("backup-u-029", !ready);
    }
    function resetBackupScope(){$("#<%= ddlBackupStartTa.ClientID %>").val("");$("#<%= ddlBackupEndTa.ClientID %>").val("");toggleBackupScope();}
    function confirmBackupPeriods(button){
        var mode=$("#<%= ddlBackupScope.ClientID %>").val(),start=$("#<%= ddlBackupStartTa.ClientID %>").val(),end=$("#<%= ddlBackupEndTa.ClientID %>").val();
        if(mode==="RANGE"&&!start){return backupNotice("Pilih TA awal terlebih dahulu.");}
        if(!end){return backupNotice(mode==="RANGE"?"Pilih TA akhir.":"Pilih Tahun Akademik.");}
        if(mode==="RANGE"&&end<=start){return backupNotice("TA akhir harus lebih besar dari TA awal.");}
        return backupConfirm(button,"Backup data mahasiswa terpilih ke Database Backup sekarang? Data pada database aktif tidak akan dihapus.",{title:"Konfirmasi backup",confirmText:"Ya, backup sekarang"});
    }

    function toggleScheduleFormJS(chk) {
        var $form = $("#pnlScheduleFormContainer");
        var $badge = $("#lblJobStatusBadge");
        var $summaryStatus = $("#lblSummaryScheduleStatus");
        var $summaryDetails = $("#<%= pnlSummaryDetails.ClientID %>");
        var $hdn = $("#<%= hdnJobActive.ClientID %>");

        if (chk.checked) {
            $("#pnlAutomaticSettings").collapse("show");
            $form.show();
            $badge.removeClass("label-default label-danger").addClass("label-success").text("ON");
            $hdn.val("1");
        } else {
            $badge.removeClass("label-success label-danger").addClass("label-default").text("OFF");
            $summaryStatus.removeClass("label-success label-danger").addClass("label-default").text("OFF");
            $summaryDetails.stop(true, true).hide();
            $hdn.val("0");
            window.setTimeout(function () { __doPostBack('<%= btnDisableSchedule.UniqueID %>', ''); }, 50);
        }
    }

    $(document).ready(function() {
        toggleBackupScope();
        var $hdn = $("#<%= hdnJobActive.ClientID %>");
        var $chk = $("#<%= chkJobToggleJS.ClientID %>");
        var $form = $("#pnlScheduleFormContainer");
        $form.show();
        if ($hdn.val() === "0") {
            $chk.prop("checked", false);
            $("#lblJobStatusBadge").removeClass("label-success").addClass("label-default").text("OFF");
        } else {
            $chk.prop("checked", true);
            $form.show();
            $("#lblJobStatusBadge").removeClass("label-default").addClass("label-success").text("ON");
        }
    });
</script>
<script type="text/javascript">
(function () {
    function updateBackupCountdown() {
        var el = document.getElementById('backupCountdown');
        if (!el) { return; }
        var target = new Date(el.getAttribute('data-next'));
        var remaining = target.getTime() - new Date().getTime();
        if (isNaN(target.getTime())) { el.textContent = '-'; return; }
        if (remaining <= 0) { el.textContent = 'Menunggu pemeriksaan jadwal'; return; }
        var total = Math.floor(remaining / 1000);
        var days = Math.floor(total / 86400); total %= 86400;
        var hours = Math.floor(total / 3600); total %= 3600;
        var minutes = Math.floor(total / 60); var seconds = total % 60;
        el.textContent = (days > 0 ? days + ' hari ' : '') + String(hours).padStart(2, '0') + ':' + String(minutes).padStart(2, '0') + ':' + String(seconds).padStart(2, '0');
    }
    updateBackupCountdown();
    window.setInterval(updateBackupCountdown, 1000);
}());
</script>

<div class="backup-page backup-page-operation">
    <div class="backup-page-header">
        <span class="backup-page-eyebrow">Operasional</span>
        <h1>Backup Data</h1>
    </div>

    <!-- NAVIGASI BACKUP OTOMATIS DAN BACKUP TAHUN AKADEMIK -->
    <ul class="nav nav-tabs backup-u-064">
        <li class="<%= If(CurrentBackupSection="otomatis","active","") %>" id="tabSubOtomatis">
            <a href="index.aspx?tab=backup&amp;section=otomatis">
                <i class="fa fa-clock-o me-1"></i> Backup Otomatis
            </a>
        </li>
        <li class="<%= If(CurrentBackupSection="tahun","active","") %>" id="tabSubManual">
            <a href="index.aspx?tab=backup&amp;section=tahun">
                <i class="fa fa-calendar me-1"></i> Backup Tahun Akademik
            </a>
        </li>
    </ul>

    <div class="tab-content">
        <!-- SUB-TAB 1: BACKUP OTOMATIS -->
        <div class="tab-pane <%= If(CurrentBackupSection="otomatis","active","") %>" id="subtab-otomatis">
            <!-- RINGKASAN DETAIL PENJADWALAN OTOMATIS (SINGLE STREAMLINED BAR) -->
            <div class="well backup-u-007">
                <div class="backup-u-027">
                    <div class="backup-u-025">
                        <i class="fa fa-clock-o text-danger backup-u-037"></i>
                        <div>
                            <strong class="backup-u-021">Status Penjadwalan Otomatis:</strong>
                            <span class="backup-u-066"><asp:Label ID="lblSummaryScheduleStatus" runat="server" ClientIDMode="Static" /></span>
                        </div>
                    </div>

                    <asp:Panel CssClass="backup-u-026" ID="pnlSummaryDetails" runat="server">
                        <div><i class="fa fa-calendar text-primary me-1"></i> Frekuensi: <strong><asp:Literal ID="litSummaryFrekuensi" runat="server" /></strong></div>
                        <div><i class="fa fa-clock-o text-info me-1"></i> Jam Eksekusi: <strong><asp:Literal ID="litSummaryJam" runat="server" /></strong></div>
                        <div><i class="fa fa-database text-success me-1"></i> Tabel: <strong><asp:Literal ID="litSummaryTables" runat="server" /></strong></div>
                        <div><i class="fa fa-history text-warning me-1"></i> Jadwal Backup Berikutnya: <strong><asp:Literal ID="litSummaryNextRun" runat="server" /></strong></div>
                        <div><i class="fa fa-hourglass-half text-danger me-1"></i> Hitung Mundur: <strong><asp:Literal ID="litSummaryCountdown" runat="server" /></strong></div>
                    </asp:Panel>
                </div>
            </div>

            <!-- PANEL CONFIG PENJADWALAN OTOMATIS WITH CLIENT-SIDE SLIDE ANIMATION -->
            <div class="panel panel-default backup-u-012">
                <div class="panel-heading backup-u-006">
                    <a class="backup-collapse-toggle collapsed" data-toggle="collapse" href="#pnlAutomaticSettings" aria-expanded="false" aria-controls="pnlAutomaticSettings">
                        <i class="fa fa-clock-o text-primary backup-u-067"></i> Pengaturan Backup Otomatis <span class="backup-collapse-hint">Buka pengaturan <i class="fa fa-chevron-down"></i></span>
                    </a>

                    <div class="backup-u-025">
                        <div class="switch-toggle">
                            <input type="checkbox" id="chkJobToggleJS" runat="server" ClientIDMode="Static" checked="false" onclick="toggleScheduleFormJS(this)" />
                            <span class="slider"></span>
                        </div>
                        <asp:HiddenField ID="hdnJobActive" runat="server" Value="0" />
                        <asp:LinkButton CssClass="backup-u-029" ID="btnDisableSchedule" runat="server" OnClick="btnDisableSchedule_Click" CausesValidation="false" />
                        <span id="lblJobStatusBadge" class="label label-default backup-u-034">OFF</span>
                    </div>
                </div>

                <div id="pnlAutomaticSettings" class="panel-collapse collapse">
                <div id="pnlScheduleFormContainer" class="panel-body backup-u-072">
                    <asp:Literal ID="litAlertSchedule" runat="server" />
                            <p class="backup-mode-help"><i class="fa fa-info-circle"></i>Gunakan menu ini untuk menjalankan backup berkala secara otomatis sesuai jadwal, Tahun Akademik, dan tabel yang dipilih.</p>

                    <div class="row">
                        <div class="col-md-12">
                            <!-- 1. PENGATURAN WAKTU & FREKUENSI EKSEKUSI -->
                            <div class="well backup-u-010">
                                <h5 class="backup-u-052"><i class="fa fa-calendar-check-o text-primary backup-u-067"></i> 1. Pengaturan Waktu &amp; Frekuensi Eksekusi</h5>
                                
                                <div class="row">
                                    <div class="col-md-6 col-sm-12">
                                        <div class="form-group">
                                            <label for="<%= ddlFrekuensi.ClientID %>">Frekuensi Backup Otomatis:</label>
                                            <asp:DropDownList ID="ddlFrekuensi" runat="server" CssClass="form-control">
                                                <asp:ListItem Value="SEMESTER" Text="Setiap Akhir Semester (Setiap Januari & Agustus)" />
                                                <asp:ListItem Value="MONTHLY" Text="Bulanan (Setiap Tanggal 1 Awal Bulan)" />
                                                <asp:ListItem Value="DAILY" Text="Harian" />
                                            </asp:DropDownList>
                                        </div>
                                    </div>
                                    <div class="col-md-6 col-sm-12">
                                        <div class="form-group">
                                            <label for="<%= ddlJamEksekusi.ClientID %>">Waktu Eksekusi (waktu server):</label>
                                            <asp:DropDownList ID="ddlJamEksekusi" runat="server" CssClass="form-control">
                                                <asp:ListItem Value="NEXT_1_MINUTE" Text="1 menit lagi (uji coba)" />
                                                <asp:ListItem Value="01:00" Text="Pukul 01:00 WIB" />
                                                <asp:ListItem Value="02:00" Text="Pukul 02:00 WIB" />
                                                <asp:ListItem Value="03:00" Text="Pukul 03:00 WIB" />
                                                <asp:ListItem Value="23:00" Text="Pukul 23:00 WIB" />
                                            </asp:DropDownList>
                                        </div>
                                    </div>
                                </div>
                            </div>

                            <!-- 2. DATABASE DAN CAKUPAN DATA BACKUP -->
                            <div class="well backup-u-011">
                                <h5 class="backup-u-052"><i class="fa fa-filter text-danger backup-u-067"></i> 2. Cakupan Data Backup</h5>
                                
                                <div class="form-group backup-u-058">
                                    <span class="backup-source-database" aria-hidden="true"><asp:DropDownList ID="ddlSourceDatabaseSchedule" runat="server" CssClass="form-control"></asp:DropDownList></span>
                                    <label for="<%= ddlTahunJadwal.ClientID %>">Pilih Tahun:</label>
                                    <asp:DropDownList ID="ddlTahunJadwal" runat="server" CssClass="form-control" AutoPostBack="true" OnSelectedIndexChanged="ddlTahunJadwal_SelectedIndexChanged"></asp:DropDownList>
                                    <label class="backup-u-069" for="<%= ddlBatasThAkdk.ClientID %>">Detail Tahun Akademik:</label>
                                    <asp:DropDownList ID="ddlBatasThAkdk" runat="server" CssClass="form-control"></asp:DropDownList>
                                    <label class="backup-u-069">Tabel yang dibackup:</label>
                                    <asp:CheckBoxList ID="cblScheduleTables" runat="server" RepeatDirection="Horizontal" RepeatLayout="Flow" CssClass="backup-table-options">
                                        <asp:ListItem Value="tbio01" Text=" Biodata (tbio01) · wajib" Selected="True" Enabled="False" />
                                        <asp:ListItem Value="treg" Text=" Registrasi (treg)" Selected="True" />
                                        <asp:ListItem Value="tkrs06" Text=" KRS (tkrs06)" Selected="True" />
                                        <asp:ListItem Value="t_absensi14" Text=" Absensi (t_absensi14)" Selected="True" />
                                    </asp:CheckBoxList>
                                    <p class="help-block"><i class="fa fa-lock" aria-hidden="true"></i>Biodata wajib disertakan pada setiap backup.</p>
                                </div>
                            </div>
                        </div>
                    </div>

                    <div class="backup-u-076">
                        <asp:Button ID="btnSimpanJadwal" runat="server" Text="Simpan Pengaturan" CssClass="btn btn-success btn-lg backup-u-048" OnClick="btnSimpanJadwal_Click" />
                    </div>
                </div>
                </div>
            </div>
        </div>

        <!-- SUB-TAB 2: BACKUP TAHUN AKADEMIK -->
        <div class="tab-pane <%= If(CurrentBackupSection="tahun","active","") %>" id="subtab-manual">
            <!-- PANEL EKSEKUSI MANUAL ON-DEMAND -->
            <div class="panel panel-default backup-u-012">
                <div class="panel-heading backup-u-005">
                    <i class="fa fa-play-circle text-danger backup-u-067"></i> Backup Tahun Akademik
                </div>
                <div class="panel-body backup-u-072">
                    <asp:Literal ID="litAlertBackup" runat="server" />
                    <p class="backup-mode-help"><i class="fa fa-info-circle"></i>Gunakan menu ini untuk menyalin data banyak mahasiswa berdasarkan satu atau beberapa Tahun Akademik. Data pada database aktif tetap dipertahankan.</p>

                    <div class="row">
                        <div class="col-md-12">


                            <div class="row">
                                <div class="backup-source-database" aria-hidden="true">
                                    <asp:DropDownList ID="ddlSourceDatabase" runat="server" CssClass="form-control" />
                                </div>
                                <div class="col-md-4 form-group">
                                    <label for="<%= ddlBackupScope.ClientID %>">Cakupan backup:</label>
                                    <asp:DropDownList ID="ddlBackupScope" runat="server" CssClass="form-control" onchange="resetBackupScope()">
                                        <asp:ListItem Value="SINGLE">1 Tahun Akademik</asp:ListItem>
                                        <asp:ListItem Value="RANGE">Rentang Tahun Akademik</asp:ListItem>
                                    </asp:DropDownList>
                                </div>
                                <div class="col-md-4 form-group backup-u-029" id="backupStartTaGroup">
                                    <label for="<%= ddlBackupStartTa.ClientID %>">TA awal:</label>
                                    <asp:DropDownList ID="ddlBackupStartTa" runat="server" CssClass="form-control" onchange="toggleBackupScope()" />
                                </div>
                                <div class="col-md-4 form-group">
                                    <label id="backupEndTaLabel" for="<%= ddlBackupEndTa.ClientID %>">Tahun Akademik:</label>
                                    <asp:DropDownList ID="ddlBackupEndTa" runat="server" CssClass="form-control" onchange="toggleBackupScope()" />
                                </div>
                            </div>
                            <div class="well backup-u-010">
                                <label>Tabel yang dibackup:</label>
                                <asp:CheckBoxList ID="cblBackupTables" runat="server" RepeatDirection="Horizontal" RepeatLayout="Flow" CssClass="backup-table-options">
                                    <asp:ListItem Value="tbio01" Text=" Biodata (tbio01) · wajib" Selected="True" Enabled="False" />
                                    <asp:ListItem Value="treg" Text=" Registrasi (treg)" Selected="True" />
                                    <asp:ListItem Value="tkrs06" Text=" KRS (tkrs06)" Selected="True" />
                                    <asp:ListItem Value="t_absensi14" Text=" Absensi (t_absensi14)" Selected="True" />
                                </asp:CheckBoxList>
                                <p class="help-block"><i class="fa fa-lock" aria-hidden="true"></i>Biodata wajib disertakan; pilih minimal satu tabel akademik lainnya.</p>
                            </div>
                            <div id="backupScopeSummary" class="row scope-summary backup-u-029">
                                <div class="col-md-6"><div class="scope-summary-card active-card"><div class="scope-summary-icon"><svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path fill="currentColor" d="M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8Zm0 2c-4.42 0-8 2.24-8 5v1h16v-1c0-2.76-3.58-5-8-5Z" /></svg></div><div class="scope-summary-content"><span>Total Mahasiswa Dibackup</span><strong id="backupSummaryTotal">0</strong></div></div></div>
                                <div class="col-md-6"><div class="scope-summary-card period-card"><div class="scope-summary-icon"><svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path fill="currentColor" d="M7 2h2v3h6V2h2v3h3v17H4V5h3V2Zm11 8H6v10h12V10ZM6 7v1h12V7H6Z" /></svg></div><div class="scope-summary-content"><span>Cakupan Tahun Akademik</span><strong id="backupSummaryPeriod">-</strong></div></div></div>
                            </div>



                            <div class="backup-u-077"><asp:Button ID="btnJalankanBackup" runat="server" Text="Backup Sekarang" CssClass="btn btn-danger btn-lg backup-u-048" OnClick="btnJalankanBackup_Click" OnClientClick="return confirmBackupPeriods(this);" /></div>
                        </div>
                    </div>
                </div>
            </div>
        </div>

    </div>
</div>
