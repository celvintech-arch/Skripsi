<!-- #INCLUDE file ="con_backup.ascx" -->
<%@ Import Namespace="System.Data" %>
<%@ Import Namespace="System.Data.SqlClient" %>
<%@ Import Namespace="System.Collections.Generic" %>
<%@ Import Namespace="System.Web.Script.Serialization" %>

<script runat="server">
    Protected IsStaffDashboard As Boolean = False

    Protected Sub Page_Load(ByVal sender As Object, ByVal e As EventArgs)
        RequireBackupReportAccess()
        IsStaffDashboard = IsBackupStaff()
        If Not IsPostBack Then
            LoadMonitoringOverview()
            LoadDatabaseStats()
            LoadInventorySummary()
        End If
    End Sub

    Private Sub LoadMonitoringOverview()
        Try
            Dim serviceState=ReadBackupServiceState()
            litServiceStatus.Text="<span class='monitor-status monitor-status-" & serviceState.CssClass & "'><i class='fa " & If(serviceState.IsReady,"fa-check-circle","fa-exclamation-circle") & "'></i>" & Server.HtmlEncode(serviceState.StatusText) & "</span>"
            litAgentName.Text=Server.HtmlEncode(serviceState.AgentName)
            litLastHeartbeat.Text=If(serviceState.LastSeenAt.HasValue,serviceState.LastSeenAt.Value.ToString("dd MMM yyyy HH:mm:ss"),"Belum pernah terhubung")
            pnlAgentMessage.Visible=Not serviceState.IsReady
            litAgentMessage.Text=If(serviceState.IsReady,"",Server.HtmlEncode(serviceState.LastMessage))

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
            If active.Rows.Count>0 Then litDashboardRefresh.Text="<script>window.setTimeout(function(){window.location.replace('index.aspx?tab=dashboard&poll='+Date.now());},10000);</" & "script>"
        Catch ex As Exception
            litMonitoringMessage.Text="<div class='alert alert-warning'><strong>Ringkasan pemantauan belum dapat dimuat.</strong> " & Server.HtmlEncode(BackupErrorMessage(ex)) & "</div>"
            litServiceStatus.Text="<span class='monitor-status monitor-status-danger'>Belum siap</span>"
            litAgentName.Text="-":litLastHeartbeat.Text="-":litAgentMessage.Text="Status belum tersedia.":pnlAgentMessage.Visible=True
            litAutomaticStatus.Text="<span class='monitor-status monitor-status-neutral'>-</span>":litAutomaticFrequency.Text="-":litAutomaticScope.Text="-":litNextSchedule.Text="-"
            litLastBackup.Text="-":litLastRestore.Text="-":litLastExport.Text="-":litActiveProcessCount.Text="0"
            litDashboardRefresh.Text=""
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
            ' Statistik fisik memakai metadata partisi, tanpa scan seluruh tabel pada setiap polling.
            Dim qryStat As String = ";WITH PhysicalRows AS (" & _
                "SELECT o.name,SUM(CONVERT(bigint,p.rows)) [RowCount] FROM sys.partitions p " & _
                "JOIN sys.objects o ON o.object_id=p.object_id WHERE o.schema_id=SCHEMA_ID('dbo') " & _
                "AND o.type='U' AND p.index_id IN(0,1) AND o.name IN('tbio01','treg','tkrs06','t_absensi14') GROUP BY o.name) SELECT " & _
                "COALESCE((SELECT [RowCount] FROM PhysicalRows WHERE name='tbio01'),0) AS LiveBio, " & _
                "COALESCE((SELECT [RowCount] FROM PhysicalRows WHERE name='treg'),0) AS LiveReg, " & _
                "COALESCE((SELECT [RowCount] FROM PhysicalRows WHERE name='tkrs06'),0) AS LiveKrs, " & _
                "COALESCE((SELECT [RowCount] FROM PhysicalRows WHERE name='t_absensi14'),0) AS LiveAbs, " & _
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
            litSizeLive.Text=FormatDatabaseSize(sizeLive)
            litSizeBackup.Text=If(hasBackupStats AndAlso backupSize >= 0, FormatDatabaseSize(backupSize), "-")
            litLiveBio.Text=String.Format("{0:N0}",liveBio):litLiveReg.Text=String.Format("{0:N0}",liveReg):litLiveKrs.Text=String.Format("{0:N0}",liveKrs):litLiveAbs.Text=String.Format("{0:N0}",liveAbs)
            litArcBio.Text=If(hasBackupStats,String.Format("{0:N0}",arcBio),"-"):litArcReg.Text=If(hasBackupStats,String.Format("{0:N0}",arcReg),"-"):litArcKrs.Text=If(hasBackupStats,String.Format("{0:N0}",arcKrs),"-"):litArcAbs.Text=If(hasBackupStats,String.Format("{0:N0}",arcAbs),"-")
            litTotalBio.Text=If(hasBackupStats,String.Format("{0:N0}",liveBio+arcBio),"-"):litTotalReg.Text=If(hasBackupStats,String.Format("{0:N0}",liveReg+arcReg),"-"):litTotalKrs.Text=If(hasBackupStats,String.Format("{0:N0}",liveKrs+arcKrs),"-"):litTotalAbs.Text=If(hasBackupStats,String.Format("{0:N0}",liveAbs+arcAbs),"-")
            Dim totalLive As Long=liveBio+liveReg+liveKrs+liveAbs
            Dim totalBackup As Long=arcBio+arcReg+arcKrs+arcAbs
            litLiveCount.Text=String.Format("{0:N0}",totalLive)
            litBackupCount.Text=If(hasBackupStats,String.Format("{0:N0}",totalBackup),"-")
            litTotalCount.Text=If(hasBackupStats,String.Format("{0:N0}",totalLive+totalBackup),"-")
        Catch ex As Exception
            System.Diagnostics.Trace.TraceError("Backup Data dashboard statistics: {0}",ex)
            litSizeLive.Text="-":litSizeBackup.Text="-"
            litLiveBio.Text="-":litLiveReg.Text="-":litLiveKrs.Text="-":litLiveAbs.Text="-"
            litArcBio.Text="-":litArcReg.Text="-":litArcKrs.Text="-":litArcAbs.Text="-"
            litTotalBio.Text="-":litTotalReg.Text="-":litTotalKrs.Text="-":litTotalAbs.Text="-"
            litLiveCount.Text="-":litBackupCount.Text="-":litTotalCount.Text="-"
            litMonitoringMessage.Text &= "<div class='alert alert-warning'>Statistik database belum dapat dimuat. Silakan muat ulang halaman.</div>"
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

    Private Function FormatDatabaseSize(sizeMb As Double) As String
        If sizeMb < 0 Then Return "-"
        If sizeMb >= 1000.0 Then
            Return String.Format("{0:N2} GB", sizeMb / 1024.0)
        Else
            Return String.Format("{0:N1} MB", sizeMb)
        End If
    End Function

    Private Function GetInventorySummary() As DataTable
        Dim data As New DataTable()
        Dim sql As String = "SELECT p.ThAkdk, p.StudentCount AS BackupStudents, ISNULL(p.LiveStudentCount,0) AS LiveStudentCount, p.LatestStudentCount, ISNULL(p.VerificationStatus,'UNVERIFIED') AS VerificationStatus, p.VerifiedAt, p.UpdatedAt FROM dbo.BackupAgentPeriodInventory p JOIN dbo.BackupAgentNode a ON a.AgentId=p.AgentId WHERE a.IsPrimary=1 AND a.IsEnabled=1 ORDER BY p.ThAkdk DESC"
        Using cn As New SqlConnection(connstringLive)
            Using cmd As New SqlCommand(sql, cn)
                Using ad As New SqlDataAdapter(cmd)
                    ad.Fill(data)
                End Using
            End Using
        End Using
        Return data
    End Function

    Private Sub LoadInventorySummary()
        Dim data = GetInventorySummary()
        If gvPeriodInventory.AllowPaging AndAlso data.Rows.Count > 0 Then
            Dim maxPage = (data.Rows.Count - 1) \ gvPeriodInventory.PageSize
            If gvPeriodInventory.PageIndex > maxPage Then
                gvPeriodInventory.PageIndex = maxPage
            End If
        End If
        gvPeriodInventory.DataSource = data
        gvPeriodInventory.DataBind()
        lblInventoryCount.Text = data.Rows.Count.ToString("N0") & " periode TA"
    End Sub

    Protected Sub gvPeriodInventory_PageIndexChanging(sender As Object, e As GridViewPageEventArgs)
        gvPeriodInventory.PageIndex = e.NewPageIndex
        LoadInventorySummary()
    End Sub

    Protected Sub btnCheckVerification_Click(sender As Object, e As EventArgs)
        Try
            Using cn As New SqlConnection(connstringLive)
                Using cmd As New SqlCommand("dbo.sp_VerifyBackupPeriodInventory", cn)
                    cmd.CommandType = CommandType.StoredProcedure
                    cmd.Parameters.Add("@ThAkdk", SqlDbType.Char, 5).Value = DBNull.Value
                    cn.Open()
                    cmd.ExecuteNonQuery()
                End Using
            End Using
            LoadInventorySummary()
            litMonitoringMessage.Text = "<div class='alert alert-info alert-dismissible'><button type='button' class='close' data-dismiss='alert' aria-label='Close'><span aria-hidden='true'>&times;</span></button><i class='fa fa-check-circle'></i> <strong>Verifikasi Selesai.</strong> Data inventaris per periode telah diperiksa terhadap data aktif database saat ini.</div>"
        Catch ex As Exception
            litMonitoringMessage.Text = "<div class='alert alert-danger alert-dismissible'><button type='button' class='close' data-dismiss='alert' aria-label='Close'><span aria-hidden='true'>&times;</span></button><strong>Gagal verifikasi data:</strong> " & Server.HtmlEncode(BackupErrorMessage(ex)) & "</div>"
        End Try
    End Sub

    Protected Sub gvPeriodInventory_RowCommand(sender As Object, e As GridViewCommandEventArgs)
        Dim targetTa As String = Convert.ToString(e.CommandArgument).Trim()
        If String.IsNullOrWhiteSpace(targetTa) Then Return

        If e.CommandName = "SyncPeriod" Then
            Try
                If Not IsBackupStaff() Then
                    Throw New ApplicationException("Hanya staf operator backup yang berhak menjalankan sinkronisasi data.")
                End If
                EnsureBackupServiceReady(ReadBackupServiceState(), "Sinkronisasi backup")
                Using cn As New SqlConnection(connstringLive)
                    Using cmd As New SqlCommand("dbo.sp_CreateBackupTransferJob", cn)
                        cmd.CommandType = CommandType.StoredProcedure
                        cmd.Parameters.Add("@CutoffThAkdk", SqlDbType.Char, 5).Value = targetTa
                        cmd.Parameters.Add("@RequestedBy", SqlDbType.VarChar, 50).Value = BackupRequestedBy()
                        cmd.Parameters.Add("@TriggerSource", SqlDbType.VarChar, 10).Value = "MANUAL"
                        cmd.Parameters.Add("@SelectionMode", SqlDbType.VarChar, 10).Value = "SINGLE"
                        cmd.Parameters.Add("@StartThAkdk", SqlDbType.Char, 5).Value = DBNull.Value
                        cmd.Parameters.Add("@SelectedTables", SqlDbType.VarChar, 100).Value = "tbio01,treg,tkrs06,t_absensi14"
                        cn.Open()
                        Using rd = cmd.ExecuteReader()
                            If Not rd.Read() Then Throw New ApplicationException("Pembuatan job sinkronisasi tidak menghasilkan status.")
                        End Using
                    End Using
                End Using
                LoadMonitoringOverview()
                LoadInventorySummary()
                litMonitoringMessage.Text = "<div class='alert alert-success alert-dismissible'><button type='button' class='close' data-dismiss='alert' aria-label='Close'><span aria-hidden='true'>&times;</span></button><i class='fa fa-check-circle'></i> <strong>Job Sinkronisasi Backup Berhasil Dibuat!</strong> Antrean backup untuk Tahun Akademik <strong>" & Server.HtmlEncode(targetTa) & "</strong> telah berhasil dibuat. Agent akan memproses data.</div>"
            Catch ex As Exception
                litMonitoringMessage.Text = "<div class='alert alert-danger alert-dismissible'><button type='button' class='close' data-dismiss='alert' aria-label='Close'><span aria-hidden='true'>&times;</span></button><strong>Sinkronisasi Gagal:</strong> " & Server.HtmlEncode(BackupErrorMessage(ex)) & "</div>"
            End Try
        ElseIf e.CommandName = "RestorePeriod" Then
            Try
                If Not IsBackupStaff() Then
                    Throw New ApplicationException("Hanya staf operator backup yang berhak menjalankan pemulihan data.")
                End If
                EnsureBackupServiceReady(ReadBackupServiceState(), "Pemulihan data")
                Using cn As New SqlConnection(connstringLive)
                    Using cmd As New SqlCommand("dbo.sp_CreateRestoreTransferJob", cn)
                        cmd.CommandType = CommandType.StoredProcedure
                        cmd.Parameters.Add("@StudentNim", SqlDbType.Char, 9).Value = DBNull.Value
                        cmd.Parameters.Add("@ThAkdkList", SqlDbType.NVarChar, -1).Value = targetTa
                        cmd.Parameters.Add("@RequestedBy", SqlDbType.VarChar, 50).Value = BackupRequestedBy()
                        cmd.Parameters.Add("@ExpectedStudents", SqlDbType.Int).Value = DBNull.Value
                        cmd.Parameters.Add("@SelectedTables", SqlDbType.VarChar, 100).Value = "tbio01,treg,tkrs06,t_absensi14"
                        cn.Open()
                        Using rd = cmd.ExecuteReader()
                            If Not rd.Read() Then Throw New ApplicationException("Pembuatan job pemulihan tidak menghasilkan status.")
                        End Using
                    End Using
                End Using
                LoadMonitoringOverview()
                LoadInventorySummary()
                litMonitoringMessage.Text = "<div class='alert alert-success alert-dismissible'><button type='button' class='close' data-dismiss='alert' aria-label='Close'><span aria-hidden='true'>&times;</span></button><i class='fa fa-check-circle'></i> <strong>Job Pemulihan Berhasil Dibuat!</strong> Antrean pemulihan data untuk Tahun Akademik <strong>" & Server.HtmlEncode(targetTa) & "</strong> telah berhasil dibuat. Agent akan memulihkan data ke database aktif.</div>"
            Catch ex As Exception
                litMonitoringMessage.Text = "<div class='alert alert-danger alert-dismissible'><button type='button' class='close' data-dismiss='alert' aria-label='Close'><span aria-hidden='true'>&times;</span></button><strong>Pemulihan Gagal:</strong> " & Server.HtmlEncode(BackupErrorMessage(ex)) & "</div>"
            End Try
        End If
    End Sub

    Private Function VerificationBadge(statusObj As Object, verifiedAtObj As Object) As String
        Dim status As String = If(statusObj Is Nothing OrElse IsDBNull(statusObj), "UNVERIFIED", statusObj.ToString().Trim().ToUpperInvariant())
        Dim tooltip As String = ""
        If verifiedAtObj IsNot Nothing AndAlso Not IsDBNull(verifiedAtObj) Then
            tooltip = " title='Diverifikasi: " & CDate(verifiedAtObj).ToString("dd MMM yyyy HH:mm") & "'"
        End If
        Select Case status
            Case "VERIFIED"
                Return "<span class='label label-success'" & tooltip & "><i class='fa fa-check-circle'></i> Sesuai</span>"
            Case "ARCHIVED"
                Return "<span class='label label-info'" & tooltip & "><i class='fa fa-archive'></i> Terarsip</span>"
            Case "MISMATCH"
                Return "<span class='label label-danger'" & tooltip & "><i class='fa fa-exclamation-triangle'></i> Selisih</span>"
            Case Else
                Return "<span class='label label-default'" & tooltip & "><i class='fa fa-clock-o'></i> Belum Dicek</span>"
        End Select
    End Function

    Private Function CanSyncBackup(statusObj As Object, liveObj As Object, backupObj As Object) As Boolean
        If Not IsStaffDashboard Then Return False
        Dim status = If(statusObj Is Nothing OrElse IsDBNull(statusObj), "", statusObj.ToString().Trim().ToUpperInvariant())
        Dim liveCount = If(liveObj Is Nothing OrElse IsDBNull(liveObj), 0, Convert.ToInt32(liveObj))
        Dim backupCount = If(backupObj Is Nothing OrElse IsDBNull(backupObj), 0, Convert.ToInt32(backupObj))
        Return (status = "MISMATCH" AndAlso liveCount > backupCount)
    End Function

    Private Function CanRestorePeriod(statusObj As Object, liveObj As Object, backupObj As Object) As Boolean
        If Not IsStaffDashboard Then Return False
        Dim status = If(statusObj Is Nothing OrElse IsDBNull(statusObj), "", statusObj.ToString().Trim().ToUpperInvariant())
        Dim liveCount = If(liveObj Is Nothing OrElse IsDBNull(liveObj), 0, Convert.ToInt32(liveObj))
        Dim backupCount = If(backupObj Is Nothing OrElse IsDBNull(backupObj), 0, Convert.ToInt32(backupObj))
        Return (status = "ARCHIVED") OrElse (status = "MISMATCH" AndAlso backupCount > liveCount)
    End Function

    Private Function RestoreButtonText(liveObj As Object) As String
        Dim liveCount = If(liveObj Is Nothing OrElse IsDBNull(liveObj), 0, Convert.ToInt32(liveObj))
        If liveCount = 0 Then
            Return "<i class='fa fa-history'></i> Pulihkan ke Aktif"
        Else
            Return "<i class='fa fa-history'></i> Pulihkan Selisih"
        End If
    End Function

    Private Function ManagerActionLabel(statusObj As Object, liveObj As Object, backupObj As Object) As String
        If IsStaffDashboard Then Return ""
        Dim status = If(statusObj Is Nothing OrElse IsDBNull(statusObj), "", statusObj.ToString().Trim().ToUpperInvariant())
        Dim liveCount = If(liveObj Is Nothing OrElse IsDBNull(liveObj), 0, Convert.ToInt32(liveObj))
        Dim backupCount = If(backupObj Is Nothing OrElse IsDBNull(backupObj), 0, Convert.ToInt32(backupObj))
        If status = "ARCHIVED" Then
            Return "<span class='text-info small'><i class='fa fa-archive'></i> Data Terarsip</span>"
        ElseIf status = "MISMATCH" Then
            If liveCount > backupCount Then
                Return "<span class='text-danger small'><i class='fa fa-exclamation-triangle'></i> Perlu Backup</span>"
            Else
                Return "<span class='text-danger small'><i class='fa fa-exclamation-triangle'></i> Perlu Pulihkan</span>"
            End If
        End If
        Return ""
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
    <asp:Literal ID="litDashboardRefresh" runat="server" />

    <% If IsStaffDashboard Then %>
    <section class="dashboard-menu-section" aria-labelledby="dashboardOperationalTitle">
        <h2 id="dashboardOperationalTitle">Operasional</h2>
        <nav class="dashboard-quick-menu dashboard-quick-menu-operational" aria-label="Menu operasional Backup Data">
        <a class="dashboard-quick-card dashboard-quick-card-backup" href="index.aspx?tab=backup">
            <span class="dashboard-quick-icon" aria-hidden="true">
                <svg viewBox="0 0 24 24" focusable="false"><ellipse cx="12" cy="5" rx="7" ry="3"></ellipse><path d="M5 5v5c0 1.7 3.1 3 7 3s7-1.3 7-3V5"></path><path d="M5 10v5c0 1.7 3.1 3 7 3s7-1.3 7-3v-5"></path><path d="M5 15v4c0 1.7 3.1 3 7 3s7-1.3 7-3v-4"></path></svg>
            </span>
            <span class="dashboard-quick-content">
                <strong>Backup Data</strong>
            </span>
            <svg class="dashboard-quick-arrow" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="m9 18 6-6-6-6"></path></svg>
        </a>
        <a class="dashboard-quick-card dashboard-quick-card-restore" href="index.aspx?tab=pemulihan">
            <span class="dashboard-quick-icon" aria-hidden="true">
                <svg viewBox="0 0 24 24" focusable="false"><path d="M3 7v6h6"></path><path d="M5.5 17a8 8 0 1 0 .5-10L3 10"></path></svg>
            </span>
            <span class="dashboard-quick-content">
                <strong>Pemulihan Data</strong>
            </span>
            <svg class="dashboard-quick-arrow" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="m9 18 6-6-6-6"></path></svg>
        </a>
        <a class="dashboard-quick-card dashboard-quick-card-export" href="index.aspx?tab=ekspor">
            <span class="dashboard-quick-icon" aria-hidden="true">
                <svg viewBox="0 0 24 24" focusable="false"><ellipse cx="12" cy="5" rx="7" ry="3"></ellipse><path d="M5 5v5c0 1.7 3.1 3 7 3 1.1 0 2.2-.1 3.1-.3"></path><path d="M5 10v5c0 1.7 3.1 3 7 3"></path><path d="M16 15v6"></path><path d="m13.5 18.5 2.5 2.5 2.5-2.5"></path></svg>
            </span>
            <span class="dashboard-quick-content">
                <strong>Ekspor Database</strong>
            </span>
            <svg class="dashboard-quick-arrow" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="m9 18 6-6-6-6"></path></svg>
        </a>
        <a class="dashboard-quick-card dashboard-quick-card-users" href="index.aspx?tab=operator">
            <span class="dashboard-quick-icon" aria-hidden="true">
                <svg viewBox="0 0 24 24" focusable="false"><circle cx="9" cy="8" r="3"></circle><path d="M3.5 19c.5-3.2 2.4-5 5.5-5s5 1.8 5.5 5"></path><circle cx="17" cy="9" r="2.5"></circle><path d="M15.5 14.5c2.8-.7 5 .9 5.5 3.5"></path></svg>
            </span>
            <span class="dashboard-quick-content">
                <strong>Pengelola Pengguna</strong>
            </span>
            <svg class="dashboard-quick-arrow" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="m9 18 6-6-6-6"></path></svg>
        </a>
        </nav>
    </section>
    <% End If %>

    <section class="dashboard-menu-section dashboard-monitoring-menu-section" aria-labelledby="dashboardMonitoringTitle">
        <h2 id="dashboardMonitoringTitle">Pemantauan</h2>
        <nav class="dashboard-quick-menu dashboard-quick-menu-monitoring" aria-label="Menu pemantauan Backup Data">
        <a class="dashboard-quick-card" href="index.aspx?tab=summary">
            <span class="dashboard-quick-icon" aria-hidden="true">
                <svg viewBox="0 0 24 24" focusable="false"><path d="M4 20V10"></path><path d="M10 20V4"></path><path d="M16 20v-7"></path><path d="M22 20H2"></path></svg>
            </span>
            <span class="dashboard-quick-content">
                <strong>Laporan</strong>
            </span>
            <svg class="dashboard-quick-arrow" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="m9 18 6-6-6-6"></path></svg>
        </a>
        <% If IsStaffDashboard Then %>
        <a class="dashboard-quick-card" href="index.aspx?tab=riwayat">
            <span class="dashboard-quick-icon" aria-hidden="true">
                <svg viewBox="0 0 24 24" focusable="false"><path d="M3 12a9 9 0 1 0 3-6.7L3 8"></path><path d="M3 3v5h5"></path><path d="M12 7v5l3 2"></path></svg>
            </span>
            <span class="dashboard-quick-content">
                <strong>Riwayat Proses</strong>
            </span>
            <svg class="dashboard-quick-arrow" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="m9 18 6-6-6-6"></path></svg>
        </a>
        <% End If %>
        </nav>
    </section>

    <div class="monitor-overview-grid">
        <section class="monitor-panel monitor-service-panel">
            <div class="monitor-panel-heading"><span><i class="fa fa-server"></i> Status Layanan Backup</span><asp:Literal ID="litServiceStatus" runat="server" /></div>
            <dl class="monitor-detail-list">
                <div><dt>Agent utama</dt><dd><asp:Literal ID="litAgentName" runat="server" /></dd></div>
                <div><dt>Heartbeat terakhir</dt><dd><asp:Literal ID="litLastHeartbeat" runat="server" /></dd></div>
                <asp:Panel ID="pnlAgentMessage" runat="server" CssClass="monitor-detail-wide"><dt>Pesan terakhir agent</dt><dd><asp:Literal ID="litAgentMessage" runat="server" /></dd></asp:Panel>
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
        <div class="monitor-activity-card"><i class="fa fa-file-o"></i><span>Ekspor terakhir</span><strong><asp:Literal ID="litLastExport" runat="server" /></strong></div>
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
                        <td class="backup-u-040"><i class="fa fa-user text-primary me-2"></i> Biodata</td>
                        <td class="text-center font-bold backup-u-020"><asp:Literal ID="litLiveBio" runat="server" /></td>
                        <td class="text-center backup-u-022"><asp:Literal ID="litArcBio" runat="server" /></td>
                        <td class="text-center backup-u-048"><asp:Literal ID="litTotalBio" runat="server" /></td>
                    </tr>
                    <tr>
                        <td class="backup-u-040"><i class="fa fa-file-text-o text-warning me-2"></i> Registrasi</td>
                        <td class="text-center font-bold backup-u-020"><asp:Literal ID="litLiveReg" runat="server" /></td>
                        <td class="text-center backup-u-022"><asp:Literal ID="litArcReg" runat="server" /></td>
                        <td class="text-center backup-u-048"><asp:Literal ID="litTotalReg" runat="server" /></td>
                    </tr>
                    <tr>
                        <td class="backup-u-040"><i class="fa fa-list-alt text-info me-2"></i> KRS</td>
                        <td class="text-center font-bold backup-u-020"><asp:Literal ID="litLiveKrs" runat="server" /></td>
                        <td class="text-center backup-u-022"><asp:Literal ID="litArcKrs" runat="server" /></td>
                        <td class="text-center backup-u-048"><asp:Literal ID="litTotalKrs" runat="server" /></td>
                    </tr>
                    <tr>
                        <td class="backup-u-040"><i class="fa fa-calendar-check-o text-success me-2"></i> Absensi</td>
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

    <!-- PUSAT REKONSILIASI & SINKRONISASI DATA PER PERIODE -->
    <div class="panel panel-default">
        <div class="panel-heading backup-u-043">
            <div>
                <i class="fa fa-balance-scale text-primary backup-u-067"></i>
                <span class="font-bold">Pusat Rekonsiliasi &amp; Sinkronisasi Data per Periode</span>
                <asp:Label ID="lblInventoryCount" runat="server" CssClass="text-muted" />
            </div>
            <div>
                <asp:LinkButton ID="btnCheckVerification" runat="server" CssClass="btn btn-default btn-xs" OnClick="btnCheckVerification_Click" ToolTip="Cek ulang kesesuaian data backup terhadap data aktif saat ini">
                    <i class="fa fa-refresh"></i> Cek Verifikasi Sekarang
                </asp:LinkButton>
            </div>
        </div>
        <div class="table-responsive">
            <asp:GridView ID="gvPeriodInventory" runat="server" AutoGenerateColumns="false" CssClass="table table-striped table-hover" GridLines="None" EmptyDataText="Data inventaris per periode belum tersedia."
                AllowPaging="true" PageSize="10"
                OnPageIndexChanging="gvPeriodInventory_PageIndexChanging"
                OnRowCommand="gvPeriodInventory_RowCommand"
                PagerSettings-Mode="NumericFirstLast"
                PagerSettings-FirstPageText="Awal"
                PagerSettings-LastPageText="Akhir"
                PagerStyle-CssClass="customPager"
                PagerStyle-HorizontalAlign="Center">
                <Columns>
                    <asp:BoundField DataField="ThAkdk" HeaderText="Tahun Akademik" ItemStyle-Font-Bold="true" />
                    <asp:BoundField DataField="BackupStudents" HeaderText="Mahasiswa pada Backup" DataFormatString="{0:N0}" ItemStyle-HorizontalAlign="Right" HeaderStyle-CssClass="text-right" />
                    <asp:BoundField DataField="LiveStudentCount" HeaderText="Mahasiswa Data Aktif" DataFormatString="{0:N0}" ItemStyle-HorizontalAlign="Right" HeaderStyle-CssClass="text-right" />
                    <asp:TemplateField HeaderText="Status Verifikasi" ItemStyle-HorizontalAlign="Center" HeaderStyle-CssClass="text-center">
                        <ItemTemplate>
                            <%# VerificationBadge(Eval("VerificationStatus"), Eval("VerifiedAt")) %>
                        </ItemTemplate>
                    </asp:TemplateField>
                    <asp:BoundField DataField="UpdatedAt" HeaderText="Sinkronisasi Terakhir" DataFormatString="{0:dd MMM yyyy HH:mm:ss}" ItemStyle-HorizontalAlign="Center" HeaderStyle-CssClass="text-center" />
                    <asp:TemplateField HeaderText="Tindakan" ItemStyle-HorizontalAlign="Center" HeaderStyle-CssClass="text-center">
                        <ItemTemplate>
                            <asp:LinkButton ID="btnSyncPeriod" runat="server"
                                CommandName="SyncPeriod"
                                CommandArgument='<%# Eval("ThAkdk") %>'
                                CssClass="btn btn-xs btn-warning"
                                Visible='<%# CanSyncBackup(Eval("VerificationStatus"), Eval("LiveStudentCount"), Eval("BackupStudents")) %>'
                                data-ta='<%# Eval("ThAkdk") %>'
                                OnClientClick="return confirmSyncPeriod(this);"
                                ToolTip="Jalankan job backup untuk menyalin data aktif baru ke database backup">
                                <i class="fa fa-refresh"></i> Sinkronkan Backup
                            </asp:LinkButton>
                            <asp:LinkButton ID="btnRestorePeriod" runat="server"
                                CommandName="RestorePeriod"
                                CommandArgument='<%# Eval("ThAkdk") %>'
                                CssClass="btn btn-xs btn-success"
                                Visible='<%# CanRestorePeriod(Eval("VerificationStatus"), Eval("LiveStudentCount"), Eval("BackupStudents")) %>'
                                data-ta='<%# Eval("ThAkdk") %>'
                                data-students='<%# Eval("BackupStudents") %>'
                                OnClientClick="return confirmRestorePeriod(this);"
                                ToolTip="Pulihkan data mahasiswa dari Database Backup ke Database Aktif">
                                <%# RestoreButtonText(Eval("LiveStudentCount")) %>
                            </asp:LinkButton>
                            <asp:Label ID="lblVerified" runat="server"
                                CssClass="text-success small"
                                Visible='<%# Eval("VerificationStatus").ToString() = "VERIFIED" %>'>
                                <i class="fa fa-check"></i> Sesuai
                            </asp:Label>
                            <asp:Literal ID="litManagerStatus" runat="server"
                                Text='<%# ManagerActionLabel(Eval("VerificationStatus"), Eval("LiveStudentCount"), Eval("BackupStudents")) %>' />
                        </ItemTemplate>
                    </asp:TemplateField>
                </Columns>
            </asp:GridView>
        </div>
    </div>

</div>

<script type="text/javascript">
function confirmSyncPeriod(button) {
    var thAkdk = (button && button.getAttribute("data-ta")) || "";
    return backupConfirm(button, "Jalankan job sinkronisasi backup untuk Tahun Akademik " + thAkdk + "? Sistem akan membuat antrean backup data mahasiswa dari database aktif.", {
        title: "Konfirmasi Sinkronisasi TA " + thAkdk,
        confirmText: "Ya, Sinkronkan",
        confirmColor: "#f39c12",
        icon: "warning"
    });
}
function confirmRestorePeriod(button) {
    var thAkdk = (button && button.getAttribute("data-ta")) || "";
    var students = (button && button.getAttribute("data-students")) || "";
    var studentInfo = students ? " (" + students + " mahasiswa pada backup)" : "";
    return backupConfirm(button, "Pulihkan data Tahun Akademik " + thAkdk + studentInfo + " dari Database Backup ke Database Aktif? Data yang sudah ada di database aktif tidak akan ditimpa.", {
        title: "Konfirmasi Pemulihan TA " + thAkdk,
        confirmText: "Ya, Pulihkan ke Aktif",
        confirmColor: "#00a65a",
        icon: "question"
    });
}
</script>
