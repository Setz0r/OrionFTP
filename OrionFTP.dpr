program OrionFTP;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  Classes,
  OverbyteIcsFtpCli,
  OverbyteIcsWinsock,
  KUtil in 'KUtil.pas';

const
    ConFtpVersion  = 100;

type
  TFTPRec = record
    Host : String;
    User : String;
    Pass : String;
    Port : String;
    Dir : String;
    src : String;
    des : string;
  end;

  TFTPErr = (ERR_USERNAME, ERR_PASSWORD, ERR_HOST, ERR_SOURCE);

  { We use TConApplication class (actually a component) to encapsulate all }
  { the work to be done. This is easier because TFtpCli is event driven    }
  { and need methods (that is procedure of object) to handle events.       }
  TConApplication = class(TComponent)
  protected
      FFtpCli     : TFtpClient;
      FResult     : Integer;
      mySite : TFTPRec;
      //procedure FtpUploadFile(Sender : TObject);
      procedure FtpRequestDone(Sender    : TObject;
                               RqType    : TFtpRequest;
                               ErrorCode : Word);
      procedure FtpDisplay(Sender    : TObject;
                           var Msg   : String);
  public
      constructor Create(AOwner: TComponent); override;
      destructor  Destroy; override;
      procedure   Execute;
  end;

{* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *}
constructor TConApplication.Create(AOwner: TComponent);
begin
    inherited Create(AOwner);
    FFtpCli := TFtpClient.Create(Self);
    FResult := 0;
end;


{* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *}
destructor TConApplication.Destroy;
begin
    if Assigned(FFtpCli) then begin
        FFtpCli.Destroy;
        FFtpCli := nil;
    end;
    inherited Destroy;
end;


{* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *}
procedure TConApplication.Execute;
begin
    { Prepare connection to Ftp server }
    FFtpCli.HostName      := mySite.Host;
    FFtpCli.Port          := mySite.Port;
    FFtpCli.HostDirName   := mySite.Dir;
    FFtpCli.Binary        := False;
    FFtpCli.UserName      := mySite.User;
    FFtpCli.Password      := mySite.Pass;
    FFtpCli.OnDisplay     := FtpDisplay;
    FFtpCli.OnRequestDone := FtpRequestDone;
    FFtpCli.Passive       := True;
    { Delete existing file }
    DeleteFile(FFtpCli.LocalFileName);

    { Start FTP transfert by connecting to the server }
    WriteLn('Connecting to ', FFtpCli.HostName, '/', FFtpCli.Port);
    FFtpCli.OpenAsync;

    { We need a message loop in order for windows message processing to work. }
    { There is a message loop built into each TWSocket, so we use the one in  }
    { TFtpCli control socket.                                                 }
    { MessageLoop will exit only when WM_QUIT message is posted. We do that   }
    { form the OnRequestDone event handler when the component has finished.   }
    FFtpCli.ControlSocket.MessageLoop;
end;


{* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *}
procedure TConApplication.FtpDisplay(Sender: TObject; var Msg: String);
begin
    WriteLn(Msg);
end;


{* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *}
procedure TConApplication.FtpRequestDone(
    Sender    : TObject;
    RqType    : TFtpRequest;
    ErrorCode : Word);
var
    EndFlag : Boolean;
begin
    EndFlag := FALSE;

    { Check status }
    if ErrorCode <> 0 then begin
        WriteLn('Failed, error #' + IntToStr(ErrorCode));
        FFtpCli.Abort;
        EndFlag := TRUE;
    end
    else begin
        case RqType of
        ftpOpenAsync   : begin FFtpCli.UserAsync;    end;
        ftpUserAsync   : begin FFtpCli.PassAsync;    end;
        ftpPassAsync   : begin FFtpCli.CwdAsync;     end;
        ftpCwdAsync    : begin FFtpCli.TypeSetAsync; end;
        ftpQuitAsync   : begin EndFlag := TRUE;      end;
        ftpTypeSetAsync:
            begin
                FFtpCli.LocalFileName := mySite.src;
                FFtpCli.HostFileName := mySite.des;
                FFtpCli.PutAsync;
            end;
        ftpPutAsync  :
            begin
                FResult := FFtpCli.StatusCode;
                FFtpCli.QuitAsync;
            end;
        else
            begin
                WriteLn('Unknown FtpRequest ' + IntToStr(Ord(RqType)));
                EndFlag := TRUE;
            end;
        end;
    end;

    { If something wrong or end of job, then go back to the OS }
    if EndFlag then begin
        if FResult = 226 then
            WriteLn('Transfer succesful.')
        else
            WriteLn('Transfer failed !');

        { Break message loop we called from the execute method }
        FFtpCli.ControlSocket.PostQuitMessage();
    end;
