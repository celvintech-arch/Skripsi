<%@ Control Language="VB" ClassName="backup_index_lazy_control" %>

<!-- #INCLUDE file="ascx/con_backup.ascx" -->

<script runat="server">
    Protected CurrentTab As String = "dashboard"
    Protected IsManagerView As Boolean = False

    Protected Overrides Sub OnInit(ByVal e As EventArgs)
        MyBase.OnInit(e)
        cekauthlintarNew()
        IsManagerView = IsBackupManager()
        CurrentTab = If(IsManagerView, "dashboard", "backup")

        Dim requestedTab As String = Request.QueryString("tab")
        If Not String.IsNullOrWhiteSpace(requestedTab) Then
            CurrentTab = requestedTab.Trim().ToLowerInvariant()
        End If

        Select Case CurrentTab
            Case "dashboard", "statistik", "benchmark"
                CurrentTab = "dashboard"
            Case "summary", "summary-report", "laporan"
                CurrentTab = "summary"
            Case "backup"
                CurrentTab = "backup"
            Case "pemulihan", "restore"
                CurrentTab = "pemulihan"
            Case "riwayat", "history"
                CurrentTab = "riwayat"
            Case "operator", "operators"
                CurrentTab = "operator"
            Case "ekspor", "export"
                CurrentTab = "ekspor"
            Case Else
                CurrentTab = If(IsManagerView, "dashboard", "backup")
        End Select

        If IsManagerView AndAlso CurrentTab <> "dashboard" AndAlso CurrentTab <> "summary" Then
            Response.Redirect("index.aspx?tab=dashboard&access=denied")
            Return
        End If

        Dim controlPath As String = ""
        Select Case CurrentTab
            Case "dashboard"
                controlPath = "ascx/statistik.ascx"
            Case "summary"
                controlPath = "ascx/summary_report.ascx"
            Case "pemulihan"
                controlPath = "ascx/pemulihan.ascx"
            Case "riwayat"
                controlPath = "ascx/riwayat.ascx"
            Case "operator"
                controlPath = "ascx/operator.ascx"
            Case "ekspor"
                controlPath = "ascx/ekspor.ascx"
            Case Else
                controlPath = "ascx/backup.ascx"
        End Select

        Dim activeControl As System.Web.UI.Control = LoadControl(controlPath)
        activeControl.ID = "module_" & CurrentTab
        phModule.Controls.Add(activeControl)
    End Sub
</script>
<div class="backup-u-074">
    <div class="box box-danger backup-u-058">
        <div class="box-header with-border backup-u-071">
            <ul class="nav nav-pills nav-pills-custom backup-u-055">
                <% If IsManagerView Then %>
                    <li class="<%= If(CurrentTab = "dashboard", "active", "") %>">
                        <a href="index.aspx?tab=dashboard"><i class="fa fa-dashboard me-1"></i> Dashboard</a>
                    </li>
                    <li class="<%= If(CurrentTab = "summary", "active", "") %>">
                        <a href="index.aspx?tab=summary"><i class="fa fa-bar-chart me-1"></i> Laporan</a>
                    </li>
                <% Else %>
                    <li class="dropdown nav-menu-group <%= If(CurrentTab = "backup" OrElse CurrentTab = "pemulihan" OrElse CurrentTab = "ekspor", "active", "") %>">
                        <a href="#" class="dropdown-toggle" data-toggle="dropdown" role="button" aria-haspopup="true" aria-expanded="false"><i class="fa fa-cogs me-1"></i> Operasional <span class="caret"></span></a>
                        <ul class="dropdown-menu">
                            <li class="<%= If(CurrentTab = "backup", "active", "") %>"><a href="index.aspx?tab=backup"><i class="fa fa-database"></i> Backup Data</a></li>
                            <li class="<%= If(CurrentTab = "pemulihan", "active", "") %>"><a href="index.aspx?tab=pemulihan"><i class="fa fa-undo"></i> Pemulihan Data</a></li>
                            <li class="<%= If(CurrentTab = "ekspor", "active", "") %>"><a href="index.aspx?tab=ekspor"><i class="fa fa-download"></i> Ekspor Database</a></li>
                        </ul>
                    </li>
                    <li class="dropdown nav-menu-group <%= If(CurrentTab = "dashboard" OrElse CurrentTab = "summary" OrElse CurrentTab = "riwayat", "active", "") %>">
                        <a href="#" class="dropdown-toggle" data-toggle="dropdown" role="button" aria-haspopup="true" aria-expanded="false"><i class="fa fa-line-chart me-1"></i> Pemantauan <span class="caret"></span></a>
                        <ul class="dropdown-menu">
                            <li class="<%= If(CurrentTab = "dashboard", "active", "") %>"><a href="index.aspx?tab=dashboard"><i class="fa fa-dashboard"></i> Dashboard</a></li>
                            <li class="<%= If(CurrentTab = "summary", "active", "") %>"><a href="index.aspx?tab=summary"><i class="fa fa-bar-chart"></i> Laporan</a></li>
                            <li class="<%= If(CurrentTab = "riwayat", "active", "") %>"><a href="index.aspx?tab=riwayat"><i class="fa fa-history"></i> Riwayat Proses</a></li>
                        </ul>
                    </li>
                    <li class="dropdown nav-menu-group <%= If(CurrentTab = "operator", "active", "") %>">
                        <a href="#" class="dropdown-toggle" data-toggle="dropdown" role="button" aria-haspopup="true" aria-expanded="false"><i class="fa fa-shield me-1"></i> Administrasi <span class="caret"></span></a>
                        <ul class="dropdown-menu">
                            <li class="<%= If(CurrentTab = "operator", "active", "") %>"><a href="index.aspx?tab=operator"><i class="fa fa-users"></i> Kelola Pengguna</a></li>
                        </ul>
                    </li>
                <% End If %>
            </ul>
        </div>

        <div class="box-body backup-u-073">
            <% If Request.QueryString("access") = "denied" Then %>
                <div class="alert alert-warning"><strong>Akses dibatasi.</strong> Manager hanya dapat membuka Dashboard dan Laporan.</div>
            <% End If %>
            <asp:PlaceHolder ID="phModule" runat="server" />
        </div>
    </div>
</div>
