<%@ Control Language="VB" ClassName="backup_data_summary_report_control" %>
<!-- #INCLUDE file="con_backup.ascx" -->
<!-- #INCLUDE file="table_helpers.ascx" -->
<!-- #INCLUDE file="pdf_report_writer.ascx" -->

<script runat="server">
Protected Sub Page_Load(sender As Object,e As EventArgs)
 RequireBackupReportAccess()
 Response.Cache.SetCacheability(HttpCacheability.NoCache)
 Response.Cache.SetNoStore()
 If Not IsPostBack Then
  txtStartDate.Text=Date.Today.AddDays(-30).ToString("yyyy-MM-dd")
  txtEndDate.Text=Date.Today.ToString("yyyy-MM-dd")
  LoadAcademicPeriods()
  LoadReport()
 End If
 ApplyDateBounds()
End Sub

Private Sub ApplyDateBounds()
 If Not String.IsNullOrWhiteSpace(txtStartDate.Text) Then
  txtEndDate.Attributes("min") = txtStartDate.Text.Trim()
 End If
 If Not String.IsNullOrWhiteSpace(txtEndDate.Text) Then
  txtStartDate.Attributes("max") = txtEndDate.Text.Trim()
 End If
End Sub

Protected Sub btnApplyReport_Click(sender As Object,e As EventArgs)
 gvReportJobs.PageIndex = 0
 LoadReport()
End Sub

Protected Sub btnExportPdf_Click(sender As Object,e As EventArgs)
 Dim startDate As DateTime,endDate As DateTime
 If Not ReadDateRange(startDate,endDate) Then Return
 Try
  LoadSummary(startDate,endDate)
  Dim jobs=GetJobDetails(startDate,endDate)
  Dim inventory=GetInventorySummary()
  Dim summaryItems As New System.Collections.Generic.List(Of System.Collections.Generic.KeyValuePair(Of String,String))()
  summaryItems.Add(New System.Collections.Generic.KeyValuePair(Of String,String)("Total Proses",litTotalJobs.Text))
  summaryItems.Add(New System.Collections.Generic.KeyValuePair(Of String,String)("Berhasil",litSuccessJobs.Text))
  summaryItems.Add(New System.Collections.Generic.KeyValuePair(Of String,String)("Gagal",litFailedJobs.Text))
  summaryItems.Add(New System.Collections.Generic.KeyValuePair(Of String,String)("Dibatalkan",litCancelledJobs.Text))
  summaryItems.Add(New System.Collections.Generic.KeyValuePair(Of String,String)("Mahasiswa Diproses",litProcessedStudents.Text))
  summaryItems.Add(New System.Collections.Generic.KeyValuePair(Of String,String)("Rata-rata Durasi",litAverageDuration.Text))
  Dim period=startDate.ToString("dd MMM yyyy") & " - " & endDate.ToString("dd MMM yyyy")
  Dim pdf=BackupSummaryPdfWriter.Create(period,ReportFilterDescription(),summaryItems,jobs,inventory)
  Dim fileName="LINTAR_Laporan_Ringkasan_" & DateTime.Now.ToString("yyyyMMdd_HHmmss") & ".pdf"
  Response.Clear()
  Response.Buffer=True
  Response.ContentType="application/pdf"
  Response.AddHeader("Content-Disposition","attachment; filename=" & fileName)
  Response.AddHeader("Content-Length",pdf.Length.ToString())
  Response.BinaryWrite(pdf)
  Response.Flush()
  Response.SuppressContent=True
  HttpContext.Current.ApplicationInstance.CompleteRequest()
 Catch ex As Exception
  litReportMessage.Text="<div class='alert alert-danger'><strong>PDF gagal dibuat.</strong> " & Server.HtmlEncode(BackupErrorMessage(ex)) & "</div>"
 Finally
  tutupsr()
 End Try
End Sub

