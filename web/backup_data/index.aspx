<%@ Page Language="VB" MasterPageFile="Site.master" MaintainScrollPositionOnPostback="True" EnableViewStateMac="True" EnableEventValidation="True" Title="Backup Data Mahasiswa" %>
<%@ Register TagPrefix="uc" TagName="BackupSection" Src="index.ascx" %>

<script runat="server">
    ' =========================================================================================
    ' SIKLUS HIDUP HALAMAN: OnInit
    ' Bertanggung jawab atas autentikasi sesi pengguna LINTAR dan keamanan HTTP cache.
    ' =========================================================================================
    Protected Overrides Sub OnInit(ByVal e As EventArgs)
        MyBase.OnInit(e)
        
        ' 1. Validasi Autentikasi Global LINTAR:
        ' Memeriksa apakah sesi pengguna (idlintar / userid_lintar) sah dan masih aktif.
        ' Jika sesi habis/tidak sah, fungsi ini otomatis me-redirect pengguna ke halaman login utama.
        cekauthlintarNew()
        
        ' 2. Proteksi ViewState Tampering (Anti-CSRF Resmi ASP.NET):
        ' Mengikat token ViewState dengan ID Sesi dan User ID pengguna yang sedang login.
        ViewStateUserKey = Session.SessionID & "|" & Convert.ToString(Session("idlintar"))
        
        ' 3. Kebijakan Cache Browser:
        ' Memastikan browser tidak menyimpan cache halaman administratif agar data monitoring selalu real-time.
        Response.Cache.SetCacheability(HttpCacheability.NoCache)
        Response.Cache.SetNoStore()
    End Sub

    ' =========================================================================================
    ' SIKLUS HIDUP HALAMAN: OnPreLoad
    ' Sinkronisasi token formulir yang aman dan toleran terhadap multi-tab browsing.
    ' =========================================================================================
    Protected Overrides Sub OnPreLoad(ByVal e As EventArgs)
        Dim userId As String = Convert.ToString(Session("idlintar"))
        Dim tokenKey As String = "BackupPostbackToken|" & userId
        Dim token As String = Convert.ToString(Session(tokenKey))
        
        ' Jika token sesi belum terbentuk, buat token baru
        If String.IsNullOrEmpty(token) Then
            token = Guid.NewGuid().ToString("N")
            Session(tokenKey) = token
        End If
        
        ' Pastikan ViewState selalu terisi token yang valid tanpa melempar unhandled exception
        If ViewState("BackupPostbackToken") Is Nothing Then
            ViewState("BackupPostbackToken") = token
        End If
        
        MyBase.OnPreLoad(e)
    End Sub
</script>

<asp:Content ID="TitleContent" ContentPlaceHolderID="TitleContent" runat="server">
    Backup Data Mahasiswa | Universitas Tarumanagara
</asp:Content>

<asp:Content ID="MainContent" ContentPlaceHolderID="MainContent" runat="server">
    <%-- Include koneksi dan fungsi global autentikasi portal LINTAR 2022 --%>
    <!-- #INCLUDE virtual="/con_ascx2022/conlintar2022.ascx" -->
    
    <%-- Memuat controller dinamis untuk memuat tab modul yang aktif --%>
    <uc:BackupSection ID="secBackup" runat="server" />
</asp:Content>
