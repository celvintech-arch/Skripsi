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
        
        ' 2. Proteksi ViewState Tampering (Anti-CSRF):
        ' Mengikat token ViewState dengan ID Sesi dan User ID pengguna yang sedang login.
        ViewStateUserKey = Session.SessionID & "|" & Convert.ToString(Session("idlintar"))
        
        ' 3. Kebijakan Cache Browser:
        ' Memastikan browser tidak menyimpan cache halaman administratif agar data monitoring selalu real-time.
        Response.Cache.SetCacheability(HttpCacheability.NoCache)
        Response.Cache.SetNoStore()
    End Sub

    ' =========================================================================================
    ' SIKLUS HIDUP HALAMAN: OnPreLoad
    ' Melakukan validasi Anti-CSRF Token unik per permintaan postback untuk mencegah replay attack.
    ' =========================================================================================
    Protected Overrides Sub OnPreLoad(ByVal e As EventArgs)
        Dim tokenKey As String = "BackupPostbackToken|" & Convert.ToString(Session("idlintar"))
        Dim token As String = Convert.ToString(Session(tokenKey))
        
        ' Jika terjadi PostBack, verifikasi token yang dikirimkan klien cocok dengan token di sesi server.
        If IsPostBack AndAlso (String.IsNullOrEmpty(token) OrElse
           Not String.Equals(Convert.ToString(ViewState("BackupPostbackToken")), token, StringComparison.Ordinal)) Then
            Throw New HttpException(400, "Formulir sudah tidak berlaku. Muat ulang halaman sebelum melanjutkan.")
        End If
        
        ' Buat token acak baru (GUID) untuk siklus request berikutnya.
        If String.IsNullOrEmpty(token) Then
            token = Guid.NewGuid().ToString("N")
            Session(tokenKey) = token
        End If
        ViewState("BackupPostbackToken") = token
        
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