Private Sub LoadAcademicPeriods()
 ddlAcademicPeriod.Items.Clear()
 ddlAcademicPeriod.Items.Add(New ListItem("Semua Tahun Akademik",""))
 Try
  Using cmd As New SqlCommand("SELECT DISTINCT RTRIM(p.ThAkdk) ThAkdk FROM dbo.BackupAgentPeriodInventory p JOIN dbo.BackupAgentNode a ON a.AgentId=p.AgentId WHERE a.IsPrimary=1 AND a.IsEnabled=1 ORDER BY ThAkdk DESC",cnsr)
   cnsr.Open()
   Using rd=cmd.ExecuteReader()
    While rd.Read()
     Dim value=rd("ThAkdk").ToString().Trim()
     ddlAcademicPeriod.Items.Add(New ListItem(value,value))
    End While
   End Using
  End Using
 Catch ex As Exception
  litReportMessage.Text="<div class='alert alert-warning'><strong>Daftar Tahun Akademik belum tersedia.</strong> " & Server.HtmlEncode(BackupErrorMessage(ex)) & "</div>"
 Finally
  tutupsr()
 End Try
End Sub

Private Function ReadDateRange(ByRef startDate As DateTime,ByRef endDate As DateTime) As Boolean
 Dim format="yyyy-MM-dd",culture=System.Globalization.CultureInfo.InvariantCulture
 If Not DateTime.TryParseExact(txtStartDate.Text.Trim(),format,culture,System.Globalization.DateTimeStyles.None,startDate) OrElse Not DateTime.TryParseExact(txtEndDate.Text.Trim(),format,culture,System.Globalization.DateTimeStyles.None,endDate) Then
  litReportMessage.Text="<div class='alert alert-warning'><strong>Periode tidak valid.</strong> Gunakan tanggal awal dan akhir yang lengkap.</div>"
  Return False
 End If
 If startDate>endDate Then
  litReportMessage.Text="<div class='alert alert-warning'><strong>Periode tidak valid.</strong> Tanggal awal tidak boleh melewati tanggal akhir.</div>"
  Return False
 End If
 If (endDate-startDate).TotalDays>366 Then
  litReportMessage.Text="<div class='alert alert-warning'><strong>Periode terlalu panjang.</strong> Pilih rentang maksimum 366 hari agar laporan tetap ringan.</div>"
  Return False
 End If
 ApplyDateBounds()
 Return True
End Function

Private Sub AddReportParameters(cmd As SqlCommand,startDate As DateTime,endDate As DateTime)
 cmd.Parameters.Add("@StartDate",SqlDbType.DateTime2).Value=startDate
 cmd.Parameters.Add("@EndExclusive",SqlDbType.DateTime2).Value=endDate.AddDays(1)
 cmd.Parameters.Add("@OperationType",SqlDbType.VarChar,10).Value=ddlOperation.SelectedValue
 cmd.Parameters.Add("@Status",SqlDbType.VarChar,20).Value=ddlStatus.SelectedValue
 cmd.Parameters.Add("@TableName",SqlDbType.VarChar,30).Value=ddlTable.SelectedValue
 cmd.Parameters.Add("@ThAkdk",SqlDbType.Char,5).Value=ddlAcademicPeriod.SelectedValue
End Sub

Private Function AcademicScopeFilterSql() As String
 ' Match the stored scope, not just its final academic period.
 Return "(@ThAkdk='' OR " & _
  "(j.OperationType='BACKUP' AND NULLIF(LTRIM(RTRIM(j.StudentNim)),'') IS NULL AND (" & _
  "(j.RestoreThAkdkList LIKE 'SINGLE:[0-9][0-9][0-9][0-9][0-9]' AND SUBSTRING(j.RestoreThAkdkList,8,5)=@ThAkdk) OR " & _
  "(j.RestoreThAkdkList LIKE 'RANGE:[0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9]' AND @ThAkdk BETWEEN SUBSTRING(j.RestoreThAkdkList,7,5) AND SUBSTRING(j.RestoreThAkdkList,13,5)) OR " & _
  "(j.RestoreThAkdkList LIKE 'UP_TO:[0-9][0-9][0-9][0-9][0-9]' AND @ThAkdk<=SUBSTRING(j.RestoreThAkdkList,7,5)) OR " & _
  "(NULLIF(LTRIM(RTRIM(j.RestoreThAkdkList)),'') IS NULL AND @ThAkdk<=j.CutoffThAkdk))) OR " & _
  "(j.OperationType='RESTORE' AND EXISTS (SELECT 1 FROM STRING_SPLIT(ISNULL(j.RestoreThAkdkList,''),',') p WHERE LTRIM(RTRIM(p.value))=@ThAkdk)))"
