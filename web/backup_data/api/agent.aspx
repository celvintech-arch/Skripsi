<%@ Page Language="VB" EnableSessionState="False" %>
<%@ Import Namespace="System" %>
<%@ Import Namespace="System.Collections" %>
<%@ Import Namespace="System.Collections.Generic" %>
<%@ Import Namespace="System.Data" %>
<%@ Import Namespace="System.Data.SqlClient" %>
<%@ Import Namespace="System.IO" %>
<%@ Import Namespace="System.Globalization" %>
<%@ Import Namespace="System.Web" %>
<%@ Import Namespace="System.Web.Script.Serialization" %>
<!-- #INCLUDE virtual="/con_ascx2022/condecdummy.ascx" -->

<script runat="server">
 Private Function GetBackupLiveSqlConnectionString() As String
  Dim source As New OleDb.OleDbConnectionStringBuilder(connstringdec)
  Dim target As New SqlConnectionStringBuilder()
  target.DataSource=Convert.ToString(source("Data Source"))
  target.InitialCatalog=Convert.ToString(source("Initial Catalog"))
  target.UserID=Convert.ToString(source("User ID"))
  target.Password=Convert.ToString(source("Password"))
  target.ConnectTimeout=30
  target.Pooling=True
  target.ApplicationName="LINTAR Backup Agent API"
  Return target.ConnectionString
 End Function

 Protected Sub Page_Load(sender As Object,e As EventArgs)
  HandleAgentRequest(Context)
 End Sub

 Private Sub HandleAgentRequest(context As HttpContext)
  context.Response.ContentType="application/json"
  context.Response.TrySkipIisCustomErrors=True
  context.Response.Cache.SetCacheability(HttpCacheability.NoCache)
  context.Response.Cache.SetNoStore()
  Try
   If Not String.Equals(context.Request.HttpMethod,"POST",StringComparison.OrdinalIgnoreCase) Then WriteJson(context,405,New With {.ok=False,.message="Gunakan POST."}) : Return
   If context.Request.ContentLength>104857600 Then WriteJson(context,413,New With {.ok=False,.message="Payload melebihi batas 100 MB."}) : Return
   Dim action=If(context.Request.QueryString("action"),"").Trim().ToLowerInvariant()
  If Array.IndexOf(New String(){"heartbeat","schema","claim","backupbatch","backupconfirm","backupmetrics","restorepush","restorecomplete","exportconfirm","inventory","jobprogress","jobfail","lookupclaim","lookupcomplete","sourcecheck"},action)<0 Then WriteJson(context,404,New With {.ok=False,.message="Endpoint tidak tersedia."}) : Return
   Dim apiKey=If(context.Request.Headers("X-Backup-Agent-Key"),"").Trim()
   If apiKey.Length<32 OrElse apiKey.Length>256 Then Throw New HttpException(401,"Token agent tidak tersedia atau tidak valid.")

   Dim body=TryCast(CreateJsonSerializer().DeserializeObject(New StreamReader(context.Request.InputStream).ReadToEnd()),Dictionary(Of String,Object))
   If body Is Nothing Then body=New Dictionary(Of String,Object)()
   Dim ready=String.Equals(GetValue(body,"databaseReady"),"true",StringComparison.OrdinalIgnoreCase),msg=GetValue(body,"message")
   Using cn As New SqlConnection(GetBackupLiveSqlConnectionString())
    cn.Open()
    Dim agentName=Authenticate(cn,apiKey,ready,msg)
    Select Case action
     Case "heartbeat" : WriteJson(context,200,New With {.ok=True,.agentName=agentName,.serverTime=DateTime.Now.ToString("o"),.databaseReady=ready,.backupStatsReceived=msg.TrimStart().StartsWith("{")})
     Case "schema" : WriteJson(context,200,New With {.ok=True,.tables=GetSchema(cn)})
     Case "claim" : WriteJson(context,200,Claim(cn,apiKey))
     Case "backupbatch" : WriteJson(context,200,GetBackupBatch(cn,apiKey,GetValue(body,"jobId"),body))
     Case "backupconfirm" : WriteJson(context,200,ConfirmBackupBatch(cn,apiKey,GetValue(body,"jobId"),body))
     Case "backupmetrics" : WriteJson(context,200,BackupMetrics(cn,apiKey,GetValue(body,"jobId"),body))
     Case "restorepush" : WriteJson(context,200,RestorePush(cn,apiKey,GetValue(body,"jobId"),body))
     Case "restorecomplete" : WriteJson(context,200,CompleteRestore(cn,apiKey,GetValue(body,"jobId")))
     Case "exportconfirm" : WriteJson(context,200,CompleteExport(cn,apiKey,GetValue(body,"jobId"),body))
     Case "inventory" : WriteJson(context,200,SyncInventory(cn,apiKey,body))
     Case "jobprogress" : WriteJson(context,200,UpdateJobProgress(cn,apiKey,GetValue(body,"jobId"),body))
     Case "jobfail" : WriteJson(context,200,FailJob(cn,apiKey,GetValue(body,"jobId"),body))
     Case "lookupclaim" : WriteJson(context,200,ClaimLookup(cn,apiKey))
     Case "lookupcomplete" : WriteJson(context,200,CompleteLookup(cn,apiKey,GetValue(body,"lookupId"),body))
     Case "sourcecheck" : WriteJson(context,200,CheckSourceNims(cn,apiKey,body))
    End Select
   End Using
  Catch ex As HttpException
   WriteApiErrorHeader(context,ex.Message) : WriteJson(context,ex.GetHttpCode(),New With {.ok=False,.message=ex.Message})
  Catch ex As SqlException
   WriteApiErrorHeader(context,ex.Message) : WriteJson(context,400,New With {.ok=False,.message=ex.Message})
  Catch ex As Exception
   WriteApiErrorHeader(context,ex.Message) : WriteJson(context,500,New With {.ok=False,.message="API agent gagal: " & ex.Message})
  End Try
 End Sub

 Private Function Authenticate(cn As SqlConnection,apiKey As String,ready As Boolean,message As String) As String
  Using cmd As New SqlCommand("dbo.sp_AgentHeartbeat",cn)
   cmd.CommandType=CommandType.StoredProcedure
   cmd.Parameters.Add("@ApiKey",SqlDbType.NVarChar,256).Value=apiKey
   cmd.Parameters.Add("@DatabaseReady",SqlDbType.Bit).Value=ready
   cmd.Parameters.Add("@Message",SqlDbType.NVarChar,500).Value=If(String.IsNullOrWhiteSpace(message),CObj(DBNull.Value),message)
   Using rd=cmd.ExecuteReader()
    If Not rd.Read() Then Throw New HttpException(403,"Perangkat backup utama tidak ditemukan.")
    Return rd("AgentName").ToString()
   End Using
  End Using
 End Function

 Private Function UpdateJobProgress(cn As SqlConnection,apiKey As String,jobText As String,body As Dictionary(Of String,Object)) As Object
  Dim jobId As Guid : If Not Guid.TryParse(jobText,jobId) Then Throw New HttpException(400,"Job tidak valid.")
  Dim message=GetValue(body,"message"),totalStudents As Integer
  If message.Length>500 Then message=message.Substring(0,500)
  Using cmd As New SqlCommand("SET NOCOUNT ON; UPDATE j SET LeaseExpiresAt=DATEADD(MINUTE,10,SYSDATETIME()),ProgressMessage=@m,TotalStudents=CASE WHEN @total>0 THEN @total ELSE TotalStudents END,ErrorMessage=NULL FROM dbo.BackupTransferJob j JOIN dbo.BackupAgentNode a ON a.AgentName=j.AgentName WHERE j.JobId=@j AND j.Status IN('CLAIMED','TRANSFERRING') AND a.IsPrimary=1 AND a.IsEnabled=1 AND a.ApiKeyHash=HASHBYTES('SHA2_256',@t); SELECT j.Status,j.ProcessedStudents,j.ProgressMessage,j.ErrorMessage FROM dbo.BackupTransferJob j JOIN dbo.BackupAgentNode a ON a.AgentName=j.AgentName WHERE j.JobId=@j AND a.IsPrimary=1 AND a.IsEnabled=1 AND a.ApiKeyHash=HASHBYTES('SHA2_256',@t);",cn)
   cmd.Parameters.Add("@j",SqlDbType.UniqueIdentifier).Value=jobId
   cmd.Parameters.Add("@t",SqlDbType.NVarChar,256).Value=apiKey
   cmd.Parameters.Add("@m",SqlDbType.NVarChar,2000).Value=If(String.IsNullOrWhiteSpace(message),CObj(DBNull.Value),message)
   cmd.Parameters.Add("@total",SqlDbType.Int).Value=totalStudents
   Using rd=cmd.ExecuteReader()
    If rd.Read() Then
     Dim status=rd("Status").ToString(),failure=DbText(rd,"ErrorMessage"),progress=DbText(rd,"ProgressMessage")
     Return New With {.ok=True,.status=status,.processedStudents=Convert.ToInt32(rd("ProcessedStudents")),.cancelled=(status="FAILED" AndAlso failure.StartsWith("[CANCELLED]",StringComparison.OrdinalIgnoreCase)),.message=If(status="FAILED",failure,progress)}
    End If
   End Using
  End Using
  Throw New HttpException(403,"Progress job tidak dapat diperbarui oleh agent ini.")
 End Function
 Private Function FailJob(cn As SqlConnection,apiKey As String,jobText As String,body As Dictionary(Of String,Object)) As Object
  Dim jobId As Guid : If Not Guid.TryParse(jobText,jobId) Then Throw New HttpException(400,"Job tidak valid.")
  Dim failure=GetValue(body,"errorMessage")
  If String.IsNullOrWhiteSpace(failure) Then failure="Agent menghentikan job karena terjadi kesalahan."
  If failure.Length>2000 Then failure=failure.Substring(0,2000)
  Using cmd As New SqlCommand("SET NOCOUNT ON; UPDATE j SET Status='FAILED',CompletedAt=SYSDATETIME(),LeaseExpiresAt=NULL,ProgressMessage=NULL,ResultMessage=NULL,ErrorMessage=@e FROM dbo.BackupTransferJob j JOIN dbo.BackupAgentNode a ON a.AgentName=j.AgentName WHERE j.JobId=@j AND j.Status IN('CLAIMED','TRANSFERRING') AND a.IsPrimary=1 AND a.IsEnabled=1 AND a.ApiKeyHash=HASHBYTES('SHA2_256',@t); SELECT j.Status,j.ProcessedStudents,j.ErrorMessage FROM dbo.BackupTransferJob j JOIN dbo.BackupAgentNode a ON a.AgentName=j.AgentName WHERE j.JobId=@j AND a.IsPrimary=1 AND a.IsEnabled=1 AND a.ApiKeyHash=HASHBYTES('SHA2_256',@t);",cn)
   cmd.Parameters.Add("@j",SqlDbType.UniqueIdentifier).Value=jobId
   cmd.Parameters.Add("@t",SqlDbType.NVarChar,256).Value=apiKey
   cmd.Parameters.Add("@e",SqlDbType.NVarChar,2000).Value=failure
   Using rd=cmd.ExecuteReader()
    If rd.Read() Then Return New With {.ok=True,.status=rd("Status").ToString(),.processedStudents=Convert.ToInt32(rd("ProcessedStudents")),.message=DbText(rd,"ErrorMessage")}
   End Using
  End Using
  Throw New HttpException(403,"Job gagal tidak dapat diperbarui oleh agent ini.")
 End Function

 Private Function Claim(cn As SqlConnection,apiKey As String) As Object
  RunScheduledBackup(cn)
  Using cmd As New SqlCommand("dbo.sp_AgentClaimBackupTransferJob",cn)
   cmd.CommandType=CommandType.StoredProcedure
   cmd.Parameters.Add("@ApiKey",SqlDbType.NVarChar,256).Value=apiKey
   cmd.Parameters.Add("@LeaseMinutes",SqlDbType.Int).Value=5
   Using rd=cmd.ExecuteReader()
    If Not rd.Read() OrElse rd.IsDBNull(0) Then Return New With {.ok=True,.hasJob=False}
    Return New With {.ok=True,.hasJob=True,.jobId=rd("JobId").ToString(),.operationType=rd("OperationType").ToString(),.cutoffThAkdk=DbText(rd,"CutoffThAkdk"),.studentNim=DbText(rd,"StudentNim"),.restoreThAkdkList=DbText(rd,"RestoreThAkdkList"),.selectedTables=DbText(rd,"SelectedTables"),.lastProgressNim=DbText(rd,"LastProgressNim"),.retryCount=Convert.ToInt32(rd("RetryCount")),.targetStudents=DbIntOptional(rd,"TargetStudents")}
   End Using
  End Using
 End Function

 Private Function ClaimLookup(cn As SqlConnection,apiKey As String) As Object
  Dim sql="SET NOCOUNT ON; SET XACT_ABORT ON; DECLARE @agent nvarchar(128),@id uniqueidentifier; SELECT @agent=AgentName FROM dbo.BackupAgentNode WHERE IsPrimary=1 AND IsEnabled=1 AND ApiKeyHash=HASHBYTES('SHA2_256',@t); IF @agent IS NULL THROW 51104,'Token agent tidak valid.',1; BEGIN TRAN; UPDATE dbo.BackupLookupRequest SET Status='WAITING',LeaseExpiresAt=NULL WHERE AgentName=@agent AND Status='CLAIMED' AND LeaseExpiresAt<SYSDATETIME() AND ExpiresAt>SYSDATETIME(); UPDATE dbo.BackupLookupRequest SET Status='FAILED',CompletedAt=SYSDATETIME(),ErrorMessage='Permintaan pencarian kedaluwarsa.' WHERE AgentName=@agent AND Status IN('WAITING','CLAIMED') AND ExpiresAt<=SYSDATETIME(); SELECT TOP(1) @id=LookupId FROM dbo.BackupLookupRequest WITH(UPDLOCK,READPAST) WHERE AgentName=@agent AND Status='WAITING' AND ExpiresAt>SYSDATETIME() ORDER BY CreatedAt,LookupId; IF @id IS NOT NULL UPDATE dbo.BackupLookupRequest SET Status='CLAIMED',LeaseExpiresAt=DATEADD(MINUTE,5,SYSDATETIME()) WHERE LookupId=@id; COMMIT; SELECT LookupId,QueryType,SearchKeyword,FilterYear FROM dbo.BackupLookupRequest WHERE LookupId=@id;"
  Using cmd As New SqlCommand(sql,cn)
   cmd.Parameters.Add("@t",SqlDbType.NVarChar,256).Value=apiKey
   Using rd=cmd.ExecuteReader()
    If Not rd.Read() OrElse rd.IsDBNull(0) Then Return New With {.ok=True,.hasLookup=False}
    Return New With {.ok=True,.hasLookup=True,.lookupId=rd("LookupId").ToString(),.queryType=rd("QueryType").ToString(),.searchKeyword=DbText(rd,"SearchKeyword"),.filterYear=DbText(rd,"FilterYear")}
   End Using
  End Using
 End Function

 Private Function CompleteLookup(cn As SqlConnection,apiKey As String,lookupText As String,body As Dictionary(Of String,Object)) As Object
  Dim lookupId As Guid : If Not Guid.TryParse(lookupText,lookupId) Then Throw New HttpException(400,"Lookup tidak valid.")
  Dim succeeded=Not String.Equals(GetValue(body,"success"),"false",StringComparison.OrdinalIgnoreCase)
  Dim resultJson As String=Nothing,errorMessage=GetValue(body,"errorMessage")
  If body.ContainsKey("result") AndAlso body("result") IsNot Nothing Then resultJson=CreateJsonSerializer().Serialize(body("result"))
  If resultJson IsNot Nothing AndAlso resultJson.Length>2000000 Then Throw New HttpException(400,"Hasil lookup terlalu besar.")
  If errorMessage.Length>1000 Then errorMessage=errorMessage.Substring(0,1000)
  Dim sql="SET NOCOUNT ON; UPDATE q SET Status=CASE WHEN @ok=1 THEN 'SUCCESS' ELSE 'FAILED' END,ResultJson=CASE WHEN @ok=1 THEN @json ELSE NULL END,ErrorMessage=CASE WHEN @ok=1 THEN NULL ELSE @error END,CompletedAt=SYSDATETIME(),LeaseExpiresAt=NULL,ExpiresAt=DATEADD(MINUTE,15,SYSDATETIME()) FROM dbo.BackupLookupRequest q JOIN dbo.BackupAgentNode a ON a.AgentName=q.AgentName WHERE q.LookupId=@id AND q.Status='CLAIMED' AND a.IsPrimary=1 AND a.IsEnabled=1 AND a.ApiKeyHash=HASHBYTES('SHA2_256',@t); SELECT Status FROM dbo.BackupLookupRequest WHERE LookupId=@id;"
  Using cmd As New SqlCommand(sql,cn)
   cmd.Parameters.Add("@id",SqlDbType.UniqueIdentifier).Value=lookupId:cmd.Parameters.Add("@t",SqlDbType.NVarChar,256).Value=apiKey:cmd.Parameters.Add("@ok",SqlDbType.Bit).Value=succeeded
   cmd.Parameters.Add("@json",SqlDbType.NVarChar,-1).Value=If(resultJson Is Nothing,CObj(DBNull.Value),resultJson)
   cmd.Parameters.Add("@error",SqlDbType.NVarChar,1000).Value=If(String.IsNullOrWhiteSpace(errorMessage),CObj(DBNull.Value),errorMessage)
   Dim status=Convert.ToString(cmd.ExecuteScalar())
   If status="" Then Throw New HttpException(403,"Lookup tidak dapat diselesaikan oleh agent ini.")
   Return New With {.ok=True,.status=status}
  End Using
 End Function

 Private Function CheckSourceNims(cn As SqlConnection,apiKey As String,body As Dictionary(Of String,Object)) As Object
  Dim values=TryCast(If(body.ContainsKey("nims"),body("nims"),Nothing),IList)
  If values Is Nothing OrElse values.Count=0 OrElse values.Count>500 Then Throw New HttpException(400,"Daftar NIM pemeriksaan tidak valid.")
  Dim unique As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
  For Each value In values
   Dim nim=Convert.ToString(value).Trim():If nim.Length=9 Then unique.Add(nim)
  Next
  If unique.Count=0 Then Throw New HttpException(400,"Daftar NIM pemeriksaan tidak berisi NIM valid.")
  Dim existing As New List(Of String)(),parameters As New List(Of String)()
  Using cmd As New SqlCommand("",cn)
   Dim i=0
   For Each nim In unique
    Dim name="@n" & i.ToString():parameters.Add(name):cmd.Parameters.Add(name,SqlDbType.Char,9).Value=nim:i+=1
   Next
   cmd.Parameters.Add("@t",SqlDbType.NVarChar,256).Value=apiKey
   cmd.CommandText="IF NOT EXISTS(SELECT 1 FROM dbo.BackupAgentNode WHERE IsPrimary=1 AND IsEnabled=1 AND ApiKeyHash=HASHBYTES('SHA2_256',@t)) THROW 51104,'Token agent tidak valid.',1; SELECT DISTINCT RTRIM(nim1) Nim1 FROM dbo.tbio01 WHERE nim1 IN (" & String.Join(",",parameters.ToArray()) & ");"
   Using rd=cmd.ExecuteReader():While rd.Read():existing.Add(rd("Nim1").ToString().Trim()):End While:End Using
  End Using
  Return New With {.ok=True,.existingNims=existing.ToArray()}
 End Function

 Private Function GetBackupBatch(cn As SqlConnection,apiKey As String,jobText As String,body As Dictionary(Of String,Object)) As Object
  Dim jobId As Guid : If Not Guid.TryParse(jobText,jobId) Then Throw New HttpException(400,"Job tidak valid.")
  Dim batchSize As Integer=1000,requested As Integer
  If Integer.TryParse(GetValue(body,"batchSize"),requested) Then batchSize=requested
  If batchSize<1 OrElse batchSize>1000 Then Throw New HttpException(400,"Ukuran batch backup harus antara 1 dan 1000.")
  Dim nims As New List(Of String)()
  Try
   Using cmd As New SqlCommand("dbo.sp_AgentGetBackupBatch",cn)
    cmd.CommandType=CommandType.StoredProcedure
    cmd.Parameters.Add("@ApiKey",SqlDbType.NVarChar,256).Value=apiKey
    cmd.Parameters.Add("@JobId",SqlDbType.UniqueIdentifier).Value=jobId
    cmd.Parameters.Add("@BatchSize",SqlDbType.Int).Value=batchSize
    Using rd=cmd.ExecuteReader()
     While rd.Read() : nims.Add(rd("Nim1").ToString().Trim()) : End While
    End Using
   End Using
  Catch ex As SqlException When ex.Number=51110
   Using cmd As New SqlCommand("SET NOCOUNT ON; IF NOT EXISTS(SELECT 1 FROM dbo.BackupTransferJob j JOIN dbo.BackupAgentNode a ON a.AgentName=j.AgentName WHERE j.JobId=@j AND j.OperationType='BACKUP' AND j.Status IN('CLAIMED','TRANSFERRING') AND a.IsPrimary=1 AND a.IsEnabled=1 AND a.ApiKeyHash=HASHBYTES('SHA2_256',@t)) THROW 51104,'Job atau token tidak valid.',1; UPDATE dbo.BackupTransferJob SET Status='TRANSFERRING',LeaseExpiresAt=DATEADD(MINUTE,10,SYSDATETIME()) WHERE JobId=@j; SELECT TOP(@s) Nim1 FROM dbo.BackupTransferJobStudent WHERE JobId=@j AND Status='PENDING' ORDER BY Nim1;",cn)
    cmd.Parameters.Add("@j",SqlDbType.UniqueIdentifier).Value=jobId
    cmd.Parameters.Add("@t",SqlDbType.NVarChar,256).Value=apiKey
    cmd.Parameters.Add("@s",SqlDbType.Int).Value=batchSize
    Using rd=cmd.ExecuteReader()
     While rd.Read() : nims.Add(rd("Nim1").ToString().Trim()) : End While
    End Using
   End Using
  End Try
  Dim backupScope=GetBackupScope(cn,apiKey,jobId)
  Dim selectedTables=GetSelectedJobTables(cn,apiKey,jobId,"BACKUP")
  Dim tables As New Dictionary(Of String,Object)()
  For Each sourceTable In selectedTables
   tables(sourceTable & "_backup")=GetRows(cn,sourceTable,nims,If(sourceTable="tbio01","",backupScope))
  Next
  Return New With {.ok=True,.jobId=jobText,.batchSize=batchSize,.nims=nims,.backupScope=backupScope,.selectedTables=String.Join(",",selectedTables.ToArray()),.tables=tables}
 End Function

 Private Function NormalizeSelectedTables(value As String) As List(Of String)
  Dim allowed=New String(){"tbio01","treg","tkrs06","t_absensi14"},chosen As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
  If String.IsNullOrWhiteSpace(value) Then value=String.Join(",",allowed)
  For Each raw In value.Split(","c)
   Dim tableName=raw.Trim().ToLowerInvariant()
   If tableName="" Then Continue For
   If Array.IndexOf(allowed,tableName)<0 Then Throw New HttpException(400,"Pilihan tabel job tidak valid.")
   chosen.Add(tableName)
  Next
  If chosen.Count=0 Then Throw New HttpException(400,"Minimal satu tabel harus dipilih.")
  chosen.Add("tbio01")
  Dim result As New List(Of String)()
  For Each tableName In allowed : If chosen.Contains(tableName) Then result.Add(tableName)
  Next
  Return result
 End Function

 Private Function GetSelectedJobTables(cn As SqlConnection,apiKey As String,jobId As Guid,operation As String) As List(Of String)
  Using cmd As New SqlCommand("SELECT j.SelectedTables FROM dbo.BackupTransferJob j JOIN dbo.BackupAgentNode a ON a.AgentName=j.AgentName WHERE j.JobId=@j AND j.OperationType=@o AND a.IsPrimary=1 AND a.IsEnabled=1 AND a.ApiKeyHash=HASHBYTES('SHA2_256',@t)",cn)
   cmd.Parameters.Add("@j",SqlDbType.UniqueIdentifier).Value=jobId
   cmd.Parameters.Add("@o",SqlDbType.VarChar,10).Value=operation
   cmd.Parameters.Add("@t",SqlDbType.NVarChar,256).Value=apiKey
   Dim value=cmd.ExecuteScalar()
   If value Is Nothing Then Throw New HttpException(403,"Pilihan tabel job tidak dapat dibaca.")
   Return NormalizeSelectedTables(Convert.ToString(value))
  End Using
 End Function

 Private Function GetBackupScope(cn As SqlConnection,apiKey As String,jobId As Guid) As String
  Using cmd As New SqlCommand("SELECT ISNULL(j.RestoreThAkdkList,'') FROM dbo.BackupTransferJob j JOIN dbo.BackupAgentNode a ON a.AgentName=j.AgentName WHERE j.JobId=@j AND j.OperationType='BACKUP' AND a.IsPrimary=1 AND a.IsEnabled=1 AND a.ApiKeyHash=HASHBYTES('SHA2_256',@t)",cn)
   cmd.Parameters.Add("@j",SqlDbType.UniqueIdentifier).Value=jobId
   cmd.Parameters.Add("@t",SqlDbType.NVarChar,256).Value=apiKey
   Dim value=cmd.ExecuteScalar()
   If value Is Nothing Then Throw New HttpException(403,"Cakupan job backup tidak dapat dibaca.")
   Return Convert.ToString(value).Trim().ToUpperInvariant()
  End Using
 End Function

 Private Sub AddBackupScopeFilter(cmd As SqlCommand,sourceTable As String,scope As String,ByRef sql As String)
  If sourceTable="tbio01" OrElse String.IsNullOrWhiteSpace(scope) Then Return
  Dim mode="",startTa="",endTa=""
  If scope.StartsWith("SINGLE:",StringComparison.Ordinal) Then
   mode="SINGLE":endTa=scope.Substring(7)
  ElseIf scope.StartsWith("UP_TO:",StringComparison.Ordinal) Then
   mode="UP_TO":endTa=scope.Substring(6)
  ElseIf scope.StartsWith("RANGE:",StringComparison.Ordinal) Then
   Dim values=scope.Substring(6).Split("-"c)
   If values.Length=2 Then mode="RANGE":startTa=values(0):endTa=values(1)
  End If
   If mode="" OrElse Not IsAcademicPeriod(endTa) Then Throw New HttpException(400,"Cakupan Tahun Akademik job tidak valid.")
  cmd.Parameters.Add("@scopeEnd",SqlDbType.Char,5).Value=endTa
  If mode="SINGLE" Then
   sql &= " AND LTRIM(RTRIM(th_akdk))=@scopeEnd"
  ElseIf mode="UP_TO" Then
   sql &= " AND LTRIM(RTRIM(th_akdk))<=@scopeEnd"
  Else
    If Not IsAcademicPeriod(startTa) Then Throw New HttpException(400,"Rentang Tahun Akademik job tidak valid.")
   cmd.Parameters.Add("@scopeStart",SqlDbType.Char,5).Value=startTa
   sql &= " AND LTRIM(RTRIM(th_akdk)) BETWEEN @scopeStart AND @scopeEnd"
  End If
 End Sub

 Private Function IsAcademicPeriod(value As String) As Boolean
  If value Is Nothing OrElse value.Length<>5 Then Return False
  For Each character As Char In value
   If Not Char.IsDigit(character) Then Return False
  Next
  Return True
 End Function

 Private Function GetRows(cn As SqlConnection,sourceTable As String,nims As List(Of String),scope As String) As List(Of Dictionary(Of String,Object))
  Dim result As New List(Of Dictionary(Of String,Object))()
  If nims.Count=0 Then Return result
  Dim cols As New List(Of String)()
  Using cm As New SqlCommand("SELECT QUOTENAME(name) FROM sys.columns WHERE object_id=OBJECT_ID('dbo." & sourceTable & "') ORDER BY column_id",cn),rd=cm.ExecuteReader()
   While rd.Read() : cols.Add(rd(0).ToString()) : End While
  End Using
  Using cmd As New SqlCommand("",cn)
   Dim ps As New List(Of String)()
   For i As Integer=0 To nims.Count-1
    Dim pn="@n" & i.ToString() : ps.Add(pn) : cmd.Parameters.Add(pn,SqlDbType.Char,9).Value=nims(i)
   Next
   Dim sql="SELECT " & String.Join(",",cols.ToArray()) & " FROM dbo." & sourceTable & " WHERE nim1 IN (" & String.Join(",",ps.ToArray()) & ")"
   AddBackupScopeFilter(cmd,sourceTable,scope,sql)
   cmd.CommandText=sql
   Using rd=cmd.ExecuteReader()
    While rd.Read()
     Dim row As New Dictionary(Of String,Object)()
     For i As Integer=0 To rd.FieldCount-1 : row(rd.GetName(i))=If(rd.IsDBNull(i),Nothing,rd.GetValue(i)) : Next
     result.Add(row)
    End While
   End Using
  End Using
  Return result
 End Function

 Private Function ConfirmBackupBatch(cn As SqlConnection,apiKey As String,jobText As String,body As Dictionary(Of String,Object)) As Object
  Dim jobId As Guid
  If Not Guid.TryParse(jobText,jobId) OrElse Not body.ContainsKey("nims") Then Throw New HttpException(400,"Konfirmasi batch tidak valid.")
  Using cmd As New SqlCommand("dbo.sp_AgentConfirmBackupBatch",cn)
   cmd.CommandType=CommandType.StoredProcedure
   cmd.Parameters.Add("@ApiKey",SqlDbType.NVarChar,256).Value=apiKey
   cmd.Parameters.Add("@JobId",SqlDbType.UniqueIdentifier).Value=jobId
   cmd.Parameters.Add("@NimsJson",SqlDbType.NVarChar,-1).Value=CreateJsonSerializer().Serialize(body("nims"))
   Using rd=cmd.ExecuteReader()
    If rd.Read() Then Return New With {.ok=True,.status=rd("Status").ToString(),.copiedStudents=Convert.ToInt32(rd("CopiedStudents")),.pendingStudents=Convert.ToInt32(rd("PendingStudents"))}
   End Using
  End Using
  Throw New HttpException(500,"Konfirmasi backup tidak menghasilkan status.")
 End Function

 Private Function SyncInventory(cn As SqlConnection,apiKey As String,body As Dictionary(Of String,Object)) As Object
  If Not body.ContainsKey("periods") Then Throw New HttpException(400,"Inventaris tidak tersedia.")
  Using cmd As New SqlCommand("dbo.sp_AgentSyncPeriodInventory",cn)
   cmd.CommandType=CommandType.StoredProcedure
   cmd.Parameters.Add("@ApiKey",SqlDbType.NVarChar,256).Value=apiKey
   cmd.Parameters.Add("@InventoryJson",SqlDbType.NVarChar,-1).Value=CreateJsonSerializer().Serialize(body("periods"))
   cmd.ExecuteNonQuery()
  End Using
 Return New With {.ok=True}
 End Function

 Private Function CompleteExport(cn As SqlConnection,apiKey As String,jobText As String,body As Dictionary(Of String,Object)) As Object
  Dim jobId As Guid : If Not Guid.TryParse(jobText,jobId) Then Throw New HttpException(400,"Job tidak valid.")
  Dim fileName=Path.GetFileName(GetValue(body,"fileName")),hash=GetValue(body,"sha256"),sizeBytes As Long
  If String.IsNullOrWhiteSpace(fileName) OrElse Not fileName.EndsWith(".bak",StringComparison.OrdinalIgnoreCase) Then Throw New HttpException(400,"Nama file ekspor tidak valid.")
  If hash.Length<>64 OrElse Not Long.TryParse(GetValue(body,"sizeBytes"),sizeBytes) OrElse sizeBytes<=0 Then Throw New HttpException(400,"Metadata ekspor tidak valid.")
  Dim detail="File lokal: " & fileName & " | Ukuran: " & Math.Round(sizeBytes/1048576.0,2).ToString("N2",CultureInfo.InvariantCulture) & " MB | SHA-256: " & hash.ToUpperInvariant() & " | RESTORE VERIFYONLY berhasil."
  Using cmd As New SqlCommand("SET NOCOUNT ON; UPDATE j SET Status='SUCCESS',ProcessedStudents=0,CompletedAt=SYSDATETIME(),LeaseExpiresAt=NULL,ProgressMessage=NULL,ResultMessage=@m,ErrorMessage=NULL FROM dbo.BackupTransferJob j JOIN dbo.BackupAgentNode a ON a.AgentName=j.AgentName WHERE j.JobId=@j AND j.OperationType='EXPORT' AND j.Status IN('CLAIMED','TRANSFERRING') AND a.IsPrimary=1 AND a.IsEnabled=1 AND a.ApiKeyHash=HASHBYTES('SHA2_256',@t); SELECT j.Status,j.ResultMessage FROM dbo.BackupTransferJob j JOIN dbo.BackupAgentNode a ON a.AgentName=j.AgentName WHERE j.JobId=@j AND j.OperationType='EXPORT' AND j.Status='SUCCESS' AND a.ApiKeyHash=HASHBYTES('SHA2_256',@t);",cn)
   cmd.Parameters.Add("@j",SqlDbType.UniqueIdentifier).Value=jobId
   cmd.Parameters.Add("@t",SqlDbType.NVarChar,256).Value=apiKey
   cmd.Parameters.Add("@m",SqlDbType.NVarChar,2000).Value=detail
   Using rd=cmd.ExecuteReader()
    If rd.Read() Then Return New With {.ok=True,.status=rd("Status").ToString(),.message=DbText(rd,"ResultMessage")}
   End Using
  End Using
  Throw New HttpException(403,"Konfirmasi ekspor ditolak.")
 End Function

 Private Function RestorePush(cn As SqlConnection,apiKey As String,jobText As String,body As Dictionary(Of String,Object)) As Object
  Dim jobId As Guid
  If Not Guid.TryParse(jobText,jobId) OrElse Not body.ContainsKey("tables") OrElse Not body.ContainsKey("nims") Then Throw New HttpException(400,"Payload pemulihan tidak valid.")
  Dim nims=TryCast(body("nims"),System.Collections.IList),tables=TryCast(body("tables"),Dictionary(Of String,Object))
  If nims Is Nothing OrElse tables Is Nothing OrElse nims.Count=0 OrElse nims.Count>500 Then Throw New HttpException(400,"Batch pemulihan tidak valid.")
  ValidateRestoreJob(cn,apiKey,jobId)
  Dim selectedTables=GetSelectedJobTables(cn,apiKey,jobId,"RESTORE")
  Dim newNims=GetUnrestoredNims(cn,jobId,nims)
  Dim tx=cn.BeginTransaction()
  Try
   Dim insertedNims As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
   If newNims.Count>0 Then
    ValidateRequiredRestoreRows(tables,newNims,selectedTables)
    For Each sourceTable In selectedTables
     insertedNims.UnionWith(InsertMissingLiveRows(cn,tx,tables,sourceTable & "_backup",sourceTable,newNims))
    Next
   End If
   Dim skippedNims As New HashSet(Of String)(newNims,StringComparer.OrdinalIgnoreCase)
   skippedNims.ExceptWith(insertedNims)
   Dim confirmNims As New List(Of String)()
   For Each nim In insertedNims : confirmNims.Add(nim) : Next
   Dim lastNim=Convert.ToString(nims(nims.Count-1)).Trim()
   Dim processed As Integer
   Using cmd As New SqlCommand("dbo.sp_AgentConfirmRestoreBatch",cn,tx)
    cmd.CommandType=CommandType.StoredProcedure
    cmd.Parameters.Add("@ApiKey",SqlDbType.NVarChar,256).Value=apiKey
    cmd.Parameters.Add("@JobId",SqlDbType.UniqueIdentifier).Value=jobId
    cmd.Parameters.Add("@NimsJson",SqlDbType.NVarChar,-1).Value=CreateJsonSerializer().Serialize(confirmNims)
    cmd.Parameters.Add("@LastNim",SqlDbType.Char,9).Value=lastNim
    Using rd=cmd.ExecuteReader()
     If rd.Read() Then processed=Convert.ToInt32(rd("ProcessedStudents"))
     End Using
    End Using
    Dim summary=ApplyRestoreConflictStatuses(cn,tx,jobId,skippedNims)
    processed=summary(0)
    tx.Commit()
    Return New With {.ok=True,.restoredStudents=insertedNims.Count,.skippedStudents=skippedNims.Count,.totalSkippedStudents=summary(1),.processedStudents=processed,.lastProgressNim=lastNim}
  Catch
   If tx.Connection IsNot Nothing Then tx.Rollback()
   Throw
  End Try
 End Function

 Private Function ValidateRestoreJob(cn As SqlConnection,apiKey As String,jobId As Guid) As Boolean
  Using cmd As New SqlCommand("SELECT j.StudentNim FROM dbo.BackupTransferJob j JOIN dbo.BackupAgentNode a ON a.AgentName=j.AgentName WHERE j.JobId=@j AND j.OperationType='RESTORE' AND j.Status IN('CLAIMED','TRANSFERRING') AND a.IsPrimary=1 AND a.IsEnabled=1 AND a.ApiKeyHash=HASHBYTES('SHA2_256',@t)",cn)
   cmd.Parameters.Add("@j",SqlDbType.UniqueIdentifier).Value=jobId : cmd.Parameters.Add("@t",SqlDbType.NVarChar,256).Value=apiKey
   Dim value=cmd.ExecuteScalar()
   If value Is Nothing Then Throw New HttpException(403,"Job pemulihan atau token tidak valid.")
   Return value IsNot DBNull.Value AndAlso Not String.IsNullOrWhiteSpace(Convert.ToString(value))
  End Using
 End Function

 Private Function BackupMetrics(cn As SqlConnection,apiKey As String,jobText As String,body As Dictionary(Of String,Object)) As Object
  Dim jobId As Guid : If Not Guid.TryParse(jobText,jobId) Then Throw New HttpException(400,"Job tidak valid.")
  Dim phase=GetValue(body,"phase").Trim().ToLowerInvariant()
  If phase="baseline" Then
   Using cmd As New SqlCommand("IF NOT EXISTS(SELECT 1 FROM dbo.BackupTransferJob j JOIN dbo.BackupAgentNode a ON a.AgentName=j.AgentName WHERE j.JobId=@j AND j.OperationType='BACKUP' AND j.Status IN('CLAIMED','TRANSFERRING') AND a.IsPrimary=1 AND a.IsEnabled=1 AND a.ApiKeyHash=HASHBYTES('SHA2_256',@t)) THROW 51104,'Job atau token tidak valid.',1; SELECT (SELECT COUNT(*) FROM dbo.tbio01) BioRows,(SELECT COUNT(*) FROM dbo.treg) RegRows,(SELECT COUNT(*) FROM dbo.tkrs06) KrsRows,(SELECT COUNT(*) FROM dbo.t_absensi14) AbsRows,(SELECT SUM(CONVERT(decimal(18,2),size)*8.0/1024.0) FROM sys.database_files WHERE type=0) SizeMb;",cn)
    cmd.Parameters.Add("@j",SqlDbType.UniqueIdentifier).Value=jobId:cmd.Parameters.Add("@t",SqlDbType.NVarChar,256).Value=apiKey
    Using rd=cmd.ExecuteReader():rd.Read():Return New With {.ok=True,.bioRows=Convert.ToInt64(rd("BioRows")),.regRows=Convert.ToInt64(rd("RegRows")),.krsRows=Convert.ToInt64(rd("KrsRows")),.absRows=Convert.ToInt64(rd("AbsRows")),.sizeMb=Convert.ToDouble(rd("SizeMb"))}:End Using
   End Using
  End If
  If phase<>"complete" Then Throw New HttpException(400,"Fase metrik backup tidak valid.")
  Dim liveBioBefore=BodyLong(body,"liveBioBefore"),liveRegBefore=BodyLong(body,"liveRegBefore"),liveKrsBefore=BodyLong(body,"liveKrsBefore"),liveAbsBefore=BodyLong(body,"liveAbsBefore")
  Dim liveSizeBefore=BodyDouble(body,"liveSizeBefore")
  Dim arcBioBefore=BodyLong(body,"arcBioBefore"),arcRegBefore=BodyLong(body,"arcRegBefore"),arcKrsBefore=BodyLong(body,"arcKrsBefore"),arcAbsBefore=BodyLong(body,"arcAbsBefore"),arcBioAfter=BodyLong(body,"arcBioAfter"),arcRegAfter=BodyLong(body,"arcRegAfter"),arcKrsAfter=BodyLong(body,"arcKrsAfter"),arcAbsAfter=BodyLong(body,"arcAbsAfter")
  Dim arcSizeBefore=BodyDouble(body,"arcSizeBefore"),arcSizeAfter=BodyDouble(body,"arcSizeAfter")
  Using cmd As New SqlCommand("SET NOCOUNT ON; DECLARE @processed int=(SELECT ProcessedStudents FROM dbo.BackupTransferJob WHERE JobId=@j),@m nvarchar(2000); SET @m=CONCAT(ISNULL(@processed,0),' Data Mahasiswa Berhasil Dibackup'); UPDATE j SET ProgressMessage=NULL,ResultMessage=@m,ErrorMessage=NULL FROM dbo.BackupTransferJob j JOIN dbo.BackupAgentNode a ON a.AgentName=j.AgentName WHERE j.JobId=@j AND j.OperationType='BACKUP' AND j.Status='SUCCESS' AND a.IsPrimary=1 AND a.IsEnabled=1 AND a.ApiKeyHash=HASHBYTES('SHA2_256',@t); IF @@ROWCOUNT<>1 THROW 51104,'Snapshot job atau token tidak valid.',1; SELECT @m Message;",cn)
   cmd.Parameters.Add("@j",SqlDbType.UniqueIdentifier).Value=jobId:cmd.Parameters.Add("@t",SqlDbType.NVarChar,256).Value=apiKey
   cmd.Parameters.Add("@lbb",SqlDbType.BigInt).Value=liveBioBefore:cmd.Parameters.Add("@lrb",SqlDbType.BigInt).Value=liveRegBefore:cmd.Parameters.Add("@lkb",SqlDbType.BigInt).Value=liveKrsBefore:cmd.Parameters.Add("@lab",SqlDbType.BigInt).Value=liveAbsBefore
   cmd.Parameters.Add("@lsb",SqlDbType.Decimal).Value=liveSizeBefore
   cmd.Parameters.Add("@abb",SqlDbType.BigInt).Value=arcBioBefore:cmd.Parameters.Add("@arb",SqlDbType.BigInt).Value=arcRegBefore:cmd.Parameters.Add("@akb",SqlDbType.BigInt).Value=arcKrsBefore:cmd.Parameters.Add("@aab",SqlDbType.BigInt).Value=arcAbsBefore:cmd.Parameters.Add("@aba",SqlDbType.BigInt).Value=arcBioAfter:cmd.Parameters.Add("@ara",SqlDbType.BigInt).Value=arcRegAfter:cmd.Parameters.Add("@aka",SqlDbType.BigInt).Value=arcKrsAfter:cmd.Parameters.Add("@aaa",SqlDbType.BigInt).Value=arcAbsAfter
   cmd.Parameters.Add("@asb",SqlDbType.Decimal).Value=arcSizeBefore:cmd.Parameters.Add("@asa",SqlDbType.Decimal).Value=arcSizeAfter
   Return New With {.ok=True,.message=Convert.ToString(cmd.ExecuteScalar())}
  End Using
 End Function

 Private Function BodyLong(body As Dictionary(Of String,Object),name As String) As Long
  Try
   If Not body.ContainsKey(name) OrElse body(name) Is Nothing Then Throw New Exception()
   Dim value=Convert.ToInt64(body(name),CultureInfo.InvariantCulture):If value<0 Then Throw New Exception()
   Return value
  Catch
   Throw New HttpException(400,"Metrik " & name & " tidak valid.")
  End Try
 End Function
 Private Function BodyDouble(body As Dictionary(Of String,Object),name As String) As Double
  Try
   If Not body.ContainsKey(name) OrElse body(name) Is Nothing Then Throw New Exception()
   Dim value=Convert.ToDouble(body(name),CultureInfo.InvariantCulture):If value<0 Then Throw New Exception()
   Return value
  Catch
   Throw New HttpException(400,"Metrik " & name & " tidak valid.")
  End Try
 End Function

 Private Sub RunScheduledBackup(cn As SqlConnection)
  Dim enabled As Boolean=False,frequency As String="",cutoff As String="",selectedTables As String="tbio01,treg,tkrs06,t_absensi14",requestedBy As String="Application",executionTime As TimeSpan,nextRun As Nullable(Of DateTime)=Nothing
  Using cmd As New SqlCommand("SELECT IsEnabled,Frequency,ExecutionTime,CutoffThAkdk,NextRunAt,SelectedTables,UpdatedBy FROM dbo.BackupJobConfiguration WHERE ConfigurationId=1",cn)
   Using rd=cmd.ExecuteReader()
    If Not rd.Read() Then Return
    enabled=Convert.ToBoolean(rd("IsEnabled"))
    frequency=rd("Frequency").ToString().Trim()
    executionTime=CType(rd("ExecutionTime"),TimeSpan)
    cutoff=rd("CutoffThAkdk").ToString().Trim()
    selectedTables=rd("SelectedTables").ToString().Trim()
    requestedBy=rd("UpdatedBy").ToString().Trim()
    If Not rd.IsDBNull(rd.GetOrdinal("NextRunAt")) Then nextRun=CType(rd("NextRunAt"),DateTime)
   End Using
  End Using
  If Not enabled OrElse Not nextRun.HasValue OrElse nextRun.Value>DateTime.Now Then Return
  Using cmd As New SqlCommand("SELECT COUNT(*) FROM dbo.BackupTransferJob WHERE OperationType='BACKUP' AND Status IN('WAITING','CLAIMED','TRANSFERRING')",cn)
   If Convert.ToInt32(cmd.ExecuteScalar())>0 Then Return
  End Using
  Using cmd As New SqlCommand("dbo.sp_CreateBackupTransferJob",cn)
   cmd.CommandType=CommandType.StoredProcedure
   cmd.Parameters.Add("@CutoffThAkdk",SqlDbType.Char,5).Value=cutoff
   cmd.Parameters.Add("@RequestedBy",SqlDbType.VarChar,50).Value=requestedBy
   cmd.Parameters.Add("@TriggerSource",SqlDbType.VarChar,10).Value="SCHEDULED"
   cmd.Parameters.Add("@SelectedTables",SqlDbType.VarChar,100).Value=selectedTables
   cmd.CommandTimeout=60
   cmd.ExecuteNonQuery()
  End Using
  Using cmd As New SqlCommand("dbo.sp_SaveBackupJobConfiguration",cn)
   cmd.CommandType=CommandType.StoredProcedure
   cmd.Parameters.Add("@IsEnabled",SqlDbType.Bit).Value=True
   cmd.Parameters.Add("@Frequency",SqlDbType.VarChar,10).Value=frequency
   cmd.Parameters.Add("@ExecutionTime",SqlDbType.Time).Value=executionTime
   cmd.Parameters.Add("@CutoffThAkdk",SqlDbType.Char,5).Value=cutoff
   cmd.Parameters.Add("@AdminUser",SqlDbType.VarChar,50).Value=requestedBy
   cmd.Parameters.Add("@SelectedTables",SqlDbType.VarChar,100).Value=selectedTables
   cmd.ExecuteNonQuery()
  End Using
 End Sub

 Private Function GetUnrestoredNims(cn As SqlConnection,jobId As Guid,nims As System.Collections.IList) As HashSet(Of String)
  Dim result As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
  For Each value In nims : result.Add(Convert.ToString(value).Trim()) : Next
  Using cmd As New SqlCommand("",cn)
   Dim ps As New List(Of String)()
   For i As Integer=0 To nims.Count-1
    Dim pn="@n" & i.ToString() : ps.Add(pn) : cmd.Parameters.Add(pn,SqlDbType.Char,9).Value=Convert.ToString(nims(i))
   Next
   cmd.Parameters.Add("@j",SqlDbType.UniqueIdentifier).Value=jobId
   cmd.CommandText="SELECT Nim1 FROM dbo.BackupTransferJobStudent WHERE JobId=@j AND Status IN('RESTORED','SKIPPED') AND Nim1 IN (" & String.Join(",",ps.ToArray()) & ")"
   Using rd=cmd.ExecuteReader() : While rd.Read() : result.Remove(rd(0).ToString().Trim()) : End While : End Using
  End Using
  Return result
 End Function

 Private Function NormalizeRows(value As Object) As System.Collections.IList
  Dim rows=TryCast(value,System.Collections.IList)
  If rows IsNot Nothing Then Return rows
  Dim result As New ArrayList()
  If TryCast(value,Dictionary(Of String,Object)) IsNot Nothing Then result.Add(value)
  Return result
 End Function
 Private Sub ValidateRequiredRestoreRows(tables As Dictionary(Of String,Object),nims As HashSet(Of String),selectedTables As List(Of String))
  For Each sourceTable In selectedTables
   Dim tableName=sourceTable & "_backup"
   If Not tables.ContainsKey(tableName) Then Throw New HttpException(400,"Payload " & tableName & " tidak tersedia.")
  Next
  For Each tableName In New String(){"tbio01_backup"}
   Dim rows=NormalizeRows(tables(tableName)),found As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
   If rows IsNot Nothing Then
    For Each raw In rows
     Dim row=TryCast(raw,Dictionary(Of String,Object))
     If row IsNot Nothing AndAlso row.ContainsKey("nim1") Then found.Add(Convert.ToString(row("nim1")).Trim())
    Next
   End If
   For Each nim In nims
    If Not found.Contains(nim) Then Throw New HttpException(400,"Payload restore tidak lengkap untuk NIM " & nim & ".")
   Next
  Next
 End Sub
 Private Function ApplyRestoreConflictStatuses(cn As SqlConnection,tx As SqlTransaction,jobId As Guid,conflicts As HashSet(Of String)) As Integer()
  Using cmd As New SqlCommand("",cn,tx)
   cmd.Parameters.Add("@j",SqlDbType.UniqueIdentifier).Value=jobId
   If conflicts.Count>0 Then
    Dim ps As New List(Of String)(),i As Integer=0
    For Each nim In conflicts
     Dim pn="@s" & i.ToString() : ps.Add(pn) : cmd.Parameters.Add(pn,SqlDbType.Char,9).Value=nim : i+=1
    Next
    cmd.CommandText="UPDATE dbo.BackupTransferJobStudent SET Status='SKIPPED' WHERE JobId=@j AND Nim1 IN (" & String.Join(",",ps.ToArray()) & ");"
   End If
   cmd.CommandText &= "DECLARE @restored int=(SELECT COUNT(*) FROM dbo.BackupTransferJobStudent WHERE JobId=@j AND Status='RESTORED'),@skipped int=(SELECT COUNT(*) FROM dbo.BackupTransferJobStudent WHERE JobId=@j AND Status='SKIPPED'); UPDATE dbo.BackupTransferJob SET ProcessedStudents=@restored WHERE JobId=@j; SELECT @restored RestoredStudents,@skipped SkippedStudents;"
   Using rd=cmd.ExecuteReader()
    If rd.Read() Then Return New Integer(){Convert.ToInt32(rd("RestoredStudents")),Convert.ToInt32(rd("SkippedStudents"))}
   End Using
  End Using
  Throw New ApplicationException("Ringkasan pemulihan tidak tersedia.")
 End Function

 Private Function InsertMissingLiveRows(cn As SqlConnection,tx As SqlTransaction,tables As Dictionary(Of String,Object),sourceName As String,targetName As String,allowedNims As HashSet(Of String)) As HashSet(Of String)
  Dim insertedNims As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
  If Not tables.ContainsKey(sourceName) Then Return insertedNims
  Dim rows=NormalizeRows(tables(sourceName)) : If rows.Count=0 Then Return insertedNims
  Dim typeMap=GetColumnTypes(cn,tx,targetName),included As New List(Of KeyValuePair(Of String,String))()
  For Each col In typeMap
   For Each raw In rows
    Dim candidate=TryCast(raw,Dictionary(Of String,Object))
    If candidate IsNot Nothing AndAlso candidate.ContainsKey("nim1") AndAlso allowedNims.Contains(Convert.ToString(candidate("nim1")).Trim()) AndAlso candidate.ContainsKey(col.Key) Then included.Add(col) : Exit For
   Next
  Next
  If included.Count=0 Then Return insertedNims
  Dim keyColumns=GetRestoreKeyColumns(cn,tx,targetName,typeMap)
  Dim includedNames As New HashSet(Of String)(included.ConvertAll(Function(c) c.Key),StringComparer.OrdinalIgnoreCase)
  If Not includedNames.Contains("nim1") Then Throw New HttpException(400,"Payload " & sourceName & " tidak memiliki kolom nim1.")
  For Each keyColumn In keyColumns
   If Not includedNames.Contains(keyColumn) Then Throw New HttpException(400,"Payload " & sourceName & " tidak memiliki kolom kunci " & keyColumn & ".")
  Next
  Dim table As New DataTable()
  Using schemaCmd As New SqlCommand("SELECT TOP (0) " & String.Join(",",included.ConvertAll(Function(c) "[" & c.Key.Replace("]","]]" ) & "]").ToArray()) & " FROM dbo.[" & targetName.Replace("]","]]" ) & "]",cn,tx)
   Using rd=schemaCmd.ExecuteReader()
    For i As Integer=0 To rd.FieldCount-1 : table.Columns.Add(rd.GetName(i),rd.GetFieldType(i)) : Next
   End Using
  End Using
  For Each raw In rows
   Dim source=TryCast(raw,Dictionary(Of String,Object))
   If source Is Nothing OrElse Not source.ContainsKey("nim1") OrElse Not allowedNims.Contains(Convert.ToString(source("nim1")).Trim()) Then Continue For
   Dim dataRow=table.NewRow()
   For Each col In included
    If Not source.ContainsKey(col.Key) OrElse source(col.Key) Is Nothing Then dataRow(col.Key)=DBNull.Value Else dataRow(col.Key)=ConvertBulkValue(source(col.Key),table.Columns(col.Key).DataType)
   Next
   table.Rows.Add(dataRow)
  Next
  If table.Rows.Count=0 Then Return insertedNims
  Dim stage="#RestoreStage_" & Guid.NewGuid().ToString("N")
  Dim columnNames As New List(Of String)()
  For Each column As DataColumn In table.Columns : columnNames.Add(column.ColumnName) : Next
  Dim quotedColumns=columnNames.ConvertAll(Function(name) "[" & name.Replace("]","]]" ) & "]")
  Using createCmd As New SqlCommand("SELECT TOP (0) " & String.Join(",",quotedColumns.ToArray()) & " INTO [" & stage.Replace("]","]]" ) & "] FROM dbo.[" & targetName.Replace("]","]]" ) & "]",cn,tx)
   createCmd.ExecuteNonQuery()
  End Using
  Using bulk As New SqlBulkCopy(cn,SqlBulkCopyOptions.TableLock Or SqlBulkCopyOptions.CheckConstraints,tx)
   bulk.DestinationTableName="[" & stage.Replace("]","]]" ) & "]" : bulk.BatchSize=table.Rows.Count : bulk.BulkCopyTimeout=600
   For Each column As DataColumn In table.Columns : bulk.ColumnMappings.Add(column.ColumnName,column.ColumnName) : Next
   bulk.WriteToServer(table)
  End Using
  Dim keyExpressions As New List(Of String)(),partitionColumns As New List(Of String)()
  For Each keyColumn In keyColumns
   Dim quotedKey="[" & keyColumn.Replace("]","]]" ) & "]"
   keyExpressions.Add("(target." & quotedKey & "=source_rows." & quotedKey & " OR (target." & quotedKey & " IS NULL AND source_rows." & quotedKey & " IS NULL))")
   partitionColumns.Add(quotedKey)
  Next
  Dim selectValues=columnNames.ConvertAll(Function(name) "source_rows.[" & name.Replace("]","]]" ) & "]")
  Dim sql="SET NOCOUNT ON; DECLARE @inserted TABLE(Nim1 nvarchar(50)); " &
   ";WITH source_rows AS(SELECT " & String.Join(",",quotedColumns.ToArray()) & ",ROW_NUMBER() OVER(PARTITION BY " & String.Join(",",partitionColumns.ToArray()) & " ORDER BY (SELECT 0)) rn FROM [" & stage.Replace("]","]]" ) & "]) " &
   "INSERT dbo.[" & targetName.Replace("]","]]" ) & "](" & String.Join(",",quotedColumns.ToArray()) & ") OUTPUT CONVERT(nvarchar(50),INSERTED.[nim1]) INTO @inserted(Nim1) " &
   "SELECT " & String.Join(",",selectValues.ToArray()) & " FROM source_rows WHERE source_rows.rn=1 AND NOT EXISTS(SELECT 1 FROM dbo.[" & targetName.Replace("]","]]" ) & "] target WHERE " & String.Join(" AND ",keyExpressions.ToArray()) & "); SELECT DISTINCT Nim1 FROM @inserted;"
  Using insertCmd As New SqlCommand(sql,cn,tx)
   insertCmd.CommandTimeout=600
   Using rd=insertCmd.ExecuteReader()
    While rd.Read() : insertedNims.Add(Convert.ToString(rd(0)).Trim()) : End While
   End Using
  End Using
  Return insertedNims
 End Function

 Private Function GetRestoreKeyColumns(cn As SqlConnection,tx As SqlTransaction,tableName As String,typeMap As List(Of KeyValuePair(Of String,String))) As List(Of String)
  Dim result As New List(Of String)()
  Dim sql="DECLARE @indexId int=(SELECT TOP(1) index_id FROM sys.indexes WHERE object_id=OBJECT_ID(@table) AND is_unique=1 AND is_disabled=0 AND has_filter=0 ORDER BY is_primary_key DESC,index_id); SELECT c.name FROM sys.index_columns ic JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id WHERE ic.object_id=OBJECT_ID(@table) AND ic.index_id=@indexId AND ic.is_included_column=0 ORDER BY ic.key_ordinal;"
  Using cmd As New SqlCommand(sql,cn,tx)
   cmd.Parameters.Add("@table",SqlDbType.NVarChar,260).Value="dbo." & tableName
   Using rd=cmd.ExecuteReader() : While rd.Read() : result.Add(Convert.ToString(rd(0))) : End While : End Using
  End Using
  If result.Count=0 Then
   Dim fallback As New Dictionary(Of String,String())(StringComparer.OrdinalIgnoreCase)
   fallback("tbio01")=New String(){"nim1"}
   fallback("treg")=New String(){"th_akdk","nim1"}
   fallback("tkrs06")=New String(){"th_akdk","nim1","kode_mk","kd_kls"}
   fallback("t_absensi14")=New String(){"th_akdk","kd_mk","kd_kls","jns_kul","tgl_temu","nim1","temuke"}
   If Not fallback.ContainsKey(tableName) Then Throw New ApplicationException("Kunci aman tabel " & tableName & " tidak tersedia.")
   Dim available As New HashSet(Of String)(typeMap.ConvertAll(Function(c) c.Key),StringComparer.OrdinalIgnoreCase)
   For Each keyColumn In fallback(tableName)
    If Not available.Contains(keyColumn) Then Throw New ApplicationException("Kunci aman tabel " & tableName & " tidak lengkap: " & keyColumn & ".")
    result.Add(keyColumn)
   Next
  End If
  Return result
 End Function

 Private Function ConvertBulkValue(value As Object,dataType As Type) As Object
  If value Is Nothing Then Return DBNull.Value
  If dataType Is GetType(Byte()) AndAlso TypeOf value Is System.Collections.IList Then
   Dim a=DirectCast(value,System.Collections.IList),b(a.Count-1) As Byte
   For i As Integer=0 To a.Count-1 : b(i)=Convert.ToByte(a(i)) : Next
   Return b
  End If
  If dataType Is GetType(Guid) Then Return Guid.Parse(Convert.ToString(value))
  If dataType Is GetType(DateTime) Then Return Convert.ToDateTime(value)
  If dataType Is GetType(DateTimeOffset) Then Return DateTimeOffset.Parse(Convert.ToString(value))
  If dataType Is GetType(TimeSpan) Then Return TimeSpan.Parse(Convert.ToString(value))
  Return Convert.ChangeType(value,dataType,System.Globalization.CultureInfo.InvariantCulture)
 End Function
 Private Function GetColumnTypes(cn As SqlConnection,tx As SqlTransaction,tableName As String) As List(Of KeyValuePair(Of String,String))
  Dim result As New List(Of KeyValuePair(Of String,String))()
  Using cmd As New SqlCommand("SELECT c.name,t.name FROM sys.columns c JOIN sys.types t ON t.user_type_id=c.user_type_id WHERE c.object_id=OBJECT_ID('dbo." & tableName & "') AND c.is_identity=0 AND c.is_computed=0 AND t.name NOT IN ('timestamp','rowversion') ORDER BY c.column_id",cn,tx),rd=cmd.ExecuteReader()
   While rd.Read() : result.Add(New KeyValuePair(Of String,String)(rd(0).ToString(),rd(1).ToString())) : End While
  End Using
  Return result
 End Function

 Private Function CompleteRestore(cn As SqlConnection,apiKey As String,jobText As String) As Object
  Dim jobId As Guid : If Not Guid.TryParse(jobText,jobId) Then Throw New HttpException(400,"Job tidak valid.")
  Dim sql="SET NOCOUNT ON; DECLARE @restored int=(SELECT COUNT(*) FROM dbo.BackupTransferJobStudent WHERE JobId=@j AND Status='RESTORED'),@skipped int=(SELECT COUNT(*) FROM dbo.BackupTransferJobStudent WHERE JobId=@j AND Status='SKIPPED'); UPDATE j SET Status='SUCCESS',ProcessedStudents=@restored,CompletedAt=SYSDATETIME(),LeaseExpiresAt=NULL,ProgressMessage=NULL,ResultMessage=CONCAT(@restored,' Data Mahasiswa Memiliki Baris yang Berhasil Dipulihkan',CASE WHEN @skipped>0 THEN CONCAT(CHAR(13),CHAR(10),@skipped,' Data Mahasiswa Dilewati Karena Seluruh Baris Sudah Tersedia') ELSE '' END),ErrorMessage=NULL FROM dbo.BackupTransferJob j JOIN dbo.BackupAgentNode a ON a.AgentName=j.AgentName WHERE j.JobId=@j AND j.OperationType='RESTORE' AND j.Status IN('CLAIMED','TRANSFERRING') AND a.IsPrimary=1 AND a.IsEnabled=1 AND a.ApiKeyHash=HASHBYTES('SHA2_256',@t); SELECT j.Status,j.ProcessedStudents,@skipped SkippedStudents FROM dbo.BackupTransferJob j JOIN dbo.BackupAgentNode a ON a.AgentName=j.AgentName WHERE j.JobId=@j AND j.OperationType='RESTORE' AND j.Status='SUCCESS' AND a.IsPrimary=1 AND a.IsEnabled=1 AND a.ApiKeyHash=HASHBYTES('SHA2_256',@t);"
  Using cmd As New SqlCommand(sql,cn)
   cmd.Parameters.Add("@t",SqlDbType.NVarChar,256).Value=apiKey
   cmd.Parameters.Add("@j",SqlDbType.UniqueIdentifier).Value=jobId
   Using rd=cmd.ExecuteReader()
    If rd.Read() Then Return New With {.ok=True,.status=rd("Status").ToString(),.processedStudents=Convert.ToInt32(rd("ProcessedStudents")),.skippedStudents=Convert.ToInt32(rd("SkippedStudents"))}
   End Using
  End Using
  Throw New HttpException(500,"Penyelesaian restore tidak menghasilkan status.")
 End Function


 Private Function GetSchema(cn As SqlConnection) As List(Of Dictionary(Of String,Object))
  Dim result As New List(Of Dictionary(Of String,Object))()
  Dim sql="SELECT CASE o.name WHEN 'tbio01' THEN 'tbio01_backup' WHEN 'treg' THEN 'treg_backup' WHEN 'tkrs06' THEN 'tkrs06_backup' WHEN 't_absensi14' THEN 't_absensi14_backup' END TargetTable,c.column_id ColumnOrder,c.name ColumnName,CASE WHEN t.name IN ('varchar','char','varbinary','binary') THEN t.name+'('+CASE WHEN c.max_length=-1 THEN 'max' ELSE CONVERT(varchar(10),c.max_length) END+')' WHEN t.name IN ('nvarchar','nchar') THEN t.name+'('+CASE WHEN c.max_length=-1 THEN 'max' ELSE CONVERT(varchar(10),c.max_length/2) END+')' WHEN t.name IN ('decimal','numeric') THEN t.name+'('+CONVERT(varchar(10),c.precision)+','+CONVERT(varchar(10),c.scale)+')' WHEN t.name IN ('datetime2','datetimeoffset','time') THEN t.name+'('+CONVERT(varchar(10),c.scale)+')' ELSE t.name END SqlType,c.is_nullable IsNullable,CONVERT(bit,CASE WHEN ic.column_id IS NULL THEN 0 ELSE 1 END) IsKey,ISNULL(ic.key_ordinal,0) KeyOrder FROM sys.columns c JOIN sys.objects o ON o.object_id=c.object_id JOIN sys.types t ON t.user_type_id=c.user_type_id OUTER APPLY(SELECT TOP(1) i.index_id FROM sys.indexes i WHERE i.object_id=c.object_id AND i.is_unique=1 AND i.is_disabled=0 AND i.has_filter=0 ORDER BY i.is_primary_key DESC,i.index_id) ux LEFT JOIN sys.index_columns ic ON ic.object_id=c.object_id AND ic.index_id=ux.index_id AND ic.column_id=c.column_id AND ic.is_included_column=0 WHERE o.schema_id=SCHEMA_ID('dbo') AND o.name IN ('tbio01','treg','tkrs06','t_absensi14') ORDER BY TargetTable,c.column_id"
  Using cmd As New SqlCommand(sql,cn),rd=cmd.ExecuteReader()
   While rd.Read()
    Dim row As New Dictionary(Of String,Object)()
    row("table")=rd("TargetTable").ToString() : row("order")=CInt(rd("ColumnOrder")) : row("name")=rd("ColumnName").ToString() : row("type")=rd("SqlType").ToString() : row("nullable")=CBool(rd("IsNullable")) : row("key")=CBool(rd("IsKey")) : row("keyOrder")=CInt(rd("KeyOrder")) : result.Add(row)
   End While
  End Using
  Return result
 End Function

 Private Function DbText(rd As SqlDataReader,name As String) As String
  Dim ordinal=rd.GetOrdinal(name) : Return If(rd.IsDBNull(ordinal),"",rd.GetValue(ordinal).ToString().Trim())
 End Function
 Private Function DbIntOptional(rd As SqlDataReader,name As String) As Integer
  Try
   Dim ordinal=rd.GetOrdinal(name)
   Return If(rd.IsDBNull(ordinal),0,Convert.ToInt32(rd(ordinal)))
  Catch ex As IndexOutOfRangeException
   Return 0
  End Try
 End Function
 Private Function GetValue(data As Dictionary(Of String,Object),name As String) As String
  If Not data.ContainsKey(name) OrElse data(name) Is Nothing Then Return ""
  Return Convert.ToString(data(name))
 End Function
 Private Sub WriteApiErrorHeader(context As HttpContext,message As String)
  context.Response.Headers("X-Backup-Error")=Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(If(message,"")))
 End Sub
 Private Function CreateJsonSerializer() As JavaScriptSerializer
  Dim serializer As New JavaScriptSerializer()
  serializer.MaxJsonLength=Integer.MaxValue
  serializer.RecursionLimit=200
  Return serializer
 End Function
 Private Sub WriteJson(context As HttpContext,statusCode As Integer,value As Object)
  context.Response.StatusCode=statusCode : context.Response.Write(CreateJsonSerializer().Serialize(value))
 End Sub
</script>
