<%@ Page Language="VB" MasterPageFile="Site.master" MaintainScrollPositionOnPostback="True" EnableViewStateMac="True" EnableEventValidation="True" Title="Backup Data Mahasiswa" %>
<%@ Register TagPrefix="uc" TagName="BackupSection" Src="index.ascx" %>

<script runat="server">
    Protected Overrides Sub OnInit(ByVal e As EventArgs)
        MyBase.OnInit(e)
        cekauthlintarNew()
        ViewStateUserKey = Session.SessionID & "|" & Convert.ToString(Session("idlintar"))
        Response.Cache.SetCacheability(HttpCacheability.NoCache)
        Response.Cache.SetNoStore()
    End Sub

    Protected Overrides Sub OnPreLoad(ByVal e As EventArgs)
        Dim tokenKey As String = "BackupPostbackToken|" & Convert.ToString(Session("idlintar"))
        Dim token As String = Convert.ToString(Session(tokenKey))
        If IsPostBack AndAlso (String.IsNullOrEmpty(token) OrElse
           Not String.Equals(Convert.ToString(ViewState("BackupPostbackToken")), token, StringComparison.Ordinal)) Then
            Throw New HttpException(400, "Formulir sudah tidak berlaku. Muat ulang halaman sebelum melanjutkan.")
        End If
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
    <!-- #INCLUDE virtual="/con_ascx2022/conlintar2022.ascx" -->
    <uc:BackupSection ID="secBackup" runat="server" />
</asp:Content>
