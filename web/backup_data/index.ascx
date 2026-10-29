<%@ Control Language="VB" ClassName="backup_index_lazy_control" %>

<%-- Sertakan konfigurasi koneksi dan aturan otorisasi modul backup --%>
<!-- #INCLUDE file="ascx/con_backup.ascx" -->

<script runat="server">
    ' Menyimpan nama tab yang sedang aktif (default: dashboard)
    Protected CurrentTab As String = "dashboard"
    ' Menyimpan status apakah pengguna yang login memiliki peran Manager
    Protected IsManagerView As Boolean = False

    ' =========================================================================================
    ' SIKLUS HIDUP KONTROL: OnInit
    ' Bertindak sebagai Router / Dispatcher yang memuat User Control (.ascx) secara dinamis
    ' berdasarkan parameter URL ?tab=... serta membatasi hak akses pengguna.
    ' =========================================================================================
    Protected Overrides Sub OnInit(ByVal e As EventArgs)
        MyBase.OnInit(e)
        
        ' 1. Verifikasi Izin Akses Modul:
        ' Memastikan pengguna terdaftar di tabel BackupOperatorAccess (Staff atau Manager).
        EnsureBackupAccess()
        IsManagerView = IsBackupManager()
        Session("backup_nav_role") = GetBackupAccessRole()
        CurrentTab = "dashboard"

        ' 2. Baca Parameter Tab dari URL:
        Dim requestedTab As String = Request.QueryString("tab")
        If Not String.IsNullOrWhiteSpace(requestedTab) Then
            CurrentTab = requestedTab.Trim().ToLowerInvariant()
        End If

        ' 3. Normalisasi Nama Tab (Mendukung Alias Bahasa Indonesia & Inggris):
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

        ' 4. Penegakan Kebijakan Peran (Role-Based Access Control):
        ' Pengguna dengan peran 'Manager' hanya diizinkan membuka Dashboard dan Laporan Ringkasan.
        ' Jika mencoba membuka tab operasional (backup/restore/export/operator), alihkan ke dashboard.
        If IsManagerView AndAlso CurrentTab <> "dashboard" AndAlso CurrentTab <> "summary" Then
            Response.Redirect("index.aspx?tab=dashboard&access=denied")
            Return
        End If

        ' 5. Pemetaan Berkas Kontrol (.ascx):
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

        ' 6. Pemuatan Dinamis (Lazy Loading):
        ' Hanya memuat berkas kontrol tab yang aktif ke memori sehingga server tetap ringan dan cepat.
        Dim activeControl As System.Web.UI.Control = LoadControl(controlPath)
        activeControl.ID = "module_" & CurrentTab
        phModule.Controls.Add(activeControl)
    End Sub
</script>

<div class="backup-u-074">
    <div class="box box-danger backup-u-058">
        <div class="box-body backup-u-073">
            <%-- Tampilkan pesan peringatan jika Manager mencoba mengakses tab terbatas --%>
            <% If Request.QueryString("access") = "denied" Then %>
                <div class="alert alert-warning">
                    <i class="fa fa-exclamation-circle"></i> <strong>Akses dibatasi:</strong> Peran Manager hanya memiliki wewenang untuk membuka Dashboard dan Laporan Ringkasan.
                </div>
            <% End If %>
            
            <%-- Kontainer penampung modul kontrol tab yang dimuat dinamis --%>
            <asp:PlaceHolder ID="phModule" runat="server" />
        </div>
    </div>
</div>