end;

{* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *}
procedure ShowError(err: TFTPErr);
begin
    case err of
      ERR_HOST     : begin Writeln('Host name not specified.  Please supply the host name with "-h"'); end;
      ERR_SOURCE   : begin Writeln('File name not specified.');  end;
      ERR_USERNAME : begin Writeln('User name not specified.  Please supply the host name with "-u"'); end;
      ERR_PASSWORD : begin Writeln('Password not specified.  Please supply the host name with "-P"');  end;
    end;
end;

{* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *}
procedure ShowHelp;
var
  utility : TKUtil;
  AppVersion : String;

begin
    AppVersion := utility.GetVersion;

    WriteLn('');
    WriteLn('-------------------------------------------------------------------------------');
    Writeln('OtionFTP '+AppVersion);
    Writeln('Author : Aaron Snyder');
    Writeln('Date   : 2012-12-10');
    WriteLn('-------------------------------------------------------------------------------');
    WriteLn('');
    WriteLn('IPM command line utility for transfering a file from the IPM web server(s) to');
    Writeln('Orion for the purposes of importing orders using FTP.');
    WriteLn('');
    WriteLn('OrionFTP -h [-p] -u -P [-d] source [destination]');
    WriteLn('');
    WriteLn('  -h      Host Name or IP Address');
    WriteLn('  -p      Port (optional, defaults to 21)');
    WriteLn('  -u      User Name');
    WriteLn('  -P      Password');
    WriteLn('  -d      Destination Directory (optionally change the working directory, by');
    WriteLn('          defualt changes working directory to root "/"');
    WriteLn('');
    Writeln('Example: OrionFTP -h192.168.0.20 -uTestUser -PtestPass1 sourceFile.txt');
    WriteLn('');
    Writeln('Example: OrionFTP -h192.168.0.20 -p2121 -uTestUser -PtestPass1 -dNewDirectory sourceFile.txt destFile.txt');
    //WriteLn('');
end;

{* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *}
var
  j : Integer;
  site : TFTPRec;
  ConApp : TConApplication;
  splitFile: TStringList;
  utility : TKUtil;

begin
  try
    { TODO -oUser -cConsole Main : Insert code here }
    utility := TKUtil.Create('');
    splitFile := TStringList.Create;

    {ASSIGNING FTP PARAMS FROM COMMAND LINE PARAMS}
    for j := 1 to ParamCount do begin
      if Copy(ParamStr(j),0,6) = '--help' then begin ShowHelp; Halt; end
      else if Copy(ParamStr(j),0,1) = '?' then begin ShowHelp; Halt;  end
      else if Copy(ParamStr(j),0,2) = '-?' then begin ShowHelp; Halt;  end
      else if Copy(ParamStr(j),0,2) = '-h' then begin site.Host := Copy(ParamStr(j),3); end
      else if Copy(ParamStr(j),0,2) = '-p' then begin site.Port := Copy(ParamStr(j),3); end
      else if Copy(ParamStr(j),0,2) = '-u' then begin site.User := Copy(ParamStr(j),3); end
      else if Copy(ParamStr(j),0,2) = '-P' then begin site.Pass := Copy(ParamStr(j),3); end
      else if Copy(ParamStr(j),0,2) = '-d' then begin site.Dir := Copy(ParamStr(j),3); end
      else begin
        if Length(site.src) = 0 then begin site.src := ParamStr(j); end
        else site.des := ParamStr(j);
      end;

    end;

    {CHECKING FOR MISSING AND OPTIONAL PARAMETERS}
    if Length(site.Dir) = 0 then site.Dir := '/';
    if Length(site.Port) = 0 then site.Port := '21';
    if Length(site.Host) = 0 then begin ShowError(ERR_HOST); Halt; end;
    if Length(site.User) = 0 then begin ShowError(ERR_USERNAME); Halt; end;
    if Length(site.Pass) = 0 then begin ShowError(ERR_PASSWORD); Halt; end;
    if Length(site.src) = 0 then begin ShowError(ERR_SOURCE); Halt; end;

    utility.Text := site.src;
    utility.Split('\',splitFile);
    if Length(site.des) = 0 then begin site.des := splitFile[splitFile.Count-1]; end;

    {Writeln('Host: '+site.Host);
    Writeln('Port: '+site.Port);
    Writeln('User: '+site.User);
    Writeln('Pass: '+site.Pass);
    Writeln('Dir: '+site.Dir);
    Writeln('Source: '+site.src);
    Writeln('Destination: '+site.des);}
    ConApp := TConApplication.Create(nil);
    ConApp.mySite := site;
    try
        ConApp.Execute;
    finally
        ConApp.Destroy;
    end;

  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
