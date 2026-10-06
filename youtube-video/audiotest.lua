-- A/B/C DFPWM preprocessing comparison for the Agartha source.
local base = "https://github.com/Chazammm/atm10-cc-doom/releases/download/agartha-audio-test/"
local args={...}
local profile=(args[1] or ""):lower()
if profile~="a" and profile~="b" and profile~="c" then
  print("Audio profiles:")
  print("  A = neutral, 16 kHz low-pass, most detail")
  print("  B = smooth, 13.5 kHz low-pass, less DFPWM hiss")
  print("  C = presence, gentle 3.5 kHz boost + 15 kHz low-pass")
  write("Choose A, B or C: ")
  profile=read():lower()
end
if profile~="a" and profile~="b" and profile~="c" then error("Choose A, B or C.") end

local function speakerByName(name)
  if name and peripheral.isPresent(name) and peripheral.hasType(name,"speaker") then return peripheral.wrap(name) end
end
local leftName=settings.get("musicvideo.left_speaker")
local rightName=settings.get("musicvideo.right_speaker")
local left,right=speakerByName(leftName),speakerByName(rightName)
local stereo=left and right and leftName~=rightName
local mono=peripheral.find("speaker")
if not mono then error("No speaker found.") end
local volume=tonumber(settings.get("musicvideo.volume")) or 1

local bits={}
for b=0,255 do
  local t={}
  for j=0,7 do t[j+1]=bit32.band(bit32.rshift(b,j),1)~=0 and 127 or -128 end
  bits[b]=t
end
local function decoder()
  local out,old={},0
  return function(data)
    local n=#data*8
    local p=1
    for i=1,#data do table.move(bits[data:byte(i)],1,8,p,out);p=p+8 end
    if old>n then for i=n+1,old do out[i]=nil end end
    old=n
    return out
  end
end
local dl,dr,dm=decoder(),decoder(),decoder()

local function open(suffix)
  local h,err=http.get(base..profile.."_"..suffix..".dfpwm",nil,true)
  if not h then error("Audio test release missing: "..tostring(err)) end
  return h
end
local function playOne(s,name,samples)
  while not s.playAudio(samples,volume) do
    repeat local _,n=os.pullEvent("speaker_audio_empty") until not name or n==name
  end
end

print(("Playing profile %s for 20 seconds (%s)."):format(profile:upper(),stereo and "stereo" or "mono"))
if stereo then
  local hl,hr=open("left"),open("right")
  while true do
    local l,r=hl.read(3000),hr.read(3000)
    if not l or #l==0 or not r or #r==0 then break end
    local ls,rs=dl(l),dr(r)
    parallel.waitForAll(
      function() playOne(left,leftName,ls) end,
      function() playOne(right,rightName,rs) end
    )
  end
  hl.close();hr.close()
else
  local hm=open("mono")
  local name=peripheral.getName(mono)
  while true do
    local d=hm.read(3000)
    if not d or #d==0 then break end
    playOne(mono,name,dm(d))
  end
  hm.close()
end
print("Done. Run audiotest a/b/c to compare again.")
