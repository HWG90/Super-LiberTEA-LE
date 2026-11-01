do -- LLL @LABEL@ for HD2 Arsenal: the release's native files travel in this boot patch.
 -- LLL and the LuaJIT handoff below load them from LOCALAPPDATA/LLL/Helldivers2. A file is written only
 -- when it is missing or differs, through a .tmp file, and read back. An existing Native/luajit-boot.enable
 -- is kept (it is the LuaJIT switch), and so is Service/game-root.txt while it names this game's folder.
 -- Outcome: LLL/Helldivers2/Logs/LLL-files.log. A failure is reported and never stops the boot.
 if rawget(_G,'jit')==nil then
  local home=os.getenv('LOCALAPPDATA')
  local base=home and home..'/LLL/Helldivers2/'
  local written,kept,problems={},0,{}
  local function slurp(path)
   local f=io.open(path,'rb');if not f then return end
   local value=f:read('*a');f:close();return value
  end
  local function exists(path)
   local f=io.open(path,'rb');if f then f:close() end
   return f~=nil
  end
  local function game_folder(path)
   -- The two files LLL's build check hashes.
   return exists(path..'/bin/helldivers2.exe') and exists(path..'/data/game/game.dll')
  end
  local function shell(command)
   if not io.popen then return end
   local p=io.popen(command);if not p then return end
   local out=p:read('*a');p:close();return out
  end
  local function mkdir(dir)
   -- Only on a fresh install. cmd's mkdir creates the missing parents too.
   if home:find('[%%!"\r\n]') then return end
   shell('mkdir "'..(base..dir):gsub('/','\\')..'" 2>nul')
  end
  local function put(name,bytes)
   local path=base..name
   local w=io.open(path..'.tmp','wb')
   if not w then mkdir(name:match('^(.*)/')) w=io.open(path..'.tmp','wb') end
   if not w then problems[#problems+1]=name..': cannot create' return end
   w:write(bytes);w:close()
   os.remove(path)
   local moved,why=os.rename(path..'.tmp',path)
   if moved and slurp(path)==bytes then written[#written+1]=name return end
   os.remove(path..'.tmp')
   problems[#problems+1]=name..': '..tostring(why or 'read-back differs')
  end
  local function place(name,bytes)
   if slurp(base..name)==bytes then kept=kept+1 else put(name,bytes) end
  end
  if base then
   local ok,why=pcall(function()
@FILES@
@UPGRADE@    if exists(base..'Native/luajit-boot.enable') then kept=kept+1 else put('Native/luajit-boot.enable','@RUNTIME@\n') end
    -- The Steam launcher starts the helper for the game folder named here; the game runs from that folder.
    local root=(slurp(base..'Service/game-root.txt') or ''):gsub('[\r\n]+$','')
    if root~='' and game_folder(root) then kept=kept+1 else
     local cwd=(shell('cd') or ''):gsub('[\r\n]+$','')
     if (cwd:match('^%a:[\\/]') or cwd:match('^\\\\')) and not cwd:find('["%c]') and game_folder(cwd) then
      put('Service/game-root.txt',cwd..'\n')
     else problems[#problems+1]='Service/game-root.txt: game folder not found (current folder "'..cwd..'")' end
    end
   end)
   if not ok then problems[#problems+1]=tostring(why) end
   local line=os.date('%Y-%m-%d %H:%M:%S ')..'@LABEL@ files: '..#written..' written, '..kept..' in place'
    ..(#written>0 and ' ('..table.concat(written,', ')..')' or '')..(#problems>0 and '; problems: '..table.concat(problems,'; ') or '')
   local log=io.open(base..'Logs/LLL-files.log','wb')
   if not log then mkdir('Logs') log=io.open(base..'Logs/LLL-files.log','wb') end
   if log then log:write(line..'\n');log:close() end
   if #problems>0 then print('[LLL files] '..line) end
  end
 end
end
