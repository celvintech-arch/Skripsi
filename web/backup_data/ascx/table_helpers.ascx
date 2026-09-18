<%-- Shared presentation/selection rules; no database access. --%>
<%@ Import Namespace="System.Collections.Generic" %>
<script runat="server">
Private Function SelectedTables(list As CheckBoxList,requireAcademic As Boolean) As String
 Dim chosen As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
 For Each item As ListItem In list.Items
  If item.Selected Then chosen.Add(item.Value)
 Next
 If chosen.Count=0 Then Throw New ApplicationException("Pilih minimal satu tabel.")
 If requireAcademic AndAlso Not chosen.Contains("treg") AndAlso Not chosen.Contains("tkrs06") AndAlso Not chosen.Contains("t_absensi14") Then Throw New ApplicationException("Pilih minimal satu tabel Registrasi, KRS, atau Absensi.")
 chosen.Add("tbio01")
 For Each item As ListItem In list.Items : item.Selected=chosen.Contains(item.Value) : Next
 Dim result As New List(Of String)()
 For Each name In New String(){"tbio01","treg","tkrs06","t_absensi14"} : If chosen.Contains(name) Then result.Add(name)
 Next
 Return String.Join(",",result.ToArray())
End Function

Private Function BackupTableLabels(value As String,Optional emptyLabel As String="-") As String
 Dim labels As New System.Collections.Generic.List(Of String)()
 For Each name In value.Split(","c)
  Select Case name.Trim().ToLowerInvariant()
   Case "tbio01":labels.Add("Biodata")
   Case "treg":labels.Add("Registrasi")
   Case "tkrs06":labels.Add("KRS")
   Case "t_absensi14":labels.Add("Absensi")
  End Select
 Next
 Return If(labels.Count=0,emptyLabel,String.Join(", ",labels.ToArray()))
End Function

Private Function BackupFriendlyText(value As String) As String
 If String.IsNullOrWhiteSpace(value) Then Return value
 Dim result=value
 ' Hide SHA-256 metadata from legacy export messages without changing stored history.
 result=System.Text.RegularExpressions.Regex.Replace(result,"(?i)\s*\|\s*SHA-256:\s*[0-9A-F]+\s*(?=\||$)","")
 result=System.Text.RegularExpressions.Regex.Replace(result,"\s*\|\s*"," | ")
 ' Replace longer backup identifiers first so no technical suffix remains visible.
 result=System.Text.RegularExpressions.Regex.Replace(result,"(?i)\bt_absensi14_backup\b","Absensi")
 result=System.Text.RegularExpressions.Regex.Replace(result,"(?i)\btkrs06_backup\b","KRS")
 result=System.Text.RegularExpressions.Regex.Replace(result,"(?i)\btbio01_backup\b","Biodata")
 result=System.Text.RegularExpressions.Regex.Replace(result,"(?i)\btreg_backup\b","Registrasi")
 result=System.Text.RegularExpressions.Regex.Replace(result,"(?i)\bt_absensi14\b","Absensi")
 result=System.Text.RegularExpressions.Regex.Replace(result,"(?i)\btkrs06\b","KRS")
 result=System.Text.RegularExpressions.Regex.Replace(result,"(?i)\btbio01\b","Biodata")
 result=System.Text.RegularExpressions.Regex.Replace(result,"(?i)\btreg\b","Registrasi")
 Return result
End Function
</script>
