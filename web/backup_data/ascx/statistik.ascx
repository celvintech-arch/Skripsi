<!-- #INCLUDE file ="con_backup.ascx" -->
<%@ Import Namespace="System.Data" %>
<%@ Import Namespace="System.Data.SqlClient" %>
<%@ Import Namespace="System.Collections.Generic" %>
<%@ Import Namespace="System.Web.Script.Serialization" %>

<script runat="server">
    Protected Sub Page_Load(ByVal sender As Object, ByVal e As EventArgs)
        RequireBackupReportAccess()
        If Not IsPostBack Then
            LoadMonitoringOverview()
            LoadDatabaseStats()
        End If
    End Sub

    Private Sub LoadMonitoringOverview()
        Try
            Dim serviceState=ReadBackupServiceState()
            litServiceStatus.Text="<span class='monitor-status monitor-status-" & serviceState.CssClass & "'><i class='fa " & If(serviceState.IsReady,"fa-check-circle","fa-exclamation-circle") & "'></i>" & Server.HtmlEncode(serviceState.StatusText) & "</span>"
            litAgentName.Text=Server.HtmlEncode(serviceState.AgentName)
            litLastHeartbeat.Text=If(serviceState.LastSeenAt.HasValue,serviceState.LastSeenAt.Value.ToString("dd MMM yyyy HH:mm:ss"),"Belum pernah terhubung")
            litAgentMessage.Text=Server.HtmlEncode(serviceState.LastMessage)

            Dim ds As New DataSet()
            Dim sql="SELECT TOP(1) IsEnabled,Frequency,CutoffThAkdk,NextRunAt FROM dbo.BackupJobConfiguration WHERE ConfigurationId=1;" & _
                "WITH Latest AS(SELECT OperationType,Status,CreatedAt,CompletedAt,ROW_NUMBER() OVER(PARTITION BY OperationType ORDER BY CreatedAt DESC) rn FROM dbo.BackupTransferJob) SELECT OperationType,Status,CreatedAt,CompletedAt FROM Latest WHERE rn=1;" & _
                "SELECT TOP(5) OperationType,Status,ProcessedStudents,TotalStudents,CreatedAt,ProgressMessage FROM dbo.BackupTransferJob WHERE Status IN('WAITING','CLAIMED','TRANSFERRING') ORDER BY CreatedAt;"
            Using cn As New SqlConnection(connstringLive),ad As New SqlDataAdapter(sql,cn)
                ad.Fill(ds)
            End Using

            If ds.Tables.Count>0 AndAlso ds.Tables(0).Rows.Count>0 Then
                Dim config=ds.Tables(0).Rows(0),enabled=Convert.ToBoolean(config("IsEnabled"))
                litAutomaticStatus.Text="<span class='monitor-status monitor-status-" & If(enabled,"success","neutral") & "'>" & If(enabled,"ON","OFF") & "</span>"
                litAutomaticFrequency.Text=FrequencyText(config("Frequency").ToString())
                litAutomaticScope.Text="TA " & Server.HtmlEncode(config("CutoffThAkdk").ToString().Trim()) & " dan sebelumnya"
                litNextSchedule.Text=If(enabled AndAlso Not config.IsNull("NextRunAt"),Convert.ToDateTime(config("NextRunAt")).ToString("dd MMM yyyy HH:mm"),"Belum dijadwalkan")
            Else
                litAutomaticStatus.Text="<span class='monitor-status monitor-status-neutral'>Belum dikonfigurasi</span>"
                litAutomaticFrequency.Text="-":litAutomaticScope.Text="-":litNextSchedule.Text="-"
            End If

            litLastBackup.Text="Belum ada proses":litLastRestore.Text="Belum ada proses":litLastExport.Text="Belum ada proses"
            If ds.Tables.Count>1 Then
                For Each row As DataRow In ds.Tables(1).Rows
                    Dim summary=RecentProcessText(row)
                    Select Case row("OperationType").ToString().Trim().ToUpperInvariant()
                        Case "BACKUP":litLastBackup.Text=summary
                        Case "RESTORE":litLastRestore.Text=summary
                        Case "EXPORT":litLastExport.Text=summary
                    End Select
                Next
            End If

            Dim active As DataTable=If(ds.Tables.Count>2,ds.Tables(2),New DataTable())
            If active.Columns.Count>0 Then
                active.Columns.Add("OperationLabel",GetType(String)):active.Columns.Add("StatusLabel",GetType(String)):active.Columns.Add("ProgressLabel",GetType(String))
                For Each row As DataRow In active.Rows
                    row("OperationLabel")=OperationText(row("OperationType").ToString())
                    row("StatusLabel")=JobStatusText(row("Status").ToString())
                    Dim total=If(row.IsNull("TotalStudents"),0,Convert.ToInt32(row("TotalStudents")))
                    row("ProgressLabel")=Convert.ToInt32(row("ProcessedStudents")).ToString("N0") & "/" & If(total>0,total.ToString("N0"),"-")
                Next
            End If
            gvActiveDashboard.DataSource=active:gvActiveDashboard.DataBind()
            litActiveProcessCount.Text=active.Rows.Count.ToString("N0")
        Catch ex As Exception
            litMonitoringMessage.Text="<div class='alert alert-warning'><strong>Ringkasan pemantauan belum dapat dimuat.</strong> " & Server.HtmlEncode(ex.Message) & "</div>"
            litServiceStatus.Text="<span class='monitor-status monitor-status-danger'>Belum siap</span>"
            litAgentName.Text="-":litLastHeartbeat.Text="-":litAgentMessage.Text="Status belum tersedia."
            litAutomaticStatus.Text="<span class='monitor-status monitor-status-neutral'>-</span>":litAutomaticFrequency.Text="-":litAutomaticScope.Text="-":litNextSchedule.Text="-"
            litLastBackup.Text="-":litLastRestore.Text="-":litLastExport.Text="-":litActiveProcessCount.Text="0"
        End Try
    End Sub

    Private Function FrequencyText(value As String) As String
        Select Case value.Trim().ToUpperInvariant()
            Case "DAILY":Return "Harian"
            Case "MONTHLY":Return "Bulanan"
            Case "SEMESTER":Return "Setiap semester"
            Case Else:Return If(String.IsNullOrWhiteSpace(value),"-",value)
        End Select
    End Function

    Private Function OperationText(value As String) As String
        Select Case value.Trim().ToUpperInvariant()
            Case "BACKUP":Return "Backup"
            Case "RESTORE":Return "Pemulihan"
            Case "EXPORT":Return "Ekspor database"
            Case Else:Return value
        End Select
    End Function

    Private Function JobStatusText(value As String) As String
        Select Case value.Trim().ToUpperInvariant()
            Case "WAITING":Return "Menunggu"
            Case "CLAIMED","TRANSFERRING":Return "Diproses"
            Case "SUCCESS":Return "Berhasil"
            Case "FAILED":Return "Gagal/Dibatalkan"
            Case Else:Return value
        End Select
    End Function

    Private Function RecentProcessText(row As DataRow) As String
        Dim whenValue=If(row.IsNull("CompletedAt"),Convert.ToDateTime(row("CreatedAt")),Convert.ToDateTime(row("CompletedAt")))
        Return whenValue.ToString("dd MMM yyyy HH:mm") & " · " & JobStatusText(row("Status").ToString())
    End Function

    Private Sub LoadDatabaseStats()
        Try
            Dim qryStat As String = "SELECT " & _
                "(SELECT COUNT(*) FROM dbo.tbio01) AS LiveBio, " & _
                "(SELECT COUNT(*) FROM dbo.treg) AS LiveReg, " & _
                "(SELECT COUNT(*) FROM dbo.tkrs06) AS LiveKrs, " & _
                "(SELECT COUNT(*) FROM dbo.t_absensi14) AS LiveAbs, " & _
                "(SELECT SUM(size * 8.0 / 1024.0) FROM sys.database_files WHERE type=0) AS SizeLive, " & _
                "(SELECT TOP(1) LastMessage FROM dbo.BackupAgentNode WHERE IsPrimary=1 AND IsEnabled=1) AS BackupStatsJson"
            Dim stats As New DataTable()
            Using adapter As New SqlDataAdapter(qryStat,connstringLive)
                adapter.Fill(stats)
            End Using
            Dim r As DataRow=stats.Rows(0)
            Dim liveBio As Long=CLng(r("LiveBio")), liveReg As Long=CLng(r("LiveReg")), liveKrs As Long=CLng(r("LiveKrs")), liveAbs As Long=CLng(r("LiveAbs"))
            Dim sizeLive As Double=If(IsDBNull(r("SizeLive")),0.0,CDbl(r("SizeLive")))
            Dim backupStats=ParseBackupStats(If(IsDBNull(r("BackupStatsJson")),"",r("BackupStatsJson").ToString()))
            Dim arcBio As Long=StatLong(backupStats,"bioRows"),arcReg As Long=StatLong(backupStats,"regRows"),arcKrs As Long=StatLong(backupStats,"krsRows"),arcAbs As Long=StatLong(backupStats,"absRows")
            Dim backupSize As Double=StatDouble(backupStats,"sizeMb")
            Dim hasBackupStats As Boolean=backupStats IsNot Nothing AndAlso backupStats.ContainsKey("bioRows")
            litSizeLive.Text=String.Format("{0:N1} MB",sizeLive)
            litSizeBackup.Text=If(hasBackupStats,String.Format("{0:N1} MB",backupSize),"-")
            litLiveBio.Text=String.Format("{0:N0}",liveBio):litLiveReg.Text=String.Format("{0:N0}",liveReg):litLiveKrs.Text=String.Format("{0:N0}",liveKrs):litLiveAbs.Text=String.Format("{0:N0}",liveAbs)
            litArcBio.Text=If(hasBackupStats,String.Format("{0:N0}",arcBio),"-"):litArcReg.Text=If(hasBackupStats,String.Format("{0:N0}",arcReg),"-"):litArcKrs.Text=If(hasBackupStats,String.Format("{0:N0}",arcKrs),"-"):litArcAbs.Text=If(hasBackupStats,String.Format("{0:N0}",arcAbs),"-")
            litTotalBio.Text=If(hasBackupStats,String.Format("{0:N0}",liveBio+arcBio),"-"):litTotalReg.Text=If(hasBackupStats,String.Format("{0:N0}",liveReg+arcReg),"-"):litTotalKrs.Text=If(hasBackupStats,String.Format("{0:N0}",liveKrs+arcKrs),"-"):litTotalAbs.Text=If(hasBackupStats,String.Format("{0:N0}",liveAbs+arcAbs),"-")
            Dim totalLive As Long=liveBio+liveReg+liveKrs+liveAbs
            Dim totalBackup As Long=arcBio+arcReg+arcKrs+arcAbs
            litLiveCount.Text=String.Format("{0:N0}",totalLive)
            litBackupCount.Text=If(hasBackupStats,String.Format("{0:N0}",totalBackup),"-")
            litTotalCount.Text=If(hasBackupStats,String.Format("{0:N0}",totalLive+totalBackup),"-")
        Catch ex As Exception
            If cnsr.State=ConnectionState.Open Then tutupsr()
            litSizeBackup.Text="Status layanan backup belum tersedia"
        End Try
    End Sub

    Private Function ParseBackupStats(value As String) As Dictionary(Of String,Object)
        If String.IsNullOrWhiteSpace(value) OrElse Not value.TrimStart().StartsWith("{") Then Return Nothing
        Try
            Return New JavaScriptSerializer().Deserialize(Of Dictionary(Of String,Object))(value)
        Catch
            Return Nothing
        End Try
    End Function

    Private Function StatLong(stats As Dictionary(Of String,Object),key As String) As Long
        If stats Is Nothing OrElse Not stats.ContainsKey(key) OrElse stats(key) Is Nothing Then Return 0
        Dim result As Long=0:Long.TryParse(stats(key).ToString(),result):Return result
    End Function

    Private Function StatDouble(stats As Dictionary(Of String,Object),key As String) As Double
        If stats Is Nothing OrElse Not stats.ContainsKey(key) OrElse stats(key) Is Nothing Then Return -1
        Try:Return Convert.ToDouble(stats(key),System.Globalization.CultureInfo.InvariantCulture):Catch:Return -1:End Try
    End Function
