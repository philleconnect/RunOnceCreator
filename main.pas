unit main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  registry, resolve, ULockCAEntf, UGetMacAdress, UGetIPAdress, fpjson,
  jsonparser, HTTPSend, UPingThread, ssl_openssl;

type

  { Twindow }

  Twindow = class(TForm)
    closeTimer: TTimer;
    reloadTimer: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure closeTimerTimer(Sender: TObject);
    procedure reloadTimerTimer(Sender: TObject);
  private
    ipIsSet: boolean;
    procedure loadConfig;
    procedure checkNetworkConnection;
    procedure networkConnectionResult(result: boolean; return: string);
    procedure trueNetworkResult;
    procedure falseNetworkResult;
    function ValidateIP(IP4: string): Boolean;
    function sendRequest(url, params: string): string;
    function MemStreamToString(Strm: TMemoryStream): AnsiString;
  public
    { public declarations }
  end;

var
  window: Twindow;
  Lock: TLockCAEntf;
  serverURL, cleanServerURL, globalPW: string;
  pingthread: TPingThread;
  isOnline: boolean;

implementation

{$R *.lfm}

{ Twindow }

procedure Twindow.FormCreate(Sender: TObject);
var
  registry: TRegistry;
  config: TStringList;
  c: integer;
  value: TStringList;
begin
  ipIsSet:=false;
  isOnline:=false;
  //PhilleConnectStart als RunOnce in HKLM anlegen
  Lock:=TLockCAEntf.create;
  registry:=TRegistry.create;
  registry.RootKey:=HKEY_LOCAL_MACHINE;
  registry.OpenKey('Software\Microsoft\Windows\CurrentVersion\RunOnce',true);
  registry.WriteString('PhilleConnectStart', 'C:\Program Files\PhilleConnect\PhilleConnectStart.exe');
  registry.free;
  config:=TStringList.create;
  //Server-URL laden
  config.loadFromFile('C:\Program Files\PhilleConnect\pcconfig.jkm');
  c:=0;
  while (c < config.count) do begin
    if (pos('#', config[c]) = 0) then begin
      value:=TStringList.create;
      value.clear;
      value.strictDelimiter:=true;
      value.delimiter:='=';
      value.delimitedText:=config[c];
      case value[0] of
        'server':
          serverURL:=value[1];
        'global':
          globalPW:=value[1];
      end;
    end;
    c:=c+1;
  end;
  checkNetworkConnection;
end;

procedure Twindow.checkNetworkConnection;
var
  noPort: TStringList;
  cache: string;
begin
  if (pos(':', serverURL) > 0) then begin
    noPort:=TStringList.create;
    noPort.delimiter:=':';
    noPort.strictDelimiter:=true;
    noPort.delimitedText:=serverURL;
    cache:=noPort[0];
  end
  else begin
    cache:=serverURL;
  end;
  cleanServerURL:=cache;
  pingthread:=TPingThread.create(cache);
  pingthread.OnShowStatus:=@networkConnectionResult;
  pingthread.resume;
end;

procedure Twindow.networkConnectionResult(result: boolean; return: string);
var
  host: THostResolver;
begin
  if (result) then begin
    if (ValidateIP(cleanServerURL)) then begin
      if (cleanServerURL = return) then begin
        trueNetworkResult;
      end
      else begin
        falseNetworkResult;
      end;
    end
    else begin
      host:=THostResolver.create(nil);
      host.clearData();
      if (host.NameLookup(cleanServerURL)) then begin
        if (host.AddressAsString = return) then begin
          trueNetworkResult;
        end
        else begin
          falseNetworkResult;
        end;
      end
      else begin
        falseNetworkResult;
      end;
    end;
  end
  else begin
    falseNetworkResult;
  end;
end;

procedure Twindow.trueNetworkResult;
begin
  reloadTimer.enabled:=false;
  if not(isOnline) then begin
    loadConfig;
  end;
  isOnline:=true;
end;

procedure Twindow.falseNetworkResult;
begin
  reloadTimer.enabled:=true;
end;