End Function

Private Function FilterSql() As String
 Return "j.CreatedAt>=@StartDate AND j.CreatedAt<@EndExclusive " & _
  "AND (@OperationType='' OR j.OperationType=@OperationType) " & _
  "AND (@Status='' OR j.Status=@Status) " & _
  "AND (@TableName='' OR ','+j.SelectedTables+',' LIKE '%,'+@TableName+',%') " & _
  "AND " & AcademicScopeFilterSql()
End Function

Private Sub LoadReport()
 litReportMessage.Text=""
 Dim startDate As DateTime,endDate As DateTime
 If Not ReadDateRange(startDate,endDate) Then Return
 Try
  LoadSummary(startDate,endDate)
  LoadJobDetails(startDate,endDate)
  LoadInventorySummary()
  litReportPeriod.Text=startDate.ToString("dd MMM yyyy") & " - " & endDate.ToString("dd MMM yyyy")
 Catch ex As Exception
  litReportMessage.Text="<div class='alert alert-danger'><strong>Laporan gagal dimuat.</strong> " & Server.HtmlEncode(BackupErrorMessage(ex)) & "</div>"
 Finally
  tutupsr()
 End Try
End Sub

Private Sub LoadSummary(startDate As DateTime,endDate As DateTime)
 Dim sql="SELECT COUNT_BIG(*) TotalJobs," & _
  "SUM(CASE WHEN j.Status='SUCCESS' THEN 1 ELSE 0 END) SuccessJobs," & _
  "SUM(CASE WHEN j.Status='FAILED' AND ISNULL(j.ErrorMessage,'') LIKE '[[]CANCELLED]%' THEN 1 ELSE 0 END) CancelledJobs," & _
  "SUM(CASE WHEN j.Status='FAILED' AND ISNULL(j.ErrorMessage,'') NOT LIKE '[[]CANCELLED]%' THEN 1 ELSE 0 END) FailedJobs," & _
   "SUM(CONVERT(BIGINT,j.ProcessedStudents)) ProcessedStudents," & _
   "AVG(CASE WHEN j.StartedAt IS NOT NULL AND j.CompletedAt IS NOT NULL THEN CONVERT(DECIMAL(18,2),DATEDIFF(SECOND,j.StartedAt,j.CompletedAt)) END) AverageSeconds FROM dbo.BackupTransferJob j WHERE " & FilterSql()
 Using cmd As New SqlCommand(sql,cnsr)
  AddReportParameters(cmd,startDate,endDate)
  cnsr.Open()
  Using rd=cmd.ExecuteReader()
   If rd.Read() Then
    litTotalJobs.Text=NumberValue(rd("TotalJobs"))
    litSuccessJobs.Text=NumberValue(rd("SuccessJobs"))
    litFailedJobs.Text=NumberValue(rd("FailedJobs"))
    litCancelledJobs.Text=NumberValue(rd("CancelledJobs"))
    litProcessedStudents.Text=NumberValue(rd("ProcessedStudents"))
    litAverageDuration.Text=If(IsDBNull(rd("AverageSeconds")),"-",FormatDuration(Convert.ToInt64(Math.Round(Convert.ToDouble(rd("AverageSeconds"))))))
   End If
  End Using
 End Using
 cnsr.Close()
End Sub

