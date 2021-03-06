{ ############################################################################ }
{ #                                                                          # }
{ #  MirandaNG HistoryToDB Plugin v2.6                                       # }
{ #                                                                          # }
{ #  License: GPLv3                                                          # }
{ #                                                                          # }
{ #  Author: Grigorev Michael (icq: 161867489, email: sleuthhound@gmail.com) # }
{ #                                                                          # }
{ ############################################################################ }

unit MsgExport;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, JvWizard, JvExControls, JvWizardRouteMapNodes, ComCtrls, StdCtrls,
  JvComponentBase, JvThread, JclStringConversions, Global, Contacts, m_api, Event;

type
  TContactRecord = record
    hContact: TMCONTACT;
    ContactID: AnsiString;
    ContactName: AnsiString;
    ProtoName: AnsiString;
    Selected: Boolean;
  end;
  TExportForm = class(TForm)
    IMExportWizard: TJvWizard;
    Page1: TJvWizardWelcomePage;
    Page2: TJvWizardInteriorPage;
    Page3: TJvWizardInteriorPage;
    Page4: TJvWizardInteriorPage;
    LExportDesc: TLabel;
    IMExportThread: TJvThread;
    CBSelectAll: TCheckBox;
    ContactList: TListView;
    PBTotalExport: TProgressBar;
    LExportDesc2: TLabel;
    CBSyncRequest: TCheckBox;
    LExportDone: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure Page3Page(Sender: TObject);
    procedure IMExportWizardCancelButtonClick(Sender: TObject);
    procedure IMExportWizardFinishButtonClick(Sender: TObject);
    procedure IMExportThreadExecute(Sender: TObject; Params: Pointer);
    procedure CBSelectAllClick(Sender: TObject);
    procedure ContactListChanging(Sender: TObject; Item: TListItem; Change: TItemChange; var AllowChange: Boolean);
    procedure ContactListChange(Sender: TObject; Item: TListItem; Change: TItemChange);
    procedure BringFormToFront(Form: TForm);
    function CheckStopExportAndExit: Boolean;
  private
    { Private declarations }
    StartExport: Boolean;
    // ��� �������������� ���������
    procedure OnLanguageChanged(var Msg: TMessage); message WM_LANGUAGECHANGED;
    procedure LoadLanguageStrings;
  public
    { Public declarations }
  end;

var
  ExportForm: TExportForm;
  ExportContactRecords: Array of TContactRecord;

implementation

{$R *.dfm}
{$R icons.res}

procedure TExportForm.FormCreate(Sender: TObject);
begin
  StartExport := False;
  ExportFormDestroy := False;
  // ��� �������������� ���������
  ExportFormHandle := Handle;
  SetWindowLong(Handle, GWL_HWNDPARENT, 0);
  SetWindowLong(Handle, GWL_EXSTYLE, GetWindowLong(Handle, GWL_EXSTYLE) or WS_EX_APPWINDOW);
  // ��������� ���� ����������
  LoadLanguageStrings;
end;

procedure TExportForm.FormShow(Sender: TObject);
var
  ListItem: TListItem;
  hContact: TMCONTACT;
  ContactProto, ContactID, ContactName: AnsiString;
  Count: Integer;
begin
  IMExportWizard.ActivePage := Page1;
  StartExport := False;
  ContactList.Columns[0].MaxWidth := 190;
  ContactList.Columns[1].MaxWidth := 90;
  ContactList.Columns[2].MaxWidth := 140;
  ContactList.Items.BeginUpdate;
  Count := 0;
  // �������� ������ ���������
  hContact := db_find_first();
  while hContact <> 0 do
  begin
    ContactProto := GetContactProto(hContact);
    ContactID := GetContactID(hContact, ContactProto);
    ContactName := GetContactDisplayName(hContact, '', True);
    // ���. �������� ���������
    if ContactProto = MyAccount then
      ContactProto := 'ICQ';
    if ContactName = '' then
      ContactName := 'NoContactName';
    if ContactID = '' then
      ContactID := 'NoContactID';
    SetLength(ExportContactRecords, Count + 1);
    ExportContactRecords[Count].hContact := hContact;
    ExportContactRecords[Count].ContactID := ContactID;
    ExportContactRecords[Count].ContactName := ContactName;
    ExportContactRecords[Count].ProtoName := ContactProto;
    ExportContactRecords[Count].Selected := False;
    Inc(Count);
    ListItem := ContactList.Items.Add;
    ListItem.Caption := ContactName;
    ListItem.SubItems.Add(ContactProto);
    ListItem.SubItems.Add(ContactID);
    {if StrContactProtoToInt(ContactProto) = 15 then // 15 - Unknown Proto
      ListItem.Checked := False
    else
      ListItem.Checked := True;}
    hContact := db_find_next(hContact);
  end;
  ContactList.Items.EndUpdate;
end;

procedure TExportForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  if ImportLogOpened then
    CloseLogFile(5);
  ExportFormDestroy := True;
  Action := caFree;
end;

procedure TExportForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := CheckStopExportAndExit;
end;

procedure TExportForm.IMExportWizardCancelButtonClick(Sender: TObject);
begin
  Close;
end;

procedure TExportForm.IMExportWizardFinishButtonClick(Sender: TObject);
begin
  if IMExportWizard.ActivePage = Page4 then
  begin
    if CBSyncRequest.Checked then
      OnSendMessageToAllComponent('002');
    Close;
  end;
end;

procedure TExportForm.Page3Page(Sender: TObject);
begin
  StartExport := True;
  Page3.EnabledButtons := [bkCancel];
  if not IMExportThread.Terminated then
  begin
    IMExportThread.Terminate;
    while not (IMExportThread.Terminated) do
      Sleep(1);
  end;
  IMExportThread.Execute(Self);
end;

procedure TExportForm.IMExportThreadExecute(Sender: TObject; Params: Pointer);
var
  ContactRecordCnt, J, ProtoType: Integer;
  SelectedCount: Integer;
  hDBEvent: THandle;
  Msg_Date: TDateTime;
  Msg_RcvrNick, Msg_RcvrAcc, Msg_SenderNick, Msg_SenderAcc, Msg_Text, MD5String: WideString;
  Date_Str, MsgStatus: String;
  ContactProto, ContactID, ContactName: AnsiString;
  MyContactName, MyContactID: AnsiString;
  HI: THistoryItem;
  UserCodepage: Cardinal;
  UserContactProto: AnsiString;
  UseDefaultCP: Boolean;
  DBEventCount: Integer;
begin
  LExportDesc2.Caption := 'Export...';
  // ������������ ���������� ���������� ���������
  SelectedCount := 0;
  for J := 0 to Length(ExportContactRecords) do
  begin
    if ExportContactRecords[J].Selected = True then
      Inc(SelectedCount);
    if IMExportThread.Terminated then // ����� �� ������ � ������ �������� ����
      Exit;
  end;
  LExportDesc.Caption := Format(GetLangStr('TotalSelect'), [IntToStr(SelectedCount), IntToStr(Length(ExportContactRecords))]);
  // �������� ������� ���� ���������
  PBTotalExport.Position := 0;
  PBTotalExport.Max := SelectedCount;
  SelectedCount := 0;
  for ContactRecordCnt := 0 to Length(ExportContactRecords) do
  begin
    // ���� �������, �� ������������ ��� �������
    if ExportContactRecords[ContactRecordCnt].Selected = True then
    begin
      LExportDesc2.Caption := Format(GetLangStr('ContactExport'), [ExportContactRecords[ContactRecordCnt].ContactName, ExportContactRecords[ContactRecordCnt].ContactID]);
      Inc(SelectedCount);
      PBTotalExport.Position := SelectedCount;
      UserContactProto := GetContactProto(ExportContactRecords[ContactRecordCnt].hContact);
      UserCodepage := GetContactCodePage(ExportContactRecords[ContactRecordCnt].hContact, UserContactProto, UseDefaultCP);
      DBEventCount := db_event_count(ExportContactRecords[ContactRecordCnt].hContact);
      hDBEvent := db_event_first(ExportContactRecords[ContactRecordCnt].hContact);
      if EnableDebug then WriteInLog(ProfilePath, FormatDateTime('dd.mm.yy hh:mm:ss', Now) + ' - ������� IMExportThreadExecute: �������� ������� ��� Contact ID: ' + GetContactID(ExportContactRecords[ContactRecordCnt].hContact, UserContactProto) + ' | Proto: ' + UserContactProto + ' | DBEventCount: ' + IntToStr(DBEventCount), 2);
      //while (hDBEvent <> 0) and not IMExportThread.Terminated do
      while (hDBEvent <> 0) and not IMExportThread.Terminated do
      begin
        HI := ReadEvent(hDBEvent, UserCodepage);
        if EnableDebug then WriteInLog(ProfilePath, FormatDateTime('dd.mm.yy hh:mm:ss', Now) + ' - ������� IMExportThreadExecute: ' + '������� Contact ID: ' + GetContactID(ExportContactRecords[ContactRecordCnt].hContact, UserContactProto) + ' | Proto: ' + UserContactProto + ' | UserCodepage: ' + IntToStr(UserCodepage) + ' | hDBEvent: ' + IntToStr(hDBEvent) + ' | DBEventCount: ' + IntToStr(DBEventCount) + ' | HI.eventType: ' + IntToStr(HI.eventType), 2);
        if (HI.eventType = EVENTTYPE_MESSAGE and EVENTTYPE_URL) then
        begin
          // ��� �������
          ContactProto := GetContactProto(ExportContactRecords[ContactRecordCnt].hContact);
          // ������ �����������
          ContactID := GetContactID(ExportContactRecords[ContactRecordCnt].hContact, ContactProto);
          ContactName := GetContactDisplayName(ExportContactRecords[ContactRecordCnt].hContact, '', True);
          // ��� ������
          MyContactName := GetMyContactDisplayName(ContactProto);
          MyContactID := GetMyContactID(ContactProto);
          // ���. �������� ���������
          if ContactProto = MyAccount then
            ContactProto := 'ICQ';
          // ��� �������
          ProtoType := StrContactProtoToInt(ContactProto);
          if ContactID = '' then
            ContactID := 'NoContactID';
          if ContactName = '' then
            ContactName := 'NoContactName';
          if MyContactID = '' then
            MyContactID := 'NoMyContactID';
          if MyContactName = '' then
            MyContactName := 'NoMyContactName';
          // �������������, ��������������� � �.�.
          Msg_SenderNick := PrepareString(pWideChar(AnsiToWideString(MyContactName, CP_ACP)));
          Msg_SenderAcc := PrepareString(pWideChar(AnsiToWideString(MyContactID, CP_ACP)));
          Msg_SenderNick := WideStringToUTF8(Msg_SenderNick);
          Msg_SenderAcc := WideStringToUTF8(Msg_SenderAcc);
          Msg_RcvrNick := PrepareString(pWideChar(AnsiToWideString(ContactName, CP_ACP)));
          Msg_RcvrAcc := PrepareString(pWideChar(AnsiToWideString(ContactID, CP_ACP)));
          Msg_RcvrNick := WideStringToUTF8(Msg_RcvrNick);
          Msg_RcvrAcc := WideStringToUTF8(Msg_RcvrAcc);
          Msg_Text := WideStringToUTF8(PrepareString(pWideChar(HI.Text)));
          MD5String := Msg_RcvrAcc + FormatDateTime('YYYY-MM-DD HH:MM:SS', TimestampToDateTime(HI.Time)) + Msg_Text;
          if (DBType = 'oracle') or (DBType = 'oracle-9i') then
            Date_Str := FormatDateTime('DD.MM.YYYY HH:MM:SS', TimestampToDateTime(HI.Time))
          else
            Date_Str := FormatDateTime('YYYY-MM-DD HH:MM:SS', TimestampToDateTime(HI.Time));
          // ���������� ����������� �������� (�� ��������� ��� ��� ��������)
          if (mtMessage in HI.MessageType) or (mtUrl in HI.MessageType) then
          begin
            if mtIncoming in HI.MessageType then
              MsgStatus := '1'  // ��������
            else
              MsgStatus := '0'; // ���������
            if MatchStrings(LowerCase(ContactProto), 'skype*') then // ��� ��������� skype
            begin
              // ��� �������
              if EnableDebug then WriteInLog(ProfilePath, FormatDateTime('dd.mm.yy hh:mm:ss', Now) + ' - ������� IMExportThreadExecute: ' + '������� ��������� Contact ID: ' + ContactID + ' | Contact Name: ' + ContactName + ' | Proto: ' + ContactProto + ' | My Contact ID: ' + MyContactID + ' | My Contact Name: ' + MyContactName + ' | Contact Proto = ' + ContactProto + ' | MsgStatus = ' + MsgStatus + ' | DateTime = ' + FormatDateTime('DD.MM.YYYY HH:MM:SS', TimestampToDateTime(HI.Time)) + ' | Message = ' + Msg_Text, 2);
              if (MatchStrings(DBType, 'oracle*')) then // ���� Oracle, �� ����� SQL-��� � ������� CHAT_MSG_LOG_ORACLE
                WriteInLog(ProfilePath, Format(CHAT_MSG_LOG_ORACLE, [DBUserName, MsgStatus, 'to_date('''+Date_Str+''', ''dd.mm.yyyy hh24:mi:ss'')', Msg_RcvrNick, 'Skype', Msg_RcvrNick+' ('+Msg_RcvrAcc+')', BoolToIntStr(True), BoolToIntStr(False), BoolToIntStr(False), Msg_Text, EncryptMD5(MD5String)]), 5)
              else
                WriteInLog(ProfilePath, Format(CHAT_MSG_LOG, [DBUserName, MsgStatus, Date_Str, Msg_RcvrNick, 'Skype', Msg_RcvrNick+' ('+Msg_RcvrAcc+')', BoolToIntStr(True), BoolToIntStr(False), BoolToIntStr(False), Msg_Text, EncryptMD5(MD5String)]), 5);
            end
            else // ��� ��������� ����������
            begin
              // ��� �������
              if EnableDebug then WriteInLog(ProfilePath, FormatDateTime('dd.mm.yy hh:mm:ss', Now) + ' - ������� IMExportThreadExecute: ' + '������� ��������� Contact ID: ' + ContactID + ' | Contact Name: ' + ContactName + ' | Proto: ' + ContactProto + ' | My Contact ID: ' + MyContactID + ' | My Contact Name: ' + MyContactName + ' | Contact Proto = ' + ContactProto + ' | MsgStatus = ' + MsgStatus + ' | DateTime = ' + FormatDateTime('DD.MM.YYYY HH:MM:SS', TimestampToDateTime(HI.Time)) + ' | Message = ' + Msg_Text, 2);
              if (MatchStrings(DBType, 'oracle*')) then // ���� Oracle, �� ����� SQL-��� � ������� MSG_LOG_ORACLE
                WriteInLog(ProfilePath, Format(MSG_LOG_ORACLE, [DBUserName, IntToStr(ProtoType), Msg_SenderNick, Msg_SenderAcc, Msg_RcvrNick, Msg_RcvrAcc, MsgStatus, 'to_date('''+Date_Str+''', ''dd.mm.yyyy hh24:mi:ss'')', Msg_Text, EncryptMD5(MD5String)]), 5)
              else
                WriteInLog(ProfilePath, Format(MSG_LOG, [DBUserName, IntToStr(ProtoType), Msg_SenderNick, Msg_SenderAcc, Msg_RcvrNick, Msg_RcvrAcc, MsgStatus, Date_Str, Msg_Text, EncryptMD5(MD5String)]), 5);
            end;
          end;
        end;
        hDBEvent := db_event_next(ExportContactRecords[ContactRecordCnt].hContact, hDBEvent);
      end;
    end;
    if IMExportThread.Terminated then // ����� �� ������ � ������ �������� ����
      Exit;
  end;
  Page3.EnabledButtons := [bkCancel,bkNext];
  StartExport := False;
  if ImportLogOpened then
    CloseLogFile(5);
  LExportDesc2.Caption := GetLangStr('ExportDone');
end;

procedure TExportForm.BringFormToFront(Form: TForm);
begin
  if Form.WindowState = wsMaximized then
    ShowWindow(Form.Handle, SW_SHOWMAXIMIZED)
  else
    ShowWindow(Form.Handle, SW_SHOWNORMAL);
  Form.BringToFront;
end;

function TExportForm.CheckStopExportAndExit: Boolean;
begin
  if StartExport then
  begin
    case MessageBox(Handle, pWideChar(GetLangStr('ExportAbort')), pWideChar(htdPluginShortName + ' - ' +GetLangStr('ExportAbortCaption')),36) of
      6:
      begin
        if not IMExportThread.Terminated then
        begin
          IMExportThread.Terminate;
          while not (IMExportThread.Terminated) do
          begin
            Sleep(1);
            Forms.Application.ProcessMessages;
          end;
        end;
        Result := True;
      end;
      7:
      begin
        Result := False;
        Exit;
      end;
    end;
  end
  else
    Result := True;
end;

procedure TExportForm.ContactListChange(Sender: TObject; Item: TListItem; Change: TItemChange);
begin
  if Item.Checked <> ExportContactRecords[Item.Index].Selected then // ���� ������� �������� Item.Checked
  begin
    ExportContactRecords[Item.Index].Selected := Item.Checked; // �������� �������� ���������� �� ����� ��������
    { ����� ����� ������ ��� �����....}
  end;
end;

procedure TExportForm.ContactListChanging(Sender: TObject; Item: TListItem; Change: TItemChange; var AllowChange: Boolean);
begin
  ExportContactRecords[Item.Index].Selected := Item.Checked; // ���������� �������� Item.Checked, �� ���� ��� ���� �� ��� �����
  AllowChange := True; // ��������� ����� ������ :)
end;

procedure TExportForm.CBSelectAllClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to ContactList.Items.Count-1 do
  begin
    ContactList.Items[I].Checked := CBSelectAll.Checked;
    ExportContactRecords[I].Selected := CBSelectAll.Checked;
  end;
  //LExportDesc.Caption := IntToStr(Length(ExportContactRecords)) + ' - ' + IntToStr(ContactList.Items.Count);
end;

// ��� �������������� ���������
procedure TExportForm.OnLanguageChanged(var Msg: TMessage);
begin
  LoadLanguageStrings;
end;

// ��� �������������� ���������
procedure TExportForm.LoadLanguageStrings;
var
  ExportBitmap: TBitmap;
begin
  Caption := htdPluginShortName + ' - ' + GetLangStr('ExortFormCaption');
  IMExportWizard.ButtonBack.Caption := '< ' + GetLangStr('ButtonBack');
  IMExportWizard.ButtonNext.Caption := GetLangStr('ButtonNext') + ' >';
  IMExportWizard.ButtonFinish.Caption := GetLangStr('ButtonFinish');
  IMExportWizard.ButtonCancel.Caption := GetLangStr('ButtonCancel');
  IMExportWizard.Pages.Items[0].Title.Text := GetLangStr('IMExportWizardPage0Title');
  IMExportWizard.Pages.Items[0].Subtitle.Text := Format(GetLangStr('IMExportWizardPage0SubTitle'), [htdIMClientName]);
  IMExportWizard.Pages.Items[1].Title.Text := GetLangStr('IMExportWizardPage1Title');
  IMExportWizard.Pages.Items[1].Subtitle.Text := GetLangStr('IMExportWizardPage1SubTitle');
  IMExportWizard.Pages.Items[2].Title.Text := GetLangStr('IMExportWizardPage2Title');
  IMExportWizard.Pages.Items[2].Subtitle.Text := GetLangStr('IMExportWizardPage2SubTitle');
  IMExportWizard.Pages.Items[3].Title.Text := GetLangStr('IMExportWizardPage3Title');
  IMExportWizard.Pages.Items[3].Subtitle.Text := GetLangStr('IMExportWizardPage3SubTitle');
  CBSelectAll.Caption := GetLangStr('SelectAll');
  ContactList.Columns[0].Caption := GetLangStr('NickName');
  ContactList.Columns[1].Caption := GetLangStr('Protocol');
  ContactList.Columns[2].Caption := GetLangStr('Number');
  LExportDone.Caption := GetLangStr('ExportDoneDesc');
  CBSyncRequest.Caption := GetLangStr('SendSyncRequest');
  // ������ ������� ������ �� ����� ��������
  if IMExportWizard.ActivePage = Page1 then
  begin
    ExportBitmap := TBitmap.Create;
    try
      if DefaultLanguage = 'Russian' then
        ExportBitmap.LoadFromResourceName(HInstance, 'Export_Ru')
      else
        ExportBitmap.LoadFromResourceName(HInstance, 'Export_En');
      Page1.WaterMark.Image.Picture.Assign(ExportBitmap);
    finally
      ExportBitmap.Free;
    end;
  end;
end;

end.