procedure Twindow.loadConfig;
var
  MacAddr: TGetMacAdress;
  IPAddr: TGetIPAdress;
  jData: TJSONData;
  a, b, d, e: boolean;
  host: THostResolver;
  ip, SMBServerURL, mac, thisIp, response, os: string;
  hosts, masterURL: TStringList;
  c: integer;
begin
  //Lokale IP- und MAC-Addresse laden
  MacAddr:=TGetMacAdress.create;
  mac:=MacAddr.getMac;
  MacAddr.free;
  IPAddr:=TGetIPAdress.create;
  thisIp:=IPAddr.getIP;
  IPAddr.free;
  //Samba-URL laden
  response:=sendRequest('https://'+serverURL+'/client.php', 'usage=config&os=win&globalpw='+globalPW+'&machine='+mac+'&ip='+thisIp);
  if (response = '!') then begin
    showMessage('Konfigurationsfehler. Programm wird beendet.');
    halt;
  end
  else if (response = 'nomachine') then begin
    showMessage('Rechner nicht registriert. Programm wird beendet.');
    halt;
  end
  else if (response = 'noconfig') then begin
    showMessage('Rechner nicht fertig eingerichtet. Programm wird beendet.');
    halt;
  end
  else if (response <> '') then begin
    jData:=GetJSON(response);
    c:=0;
    while (c < jData.count) do begin
      case jData.FindPath(IntToStr(c)+'[0]').AsString of
        'smbserver':
          SMBServerURL:=jData.FindPath(IntToStr(c)+'[1]').AsString;
      end;
      c:=c+1;
    end;
  end
  else begin
    showMessage('Serverfehler. Programm wird beendet.');
    halt;
  end;
  //URL auflösen falls keine IP
  if (ValidateIP(SMBServerURL)) then begin
    ip:=SMBServerURL;
    ipIsSet:=true;
  end
  else begin
    masterURL:=TStringList.create;
    masterURL.delimiter:='/';
    masterURL.delimitedText:=SMBServerURL;
    host:=THostResolver.create(nil);
    host.clearData();
    if (host.NameLookup(masterURL[0])) then begin
      ip:=host.AddressAsString;
      ipIsSet:=true;
    end;
  end;
  if (ipIsSet) then begin
    //Vier Einträge in hosts-Datei erstellen, um mit mehreren Nutzern auf einen
    //Server zugreifen zu können (Workaround für Windows-Bug)
    a:=false;
    b:=false;
    d:=false;
    e:=false;
    c:=0;
    hosts:=TStringList.create;
    if (fileExists('C:\Windows\System32\drivers\etc\hosts')) then begin
      hosts.loadFromFile('C:\Windows\System32\drivers\etc\hosts');
    end;
    while (c < hosts.count) do begin
      if (pos('#', hosts[c]) = 0) then begin
        if not(pos('driveone.this', hosts[c]) = 0) then begin
          a:=true;
          if (pos(ip, hosts[c]) = 0) then begin
            hosts[c]:=ip+' driveone.this';
          end;
        end
        else if not(pos('drivetwo.this', hosts[c]) = 0) then begin
          b:=true;
          if (pos(ip, hosts[c]) = 0) then begin
            hosts[c]:=ip+' drivetwo.this';
          end;
        end
        else if not(pos('drivethree.this', hosts[c]) = 0) then begin
          d:=true;
          if (pos(ip, hosts[c]) = 0) then begin
            hosts[c]:=ip+' drivethree.this';
          end;
        end
        else if not(pos('groupfolders.this', hosts[c]) = 0) then begin
          e:=true;
          if (pos(ip, hosts[c]) = 0) then begin
            hosts[c]:=ip+' groupfolders.this';
          end;
        end;
      end;
      c:=c+1;
    end;
    if (a = false) then begin
      hosts.add(ip+' driveone.this');
    end;
    if (b = false) then begin
      hosts.add(ip+' drivetwo.this');
    end;
    if (d = false) then begin
      hosts.add(ip+' drivethree.this');
    end;
    if (e = false) then begin
      hosts.add(ip+' groupfolders.this');
    end;
    hosts.saveToFile('C:\Windows\System32\drivers\etc\hosts');
    hosts.free;
    //Vier Einträge in lmhosts-Datei erstellen, um mit mehreren Nutzern auf
    //einen Server zugreifen zu können (Workaround für Windows-Bug)
    //Zusätzlicher lmhosts-Eintrag Workaround für Bug im Zusammenhang mit
    a:=false;
    b:=false;
    d:=false;
    e:=false;
    c:=0;
    hosts:=TStringList.create;
    if (fileExists('C:\Windows\System32\drivers\etc\lmhosts')) then begin
      hosts.loadFromFile('C:\Windows\System32\drivers\etc\lmhosts');
    end;
    while (c < hosts.count) do begin
      if (pos('#', hosts[c]) = 0) then begin
        if not(pos('driveone.this', hosts[c]) = 0) then begin
          a:=true;
          if (pos(ip, hosts[c]) = 0) then begin
            hosts[c]:=ip+' driveone.this';
          end;
        end
        else if not(pos('drivetwo.this', hosts[c]) = 0) then begin
          b:=true;
          if (pos(ip, hosts[c]) = 0) then begin
            hosts[c]:=ip+' drivetwo.this';
          end;
        end
        else if not(pos('drivethree.this', hosts[c]) = 0) then begin
          d:=true;
          if (pos(ip, hosts[c]) = 0) then begin
            hosts[c]:=ip+' drivethree.this';
          end;
        end
        else if not(pos('groupfolders.this', hosts[c]) = 0) then begin
          e:=true;
          if (pos(ip, hosts[c]) = 0) then begin
            hosts[c]:=ip+' groupfolders.this';
          end;
        end;
      end;
      c:=c+1;
    end;
    if (a = false) then begin
      hosts.add(ip+' driveone.this');
    end;
    if (b = false) then begin
      hosts.add(ip+' drivetwo.this');
    end;
    if (d = false) then begin
      hosts.add(ip+' drivethree.this');
    end;
    if (e = false) then begin
      hosts.add(ip+' groupfolders.this');
    end;
    hosts.saveToFile('C:\Windows\System32\drivers\etc\lmhosts');
  end;
  closeTimer.enabled:=true;