Private Function GetJobDetails(startDate As DateTime,endDate As DateTime) As DataTable
 Dim data As New DataTable()
 Dim sql="SELECT TOP(100) j.JobId,j.OperationType,j.TriggerSource,j.CutoffThAkdk,j.StudentNim,j.RestoreThAkdkList,j.SelectedTables,j.Status,j.ProcessedStudents,j.TotalStudents,j.RequestedBy,j.CreatedAt,j.StartedAt,j.CompletedAt,j.ErrorMessage FROM dbo.BackupTransferJob j WHERE " & FilterSql() & " ORDER BY j.CreatedAt DESC,j.JobId DESC"
 Using cmd As New SqlCommand(sql,cnsr)
  AddReportParameters(cmd,startDate,endDate)
  Using ad As New SqlDataAdapter(cmd):ad.Fill(data):End Using
 End Using
 data.Columns.Add("OperationLabel",GetType(String))
 data.Columns.Add("StatusLabel",GetType(String))
 data.Columns.Add("ScopeLabel",GetType(String))
 data.Columns.Add("TableLabel",GetType(String))
 data.Columns.Add("DurationLabel",GetType(String))
 For Each row As DataRow In data.Rows
  row("OperationLabel")=OperationText(row("OperationType").ToString())
  row("StatusLabel")=StatusText(row("Status").ToString(),If(row.IsNull("ErrorMessage"),"",row("ErrorMessage").ToString()))
  row("ScopeLabel")=ScopeText(row)
  row("TableLabel")=BackupTableLabels(row("SelectedTables").ToString())
 row("DurationLabel")=If(row.IsNull("StartedAt") OrElse row.IsNull("CompletedAt"),"-",FormatDuration(CLng((CType(row("CompletedAt"),DateTime)-CType(row("StartedAt"),DateTime)).TotalSeconds)))
 Next
 Return data
End Function

Private Sub LoadJobDetails(startDate As DateTime,endDate As DateTime)
 Dim data=GetJobDetails(startDate,endDate)
 If gvReportJobs.AllowPaging AndAlso data.Rows.Count > 0 Then
  Dim maxPage = (data.Rows.Count - 1) \ gvReportJobs.PageSize
  If gvReportJobs.PageIndex > maxPage Then
   gvReportJobs.PageIndex = maxPage
  End If
 End If
 gvReportJobs.DataSource=data
 gvReportJobs.DataBind()
 lblResultCount.Text=data.Rows.Count.ToString("N0") & " proses terbaru"
End Sub

Protected Sub gvReportJobs_PageIndexChanging(sender As Object, e As GridViewPageEventArgs)
 gvReportJobs.PageIndex = e.NewPageIndex
 Dim startDate As DateTime, endDate As DateTime
 If ReadDateRange(startDate, endDate) Then
  Try
   LoadJobDetails(startDate, endDate)
  Finally
   tutupsr()
  End Try
 End If
End Sub

Private Function GetInventorySummary() As DataTable
 Dim data As New DataTable()
 Dim sql="SELECT p.ThAkdk,p.StudentCount BackupStudents,ISNULL(p.LiveStudentCount,0) LiveStudentCount,p.LatestStudentCount,ISNULL(p.VerificationStatus,'UNVERIFIED') VerificationStatus,p.VerifiedAt,p.UpdatedAt FROM dbo.BackupAgentPeriodInventory p JOIN dbo.BackupAgentNode a ON a.AgentId=p.AgentId WHERE a.IsPrimary=1 AND a.IsEnabled=1 AND (@ThAkdk='' OR p.ThAkdk=@ThAkdk) ORDER BY p.ThAkdk DESC"
 Using cmd As New SqlCommand(sql,cnsr)
  cmd.Parameters.Add("@ThAkdk",SqlDbType.Char,5).Value=ddlAcademicPeriod.SelectedValue
  Using ad As New SqlDataAdapter(cmd):ad.Fill(data):End Using
 End Using
 Return data
End Function

Private Sub LoadInventorySummary()
 Dim data=GetInventorySummary()
 gvReportInventory.DataSource=data
 gvReportInventory.DataBind()
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


Private Function ReportFilterDescription() As String
 Dim operation=If(String.IsNullOrWhiteSpace(ddlOperation.SelectedValue),"Semua operasi",ddlOperation.SelectedItem.Text)
 Dim status=If(String.IsNullOrWhiteSpace(ddlStatus.SelectedValue),"Semua status",ddlStatus.SelectedItem.Text)
 Dim tableName=If(String.IsNullOrWhiteSpace(ddlTable.SelectedValue),"Semua tabel",ddlTable.SelectedItem.Text)
 Dim period=If(String.IsNullOrWhiteSpace(ddlAcademicPeriod.SelectedValue),"Semua TA",ddlAcademicPeriod.SelectedValue)
 Return operation & "; " & status & "; " & tableName & "; " & period
