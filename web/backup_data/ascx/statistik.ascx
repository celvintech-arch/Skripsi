<!-- #INCLUDE file ="con_backup.ascx" -->
<%@ Import Namespace="System.Data" %>
<%@ Import Namespace="System.Data.SqlClient" %>
<%@ Import Namespace="System.Collections.Generic" %>
<%@ Import Namespace="System.Web.Script.Serialization" %>

<script runat="server">
    Protected Sub Page_Load(ByVal sender As Object, ByVal e As EventArgs)
        RequireBackupReportAccess()
        If Not IsPostBack Then
            LoadDatabaseStats()
        End If
    End Sub

    Protected Sub btnUjiUlang_Click(ByVal sender As Object, ByVal e As EventArgs)
        LoadDatabaseStats()
    End Sub

    Private Sub LoadDatabaseStats()
        Try
            Dim qryStat As String = "SELECT " & _
                "(SELECT COUNT(*) FROM dbo.tbio01) AS LiveBio, " & _
                "(SELECT COUNT(*) FROM dbo.treg) AS LiveReg, " & _
                "(SELECT COUNT(*) FROM dbo.tkrs06) AS LiveKrs, " & _
                "(SELECT COUNT(*) FROM dbo.t_absensi14) AS LiveAbs, " & _
                "(SELECT SUM(size * 8.0 / 1024.0) FROM sys.database_files WHERE type=0) AS SizeLive, " & _
                "(SELECT COUNT(*) FROM dbo.BackupAgentNode WHERE IsEnabled=1 AND LastDatabaseReady=1 AND LastSeenAt>=DATEADD(MINUTE,-10,SYSDATETIME())) AS ReadyAgents, " & _
                "(SELECT MAX(UpdatedAt) FROM dbo.BackupAgentPeriodInventory) AS InventoryUpdated, " & _
                "(SELECT TOP(1) LastMessage FROM dbo.BackupAgentNode WHERE IsPrimary=1 AND IsEnabled=1) AS BackupStatsJson"
            Dim stats As New DataTable()
            Using adapter As New SqlDataAdapter(qryStat,connstringLive)
                adapter.Fill(stats)
            End Using
            Dim r As DataRow=stats.Rows(0)
            Dim liveBio As Long=CLng(r("LiveBio")), liveReg As Long=CLng(r("LiveReg")), liveKrs As Long=CLng(r("LiveKrs")), liveAbs As Long=CLng(r("LiveAbs"))
            Dim sizeLive As Double=If(IsDBNull(r("SizeLive")),0.0,CDbl(r("SizeLive")))
            Dim readyAgents As Integer=Convert.ToInt32(r("ReadyAgents"))
            Dim synced As String=If(IsDBNull(r("InventoryUpdated")),"belum ada inventaris",CType(r("InventoryUpdated"),DateTime).ToString("dd MMM yyyy HH:mm:ss"))
            Dim backupStats=ParseBackupStats(If(IsDBNull(r("BackupStatsJson")),"",r("BackupStatsJson").ToString()))
            Dim arcBio As Long=StatLong(backupStats,"bioRows"),arcReg As Long=StatLong(backupStats,"regRows"),arcKrs As Long=StatLong(backupStats,"krsRows"),arcAbs As Long=StatLong(backupStats,"absRows")
            Dim backupSize As Double=StatDouble(backupStats,"sizeMb"),backupLatency As Double=StatDouble(backupStats,"lookupLatencyMs"),inconsistencies As Long=StatLong(backupStats,"inconsistencies")
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
            litLatencyBackup.Text=If(hasBackupStats AndAlso backupLatency>=0,String.Format("{0:N2} ms",backupLatency),"-")
            Dim consistencyText=If(hasBackupStats AndAlso inconsistencies=0,"Konsistensi backup: baik.",If(hasBackupStats,"Inkonsistensi relasi backup: " & inconsistencies.ToString("N0") & ".","Statistik backup terstruktur belum diterima."))
            litProgressBar.Text="<div class='alert alert-info backup-u-056'><strong>Catatan perbandingan:</strong> total adalah jumlah baris fisik, bukan mahasiswa unik. NIM dapat berada di database aktif dan backup sehingga tidak boleh dianggap sebagai mahasiswa tambahan. Inventaris terakhir: " & Server.HtmlEncode(synced) & ". " & Server.HtmlEncode(consistencyText) & " Layanan backup siap: " & readyAgents.ToString() & ".</div>"

            Dim inventory As New DataTable()
            Using cmd As New SqlCommand("SELECT p.ThAkdk,ISNULL(l.LiveStudents,0) LiveStudents,p.StudentCount BackupStudents,p.UpdatedAt FROM dbo.BackupAgentPeriodInventory p JOIN dbo.BackupAgentNode a ON a.AgentName=p.AgentName LEFT JOIN (SELECT th_akdk,COUNT(DISTINCT nim1) LiveStudents FROM dbo.treg GROUP BY th_akdk) l ON l.th_akdk=p.ThAkdk WHERE a.IsPrimary=1 AND a.IsEnabled=1 ORDER BY p.ThAkdk DESC",cnsr)
                Using adapter As New SqlDataAdapter(cmd)
                    adapter.Fill(inventory)
                End Using
            End Using
            gvInventory.DataSource=inventory
            gvInventory.DataBind()
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
    <div class="backup-page-header backup-page-header-action">
        <div>
            <span class="backup-page-eyebrow">Pusat kendali</span>
            <h1>Dashboard Backup Data</h1>
        </div>
        <asp:Button ID="btnUjiUlang" runat="server" Text="Refresh Statistik" CssClass="btn btn-default backup-u-041" OnClick="btnUjiUlang_Click" />
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
                    <span class="backup-u-032">Waktu respons pencarian terakhir: <strong><asp:Literal ID="litLatencyBackup" runat="server" /></strong></span>
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

        <asp:Literal ID="litProgressBar" runat="server" />
    </div>

    <div class="panel panel-default backup-u-017">
        <div class="panel-heading backup-u-003">
            <i class="fa fa-list text-primary backup-u-067"></i>Inventaris Backup per Tahun Akademik
        </div>
        <div class="table-responsive">
            <asp:GridView ID="gvInventory" runat="server" AutoGenerateColumns="false" CssClass="table table-striped table-hover" EmptyDataText="Inventaris belum diterima dari Database Backup." GridLines="None">
                <Columns>
                    <asp:BoundField DataField="ThAkdk" HeaderText="Tahun Akademik" />
                    <asp:BoundField DataField="LiveStudents" HeaderText="Mahasiswa Live" DataFormatString="{0:N0}" ItemStyle-HorizontalAlign="Right" />
                    <asp:BoundField DataField="BackupStudents" HeaderText="Mahasiswa Backup" DataFormatString="{0:N0}" ItemStyle-HorizontalAlign="Right" />
                    <asp:BoundField DataField="UpdatedAt" HeaderText="Sinkronisasi Terakhir" DataFormatString="{0:dd MMM yyyy HH:mm:ss}" />
                </Columns>
            </asp:GridView>
        </div>
    </div>
</div>
