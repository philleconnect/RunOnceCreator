unit UGetIPAdress;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Process;

type
  TGetIPAdress = class
    public
      function getIP: string;
    private
      function GetIpAddrList: string;
  end;

implementation

function TGetIPAdress.getIP: string;
var
  delimit: TStringList;
begin
  {$IFDEF WINDOWS}
  delimit:=TStringList.create;
  delimit.delimiter:=' ';
  delimit.delimitedText:=GetIpAddrList;
  result:=delimit[1];
  {$ENDIF}
end;

function TGetIPAdress.GetIpAddrList: string;
var
  AProcess: TProcess;
  s: string;
  sl: TStringList;
  i, n: integer;
begin
  Result:='';
  sl:=TStringList.Create();
  {$IFDEF WINDOWS}
  AProcess:=TProcess.Create(nil);
  AProcess.CommandLine := 'ipconfig.exe';
  AProcess.Options := AProcess.Options + [poUsePipes, poNoConsole];
  try
    AProcess.Execute();
    Sleep(500); // poWaitOnExit don't work as expected
    sl.LoadFromStream(AProcess.Output);
  finally
    AProcess.Free();
  end;
  for i:=0 to sl.Count-1 do
  begin
    if (Pos('IPv4', sl[i])=0) and (Pos('IP-', sl[i])=0) and (Pos('IP Address', sl[i])=0) then Continue;
    s:=sl[i];
    s:=Trim(Copy(s, Pos(':', s)+1, 999));
    if Pos(':', s)>0 then Continue; // IPv6
    Result:=Result+s+' ';
  end;
  {$ENDIF}
  {$IFDEF UNIX}
  AProcess:=TProcess.Create(nil);
  AProcess.CommandLine := '/sbin/ifconfig';
  AProcess.Options := AProcess.Options + [poUsePipes, poWaitOnExit];
  try
    AProcess.Execute();
    sl.LoadFromStream(AProcess.Output);
  finally
    AProcess.Free();
  end;
  for i:=0 to sl.Count-1 do
  begin
    n:=Pos('inet addr:', sl[i]);
    if n=0 then Continue;
    s:=sl[i];
    s:=Copy(s, n+Length('inet addr:'), 999);
    Result:=Result+Trim(Copy(s, 1, Pos(' ', s)))+' ';
  end;
  {$ENDIF}
  sl.Free();
end;

end.