End Function

Private Function NumberValue(value As Object) As String
 If value Is Nothing OrElse IsDBNull(value) Then Return "0"
 Return Convert.ToInt64(value).ToString("N0")
End Function


Private Function OperationText(value As String) As String
 Select Case value.Trim().ToUpperInvariant()
  Case "BACKUP":Return "Backup"
  Case "RESTORE":Return "Pemulihan"
  Case "EXPORT":Return "Ekspor"
  Case Else:Return value
 End Select
End Function

Private Function StatusText(value As String,errorMessage As String) As String
 Dim status=value.Trim().ToUpperInvariant()
 If status="FAILED" AndAlso errorMessage.StartsWith("[CANCELLED]",StringComparison.OrdinalIgnoreCase) Then Return "Dibatalkan"
 Select Case status
  Case "WAITING":Return "Menunggu"
  Case "CLAIMED":Return "Disiapkan"
  Case "TRANSFERRING":Return "Berjalan"
  Case "SUCCESS":Return "Berhasil"
  Case "FAILED":Return "Gagal"
  Case Else:Return status
 End Select
End Function

Private Function ScopeText(row As DataRow) As String
 If Not row.IsNull("StudentNim") AndAlso Not String.IsNullOrWhiteSpace(row("StudentNim").ToString()) Then Return "NIM " & row("StudentNim").ToString().Trim()
 If Not row.IsNull("RestoreThAkdkList") AndAlso Not String.IsNullOrWhiteSpace(row("RestoreThAkdkList").ToString()) Then
  Dim scope=row("RestoreThAkdkList").ToString().Trim()
  If scope.StartsWith("SINGLE:",StringComparison.OrdinalIgnoreCase) Then Return scope.Substring(7).Trim()
  If scope.StartsWith("RANGE:",StringComparison.OrdinalIgnoreCase) Then Return scope.Substring(6).Trim().Replace("-"," sampai ")
  If scope.StartsWith("UP_TO:",StringComparison.OrdinalIgnoreCase) Then Return scope.Substring(6).Trim() & " dan sebelumnya"
  Dim periods As New System.Collections.Generic.List(Of String)()
  For Each value As String In scope.Split(","c)
   If Not String.IsNullOrWhiteSpace(value) Then periods.Add(value.Trim())
  Next
  If periods.Count>0 Then Return String.Join(", ",periods.ToArray())
 End If
 If Not row.IsNull("CutoffThAkdk") AndAlso Not String.IsNullOrWhiteSpace(row("CutoffThAkdk").ToString()) Then Return row("CutoffThAkdk").ToString().Trim()
 Return "Database Backup"
End Function


Private Function FormatDuration(totalSeconds As Long) As String
 If totalSeconds<0 Then Return "-"
 Dim duration=TimeSpan.FromSeconds(totalSeconds)
 If duration.TotalHours>=1 Then Return String.Format("{0:0}j {1:00}m {2:00}d",Math.Floor(duration.TotalHours),duration.Minutes,duration.Seconds)
 If duration.TotalMinutes>=1 Then Return String.Format("{0:0}m {1:00}d",Math.Floor(duration.TotalMinutes),duration.Seconds)
 Return duration.Seconds.ToString() & " detik"
End Function
</script>

