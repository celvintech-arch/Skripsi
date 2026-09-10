<%@ Import Namespace="System.Configuration" %>
<%@ Import Namespace="System.Data" %>
<%@ Import Namespace="System.Data.SqlClient" %>

<!-- #INCLUDE virtual="/con_ascx2022/condecdummy.ascx" -->

<script runat="server">
    Private _backupSqlConnectionString As String
    Private _backupSqlConnection As SqlConnection
    Private _backupRoleResolved As Boolean
    Private _backupRole As String

    Public Class BackupServiceState
        Public StatusCode As String = "NOT_REGISTERED"
        Public StatusText As String = "Belum terdaftar"
        Public CssClass As String = "danger"
        Public Description As String = "Database Backup utama belum terdaftar."
        Public AgentName As String = "-"
        Public LastSeenAt As Nullable(Of DateTime) = Nothing
        Public LastDatabaseReady As Nullable(Of Boolean) = Nothing
        Public LastMessage As String = "-"
        Public IsReady As Boolean = False
    End Class

    ' condecdummy.ascx tetap menjadi satu-satunya sumber konfigurasi koneksi.
    ' Adapter ini hanya mengubah format OLE DB menjadi format SqlClient di memori.
    Public ReadOnly Property connstringLive As String
        Get
            If String.IsNullOrWhiteSpace(_backupSqlConnectionString) Then
                Dim source As New OleDb.OleDbConnectionStringBuilder(connstringdec)
                Dim target As New SqlConnectionStringBuilder()
                target.DataSource = Convert.ToString(source("Data Source"))
                target.InitialCatalog = Convert.ToString(source("Initial Catalog"))
                target.UserID = Convert.ToString(source("User ID"))
                target.Password = Convert.ToString(source("Password"))
                target.ConnectTimeout = 30
                target.Pooling = True
                target.ApplicationName = "LINTAR Backup Data"
                _backupSqlConnectionString = target.ConnectionString
            End If
            Return _backupSqlConnectionString
        End Get
    End Property

    Public ReadOnly Property cnsr As SqlConnection
        Get
            If _backupSqlConnection Is Nothing Then _backupSqlConnection = New SqlConnection(connstringLive)
            Return _backupSqlConnection
        End Get
    End Property
    Sub tutupsr()
        If cnsr.State <> ConnectionState.Closed Then cnsr.Close()
    End Sub

    Public Function ReadBackupServiceState() As BackupServiceState
        Dim state As New BackupServiceState()
        Using cn As New SqlConnection(connstringLive)
            Using cmd As New SqlCommand("SELECT TOP(1) AgentName,IsEnabled,LastSeenAt,LastDatabaseReady,LastMessage FROM dbo.BackupAgentNode WHERE IsPrimary=1 ORDER BY UpdatedAt DESC",cn)
                cn.Open()
                Using rd=cmd.ExecuteReader()
                    If Not rd.Read() Then Return state
                    state.AgentName=rd("AgentName").ToString().Trim()
                    Dim enabled=Convert.ToBoolean(rd("IsEnabled"))
                    If Not rd.IsDBNull(rd.GetOrdinal("LastSeenAt")) Then state.LastSeenAt=Convert.ToDateTime(rd("LastSeenAt"))
                    If Not rd.IsDBNull(rd.GetOrdinal("LastDatabaseReady")) Then state.LastDatabaseReady=Convert.ToBoolean(rd("LastDatabaseReady"))
                    state.LastMessage=BackupAgentMessageForDisplay(If(rd.IsDBNull(rd.GetOrdinal("LastMessage")),"",rd("LastMessage").ToString()))
                    If Not enabled Then
                        state.StatusCode="NOT_READY":state.StatusText="Belum siap":state.CssClass="danger":state.Description="Agent backup utama sedang dinonaktifkan."
                    ElseIf Not state.LastSeenAt.HasValue Then
                        state.StatusCode="NOT_READY":state.StatusText="Belum siap":state.CssClass="warning":state.Description="Agent backup utama belum pernah mengirim heartbeat."
                    ElseIf state.LastSeenAt.Value<DateTime.Now.AddMinutes(-3) Then
                        state.StatusCode="OFFLINE":state.StatusText="Offline":state.CssClass="warning":state.Description="Heartbeat agent tidak diterima dalam tiga menit terakhir."
                    ElseIf Not state.LastDatabaseReady.GetValueOrDefault(False) Then
                        state.StatusCode="NOT_READY":state.StatusText="Belum siap":state.CssClass="warning":state.Description="Agent terhubung, tetapi Database Backup belum dapat diakses."
                    Else
                        state.StatusCode="READY":state.StatusText="Siap":state.CssClass="success":state.Description="Agent terhubung dan Database Backup siap memproses permintaan."
                        state.IsReady=True
                    End If
                End Using
            End Using
        End Using
        Return state
    End Function

    Public Function BackupAgentMessageForDisplay(value As String) As String
        If String.IsNullOrWhiteSpace(value) Then Return "Belum ada pesan dari agent."
        If value.TrimStart().StartsWith("{") Then Return "Heartbeat dan statistik Database Backup berhasil diterima."
        Return value.Trim()
    End Function

    Public Function BackupServiceAlertHtml(state As BackupServiceState,activityName As String) As String
        If state IsNot Nothing AndAlso state.IsReady Then Return ""
        Dim detail=state.Description
        If state.LastSeenAt.HasValue Then detail &= " Koneksi terakhir: " & state.LastSeenAt.Value.ToString("dd MMM yyyy HH:mm:ss") & "."
        If Not state.IsReady Then detail &= " " & activityName & " belum dapat dijalankan."
        Return "<div class='alert alert-" & state.CssClass & " backup-service-alert' role='status'><i class='fa " & If(state.IsReady,"fa-check-circle","fa-exclamation-triangle") & "' aria-hidden='true'></i><div><strong>Database Backup: " & Server.HtmlEncode(state.StatusText) & "</strong><span>" & Server.HtmlEncode(detail) & "</span></div></div>"
    End Function

    Public Sub EnsureBackupServiceReady(state As BackupServiceState,activityName As String)
        If state Is Nothing OrElse Not state.IsReady Then Throw New ApplicationException(activityName & " tidak dapat dijalankan karena Database Backup belum siap. Periksa Dashboard untuk status layanan terbaru.")
    End Sub

    Private Function NormalizeBackupRole(ByVal value As Object) As String
        If value Is Nothing Then Return ""
        Dim roleValue As String = value.ToString().Trim().ToUpperInvariant()
        If roleValue = "DENIED_BACKUP" Then Return "DENIED_BACKUP"
        If roleValue = "MANAGER_BACKUP" Then Return "MANAGER_BACKUP"
        If roleValue = "STAFF_BACKUP" OrElse roleValue = "ADMIN_BACKUP" OrElse roleValue = "ADMIN" OrElse roleValue = "SUPERADMIN" Then Return "STAFF_BACKUP"
        Return ""
    End Function

    Public Function GetBackupAccessRole() As String
        If _backupRoleResolved Then Return _backupRole
        _backupRoleResolved = True
        _backupRole = ""

        If Session("userid_lintar") Is Nothing OrElse String.IsNullOrWhiteSpace(Session("userid_lintar").ToString()) OrElse
           Session("idlintar") Is Nothing OrElse String.IsNullOrWhiteSpace(Session("idlintar").ToString()) Then
            Return _backupRole
        End If

        Dim userId As String = Session("idlintar").ToString().Trim()
        Try
            Using cn As New SqlConnection(connstringLive)
                Using cmd As New SqlCommand("dbo.sp_GetBackupOperatorRole", cn)
                    cmd.CommandType = CommandType.StoredProcedure
                    cmd.Parameters.Add("@UserId", SqlDbType.NVarChar, 50).Value = userId
                    cn.Open()
                    _backupRole = NormalizeBackupRole(cmd.ExecuteScalar())
                End Using
            End Using
        Catch ex As SqlException
            ' Kompatibilitas sementara sebelum migration role dijalankan.
            Try
                Using cn As New SqlConnection(connstringLive)
                    Using cmd As New SqlCommand("SELECT TOP(1) CASE WHEN IsEnabled=0 THEN 'DENIED_BACKUP' WHEN AccessRole='MANAGER_BACKUP' THEN 'MANAGER_BACKUP' ELSE 'STAFF_BACKUP' END FROM dbo.BackupOperatorAccess WHERE UserId=@UserId", cn)
                        cmd.Parameters.Add("@UserId", SqlDbType.NVarChar, 50).Value = userId
                        cn.Open()
                        _backupRole = NormalizeBackupRole(cmd.ExecuteScalar())
                    End Using
                End Using
            Catch
                _backupRole = ""
            End Try
        End Try

        ' Role modul pada database lebih spesifik daripada role pada session LINTAR.
        If String.IsNullOrWhiteSpace(_backupRole) AndAlso Session("role_backup") IsNot Nothing Then
            _backupRole = NormalizeBackupRole(Session("role_backup"))
        End If
        If String.IsNullOrWhiteSpace(_backupRole) AndAlso Session("role") IsNot Nothing Then
            _backupRole = NormalizeBackupRole(Session("role"))
        End If
        Return _backupRole
    End Function

    Sub cekauthlintarNew()
        If Session("userid_lintar") Is Nothing OrElse String.IsNullOrWhiteSpace(Session("userid_lintar").ToString()) OrElse
           Session("idlintar") Is Nothing OrElse String.IsNullOrWhiteSpace(Session("idlintar").ToString()) Then
            DenyBackupAccess(401)
            Return
        End If
        Dim roleValue=GetBackupAccessRole()
        If roleValue<>"STAFF_BACKUP" AndAlso roleValue<>"MANAGER_BACKUP" Then DenyBackupAccess(403)
    End Sub

    Public Function IsBackupStaff() As Boolean
        Return String.Equals(GetBackupAccessRole(), "STAFF_BACKUP", StringComparison.Ordinal)
    End Function

    Public Function IsBackupManager() As Boolean
        Return String.Equals(GetBackupAccessRole(), "MANAGER_BACKUP", StringComparison.Ordinal)
    End Function

    Public Sub RequireBackupStaff()
        cekauthlintarNew()
        If Not IsBackupStaff() Then Response.Redirect("index.aspx?tab=dashboard&access=denied")
    End Sub

    Public Sub RequireBackupReportAccess()
        cekauthlintarNew()
        If Not IsBackupStaff() AndAlso Not IsBackupManager() Then DenyBackupAccess(403)
    End Sub
    Private Sub DenyBackupAccess(ByVal statusCode As Integer)
        If statusCode = 401 Then
            Session.RemoveAll()
            Response.Redirect("/index.aspx")
        Else
            Response.Redirect("/utama.aspx")
        End If
    End Sub
    Public Function BackupRequestedBy() As String
        If Session("idlintar") Is Nothing OrElse String.IsNullOrWhiteSpace(Session("idlintar").ToString()) Then Return "Application"
        Return Session("idlintar").ToString().Trim()
    End Function
</script>