end;

procedure Twindow.closeTimerTimer(Sender: TObject);
begin
  close;
end;

procedure Twindow.reloadTimerTimer(Sender: TObject);
begin
  checkNetworkConnection;
end;

function Twindow.ValidateIP(IP4: string): Boolean; // Coding by Dave Sonsalla
var
  Octet : String;
  Dots, I : Integer;
begin
  IP4 := IP4+'.'; //add a dot. We use a dot to trigger the Octet check, so need the last one
  Dots := 0;
  Octet := '0';
  for I := 1 to length(IP4) do begin
    if IP4[I] in ['0'..'9','.'] then begin
      if IP4[I] = '.' then begin //found a dot so inc dots and check octet value
        Inc(Dots);
        if (length(Octet) =1) Or (StrToInt(Octet) > 255) then Dots := 5; //Either there's no number or it's higher than 255 so push dots out of range
        Octet := '0'; // Reset to check the next octet
      end // End of IP4[I] is a dot
      else // Else IP4[I] is not a dot so
        Octet := Octet + IP4[I]; // Add the next character to the octet
    end // End of IP4[I] is not a dot
    else // Else IP4[I] Is not in CheckSet so
      Dots := 5; // Push dots out of range
  end;
  result := (Dots = 4) // The only way that Dots will equal 4 is if we passed all the tests
end;

function Twindow.sendRequest(url, params: string): string;
var
   Response: TMemoryStream;
begin
   Response := TMemoryStream.Create;
   try
      if HttpPostURL(url, params, Response) then
         result:=MemStreamToString(Response);
   finally
      Response.Free;
   end;
end;

function Twindow.MemStreamToString(Strm: TMemoryStream): AnsiString;
begin
   if Strm <> nil then begin
      Strm.Position := 0;
      SetString(Result, PChar(Strm.Memory), Strm.Size);
   end;
end;

end.

