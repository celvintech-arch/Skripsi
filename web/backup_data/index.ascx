<%@ Control Language="VB" ClassName="backup_index_lazy_control" %>

<!-- #INCLUDE file="ascx/con_backup.ascx" -->

<script runat="server">
    Protected CurrentTab As String = "dashboard"
    Protected IsManagerView As Boolean = False

    Protected Overrides Sub OnInit(ByVal e As EventArgs)
        MyBase.OnInit(e)
        EnsureBackupAccess()
        IsManagerView = IsBackupManager()
        Session("backup_nav_role") = GetBackupAccessRole()
        CurrentTab = "dashboard"

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
                CurrentTab = "dashboard"
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
        <div class="box-body backup-u-073">
            <% If Request.QueryString("access") = "denied" Then %>
                <div class="alert alert-warning"><strong>Akses dibatasi.</strong> Manager hanya dapat membuka Dashboard dan Laporan.</div>
            <% End If %>
            <asp:PlaceHolder ID="phModule" runat="server" />
        </div>
    </div>
</div>
