<%@ Import Namespace="System.Configuration" %>
<%@ Import Namespace="System.Data" %>
<%@ Import Namespace="System.Data.SqlClient" %>

<!-- #INCLUDE virtual="/con_ascx2022/condecdummy.ascx" -->

<script runat="server">
    Private _backupSqlConnectionString As String
    Private _backupSqlConnection As SqlConnection
    Private _backupRoleResolved As Boolean
    Private _backupRole As String

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
