<%-- 
=============================================================================================
HELPER PEMETAAN TABEL & TEKS RAMAH PENGGUNA (table_helpers.ascx)
Berkas ini bertugas memvalidasi pilihan tabel akademik, memetakan nama fisik tabel ke
label bahasa Indonesia, dan membersihkan teks log teknis agar mudah dibaca pengguna.
=============================================================================================
--%>
<%@ Import Namespace="System.Collections.Generic" %>

<script runat="server">
    ' =========================================================================================
    ' VALIDASI & PEMILIHAN TABEL
    ' Mengambil daftar tabel yang dicentang pengguna pada antarmuka CheckBoxList.
    ' Aturan: Tabel Biodata (tbio01) wajib selalu disertakan karena merupakan tabel induk relasional.
    ' =========================================================================================
    Private Function SelectedTables(list As CheckBoxList, requireAcademic As Boolean) As String
        Dim chosen As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
        For Each item As ListItem In list.Items
            If item.Selected Then chosen.Add(item.Value)
        Next
        
        ' Validasi minimal satu tabel terpilih
        If chosen.Count = 0 Then Throw New ApplicationException("Pilih minimal satu tabel.")
        
        ' Validasi modul akademik
        If requireAcademic AndAlso Not chosen.Contains("treg") AndAlso Not chosen.Contains("tkrs06") AndAlso Not chosen.Contains("t_absensi14") Then
            Throw New ApplicationException("Pilih minimal satu tabel Registrasi, KRS, atau Absensi.")
        End If
        
        ' Pastikan tbio01 (Biodata Mahasiswa) selalu disertakan sebagai induk relasi foreign key
        chosen.Add("tbio01")
        For Each item As ListItem In list.Items
            item.Selected = chosen.Contains(item.Value)
        Next
        
        ' Urutkan tabel sesuai urutan dependensi relasional
        Dim result As New List(Of String)()
        For Each name In New String() {"tbio01", "treg", "tkrs06", "t_absensi14"}
            If chosen.Contains(name) Then result.Add(name)
        Next
        Return String.Join(",", result.ToArray())
    End Function

    ' =========================================================================================
    ' PENERJEMAH NAMA TABEL FISIK KE LABEL ANTARMUKA
    ' Contoh: "tbio01,tkrs06" diterjemahkan menjadi "Biodata, KRS"
    ' =========================================================================================
    Private Function BackupTableLabels(value As String, Optional emptyLabel As String = "-") As String
        Dim labels As New System.Collections.Generic.List(Of String)()
        For Each name In value.Split(","c)
            Select Case name.Trim().ToLowerInvariant()
                Case "tbio01" : labels.Add("Biodata")
                Case "treg" : labels.Add("Registrasi")
                Case "tkrs06" : labels.Add("KRS")
                Case "t_absensi14" : labels.Add("Absensi")
            End Select
        Next
        Return If(labels.Count = 0, emptyLabel, String.Join(", ", labels.ToArray()))
    End Function

    ' =========================================================================================
    ' PEMBERSIH TEKS LOG TEKNIS (USER-FRIENDLY TEXT SANITIZER)
    ' Menghilangkan metadata kriptografi teknis (SHA-256) dan mengganti nama tabel fisik
    ' dengan nama yang mudah dipahami oleh staf operasional pada antarmuka web.
    ' =========================================================================================
    Private Function BackupFriendlyText(value As String) As String
        If String.IsNullOrWhiteSpace(value) Then Return value
        Dim result = value
        
        ' Sembunyikan hash SHA-256 dari pesan riwayat ekspor lama tanpa mengubah log di database
        result = System.Text.RegularExpressions.Regex.Replace(result, "(?i)\s*\|\s*SHA-256:\s*[0-9A-F]+\s*(?=\||$)", "")
        result = System.Text.RegularExpressions.Regex.Replace(result, "\s*\|\s*", " | ")
        
        ' Ganti nama tabel fisik menjadi nama modul berbahasa Indonesia
        result = System.Text.RegularExpressions.Regex.Replace(result, "(?i)\bt_absensi14_backup\b", "Absensi")
        result = System.Text.RegularExpressions.Regex.Replace(result, "(?i)\btkrs06_backup\b", "KRS")
        result = System.Text.RegularExpressions.Regex.Replace(result, "(?i)\btbio01_backup\b", "Biodata")
        result = System.Text.RegularExpressions.Regex.Replace(result, "(?i)\btreg_backup\b", "Registrasi")
        result = System.Text.RegularExpressions.Regex.Replace(result, "(?i)\bt_absensi14\b", "Absensi")
        result = System.Text.RegularExpressions.Regex.Replace(result, "(?i)\btkrs06\b", "KRS")
        result = System.Text.RegularExpressions.Regex.Replace(result, "(?i)\btbio01\b", "Biodata")
        result = System.Text.RegularExpressions.Regex.Replace(result, "(?i)\btreg\b", "Registrasi")
        Return result
    End Function
</script>
