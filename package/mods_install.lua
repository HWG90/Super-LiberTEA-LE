do -- Super LiberTEA - LE @VERSION@: LLL's folder mods travel in this boot patch, after LLL's own files.
 -- Each mod goes to LOCALAPPDATA/LLL/Helldivers2/Mods/<id>. A folder without manifest.json is installed; a
 -- folder this package wrote is kept in step; another build of the mod (installed by hand or by another
 -- package) is left alone, and so is any file changed since this package wrote it. A development shim (a
 -- main.lua that only loads the mod from a file by drive path) is not a build: its folder is moved to
 -- Backups/<id>-shim-<time> as it is, and the mod installed. A file is written through a .tmp file and read
 -- back; manifest.json is written last. SuperLiberTEA/<id>.txt records what this package wrote (size and
 -- Adler-32 per file), so a later release can tell its own files from yours.
 -- Outcome: LLL/Helldivers2/Logs/SuperLiberTEA-files.log. A failure is reported and never stops the boot.
 if rawget(_G,'jit')==nil then
  local home=os.getenv('LOCALAPPDATA')
  local base=home and home..'/LLL/Helldivers2/'
  local written,kept,left,aside,problems=0,0,{},{},{}
  local function slurp(path)
   local f=io.open(path,'rb');if not f then return end
   local value=f:read('*a');f:close();return value
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
   if moved and slurp(path)==bytes then return true end
   os.remove(path..'.tmp')
   problems[#problems+1]=name..': '..tostring(why or 'read-back differs')
  end
  local function adler(s)
   local a,b=1,0
   for i=1,#s,4096 do
    local bytes={s:byte(i,i+4095)}
    for j=1,#bytes do a=(a+bytes[j])%65521;b=(b+a)%65521 end
   end
   return b*65536+a
  end
  local function shim(main)
   -- Short, and reads its code from a drive path (an Arsenal package folder, say) that other machines, or
   -- this one once that folder goes, do not have.
   return main~=nil and #main<1024 and main:find('loadstring',1,true)~=nil and main:find('io%.open%(%s*[\'"]%a:[/\\]')~=nil
  end
  local function install(id,files)
   -- files: {name, bytes, Adler-32 of bytes}; manifest.json comes last.
   local dir='Mods/'..id..'/'
   local receipt='SuperLiberTEA/'..id..'.txt'
   local prior={}
   for size,sum,name in (slurp(base..receipt) or ''):gmatch('(%d+)\t(%d+)\t([^\r\n]+)') do prior[name]={tonumber(size),tonumber(sum)} end
   local function ours(name,current)
    local p=prior[name]
    return p~=nil and p[1]==#current and p[2]==adler(current)
   end
   local manifest=slurp(base..dir..'manifest.json')
   local shipped=files[#files][2]
   local main=slurp(base..dir..'main.lua')
   if manifest and shim(main) and not ours('main.lua',main) then
    local from,to=base..dir:sub(1,-2),'Backups/'..id..'-shim-'..os.date('%Y%m%d-%H%M%S')
    local moved=os.rename(from,base..to)
    if not moved then mkdir('Backups') moved=os.rename(from,base..to) end
    if not moved then problems[#problems+1]=id..': cannot move the development shim to '..to return end
    aside[#aside+1]=id..' (development shim, now '..to..')'
    manifest=nil
   end
   if manifest and manifest~=shipped and not ours('manifest.json',manifest) then
    left[#left+1]=id..' (another build is installed)' return
   end
   local record={}
   for _,file in ipairs(files) do
    local name,bytes,sum=file[1],file[2],file[3]
    local current=slurp(base..dir..name)
    if current==bytes then kept=kept+1 record[#record+1]=#bytes..'\t'..sum..'\t'..name
    elseif current==nil or ours(name,current) then
     if put(dir..name,bytes) then written=written+1 record[#record+1]=#bytes..'\t'..sum..'\t'..name end
    else left[#left+1]=id..'/'..name..' (changed since this package wrote it)' end
   end
   local text='release\t@VERSION@\n'..table.concat(record,'\n')..'\n'
   if slurp(base..receipt)~=text then put(receipt,text) end
  end
  if base then
   local ok,why=pcall(function()
@MODS@
   end)
   if not ok then problems[#problems+1]=tostring(why) end
   local line=os.date('%Y-%m-%d %H:%M:%S ')..'Super LiberTEA - LE @VERSION@ mods: '..written..' written, '..kept..' in place'
    ..(#aside>0 and '; set aside: '..table.concat(aside,', ') or '')
    ..(#left>0 and '; left alone: '..table.concat(left,', ') or '')..(#problems>0 and '; problems: '..table.concat(problems,'; ') or '')
   local log=io.open(base..'Logs/SuperLiberTEA-files.log','wb')
   if not log then mkdir('Logs') log=io.open(base..'Logs/SuperLiberTEA-files.log','wb') end
   if log then log:write(line..'\n');log:close() end
   if #problems>0 then print('[Super LiberTEA files] '..line) end
  end
 end
end