<div class="summary-report backup-page backup-page-monitoring">
 <div class="backup-page-header backup-page-header-action">
  <div>
   <span class="backup-page-eyebrow">Pemantauan</span>
   <h1>Laporan</h1>
  </div>
  <span class="backup-page-period">Periode: <strong><asp:Literal ID="litReportPeriod" runat="server" /></strong></span>
 </div>
 <asp:Literal ID="litReportMessage" runat="server" />

 <div class="panel panel-default summary-filter-panel">
  <div class="panel-heading"><i class="fa fa-filter"></i> Filter Laporan</div>
  <div class="panel-body">
   <div class="summary-filter-grid">
    <div class="summary-filter-row summary-filter-row-primary">
     <div class="summary-filter-field"><label for="<%= txtStartDate.ClientID %>">Tanggal awal</label><asp:TextBox ID="txtStartDate" runat="server" CssClass="form-control" TextMode="Date" /></div>
     <div class="summary-filter-field"><label for="<%= txtEndDate.ClientID %>">Tanggal akhir</label><asp:TextBox ID="txtEndDate" runat="server" CssClass="form-control" TextMode="Date" /></div>
     <div class="summary-filter-field"><label for="<%= ddlAcademicPeriod.ClientID %>">Tahun Akademik</label><asp:DropDownList ID="ddlAcademicPeriod" runat="server" CssClass="form-control" /></div>
    </div>
    <div class="summary-filter-row summary-filter-row-secondary">
     <div class="summary-filter-field"><label for="<%= ddlOperation.ClientID %>">Operasi</label><asp:DropDownList ID="ddlOperation" runat="server" CssClass="form-control"><asp:ListItem Value="">Semua</asp:ListItem><asp:ListItem Value="BACKUP">Backup</asp:ListItem><asp:ListItem Value="RESTORE">Pemulihan</asp:ListItem><asp:ListItem Value="EXPORT">Ekspor</asp:ListItem></asp:DropDownList></div>
     <div class="summary-filter-field"><label for="<%= ddlStatus.ClientID %>">Status</label><asp:DropDownList ID="ddlStatus" runat="server" CssClass="form-control"><asp:ListItem Value="">Semua</asp:ListItem><asp:ListItem Value="WAITING">Menunggu</asp:ListItem><asp:ListItem Value="CLAIMED">Disiapkan</asp:ListItem><asp:ListItem Value="TRANSFERRING">Berjalan</asp:ListItem><asp:ListItem Value="SUCCESS">Berhasil</asp:ListItem><asp:ListItem Value="FAILED">Gagal/Dibatalkan</asp:ListItem></asp:DropDownList></div>
     <div class="summary-filter-field"><label for="<%= ddlTable.ClientID %>">Tabel</label><asp:DropDownList ID="ddlTable" runat="server" CssClass="form-control"><asp:ListItem Value="">Semua</asp:ListItem><asp:ListItem Value="tbio01">Biodata</asp:ListItem><asp:ListItem Value="treg">Registrasi</asp:ListItem><asp:ListItem Value="tkrs06">KRS</asp:ListItem><asp:ListItem Value="t_absensi14">Absensi</asp:ListItem></asp:DropDownList></div>
     <div class="summary-filter-action"><asp:Button ID="btnApplyReport" runat="server" Text="Tampilkan Laporan" CssClass="btn btn-primary" OnClick="btnApplyReport_Click" /><asp:Button ID="btnExportPdf" runat="server" Text="Ekspor PDF" CssClass="btn btn-danger summary-export-button" OnClick="btnExportPdf_Click" /></div>
    </div>
   </div>
  </div>
 </div>

 <div class="summary-card-grid">
  <div class="summary-card summary-card-neutral"><span class="summary-card-icon"><i class="fa fa-list-alt"></i></span><div class="summary-card-content"><span>Total Proses</span><strong><asp:Literal ID="litTotalJobs" runat="server" /></strong></div></div>
  <div class="summary-card summary-card-success"><span class="summary-card-icon"><i class="fa fa-check-circle"></i></span><div class="summary-card-content"><span>Berhasil</span><strong><asp:Literal ID="litSuccessJobs" runat="server" /></strong></div></div>
  <div class="summary-card summary-card-danger"><span class="summary-card-icon"><i class="fa fa-times-circle"></i></span><div class="summary-card-content"><span>Gagal</span><strong><asp:Literal ID="litFailedJobs" runat="server" /></strong></div></div>
  <div class="summary-card summary-card-warning"><span class="summary-card-icon"><i class="fa fa-ban"></i></span><div class="summary-card-content"><span>Dibatalkan</span><strong><asp:Literal ID="litCancelledJobs" runat="server" /></strong></div></div>
  <div class="summary-card summary-card-primary"><span class="summary-card-icon"><i class="fa fa-users"></i></span><div class="summary-card-content"><span>Mahasiswa Diproses</span><strong><asp:Literal ID="litProcessedStudents" runat="server" /></strong></div></div>
  <div class="summary-card summary-card-neutral"><span class="summary-card-icon"><i class="fa fa-clock-o"></i></span><div class="summary-card-content"><span>Rata-rata Durasi</span><strong><asp:Literal ID="litAverageDuration" runat="server" /></strong></div></div>
 </div>

 <div class="panel panel-default">
  <div class="panel-heading backup-u-043"><span><i class="fa fa-list"></i> Detail Proses</span><asp:Label ID="lblResultCount" runat="server" CssClass="text-muted" /></div>
  <div class="table-responsive">
   <asp:GridView ID="gvReportJobs" runat="server" AutoGenerateColumns="false" CssClass="table table-striped table-hover" GridLines="None" EmptyDataText="Tidak ada proses pada filter yang dipilih."
    AllowPaging="true" PageSize="5"
    OnPageIndexChanging="gvReportJobs_PageIndexChanging"
    PagerSettings-Mode="NumericFirstLast"
    PagerSettings-FirstPageText="Awal"
    PagerSettings-LastPageText="Akhir"
    PagerStyle-CssClass="customPager"
    PagerStyle-HorizontalAlign="Center">
    <Columns>
     <asp:BoundField DataField="CreatedAt" HeaderText="Dibuat" DataFormatString="{0:dd MMM yyyy HH:mm}" />
     <asp:BoundField DataField="OperationLabel" HeaderText="Operasi" />
     <asp:BoundField DataField="ScopeLabel" HeaderText="Cakupan" />
     <asp:BoundField DataField="TableLabel" HeaderText="Tabel" />
     <asp:BoundField DataField="StatusLabel" HeaderText="Status" />
     <asp:BoundField DataField="ProcessedStudents" HeaderText="Diproses" DataFormatString="{0:N0}" ItemStyle-HorizontalAlign="Right" />
     <asp:BoundField DataField="DurationLabel" HeaderText="Durasi" />
     <asp:BoundField DataField="RequestedBy" HeaderText="Pengguna" />
    </Columns>
   </asp:GridView>
  </div>
 </div>

 <div class="panel panel-default">
  <div class="panel-heading backup-u-043">
   <span><i class="fa fa-calendar"></i> Inventaris Database Backup per Tahun Akademik (Audit Data)</span>
   <% If IsBackupStaff() Then %>
   <a href="index.aspx?tab=dashboard" class="btn btn-default btn-xs" title="Kelola sinkronisasi atau pemulihan data di Dashboard">
    <i class="fa fa-sliders"></i> Kelola di Dashboard
   </a>
   <% End If %>
  </div>
  <div class="table-responsive">
   <asp:GridView ID="gvReportInventory" runat="server" AutoGenerateColumns="false" CssClass="table table-striped table-hover" GridLines="None" EmptyDataText="Inventaris belum tersedia.">
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
    </Columns>
   </asp:GridView>
  </div>
 </div>
</div>

<script type="text/javascript">

(function() {
    function setupDateFilterBounds() {
        var startInput = document.getElementById("<%= txtStartDate.ClientID %>");
        var endInput = document.getElementById("<%= txtEndDate.ClientID %>");
        if (!startInput || !endInput) return;

        function updateBounds() {
            if (startInput.value) {
                endInput.min = startInput.value;
                if (endInput.value && endInput.value < startInput.value) {
                    endInput.value = startInput.value;
                }
            } else {
                endInput.removeAttribute("min");
            }

            if (endInput.value) {
                startInput.max = endInput.value;
                if (startInput.value && startInput.value > endInput.value) {
                    startInput.value = endInput.value;
                }
            } else {
                startInput.removeAttribute("max");
            }
        }

        startInput.addEventListener("change", updateBounds);
        startInput.addEventListener("input", updateBounds);
        endInput.addEventListener("change", updateBounds);
        endInput.addEventListener("input", updateBounds);

        updateBounds();
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", setupDateFilterBounds);
    } else {
        setupDateFilterBounds();
    }
})();
</script>
