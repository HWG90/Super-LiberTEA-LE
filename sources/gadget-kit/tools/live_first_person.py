"""Submit explicit diagnostic commands to the installed local LLM addon."""
from pathlib import Path
import importlib.util,os,re,sys
os.environ['LLM_FOLDER']='/mnt/WORMHOLE/SteamLibrary/steamapps/compatdata/553850/pfx/drive_c/users/steamuser/AppData/Local/LinksLinkToMemory'
spec=importlib.util.spec_from_file_location('llm','/home/goose/.config/hd2arsenal/mods/Links-Link-to-Memory-0.5.1-CFFI-26088801/Tools/llm.py')
llm=importlib.util.module_from_spec(spec);spec.loader.exec_module(llm)
if __name__=='__main__':
 commands=sys.argv[1:]
 if commands and commands[0]=='--job':
  import json
  win='Z:'+str(Path(commands[1]).resolve())
  commands=['eval (function()local h=assert(io.open('+json.dumps(win)+',"rb"));local s=h:read("*a");h:close();local f=assert(loadstring(s));setfenv(f,getfenv(1));return f()end)()']
 if commands and commands[0]=='--file':
  win='Z:'+str(Path(commands[1]).resolve())
  import json
  commands=['eval (function()local rows={};local function out(...)local v={};for i=1,select("#",...)do v[i]=tostring(select(i,...))end;rows[#rows+1]=table.concat(v," ")end;local h=assert(io.open('+json.dumps(win)+',"rb"));local source=h:read("*a");h:close();local f=assert(loadstring(source));setfenv(f,setmetatable({out=out},{__index=_G}));local ok,why=pcall(f);rows[#rows+1]=tostring(ok)..":"..tostring(why);return table.concat(rows,"\\n")end)()']
 text=llm.run(commands,timeout=45)
 for data in re.findall(r'= bytes ([0-9a-f]+)',text):print(bytes.fromhex(data).decode('utf-8','replace'))
 print(text)
