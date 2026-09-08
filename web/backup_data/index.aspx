<%@ Page Language="VB" MasterPageFile="Site.master" MaintainScrollPositionOnPostback="True" Title="Backup Data Mahasiswa" %>
<%@ Register TagPrefix="uc" TagName="BackupSection" Src="index.ascx" %>

<asp:Content ID="TitleContent" ContentPlaceHolderID="TitleContent" runat="server">
    Backup Data Mahasiswa | Universitas Tarumanagara
</asp:Content>

<asp:Content ID="MainContent" ContentPlaceHolderID="MainContent" runat="server">
    <uc:BackupSection ID="secBackup" runat="server" />
</asp:Content>