</script>

<div class="backup-page backup-page-monitoring">
    <div class="backup-page-header">
        <div>
            <span class="backup-page-eyebrow">Pusat kendali</span>
            <h1>Dashboard Backup Data</h1>
        </div>
    </div>
    <asp:Literal ID="litMonitoringMessage" runat="server" />

    <div class="monitor-overview-grid">
        <section class="monitor-panel monitor-service-panel">
            <div class="monitor-panel-heading"><span><i class="fa fa-server"></i> Status Layanan Backup</span><asp:Literal ID="litServiceStatus" runat="server" /></div>
            <dl class="monitor-detail-list">
                <div><dt>Agent utama</dt><dd><asp:Literal ID="litAgentName" runat="server" /></dd></div>
                <div><dt>Heartbeat terakhir</dt><dd><asp:Literal ID="litLastHeartbeat" runat="server" /></dd></div>
                <div class="monitor-detail-wide"><dt>Pesan terakhir agent</dt><dd><asp:Literal ID="litAgentMessage" runat="server" /></dd></div>
            </dl>
        </section>
        <section class="monitor-panel">
            <div class="monitor-panel-heading"><span><i class="fa fa-clock-o"></i> Backup Otomatis</span><asp:Literal ID="litAutomaticStatus" runat="server" /></div>
            <dl class="monitor-detail-list">
                <div><dt>Frekuensi</dt><dd><asp:Literal ID="litAutomaticFrequency" runat="server" /></dd></div>
                <div><dt>Cakupan</dt><dd><asp:Literal ID="litAutomaticScope" runat="server" /></dd></div>
                <div class="monitor-detail-wide"><dt>Jadwal berikutnya</dt><dd><asp:Literal ID="litNextSchedule" runat="server" /></dd></div>
            </dl>
        </section>
    </div>

    <div class="monitor-activity-grid">
        <div class="monitor-activity-card"><i class="fa fa-database"></i><span>Backup terakhir</span><strong><asp:Literal ID="litLastBackup" runat="server" /></strong></div>
        <div class="monitor-activity-card"><i class="fa fa-undo"></i><span>Pemulihan terakhir</span><strong><asp:Literal ID="litLastRestore" runat="server" /></strong></div>
        <div class="monitor-activity-card"><i class="fa fa-file-archive-o"></i><span>Ekspor terakhir</span><strong><asp:Literal ID="litLastExport" runat="server" /></strong></div>
    </div>

    <div class="panel panel-default monitor-active-panel">
        <div class="panel-heading backup-u-043"><span><i class="fa fa-refresh"></i> Proses Sedang Berjalan</span><span class="monitor-count"><asp:Literal ID="litActiveProcessCount" runat="server" /> proses</span></div>
        <div class="table-responsive">
            <asp:GridView ID="gvActiveDashboard" runat="server" AutoGenerateColumns="false" CssClass="table table-striped table-hover" GridLines="None" EmptyDataText="Tidak ada proses yang sedang berjalan.">
                <Columns>
                    <asp:BoundField DataField="CreatedAt" HeaderText="Dibuat" DataFormatString="{0:dd MMM yyyy HH:mm}" />
                    <asp:BoundField DataField="OperationLabel" HeaderText="Operasi" />
                    <asp:BoundField DataField="StatusLabel" HeaderText="Status" />
                    <asp:BoundField DataField="ProgressLabel" HeaderText="Diproses" />
                    <asp:BoundField DataField="ProgressMessage" HeaderText="Keterangan" NullDisplayText="-" />
                </Columns>
            </asp:GridView>
        </div>
    </div>


    <!-- DATABASE SIZE CARDS -->
    <div class="row backup-u-057">
        <!-- CARD 1: DATABASE AKTIF STATS -->
        <div class="col-md-6 col-sm-6 col-xs-12 backup-u-063">
            <div class="card backup-u-008">
                <div class="backup-u-078">
                    <i class="fa fa-database backup-u-038"></i>
                </div>
                <div class="backup-u-030">
                    <span class="backup-u-033">Database Aktif</span>
                    <h3 class="backup-u-044"><asp:Literal ID="litSizeLive" runat="server" /></h3>
                </div>
            </div>
        </div>

        <!-- CARD 2: DATABASE BACKUP STATS -->
        <div class="col-md-6 col-sm-6 col-xs-12 backup-u-063">
            <div class="card backup-u-009">
                <div class="backup-u-079">
                    <i class="fa fa-database backup-u-039"></i>
                </div>
                <div class="backup-u-030">
                    <span class="backup-u-033">Database Backup</span>
                    <h3 class="backup-u-044"><asp:Literal ID="litSizeBackup" runat="server" /></h3>
                </div>
            </div>
        </div>

    </div>

    <!-- TABLE COMPARISON row counts -->
    <div class="panel panel-default backup-u-016">
        <div class="panel-heading backup-u-004">
            <i class="fa fa-table text-primary backup-u-067"></i>Perbandingan Jumlah Baris Fisik per Tabel
        </div>
        <div class="table-responsive">
            <table class="table table-hover table-striped backup-u-059">
                <thead>
                    <tr class="backup-u-002">
                        <th>Nama Tabel Modul</th>
                        <th class="text-center backup-u-019">Database Aktif</th>
                        <th class="text-center backup-u-022">Database Backup</th>
                        <th class="text-center backup-u-048">Total Fisik</th>
                    </tr>
                </thead>
                <tbody>
                    <tr>
                        <td class="backup-u-040"><i class="fa fa-user-circle text-primary me-2"></i> Biodata Mahasiswa <span class="backup-u-031">(tbio01)</span></td>
                        <td class="text-center font-bold backup-u-020"><asp:Literal ID="litLiveBio" runat="server" /></td>
                        <td class="text-center backup-u-022"><asp:Literal ID="litArcBio" runat="server" /></td>
                        <td class="text-center backup-u-048"><asp:Literal ID="litTotalBio" runat="server" /></td>
                    </tr>
                    <tr>
                        <td class="backup-u-040"><i class="fa fa-file-text-o text-warning me-2"></i> Registrasi Semester <span class="backup-u-031">(treg)</span></td>
                        <td class="text-center font-bold backup-u-020"><asp:Literal ID="litLiveReg" runat="server" /></td>
                        <td class="text-center backup-u-022"><asp:Literal ID="litArcReg" runat="server" /></td>
                        <td class="text-center backup-u-048"><asp:Literal ID="litTotalReg" runat="server" /></td>
                    </tr>
                    <tr>
                        <td class="backup-u-040"><i class="fa fa-list-alt text-info me-2"></i> Kartu Rencana Studi <span class="backup-u-031">(tkrs06)</span></td>
                        <td class="text-center font-bold backup-u-020"><asp:Literal ID="litLiveKrs" runat="server" /></td>
                        <td class="text-center backup-u-022"><asp:Literal ID="litArcKrs" runat="server" /></td>
                        <td class="text-center backup-u-048"><asp:Literal ID="litTotalKrs" runat="server" /></td>
                    </tr>
                    <tr>
                        <td class="backup-u-040"><i class="fa fa-calendar-check-o text-success me-2"></i> Absensi Perkuliahan <span class="backup-u-031">(t_absensi14)</span></td>
                        <td class="text-center font-bold backup-u-020"><asp:Literal ID="litLiveAbs" runat="server" /></td>
                        <td class="text-center backup-u-022"><asp:Literal ID="litArcAbs" runat="server" /></td>
                        <td class="text-center backup-u-048"><asp:Literal ID="litTotalAbs" runat="server" /></td>
                    </tr>
                </tbody>
            </table>
        </div>
    </div>

    <!-- ROW COUNT REDUCTION PROGRESS PANEL (AGGREGATED SUMMARY) -->
    <div class="panel panel-default backup-u-018">
        <h4 class="backup-u-053">
            <i class="fa fa-pie-chart text-danger backup-u-067"></i>Ringkasan Jumlah Baris Fisik
        </h4>
        
        <div class="row text-center backup-u-064">
            <div class="col-md-4 col-sm-4 col-xs-12 backup-u-060">
                <span class="backup-u-035">Total Seluruh Baris Live</span>
                <h2 class="backup-u-046"><asp:Literal ID="litLiveCount" runat="server" /></h2>
            </div>
            <div class="col-md-4 col-sm-4 col-xs-12 backup-u-060">
                <span class="backup-u-035">Total Seluruh Baris Backup</span>
                <h2 class="backup-u-047"><asp:Literal ID="litBackupCount" runat="server" /></h2>
            </div>
            <div class="col-md-4 col-sm-4 col-xs-12 backup-u-060">
                <span class="backup-u-035">Total Fisik Aktif + Backup</span>
                <h2 class="backup-u-045"><asp:Literal ID="litTotalCount" runat="server" /></h2>
            </div>
        </div>

    </div>

</div>
