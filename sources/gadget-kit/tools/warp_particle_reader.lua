-- Read-only research sampler for the local equipped backpack's live effects.
-- The EXE owns these particles separately from runtime.dll's particle API.
return function(b,port)
 local function mul(a,c)return ((a%65536)*c+math.floor(a/65536)*(c%65536)*65536)%4294967296 end
 local function ptr(a)return b:_ptr(a)end
 local function u(a)return b:_u32(a)end
 local function bits(n)return n<0 and n+4294967296 or n end
 local function lookup(manager,id)
  local cap=u(manager+0x100);local count=u(manager+0x118);local modulus=u(manager+0x11c)
  assert(cap>0 and cap<=131072 and count<=cap and modulus>0 and modulus<=cap,'Particle map bounds')
  local h=mul(id,0x5bd1e995);h=mul(bits(port.bit.bxor(h,math.floor(h/16777216))),0x5bd1e995)
  local array=ptr(manager+0x108);local slot=h%modulus;local row
  for i=1,cap do
   if slot>=cap then return nil end
   row=array+slot*32
   if u(row)==id then break end
   slot=u(row+24);row=nil
  end
  if not row then return nil end
  local resource=b:_read(row+8,8);local hi=u(row+12);local index=u(row+16)
  assert(index<131072,'Particle instance index')
  local entries=ptr(manager+0x1b8);local modulus2=u(manager+0x1cc);local count2=u(manager+0x1c8)
  assert(modulus2>0 and modulus2<=131072 and count2<=131072,'Particle resource map bounds')
  slot=hi%modulus2;local item
  for i=1,131072 do
   if slot>=modulus2 then return nil end
   item=entries+slot*24
   if b:_read(item,8)==resource then break end
   slot=u(item+16);item=nil
  end
  if not item then return nil end
  local pool=bits(port.bit.band(u(item+8),u(manager+0x228)))
  assert(pool<131072,'Particle resource pool bound')
  local entry=ptr(ptr(manager+0x278)+pool*24+8)+index*0x88
  if u(entry+0x10)~=id or b:_read(entry+0x20,8)~=resource then return nil end
  local instance=ptr(entry+8)
  assert(b:_read(instance+0x68,8)==resource,'Particle resource owner changed')
  return {id=id,entry=entry,instance=instance,resource=resource,flag=instance+0xd6}
 end
 return function()
  local s=assert(b:player_snapshot());local pack=b:backpack(s)
  if not pack then return {},s end
  local ctx=b:_alignment_context({viewmodel=pack.ref})
  local world=ptr(ctx.object+0x18);assert(world==ptr(s.base+0x2e271f8),'Particle world owner changed')
  local manager=ptr(s.base+0x2ce1720);local index=b:_map(manager+0x20,pack.entity)
  local descriptor=ptr(ptr(manager+0x38)+index*8)
  assert(b:_read(descriptor,20)==b:_descriptor(s.world,pack.entity):sub(1,20),'Particle component owner changed')
  local runtime=ptr(manager+0x48)+index*0x218
  local engine=ptr(world+0x230768);local rows={}
  for i=0,31 do
   local id=u(runtime+i*4)
   if id>0 and id<1073741824 then
    local row=lookup(engine,id)
    if row then row.source=runtime+i*4;row.owner=s.player_identity;row.pack=pack.identity;rows[#rows+1]=row end
   end
  end
  return rows,s
 end
end
