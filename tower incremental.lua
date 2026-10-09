
if game.PlaceId ~= 75766778174856 then
    warn('[PuckAFK TI] Incorrect game/place id: '..tostring(game.PlaceId)); return
end
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local RunService=game:GetService('RunService')
local TweenService=game:GetService('TweenService')
local LP=Players.LocalPlayer
local unpack=table.unpack or unpack
local gen=(getgenv and getgenv()) or _G
if type(gen.__PUCK_TOWER_UNLOAD)=='function' then pcall(gen.__PUCK_TOWER_UNLOAD) end
local alive=true
local conns={}
local threads={}
local state={phase='Starting',reason='',recent={},moveTicket=0,stuck=0,dataReady=false,stairLast=0,stairStarted=0,lastProgress=0,pending={},lastSpend=0,skip={},invalid={}}
local cfg={Master=false, Stairs=true,Upgrades=true,Doors=true,Tree=true,Rebirth=true,Mining=true,
 Crystals=true,Wood=true,Essence=true,Glyphs=true,Smelter=true,Starforge=true,Refractor=true,
 Production=true,Totems=false,Dragons=true,Volts=true,Feathers=true,Pearls=true,Gateway=true,FreeRewards=true,Preservation=true,
 TweenSpeed=165, MinimumGoldReserve=0.20, ResourceReserve=0.15, RebirthMode='Smart',
 Movement='Hybrid', GlyphSeconds=6, FastOwnedStairs=true, FastUnlockedTeleports=true, ResourceInterval=12, ClimbBurstSeconds=24, BurstUpgrades=12, MaxRemotePerSecond=8, BestOwnedTrail=true, RedeemReleaseCode=true}
local function clock() return os.clock() end
-- Intentionally quiet: the beginner build has no developer log/diagnostic mode.
local function trace(...) end
local function log(...) end
local function req(path)
 local obj=RS
 for _,name in ipairs(path) do obj=obj and obj:FindFirstChild(name) end
 if not obj then return nil end
 local ok,x=pcall(require,obj)
 if ok then return x end
 trace('Module '..table.concat(path,'.')..': '..tostring(x));return nil
end
local shared=function(name) return req({'Shared',name}) end
local DataService=req({'Packages','DataService'})
local client=DataService and DataService.client
local Stair=shared('StairConfig')
local Doors=shared('DoorConfig')
local Upgrades=shared('UpgradeConfig')
local Trees=shared('TreeConfig')
local Rebirths=shared('RebirthConfig')
local Glyphs=shared('GlyphConfig')
local Teleports=shared('TeleportConfig')
local StarConfig=shared('StarforgeConfig')
local RefractConfig=shared('RefractorConfig')
local PassConfig=shared('PassConfig')
local PassState=req({'Client','PassState'})
local Mine=shared('MineConfig')
local Crystal=shared('CrystalConfig')
local Wood=shared('WoodConfig')
local Essence=shared('EssenceConfig')
local Smelt=shared('SmelterConfig')
local Gateway=shared('GatewayConfig')
local Roost=shared('EmberConfig')
local Pearl=shared('PearlConfig')
local Volt=shared('VoltConfig')
local Feather=shared('FeatherConfig')
local Trails=shared('TrailConfig')
local Totems=shared('TotemConfig')
local Codes=shared('CodeConfig')
local PUCKUI_URL='https://raw.githubusercontent.com/PuckAFK/Puck-Loader/refs/heads/main/ui/PuckUI.lua'
local ui,win
if type(loadstring)=='function' and game.HttpGet then
 local ok,mod=pcall(function() return loadstring(game:HttpGet(PUCKUI_URL))() end)
 if ok and type(mod)=='table' then ui=mod else warn('[PuckAFK TI] PuckUI could not be loaded: '..tostring(mod)) end
end
local function get(k)
 if not client then return nil end
 local ok,v=pcall(function() return client:get(k) end)
 if ok then return v end
 return nil
end
local function balance(k) return tonumber(get(k)) or 0 end
local function ownedDoor(k) return get({'doors',k})==true end
local function level(k) return tonumber(get({'upgrades',k})) or 0 end
local function rebirthNumber() return math.floor(balance('rebirths')) end
local stairs={}
local stairRefresh=0
local function getStairs()
 if not Stair then return stairs end
 if clock()>stairRefresh or not next(stairs) then
    stairRefresh=clock()+90
    local ok,list=pcall(Stair.collect)
    if ok and type(list)=='table' then stairs=list end
 end
 return stairs
end
local function currentStep() return math.floor(tonumber(get('stairsOwned')) or tonumber(LP:GetAttribute('StairTop')) or 1) end
local function currentFloor() local s=getStairs(); return Stair and Stair.floorFor and Stair.floorFor(currentStep(),s) or math.floor((currentStep()-1)/12) end
local function hrp()
 local ch=LP.Character
 local h=ch and ch:FindFirstChildWhichIsA('Humanoid')
 local r=ch and ch:FindFirstChild('HumanoidRootPart')
 if not h or h.Health<=0 or not r then return nil,nil end
 return r,h
end
local function point(inst)
 if not inst then return nil end
 if inst:IsA('BasePart') then return inst.Position end
 if inst:IsA('Model') then return inst:GetPivot().Position end
 local p=inst:FindFirstChildWhichIsA('BasePart',true)
 return p and p.Position or nil
end
local worldIndex={}
local worldMissing={}
local function world(name)
 if not name then return nil end
 local old=worldIndex[name]
 if old and old.Parent and old:IsDescendantOf(workspace) then return old end
 if clock()<(worldMissing[name] or 0) then return nil end
 local fresh=workspace:FindFirstChild(name) or workspace:FindFirstChild(name,true)
 if fresh then worldIndex[name]=fresh;worldMissing[name]=nil
 else worldMissing[name]=clock()+12 end
 return fresh
end
local function nearestWorld(named)
 return point(world(named))
end
local function offsetPoint(obj,delta)
 local pos=point(obj); return pos and pos+Vector3.new(0,delta or 3,0) or nil
end
-- Serial movement: direct destination selection mirrors the game TeleportUI/AutoRun.
-- Never snap to an unowned step, locked teleport floor or absent portal location.
local nav={owner=nil,goal=nil,tween=nil,owned=0}
local function stopMove()
 nav.owned=nav.owned+1
 if nav.tween then pcall(function() nav.tween:Cancel() end) end
 nav.tween=nil; nav.owner=nil; nav.goal=nil
 local _,hum=hrp()
 if hum then pcall(function() hum:Move(Vector3.zero,false) end) end
end
local function pivot(pos,reason)
 local r,h=hrp();local character=LP.Character
 if not r or not character then return false end
 if h.Sit then h.Sit=false;task.wait() end
 local direction=r.CFrame.LookVector
 local ok=pcall(function()
  character:PivotTo(CFrame.lookAt(pos,pos+direction))
  r.AssemblyLinearVelocity=Vector3.zero
  r.AssemblyAngularVelocity=Vector3.zero
 end)
 return ok
end
local function bestUnlockedLanding(destination)
 if not cfg.FastUnlockedTeleports or not Teleports or not Teleports.LIST or not Teleports.landing then return nil end
 local root=hrp();if not root then return nil end
 local original=(root.Position-destination).Magnitude
 if original<55 then return nil end
 local best=nil;local remain=original
 local owned=currentFloor()
 local data=get('gateway')
 for _,loc in ipairs(Teleports.LIST) do
  if loc.floor and loc.floor<=owned and (not loc.door or ownedDoor(loc.door)) and
     (not loc.arrival or (type(data)=='table' and data.open==true)) then
   -- This is exactly the eligibility of the game's unlocked Teleport buttons.
   local landing=Teleports.landing(loc.floor,getStairs())
   if loc.arrival then landing=Stair and Stair.portalLanding and Stair.portalLanding() or landing end
   if landing then
    local home=landing:GetAttribute('StairHome') or landing.CFrame
    local locPos=home.Position+Vector3.new(0,landing.Size.Y/2+3,0)
    local d=(locPos-destination).Magnitude
    if d+24<remain and d<original*0.72 then best=locPos;remain=d end
   end
  end
 end
 return best
end
local function travel(pos,owner,radius,timeout)
 if not alive or not cfg.Master or typeof(pos)~='Vector3' then return false end
 local r,h=hrp();if not r then return false end
 radius=radius or 6;timeout=timeout or 15
 if (r.Position-pos).Magnitude<=radius then return true end
 stopMove()
 nav.owner=owner;nav.goal=pos
 local token=nav.owned
 -- AutoRun.lua uses placeOn() on the latest *owned* stair, including a PivotTo.
 if cfg.FastOwnedStairs and type(owner)=='string' and owner:sub(1,6)=='stair:' then
  pivot(pos,'owned stair')
  task.wait(0.035)
  local newer=hrp()
  if newer and (newer.Position-pos).Magnitude<=radius+1.5 then
   nav.owner=nil;nav.goal=nil;return true
  end
 end
 -- The game's TeleportUI uses PivotTo on an unlocked EndStair.
 local stop=bestUnlockedLanding(pos)
 if stop then pivot(stop,'unlocked floor');task.wait(0.04) end
 r,h=hrp();if not r then return false end
 local remaining=(r.Position-pos).Magnitude
 if remaining<=radius then return true end
 local mode=cfg.Movement
 if mode=='Hybrid' or mode=='Tween' then
  local speed=math.clamp(tonumber(cfg.TweenSpeed) or 165,25,350)
  local duration=math.clamp(remaining/speed,0.045,math.min(timeout,25))
  local ok,tween=pcall(function()
    return TweenService:Create(r,TweenInfo.new(duration,Enum.EasingStyle.Linear),{CFrame=CFrame.new(pos,pos+r.CFrame.LookVector)})
  end)
  if ok and tween then
   nav.tween=tween;tween:Play()
   local started=clock();local last=remaining;local stagnant=clock()
   while alive and cfg.Master and token==nav.owned and clock()-started<timeout do
    task.wait(0.085)
    local nr=hrp();if not nr then break end
    local d=(nr.Position-pos).Magnitude
    if d<=radius then break end
    if d<last-1 then last=d;stagnant=clock() end
    if clock()-stagnant>1.4 then break end
   end
   if nav.tween==tween then pcall(function() tween:Cancel() end);nav.tween=nil end
  end
 else
  local start=clock();local nearest=remaining;local notMoved=start
  while alive and cfg.Master and token==nav.owned and clock()-start<timeout do
   local nr,hum=hrp();if not nr then break end
   local d=(nr.Position-pos).Magnitude
   if d<=radius then break end
   hum:MoveTo(pos)
   if d<nearest-1 then nearest=d;notMoved=clock() end
   if clock()-notMoved>1.6 then hum.Jump=true;notMoved=clock();state.stuck=state.stuck+1 end
   task.wait(0.15)
  end
 end
 if token==nav.owned then nav.owner=nil;nav.goal=nil end
 local nr=hrp()
 return nr and (nr.Position-pos).Magnitude<=radius or false
end
local function keepOnOwnedStair()
 local idx=math.max(1,currentStep())
 local stair=getStairs()[idx]
 if not stair then return false end
 local home=stair:GetAttribute('StairHome') or stair.CFrame
 return travel((home*CFrame.new(0,stair.Size.Y/2+3,0)).Position,'stair:'..idx,3.5,8)
end
local function cooldown(key,seconds)
 local untilAt=state.recent[key] or 0
 if clock()<untilAt then return false end
 state.recent[key]=clock()+seconds
 return true
end
-- Small bounded queue; no remote flooding, and do not enqueue an identical purchase repeatedly.
local packets={}
local inQueue={}
local function fire(name,...)
 local container=RS:FindFirstChild('Remotes')
 local remote=container and container:FindFirstChild(name)
 if not remote or not remote:IsA('RemoteEvent') then return false end
 local args={...}
 local sig=name..':'..tostring(args[1] or '')..':'..tostring(args[2] or '')
 if inQueue[sig] or #packets>=10 then return false end
 packets[#packets+1]={remote=remote,args=args,name=name,sig=sig,at=clock()}
 inQueue[sig]=true
 return true
end
local function remoteQueue(obj,...)
 if not obj or not obj:IsA('RemoteEvent') then return false end
 local args={...};local sig=obj.Name..':'..tostring(args[1] or '')
 if inQueue[sig] or #packets>=10 then return false end
 packets[#packets+1]={remote=obj,args=args,name=obj.Name,sig=sig,at=clock()}
 inQueue[sig]=true
 return true
end
local sentAt=0
conns[#conns+1]=RunService.Heartbeat:Connect(function()
 if not alive or not cfg.Master or #packets==0 then return end
 if clock()-sentAt < 1/math.clamp(tonumber(cfg.MaxRemotePerSecond) or 7,2,10) then return end
 local packet=table.remove(packets,1)
 inQueue[packet.sig]=nil
 if clock()-packet.at>2.5 then return end
 sentAt=clock()
 -- Network errors are retried by the task controller without console spam.
 pcall(function() packet.remote:FireServer(unpack(packet.args)) end)
end)
local function afford(currency,cost,reserveFraction)
 local cash=balance(currency or 'gold')
 return type(cost)=='number' and cost>=0 and cash>=cost and cash-cost >= (reserveFraction or 0)*cash
end
local function strictAfford(currency,cost) return afford(currency,cost,0) end
local function doorCost(d)
 local amount=d.cost or math.huge
 if d.currency==nil or d.currency=='gold' then
   if Rebirths and Rebirths.scaledCost then
      local ok,n=pcall(Rebirths.scaledCost,amount,rebirthNumber())
      if ok and type(n)=='number' then amount=n end
   end
 end
 return amount
end
local function stairCost(index)
 if not Stair then return math.huge,'gold' end
 local s=getStairs()[index]
 if not s then return math.huge,'gold' end
 local currency=Stair.currencyOf and Stair.currencyOf(s) or 'gold'
 local baseCost=tonumber(s:GetAttribute('StairCost'))
 if not baseCost then
    local ok,v=pcall(Stair.costOf,index)
    if not ok then return math.huge,currency end
    baseCost=tonumber(v) or math.huge
 end
 if Rebirths and Rebirths.stairCost then
    local ok,value=pcall(Rebirths.stairCost,baseCost,currency,rebirthNumber())
    if ok and type(value)=='number' then baseCost=value end
 end
 return baseCost,currency
end
local function floorAvailable(floor)
 return currentFloor() >= (tonumber(floor) or 0)
end
local function rateAttempt(prefix,key,waitSec,name,...)
 local id=prefix..':'..tostring(key)
 if not cooldown(id,waitSec) then return false end
 return fire(name,...)
end
local priorityDoor={lavaGlyphs=10,mine=30,upgradeTree=27,ironOre=30,crystals=30,door23=30,
 door34=30,door45=29,door52=29,door53=27,door60=30,door61=27,door74=25,door81=26,
 rebirth4=50,rebirth8=50,rebirth12=50,rebirth16=50,rebirth20=50,rebirth24=50,
 rebirth28=50,rebirth29=50,rebirth30=50,rebirth31=50,rebirth32=50,rebirth33=50,rebirth34=50,rebirth35=50}
local function findDoorModel(def)
 local doors=workspace:FindFirstChild('Doors')
 return (doors and doors:FindFirstChild(def.model)) or world(def.model)
end
local function tryDoor()
 if not cfg.Doors or not Doors or not Doors.DOORS then return false end
 local floor=currentFloor();local rebirth=rebirthNumber()
 local selected=nil;local best=-math.huge
 for _,def in ipairs(Doors.DOORS) do
  if not ownedDoor(def.id) and floor>=(def.floor or 9999) and rebirth>=(def.rebirths or 0) then
   local currency=def.currency or 'gold';local price=doorCost(def)
   local reserve=currency=='gold' and (priorityDoor[def.id] and 0.05 or cfg.MinimumGoldReserve) or cfg.ResourceReserve
   if afford(currency,price,reserve) and clock()>=(state.recent['door:'..def.id] or 0) then
    local score=(priorityDoor[def.id] or 2)*100-(def.floor or 0)/4
    if score>best then selected=def;best=score end
   end
  end
 end
 if not selected then return false end
 local id=selected.id
 local where=offsetPoint(findDoorModel(selected),3.5)
 state.phase='Unlock '..id
 if not where then state.recent['door:'..id]=clock()+15;return false end
 if not travel(where,'door:'..id,13,13) then
  state.recent['door:'..id]=clock()+8;return true
 end
 state.recent['door:'..id]=clock()+2.4
 if fire('UnlockDoor',id) then log('Unlock '..id);return true end
 return false
end
local function upgradeFloor(board)
 -- UPD6 boards live under named models; an exact world model is preferred.
 local known={UpgradeBoard=0,UpgradeBoard2=3,UpgradeBoard3=10,GlyphUpgrades1=1,MineUpgrades=3,CrystalBoard=28,WoodBoard=70,EssenceBoard=108}
 return known[board] or 0
end
local function findUpgradeBoard(def)
 return world(def.board)
end
local priorities={moreMoney=17,fasterMoney=17,goldMultiplier=23,moreSilver=18,fasterMining=13,
 moreIron=12,oreDensity=9,luckyStrike=5,ironCapacity=9,fasterBelts=11,silverMultiplier=17,
 glyphLuck=8,fasterRolling=6,glyphBulk=5,crystalYield=13,crystalPower=21,growthSpeed=10,
 woodYield=13,woodPower=18,woodGrowth=8,essenceYield=14,essenceCount=12,essenceSpeed=10,
 forgeSpeed=9,forgeCapacity=10,starmetalMulti=14,refractSpeed=8,refractCapacity=9,prismMulti=14,
 roostNests=12,crucibleCapacity=10,breathPower=16,breathSpeed=12,emberMulti=14,
 clamBeds=11,pearlSize=15,clamSpeed=12,basinSize=9,voltRods=12,strikePower=15,
 strikeRate=12,capacitorSize=8,voltMulti=16,featherNests=10,plumeSize=16,moltSpeed=12}
local purchaseWindow={began=0,count=0,board=nil}
local function expectedGoldGain(id, lv, upgrades)
 if id~='moreMoney' and id~='fasterMoney' and id~='goldMultiplier' and id~='crystalPower' then return nil end
 if not Upgrades or not Upgrades.goldPerSecond then return nil end
 local baseline=Upgrades.goldPerSecond(upgrades,1)
 local preview=table.clone(upgrades);preview[id]=lv+1
 local nextRate=Upgrades.goldPerSecond(preview,1)
 return math.max(0,nextRate-baseline),math.max(1,baseline)
end
local function tryUpgrade()
 if not cfg.Upgrades or not Upgrades or not Upgrades.LIST then return false end
 local t=clock()
 if t-purchaseWindow.began>5 then purchaseWindow.began=t;purchaseWindow.count=0 end
 if purchaseWindow.count>=math.max(1,cfg.BurstUpgrades) then return false end
 local currentUpgrades=get('upgrades') or {}
 local availableDoors=get('doors') or {}
 local floor=currentFloor();local best=nil
 for _,def in ipairs(Upgrades.LIST) do
  local id=def.id;local lv=tonumber(currentUpgrades[id]) or 0
  local blocked=state.skip['upgrade:'..id] or 0
  local pending=state.pending['upgrade:'..id]
  if pending and lv>pending.level then
   state.pending['upgrade:'..id]=nil;pending=nil
  elseif pending and t-pending.at>2.5 then
   state.pending['upgrade:'..id]=nil;state.skip['upgrade:'..id]=t+10;pending=nil;blocked=t+10
  end
  if id and not pending and lv<(def.cap or 0) and t>=blocked and def.baseCost and def.growth then
   local door=Upgrades.doorFor and Upgrades.doorFor(def)
   if (not door or availableDoors[door]) and floor>=upgradeFloor(def.board) then
    local currency=def.currency or 'gold'
    local cost=Upgrades.costAt(def,lv)
    local amount=balance(currency)
    local floorReserve=(currency=='gold' and cfg.MinimumGoldReserve or cfg.ResourceReserve)
    if def.permanent and cfg.Preservation then floorReserve=0 end
    if currency=='gold' and id=='moreMoney' then floorReserve=0.02 end
    if type(cost)=='number' and cost>0 and amount>=cost and amount-cost>=amount*floorReserve then
     local extraOK=true
     if def.extra then
      local extra=Upgrades.extraCost(def,1)
      extraOK=balance(def.extra.currency)>=extra
     end
     if extraOK then
      local importance=priorities[id] or (def.permanent and cfg.Preservation and 24 or 4)
      if not cfg.Preservation and def.permanent then importance=0.2 end
      local score=importance/(0.12+cost/math.max(amount,1))
      local gain,rate=expectedGoldGain(id,lv,currentUpgrades)
      if gain and gain>0 then
       local payback=cost/gain
       score=score+math.min(35,140/math.max(4,payback))
       if payback>90 and not (def.permanent and cfg.Preservation) then score=score*0.18 end
      end
      if currency=='gold' and balance('gold')<stairCost(currentStep()+1)*1.1 and floor>=1 then
       if id~='moreMoney' and id~='fasterMoney' then score=score*0.25 end
      end
      -- Gameplay effect > cheap cosmetic or irrelevant side-upgrade.
      if score>0 and (not best or best.score<score) then best={def=def,score=score,level=lv,cost=cost} end
     end
    end
   end
  end
 end
 if not best then return false end
 local def=best.def
 local board=findUpgradeBoard(def)
 local spot=offsetPoint(board,3)
 if not spot then state.skip['upgrade:'..def.id]=clock()+25;return false end
 if not travel(spot,'upgrade:'..def.id,17,12) then
  state.skip['upgrade:'..def.id]=t+6
  return true
 end
 purchaseWindow.count=purchaseWindow.count+1
 state.phase='Improve '..def.id..' ('..best.level..')'
 if fire('BuyUpgrade',def.id,1) then
  state.pending['upgrade:'..def.id]={level=best.level,at=clock()}
  state.skip['upgrade:'..def.id]=clock()+0.22
  log('Upgrade '..def.id..' Lv '..best.level)
  return true
 end
 return false
end
local function tryTree()
 if not cfg.Tree or not Trees or not Trees.NODES or not ownedDoor(Trees.DOOR or 'upgradeTree') then return false end
 local owned=get('tree') or {};local f=currentFloor();local rb=rebirthNumber();local best
 local scoreEffect={gold=20,silver=17,iron=16,crystals=16,wood=16,essence=14,
 luck=10,speed=7,vacuum=18,totemBoost=12,ironCapacity=11,glyphBulk=9}
 for _,d in ipairs(Trees.NODES) do
  if not owned[d.id] and clock()>=(state.skip['tree:'..d.id] or 0) and
   (not Trees.available or Trees.available(d,owned,f,rb)) and
   (not d.door or ownedDoor(d.door)) and (not d.requires or owned[d.requires]) then
    if strictAfford(d.currency or 'silver',d.cost or math.huge) and
      (not d.extra or strictAfford(d.extra.currency,d.extra.amount or 0)) then
      local weight=scoreEffect[d.effect] or 4
      local ratio=(d.cost or 1)/math.max(1,balance(d.currency or 'silver'))
      local score=weight/(0.2+ratio)
      if not best or score>best.score then best={def=d,score=score} end
    end
  end
 end
 if not best then return false end
 local d=best.def
 local pos=offsetPoint(world('UpgradeTree'),4)
 if not pos then state.skip['tree:'..d.id]=clock()+25;return false end
 if not travel(pos,'tree:'..d.id,32,12) then
  state.skip['tree:'..d.id]=clock()+10;return true
 end
 state.phase='Purchase tree '..d.id
 state.skip['tree:'..d.id]=clock()+2.4
 if fire('BuyTreeNode',d.id) then log('Tree '..d.id);return true end
 return false
end
local function tryRebirth()
 if not cfg.Rebirth or not Rebirths or not Rebirths.LIST then return false end
 local idx=rebirthNumber()+1
 local d=Rebirths.LIST[idx]
 if not d then return false end
 if not ownedDoor(d.door) then return false end
 local cost=d.cost
 if (d.currency or 'gold')=='gold' and Rebirths.scaledCost then
   local ok,v=pcall(Rebirths.scaledCost,cost,idx-1);if ok then cost=v end
 end
 if balance(d.currency or 'gold')<cost or (d.extra and balance(d.extra.currency)<d.extra.amount) then return false end
 -- Smart mode pauses rebirth until all affordable permanent/preservation upgrades are bought.
 if cfg.RebirthMode=='Smart' and cfg.Preservation and Upgrades and Upgrades.LIST then
   for _,u in ipairs(Upgrades.LIST) do
      if u.permanent and level(u.id)<(u.cap or 1) and u.baseCost and u.growth then
         local neededDoor=Upgrades.doorFor and Upgrades.doorFor(u)
         if not neededDoor or ownedDoor(neededDoor) then
            local cu=Upgrades.costAt(u,level(u.id))
            local extrasOK=true
            if u.extra then
              local extraCost=Upgrades.extraCost and Upgrades.extraCost(u,1) or (u.extra.amount or math.huge)
              extrasOK=strictAfford(u.extra.currency,extraCost)
            end
            if extrasOK and strictAfford(u.currency or 'gold',cu) and findUpgradeBoard(u) then return false end
         end
      end
   end
 end
 if not cooldown('rebirth:'..idx,3.5) then return false end
 local board=workspace:FindFirstChild('Rebirths')
 board=board and board:FindFirstChild(d.board)
 local pos=offsetPoint(board,5)
 if not pos then state.reason='Rebirth board unavailable';return false end
 if not travel(pos,'rebirth',13,25) then return true end
 state.phase='Rebirth '..idx
 if fire('Rebirth',idx) then log('Rebirth '..idx);return true end
 return false
end
local function tryStair()
 if not cfg.Stairs or not Stair then return false end
 local owned=math.floor(tonumber(get('stairsOwned')) or 1)
 local visual=math.floor(tonumber(LP:GetAttribute('StairTop')) or owned)
 -- StairTop can lead authoritative ownership by one or two frames. Use actual
 -- saved ownership for purchases rather than jumping to an unconfirmed stair.
 local lastOwned=owned
 local nextIdx=owned+1
 local list=getStairs()
 if not list[nextIdx] then state.reason='Next stair has not loaded';return false end
 if Stair.needsPortal and Stair.needsPortal(nextIdx,get('gateway')) then state.reason='Complete Gateway first';return false end
 if Stair.unreleased and Stair.unreleased(nextIdx) then state.reason='Section unavailable in UPD6';return false end
 local requiredRb=Rebirths and Rebirths.rebirthsForStair and Rebirths.rebirthsForStair(nextIdx) or 0
 if rebirthNumber()<requiredRb then state.reason='Rebirth '..requiredRb..' required';return false end
 local price,currency=stairCost(nextIdx)
 if not strictAfford(currency,price) then state.reason='Waiting for '..currency..' to buy stair '..nextIdx;return false end
 local t=clock()
 if nextIdx~=state.stairLast then
  state.stairLast=nextIdx;state.stairStarted=t
 end
 if t<(state.skip['stair:'..nextIdx] or 0) then return false end
 local previous=(nextIdx==Stair.PORTAL_STEP and Stair.portalLanding and Stair.portalLanding()) or list[lastOwned]
 if not previous then return false end
 local home=previous:GetAttribute('StairHome') or previous.CFrame
 local target=(home*CFrame.new(0,previous.Size.Y/2+3,0)).Position
 local root=hrp();if not root then return false end
 -- The native StairClient checks the character ON the step using a tighter
 -- bounding box than the public withinReach helper. Stand at its centre.
 if (root.Position-target).Magnitude>2.7 then
  state.phase='Fast climb stair '..lastOwned
  if not travel(target,'stair:'..lastOwned,3.5,9) then
   state.skip['stair:'..nextIdx]=clock()+1.5
   return true
  end
 end
 state.phase='Buying stair '..nextIdx
 -- Remain on this owned stair while the game's Heartbeat-based StairClient
 -- processes the purchase. Old v1.1.0 abandoned this location after 0.65s.
 local elapsed=clock()-state.stairStarted
 if elapsed>0.85 and t>=(state.recent['stairFallback:'..nextIdx] or 0) then
  state.recent['stairFallback:'..nextIdx]=t+1.1
  fire('BuyStair',nextIdx)
 end
 if elapsed<3.2 then return true end
 -- A server rejection/attribute mismatch is possible. Back off rather than
 -- trapping the entire scheduler or flooding the purchase remote.
 state.skip['stair:'..nextIdx]=t+3
 state.stairStarted=t+3
 state.reason='Stair '..nextIdx..' not confirmed, retrying later'
 return false
end
local function readReady()
 return type(get('upgrades'))=='table' and type(get('doors'))=='table' and type(get('stairsOwned'))=='number'
end
-- The mine is client-generated and seeded by UserId. Ore visuals and exact Cell attributes
-- are authoritative inputs; do not guess arbitrary cell numbers.
local mines={list={},refreshed=0,root=nil}
local function mineList()
 local m=workspace:FindFirstChild('Mine'); local folder=m and m:FindFirstChild('MineBlocks')
 if not folder then return {} end
 if folder~=mines.root or clock()>mines.refreshed then
   mines.root=folder;mines.refreshed=clock()+5;mines.list={}
   for _,obj in ipairs(folder:GetChildren()) do
      if obj:GetAttribute('Ore')==true and type(obj:GetAttribute('Cell'))=='number' then mines.list[#mines.list+1]=obj end
   end
 end
 return mines.list
end
local function mineOne()
 if not cfg.Mining or not ownedDoor('mine') then return false end
 local list=mineList();if #list==0 then return false end
 local root=hrp();if not root then return false end
 local choice,dist;local t=clock()
 for _,ore in ipairs(list) do
  if ore.Parent and ore:GetAttribute('Ore')==true then
   local cell=ore:GetAttribute('Cell')
   local pos=point(ore)
   if pos and cell and t>=(state.recent['ore:'..cell] or 0) then
     local delta=(pos-root.Position).Magnitude
     if not dist or delta<dist then choice=ore;dist=delta end
   end
  end
 end
 if not choice then return false end
 local idx=choice:GetAttribute('Cell')
 local pos=point(choice)
 if dist>32 and not travel(pos+Vector3.new(0,3,0),'mine:'..idx,17,12) then
  state.recent['ore:'..idx]=clock()+5;return true
 end
 local multiplier=1
 if PassConfig and PassState and PassConfig.totals and Trees and Trees.totals then
  local ok,v=pcall(function() return PassConfig.totals(PassState.owned).mining*Trees.totals(get('tree') or {}).mining end)
  if ok and type(v)=='number' then multiplier=v end
 end
 local seconds=2
 if Mine and Mine.secondsFor then
  local ok,n=pcall(Mine.secondsFor,level('fasterMining'),multiplier)
  if ok and type(n)=='number' then seconds=n end
 end
 state.phase='Mine ore cell '..idx
 -- The built-in mine requires the mining hold. Deduplicate until completion/cycle.
 task.wait(math.clamp(seconds,0.11,3.2))
 local newRoot=hrp()
 if not newRoot or (newRoot.Position-pos).Magnitude>48 then return false end
 state.recent['ore:'..idx]=clock()+math.max(3.2,seconds+1)
 if fire('MineBlock',idx) then log('Mine '..idx);return true end
 return false
end
-- Crystal / wood are passive proximity harvests. Character stays in range long enough
-- for the game client/server's own hold and cooldown. No invented harvest remote.
local function ensureTool(toolName)
 local character=LP.Character
 if not character then return false end
 if character:FindFirstChild(toolName) then return true end
 local backpack=LP:FindFirstChildOfClass('Backpack')
 local tool=backpack and backpack:FindFirstChild(toolName)
 local hum=character:FindFirstChildWhichIsA('Humanoid')
 if tool and hum and tool:IsA('Tool') then
    pcall(function() hum:EquipTool(tool) end)
    return true
 end
 return false
end
local function groveOne(kind)
 local config=kind=='crystals' and Crystal or Wood
 if not config then return false end
 local door=config.DOOR
 if not ownedDoor(door) then return false end
 local spots=config.spots and config.spots() or {}
 if #spots==0 then return false end
 local stateKey=kind=='crystals' and 'crystalGarden' or 'woodGrove'
 local records=get(stateKey) or {}
 local now=workspace:GetServerTimeNow()
 local target,soon
 for _,spot in ipairs(spots) do
    local due=records[spot.Name]
    if due==nil or due<=now then
       local p=(config.base and config.base(spot)) or point(spot)
       if p then
         if not soon or (state.recent[kind..spot.Name] or 0)<soon then target=spot;soon=state.recent[kind..spot.Name] or 0 end
       end
    end
 end
 if not target then return false end
 local p=config.base(target)
 if not p then return false end
 if clock()<(state.recent[kind..target.Name] or 0) then return false end
 local dist=math.max(2,kind=='crystals' and 4 or 3.5)
 state.phase='Harvesting '..kind
 local ok=travel(p+Vector3.new(0,2.5,0),kind,dist,22)
 if not ok then
    state.recent[kind..target.Name]=clock()+10
    return true
 end
 -- Native game harvest needs a real equipped Pickaxe or Axe, including its swing.
 -- Equip AFTER reaching the room: tools are often handed out when entering it.
 local toolName=(kind=='crystals' and 'Pickaxe' or 'Axe')
 if not ensureTool(toolName) then
    task.wait(0.6)
    if not ensureTool(toolName) then
       state.reason='Game has not equipped '..toolName..' for '..kind
       state.recent[kind..target.Name]=clock()+18
       return false
    end
 end
 local okHold,hold=pcall(config.holdSeconds,get('upgrades') or {},1)
 if not okHold or type(hold)~='number' then hold=kind=='crystals' and 2.3 or 3.4 end
 task.wait(math.clamp(hold+0.38,0.65,6))
 local after=(get(stateKey) or {})[target.Name]
 local confirmed=type(after)=='number' and after>workspace:GetServerTimeNow()
 state.recent[kind..target.Name]=clock()+(confirmed and math.max(kind=='crystals' and 15 or 20,7) or 3)
 if confirmed then log('Harvest confirmed: '..kind..' '..target.Name)
 else state.reason='Harvest not confirmed: '..kind..' '..target.Name end
 return true
end
local function essenceOne()
 if not cfg.Essence or not ownedDoor('door34') then return false end
 local folder=workspace:FindFirstChild('EssenceOrbs')
 if not folder then
   if cooldown('essence-sync',12) then fire('Essence','sync') end
   return false
 end
 local root=hrp();if not root then return false end
 local nearest,best
 for _,orb in ipairs(folder:GetChildren()) do
   if orb:IsA('Model') then
     local pos=point(orb)
     if pos and (state.recent['essence:'..orb.Name] or 0)<=clock() then
       local d=(pos-root.Position).Magnitude
       if not best or d<best then nearest=orb;best=d end
     end
   end
 end
 if nearest then
   state.phase='Collect Essence'
   local pos=point(nearest)
   if travel(pos+Vector3.new(0,1.5,0),'essence',3,20) then task.wait(0.20) end
   state.recent['essence:'..nearest.Name]=clock()+2
   return true
 end
 return false
end
local function productionOne(name,enabled,door,record,deposit,collect,raw,roomName,configuration)
 if not enabled or not ownedDoor(door) or not configuration then return false end
 local r=get(record) or {};local upgrades=get('upgrades') or {}
 local root=hrp();if not root then return false end
 local ready=tonumber(r.ready or 0) or 0
 local queued=tonumber(r.queued or 0) or 0
 local charge=tonumber(configuration.CHARGE or configuration.ORE_PER_INGOT or 1) or 1
 local stock=balance(raw)
 local capacity=10
 if configuration.paceFor then
  local ok,p=pcall(function()
   if name=='Smelter' then
    local worldMachine=world('SmelterSystem')
    local path=worldMachine and configuration.path and configuration.path(worldMachine:FindFirstChild('Machine') or worldMachine)
    if path then return configuration.paceFor(path,upgrades) end
   elseif name=='Refractor' then return configuration.paceFor(upgrades,Trees and Trees.totals and Trees.totals(get('tree') or {}) or {})
   else
    local b=Trees and Trees.totals and Trees.totals(get('tree') or {}) or {}
    return configuration.paceFor(upgrades,b.starforgeCapacity or 1)
   end
  end)
  if ok and type(p)=='table' then capacity=tonumber(p.capacity) or capacity end
 end
 local action=nil
 if collect and ready>0 then action=collect
 elseif deposit and queued<capacity-0.01 and stock>=charge and
        (stock-charge>=stock*cfg.ResourceReserve or name=='Smelter') then action=deposit end
 if not action then return false end
 if not cooldown('production:'..name..':'..action,1.1) then return false end
 local area=world(roomName)
 local room=area and area:FindFirstChild('Room')
 if not room then return false end
 local at=room.Position
 if not configuration.inRoom(root.Position) then
  state.phase='Travel '..name
  if not travel(at,'production:'..name,10,14) then return true end
 end
 local newRoot=hrp()
 if not newRoot or not configuration.inRoom(newRoot.Position) then return false end
 state.phase=name..' '..action
 if fire(action) then log(name..': '..action);return true end
 return false
end
local function trySmelt()
 return productionOne('Smelter',cfg.Smelter,'ironOre','smelter','SmelterDeposit','SmelterCollect','iron','SmelterSystem',Smelt)
end
local function tryForge()
 return productionOne('Starforge',cfg.Starforge,'door45','starforge','StarforgeDeposit',nil,'ingots','StarforgeSystem',StarConfig)
end
local function tryRefract()
 return productionOne('Refractor',cfg.Refractor,'door52','refractor','RefractorDeposit',nil,'crystals','RefractorSystem',RefractConfig)
end
local function tryGlyph()
 if not cfg.Glyphs or not Glyphs or not Glyphs.SETS then return false end
 local groups={}
 for _,def in ipairs(Glyphs.SETS) do
   if ownedDoor(def.door) and balance(def.currency or 'gold')>=def.cost*math.max(12, (1/(1-cfg.MinimumGoldReserve))) then
     local owned=get('glyphs') or {}
     local useful=false
     for _,g in ipairs(def.list or {}) do if (tonumber(owned[g.id]) or 0)<(g.cap or 0) then useful=true;break end end
     if useful then groups[#groups+1]=def end
   end
 end
 if #groups==0 then return false end
 -- Built-in glyph zone auto-rolls while in reach. Prefer unlocked affordable sets.
 table.sort(groups,function(a,b) return (a.cost or 0)>(b.cost or 0) end)
 local selected
 for _,v in ipairs(groups) do
   if balance(v.currency or 'gold')>=(v.cost or 0)*20 then selected=v;break end
 end
 selected=selected or groups[#groups]
 if not cooldown('glyph-group:'..selected.id,math.max(8,tonumber(cfg.GlyphSeconds) or 8)) then return false end
 local runes=workspace:FindFirstChild('Runes')
 local spot=runes and runes:FindFirstChild(selected.model)
 if not spot then return false end
 state.phase='Glyph burst '..selected.name
 local p=point(spot)
 if p then
   travel(p+Vector3.new(0,2,0),'glyph:'..selected.id,5,22)
   task.wait(math.clamp(tonumber(cfg.GlyphSeconds) or 8,3,60))
   log('Glyph station '..selected.name)
   return true
 end
 return false
end
local function tryGateway()
 if not cfg.Gateway or not Gateway or not Gateway.eligible then return false end
 local g=get('gateway') or {}
 if not Gateway.eligible(rebirthNumber(),get('doors')) then return false end
 local fill=g.fill or {}
 if g.open==true then
   local landing=Gateway.portalZone and Gateway.portalZone()
   local root=hrp()
   if landing and root and not Stair.inSunkenTower(root.Position) and cooldown('gateway-portal',20) then
      state.phase='Enter Sunken Tower'
      travel(landing.Position,'sunken-portal',4,24);task.wait(1);return true
   end
   return false
 end
 for _,def in ipairs(Gateway.TOTEMS or {}) do
   if (tonumber(fill[def.id]) or 0)<def.target and balance(def.currency)>0 then
      local k='gateway:'..def.id
      if cooldown(k,5) then
        local zone=Gateway.padZone and Gateway.padZone(def)
        if zone then
          state.phase='Gateway deposit: '..def.id
          local ok=travel(zone.Position,'gateway:'..def.id,2.5,25)
          if ok then task.wait(0.7); log('Gateway deposit '..def.id) end
          return true
        end
      end
   end
 end
 return false
end
local function tryFreeWheel()
 if not cfg.FreeRewards then return false end
 local wheel=get('wheel')
 if type(wheel)~='table' or not ownedDoor('door15') then return false end
 -- SpinWheel client sends a request without a paid-spin argument. Only the free cooldown.
 if (tonumber(wheel.nextFree) or math.huge)>workspace:GetServerTimeNow() then return false end
 if not cooldown('freewheel',60) then return false end
 local p=nearestWorld('PrizeWheel')
 if p then travel(p+Vector3.new(0,3,0),'wheel',15,25) end
 if fire('SpinWheel') then state.phase='Free prize wheel'; log('Free wheel spin');return true end
 return false
end
-- Zone-based generators: game server awards stored resources when standing in its
-- own collector zones. These are not hidden remotes and do not bypass purchase checks.
local function collectorStep(label,enabled,door,config,stateName,field,zoneGet)
 if not enabled or not config or not ownedDoor(door) then return false end
 local record=get(stateName) or {}
 local available=tonumber(record[field] or 0) or 0
 if available<=0 then return false end
 local key='collector:'..label
 if not cooldown(key,4) then return false end
 local zone=zoneGet and zoneGet()
 if not zone or not zone:IsA('BasePart') then return false end
 local pos=zone.Position
 state.phase='Collect '..label
 local arrive=travel(pos,label,math.max(2,math.min(zone.Size.X,zone.Size.Z)/2),25)
 if arrive then task.wait(0.65);log('Collecting '..label) end
 return true
end
local function dragonsOne()
 if not cfg.Dragons then return false end
 return collectorStep('Embers',cfg.Dragons,'door53',Roost,'roost','stored',function()
    return Roost.trayZone and Roost.trayZone()
 end)
end
local function voltsOne()
 if not cfg.Volts then return false end
 return collectorStep('Volts',cfg.Volts,'door74',Volt,'capacitor','stored',function()
    return Volt.padZone and Volt.padZone()
 end)
end
local function pearlsOne()
 if not cfg.Pearls or not Pearl or not ownedDoor('door61') then return false end
 local bed=get('pearlBed') or {};local upgrades=get('upgrades') or {}
 if Pearl.autoFeed and Pearl.autoFeed(upgrades) then return false end
 local now=workspace:GetServerTimeNow()
 local feed=math.max(0,(tonumber(bed.feed) or 0)-math.max(0,now-(tonumber(bed.lastAt) or now)))
 local capacity=Pearl.basin and Pearl.basin(upgrades) or 300
 if feed>=capacity*0.45 then return false end
 if not cooldown('pearl-feed',20) then return false end
 local room=Pearl.room and Pearl.room()
 local zone=room and room:FindFirstChild('RoomZone')
 local p=zone and zone.Position or point(room)
 if not p then return false end
 local costPerSecond=tonumber(LP:GetAttribute('PearlFeedCost'))
 local free=LP:GetAttribute('PearlFreeFeed')==true
 if not free and (not costPerSecond or costPerSecond<=0) then
  state.reason='Pearl feed price not available';return false
 end
 local price=math.floor(math.max(0,capacity-feed)*(costPerSecond or 0)+0.5)
 if not free and not afford('gold',price,cfg.MinimumGoldReserve) then return false end
 local root=hrp();if not root then return false end
 state.phase='Top up pearl bed ('..math.floor(100*feed/math.max(1,capacity))..'%)'
 if not Pearl.inRoom(root.Position) then
   if not travel(p,'pearls',5,24) then return true end
 end
 local newRoot=hrp()
 if not newRoot or not Pearl.inRoom(newRoot.Position) then return false end
 local rm=RS:FindFirstChild('PearlRemotes');local obj=rm and rm:FindFirstChild('Feed')
 if obj and remoteQueue(obj) then log('Pearl bed topped up');return true end
 return false
end
local function feathersOne()
 if not cfg.Feathers or not Feather or not ownedDoor('door81') then return false end
 if not Feather.spots then return false end
 local spots=Feather.spots()
 if #spots==0 then return false end
 local data=get('rookery') or {}
 local now=workspace:GetServerTimeNow()
 local root=hrp();if not root then return false end
 local best=nil;local dist=math.huge
 for _,v in ipairs(spots) do
    local key=v.name
    local entry=data[key]
    local availableNest=(tonumber(v.nest) or 0) <= Feather.nests(get('upgrades') or {})
    local ready=Feather.ready and Feather.ready(entry,now)
    if availableNest and ready and clock()>=(state.recent['feather:'..key] or 0) then
      local d=(v.part.Position-root.Position).Magnitude
      if d<dist then best=v;dist=d end
    end
 end
 if not best then return false end
 local k='feather:'..best.name
 state.recent[k]=clock()+8
 state.phase='Collect feathers'
 local reach=Feather.reach and Feather.reach(get('upgrades') or {}) or 8
 local pos=Feather.base(best.part)+Vector3.new(0,2.5,0)
 local ok=travel(pos,'feathers',math.max(2,reach-2),23)
 if ok then task.wait(0.5);log('Feather '..best.name) end
 return true
end
-- Free progression helpers: equip the strongest already-owned trail, and claim the
-- single published RELEASE code once if the saved claim record doesn't include it.
-- Never purchase a trail or prompt the player for any Robux products.
local codeAttempted=false
local function freeCodeOne()
 if not cfg.RedeemReleaseCode or codeAttempted or not Codes or not Codes.CODES or not Codes.CODES.RELEASE then return false end
 local claimed=get('codes') or {}
 if claimed.RELEASE or claimed.release then codeAttempted=true;return false end
 codeAttempted=true
 state.phase='Claim available release code'
 return fire('RedeemCode','RELEASE')
end
local function bestOwnedTrailOne()
 if not cfg.BestOwnedTrail or not Trails or not Trails.LIST or not Trails.buffsOf then return false end
 local owned=get('trails') or {}
 local equipped=get('equippedTrail') or ''
 local bestId=nil;local best=-math.huge
 -- As in the game's TrailInventory power() calculation, multiply all bonuses.
 for _,def in ipairs(Trails.LIST) do
  if owned[def.id]==true then
   local ok,stats=pcall(Trails.buffsOf,def,owned)
   if ok and type(stats)=='table' then
    local power=1
    for _,key in ipairs(Trails.STATS or {}) do
     local mult=math.max(0.01,tonumber(stats[key]) or 1)
     if key=='gold' or key=='silver' or key=='crystals' or key=='wood' or key=='iron' or key=='essence' then
      power=power*mult
     else
      power=power*(mult^0.55)
     end
    end
    if power>best then best=power;bestId=def.id end
   end
  end
 end
 if bestId and bestId~=equipped and cooldown('trail-equip',8) then
  state.phase='Equip best owned trail'
  if fire('EquipTrail',bestId) then log('Equipped owned trail '..bestId);return true end
 end
 return false
end
-- Optional totem optimizer. TotemClient uses exactly Totem("base", slot)
-- and Totem("head",slot,id). Keep this opt-in because it spends progression currencies.
local totemTargets={'gold','silver','iron','crystals','wood','essence','starmetal','prisms','embers','pearls','volts','feathers','luck'}
local function totemOne()
 if not cfg.Totems or not Totems or not Totems.SHRINES then return false end
 local record=get('totems') or {};local used={}
 for _,id in pairs(record.slots or {}) do if id then used[id]=true end end
 for slot=1,math.min(6,Totems.SLOTS or 6) do
  local shrine=Totems.shrineOf(slot)
  if shrine and ownedDoor(shrine.door) then
   local folder=workspace:FindFirstChild(shrine.folder)
   local model=folder and folder:FindFirstChild('Slot'..slot)
   local square=model and model:FindFirstChild('Square')
   if square then
    local key=Totems.key(slot)
    local baseOwned=(record.bases or {})[key]==true
    local action,headId=nil,nil
    if not baseOwned then
     local nextBase=Totems.nextBase(record,slot)
     if nextBase then
      local all=true
      for _,entry in ipairs(Totems.baseParts(nextBase)) do
       if not afford(entry[1],entry[2],entry[1]=='gold' and 0.30 or 0.22) then all=false;break end
      end
      if all then action='base' end
     end
    elseif not (record.slots or {})[key] then
     for _,id in ipairs(totemTargets) do
      local def=Totems.BY_ID[id]
      if def and not used[id] and (record.owned or {})[id] then
       action='head';headId=id;break
      end
     end
     if not action then
      for _,id in ipairs(totemTargets) do
       local def=Totems.BY_ID[id]
       if def and not used[id] and afford(def.currency,def.cost,0.25) then
        action='head';headId=id;break
       end
      end
     end
    end
    if action then
     local id='totem:'..slot..':'..action
     if clock()>=(state.recent[id] or 0) then
      local destination=square.Position+Vector3.new(0,square.Size.Y/2+3,0)
      state.phase='Totem '..action..' slot '..slot
      if not travel(destination,id,7,22) then state.recent[id]=clock()+12;return true end
      state.recent[id]=clock()+4
      if action=='base' then return fire('Totem','base',slot)
      else return fire('Totem','head',slot,headId) end
     end
    end
   end
  end
 end
 return false
end

local nextProduction=0
local function tryProduction()
 if not cfg.Production or clock()<nextProduction then return false end
 nextProduction=clock()+1.6
 if trySmelt() then return true end
 if tryForge() then return true end
 if tryRefract() then return true end
 return false
end
-- Decisive primary-loop scheduler. One movement owner; economy work is intermittent.
local supportJobs={
 {'Codes',freeCodeOne,60},
 {'Best Trail',bestOwnedTrailOne,30},
 {'Production',tryProduction,2.0},
 {'Totems',totemOne,12},
 {'Free Wheel',tryFreeWheel,35},
 {'Dragons',dragonsOne,3},
 {'Volts',voltsOne,3},
 {'Pearls',pearlsOne,18},
 {'Feathers',feathersOne,3},
 {'Mine',mineOne,1.1},
 {'Crystals',function() return cfg.Crystals and groveOne('crystals') end,4},
 {'Wood',function() return cfg.Wood and groveOne('wood') end,4},
 {'Essence',essenceOne,1.2},
 {'Glyphs',tryGlyph,12},
 {'Gateway',tryGateway,12},
}
local supportDone={};local nextSupport=1;local lastSupport=0
local controlDone={}
local function runJob(id,fn,interval)
 local t=clock()
 if t<(controlDone[id] or 0) then return false end
 controlDone[id]=t+(interval or 0.15)
 local ok,out=pcall(fn)
 if not ok then
  state.invalid[id]=(state.invalid[id] or 0)+1
  controlDone[id]=t+math.min(30,3+state.invalid[id]*2)
  return false
 end
 if out then state.invalid[id]=0 end
 return out==true
end
local climbStart=0
local function iterate()
 if not cfg.Master then state.phase='Paused';climbStart=0;return end
 if not readReady() then state.phase='Waiting for player data';return end
 state.dataReady=true;state.floor=currentFloor();state.step=currentStep()
 state.reason=''
 local time=clock()
 if not state.lastProgress or state.lastProgress==0 then
  state.lastProgress=time;state.bestStep=state.step;state.bestRebirth=rebirthNumber()
 elseif state.step~=state.bestStep or rebirthNumber()~=state.bestRebirth then
  state.bestStep=state.step;state.bestRebirth=rebirthNumber();state.lastProgress=time
 end
 if runJob('Rebirth',tryRebirth,1.2) then climbStart=0;return end
 if runJob('Doors',tryDoor,0.7) then climbStart=0;return end
 local stairPrice,stairCurrency=stairCost(currentStep()+1)
 local canClimb=cfg.Stairs and strictAfford(stairCurrency,stairPrice)
 if canClimb then
  if climbStart==0 then climbStart=time end
  local burst=math.max(8,tonumber(cfg.ClimbBurstSeconds) or 24)
  local supportDue=time-lastSupport>=math.max(6,tonumber(cfg.ResourceInterval) or 12)
  if supportDue and time-climbStart>=burst then
    for _=1,#supportJobs do
      local entry=supportJobs[nextSupport]
      nextSupport=nextSupport%#supportJobs+1
      if runJob(entry[1],entry[2],entry[3]) then
       lastSupport=clock();climbStart=0;return
      end
    end
    lastSupport=time;climbStart=time
  end
  -- Give the native purchase loop a continuous opportunity to confirm each step.
  if runJob('Stairs',tryStair,0.13) then return end
 else
  climbStart=0
 end
 if runJob('Upgrades',tryUpgrade,0.35) then return end
 if runJob('Stairs',tryStair,0.18) then return end
 if runJob('Tree',tryTree,1.5) then return end
 for _=1,#supportJobs do
  local entry=supportJobs[nextSupport]
  nextSupport=nextSupport%#supportJobs+1
  if runJob(entry[1],entry[2],entry[3]) then lastSupport=clock();return end
 end
 state.phase=state.reason~='' and state.reason or 'Farming the next income bottleneck'
 if time-state.lastProgress>45 and state.reason=='' then
  state.phase='Progress wall: evaluate income, resource readiness and upgrades'
 end
end
local function taskLoop()
 while alive do
  pcall(iterate)
  task.wait(0.12)
 end
end
task.spawn(taskLoop)
local function unload()
 if not alive then return end
 -- Flush the selected profile before destroying PuckUI. Auto Save may not
 -- have reached its next 0.5-second poll when the user clicks Unload.
 if win and win.Config and win.Config.Available and win.Config.AutoSave and win._WriteConfig then
  pcall(function() win:_WriteConfig(win.Config.Selected,false) end)
 end
 alive=false; cfg.Master=false
 stopMove()
 table.clear(packets);table.clear(inQueue)
 for _,c in ipairs(conns) do pcall(function() c:Disconnect() end) end
 if win then pcall(function() win:Destroy() end) end
 if gen.__PUCK_TOWER_UNLOAD==unload then gen.__PUCK_TOWER_UNLOAD=nil end
end
gen.__PUCK_TOWER_UNLOAD=unload
gen.__PUCK_TOWER_START=function() cfg.Master=true end
gen.__PUCK_TOWER_STOP=function() cfg.Master=false; climbStart=0; stopMove();table.clear(packets);table.clear(inQueue) end
-- Persistent profiles are part of PuckUI. Keep this ConfigId STABLE in all future
-- versions so the user does not lose their preferred profile after script updates.
local CONFIG_ID='Tower_Incremental_UPD6_Fast_v120' -- compatible with v1.2.0
if ui and type(ui.CreateWindow)=='function' then
 local ok,result=pcall(function() return ui:CreateWindow({Title='PuckAFK | Tower Incremental',
    SubTitle='UPD6 Smart Autofarm v1.2.2',GuiName='PuckAFK_TI_UPD6_FAST',ConfigId=CONFIG_ID,
    Width=515,Height=575,Configs={AutoSave=true,AutoLoad=true}}) end)
 if ok then win=result else warn('[PuckAFK TI] Window error '..tostring(result)) end
end
-- Translate settings from v1.2.0/v1.2.1 tab layouts without losing saved profiles.
-- Also runs on manual profile loads, not just on initial Auto Load.
local movedFields={
 Settings={'Rebirth','Preservation','Movement','TweenSpeed'},
 Advanced={'Stairs','Doors','Upgrades','Tree','Mining','Crystals','Wood','Essence',
           'Glyphs','GlyphSeconds','Production','Smelter','Starforge','Refractor',
           'Dragons','Volts','Feathers','Pearls','Totems','Gateway','FreeRewards',
           'FastOwnedStairs','FastUnlockedTeleports','ResourceInterval',
           'ClimbBurstSeconds','BurstUpgrades','MaxRemotePerSecond',
           'MinimumGoldReserve','ResourceReserve','RebirthMode',
           'BestOwnedTrail','RedeemReleaseCode'},
}
local function migrateProfile(values)
 if type(values)~='table' then return end
 for destination,keys in pairs(movedFields) do
  for _,key in ipairs(keys) do
   local flag='TI_'..key
   local new=destination..'.'..flag
   if values[new]==nil then
    -- Prefer the original tab, but also accept the early 'Farm Settings' name.
    for _,oldTab in ipairs({'Settings','Farm Settings','Autofarm','Resources','Production','Advanced'}) do
     local old=oldTab..'.'..flag
     if old~=new and values[old]~=nil then
      values[new]=values[old]
      break
     end
    end
   end
  end
 end
 -- The farm must never begin automatically when a profile is loaded.
 values['Autofarm.TI_Master']=nil
end
if win and win.Config then
 migrateProfile(win.Config.LoadedValues)
 if type(win._ApplyConfigValues)=='function' then
  local originalApply=win._ApplyConfigValues
  function win:_ApplyConfigValues(values)
   migrateProfile(values)
   return originalApply(self,values)
  end
 end
end
local controls={}
local function toggle(tab,name,key,default)
 if not tab then return nil end
 local item=tab:CreateToggle({Name=name,Flag='TI_'..key,CurrentValue=default,
   NoConfig=key=='Master',
   Callback=function(v)
     if not alive then return end
     cfg[key]=v==true
     if key=='Master' and not cfg.Master then
      climbStart=0;stopMove();table.clear(packets);table.clear(inQueue)
     end
   end})
 controls[key]=item
 return item
end
local function slider(tab,name,key,min,max,inc,suffix)
 if not tab then return nil end
 local item=tab:CreateSlider({Name=name,Flag='TI_'..key,Range={min,max},Increment=inc,
   CurrentValue=cfg[key],Suffix=suffix or '',Callback=function(v)
     if not alive then return end
     cfg[key]=math.clamp(tonumber(v) or cfg[key],min,max)
   end})
 controls[key]=item
 return item
end
local function dropdown(tab,name,key,options)
 if not tab then return nil end
 local item=tab:CreateDropdown({Name=name,Options=options,CurrentOption={cfg[key]},Flag='TI_'..key,
  Callback=function(v)
   if not alive then return end
   local choice=type(v)=='table' and v[1] or v
   if type(choice)=='string' and table.find(options,choice) then cfg[key]=choice end
  end})
 controls[key]=item
 return item
end
local function setOption(key,value)
 local item=controls[key]
 if item and type(item.Set)=='function' then
  local ok=pcall(function() item:Set(value) end)
  if not ok then trace('Could not update setting '..key) end
 end
end
local function openConfigs()
 if not win then return end
 local tab=win._ConfigTab
 if not tab and type(win._EnsureConfigTab)=='function' then
  local ok,result=pcall(function() return win:_EnsureConfigTab() end)
  if ok then tab=result end
 end
 if tab and win.SelectTab then win:SelectTab(tab) end
end
-- One clean page by default. PuckUI's native Settings and Configs remain intact;
-- all per-feature and technical tuning controls live behind an optional tab.
local settingsTab=nil
local advancedTab=nil
local advancedVisible=false
if win then
 local main=win:CreateTab('Autofarm')
 main:CreateSection('Automatic Progression')
 local phaseLabel=main:CreateLabel('Status: Ready to start')
 local infoLabel=main:CreateLabel('Floor 0  |  Stairs 1  |  Rebirths 0')
 toggle(main,'Start / Stop Smart Autofarm','Master',false)
 main:CreateParagraph({Title='One-click farming',
   Content='Automatically climbs stairs, upgrades income, collects resources, handles production and progresses through the tower.',Height=62})
 main:CreateButton({Name='Settings',Callback=function()
  if settingsTab then win:SelectTab(settingsTab) end
 end})
 main:CreateButton({Name='Configs (Save / Load)',Callback=openConfigs})
 main:CreateButton({Name='Unload Script',Callback=unload})

 local settings=win:CreateTab('Settings')
 settingsTab=settings
 settings:CreateSection('Autofarm Options')
 toggle(settings,'Auto Rebirth','Rebirth',cfg.Rebirth)
 toggle(settings,'Keep upgrades before rebirth','Preservation',cfg.Preservation)
 dropdown(settings,'Movement','Movement',{'Hybrid','Tween','Walk'})
 slider(settings,'Movement speed','TweenSpeed',25,350,5,' studs/s')
 settings:CreateButton({Name='Open Saved Configs',Callback=openConfigs})
 local showAdvancedButton
 local function openAdvanced()
  advancedVisible=not advancedVisible
  if advancedTab and advancedTab.Button then
   advancedTab.Button.Visible=advancedVisible
  end
  if showAdvancedButton then
   showAdvancedButton:Set(advancedVisible and 'Hide Advanced Options' or 'Show Advanced Options')
  end
  if advancedVisible then
   if advancedTab then win:SelectTab(advancedTab) end
  else
   win:SelectTab(settings)
  end
 end
 showAdvancedButton=settings:CreateButton({Name='Show Advanced Options',Callback=openAdvanced})

 local advanced=win:CreateTab('Advanced')
 advancedTab=advanced
 -- Keep the default navigation to Autofarm, Settings and Configs only.
 if advanced.Button then advanced.Button.Visible=false end
 advanced:CreateSection('Tower Progression')
 toggle(advanced,'Auto Stairs','Stairs',cfg.Stairs)
 toggle(advanced,'Auto Doors','Doors',cfg.Doors)
 toggle(advanced,'Auto Income Upgrades','Upgrades',cfg.Upgrades)
 toggle(advanced,'Auto Upgrade Trees','Tree',cfg.Tree)
 toggle(advanced,'Assist Gateway','Gateway',cfg.Gateway)
 advanced:CreateSection('Resources')
 toggle(advanced,'Mine Silver and Iron','Mining',cfg.Mining)
 toggle(advanced,'Collect Crystals','Crystals',cfg.Crystals)
 toggle(advanced,'Chop Wood','Wood',cfg.Wood)
 toggle(advanced,'Collect Essence','Essence',cfg.Essence)
 toggle(advanced,'Roll Glyphs','Glyphs',cfg.Glyphs)
 slider(advanced,'Glyph session','GlyphSeconds',3,30,1,'s')
 advanced:CreateSection('Production')
 toggle(advanced,'Manufacturing','Production',cfg.Production)
 toggle(advanced,'Smelter','Smelter',cfg.Smelter)
 toggle(advanced,'Starforge','Starforge',cfg.Starforge)
 toggle(advanced,'Refractor','Refractor',cfg.Refractor)
 toggle(advanced,'Dragon Embers','Dragons',cfg.Dragons)
 toggle(advanced,'Collect Volts','Volts',cfg.Volts)
 toggle(advanced,'Collect Feathers','Feathers',cfg.Feathers)
 toggle(advanced,'Pearl Beds','Pearls',cfg.Pearls)
 advanced:CreateSection('Optional Extras')
 toggle(advanced,'Totem Optimizer (uses currency)','Totems',cfg.Totems)
 toggle(advanced,'Free Reward Spins','FreeRewards',cfg.FreeRewards)
 toggle(advanced,'Equip Best Owned Trail','BestOwnedTrail',cfg.BestOwnedTrail)
 toggle(advanced,'Redeem Release Reward','RedeemReleaseCode',cfg.RedeemReleaseCode)
 advanced:CreateSection('Movement and Timing')
 toggle(advanced,'Fast Owned Stairs','FastOwnedStairs',cfg.FastOwnedStairs)
 toggle(advanced,'Unlocked Teleports','FastUnlockedTeleports',cfg.FastUnlockedTeleports)
 slider(advanced,'Resource trips','ResourceInterval',6,40,1,'s')
 slider(advanced,'Climb duration','ClimbBurstSeconds',8,60,1,'s')
 slider(advanced,'Upgrade batch size','BurstUpgrades',1,24,1,'')
 slider(advanced,'Max requests per second','MaxRemotePerSecond',2,10,1,'/s')
 advanced:CreateSection('Currency and Rebirth')
 slider(advanced,'Gold reserve','MinimumGoldReserve',0,0.8,0.05,'')
 slider(advanced,'Resource reserve','ResourceReserve',0,0.8,0.05,'')
 dropdown(advanced,'Rebirth Strategy','RebirthMode',{'Smart','Immediate'})
 advanced:CreateSection('Ready-made Profiles')
 advanced:CreateButton({Name='Fast Climbing',Callback=function()
  setOption('Movement','Hybrid');setOption('TweenSpeed',165)
  setOption('FastOwnedStairs',true);setOption('FastUnlockedTeleports',true)
  setOption('ClimbBurstSeconds',36);setOption('ResourceInterval',15)
  setOption('BurstUpgrades',16);setOption('MaxRemotePerSecond',8)
 end})
 advanced:CreateButton({Name='Balanced Farming',Callback=function()
  setOption('Movement','Hybrid');setOption('TweenSpeed',110)
  setOption('FastOwnedStairs',true);setOption('FastUnlockedTeleports',true)
  setOption('ClimbBurstSeconds',24);setOption('ResourceInterval',12)
  setOption('BurstUpgrades',12);setOption('MaxRemotePerSecond',6)
 end})
 advanced:CreateButton({Name='Walking Mode',Callback=function()
  setOption('Movement','Walk');setOption('FastOwnedStairs',false)
  setOption('FastUnlockedTeleports',false);setOption('TweenSpeed',45)
  setOption('ClimbBurstSeconds',15);setOption('ResourceInterval',15)
  setOption('BurstUpgrades',6);setOption('MaxRemotePerSecond',4)
 end})
 advanced:CreateButton({Name='Return to Simple View',Callback=function()
  if advancedVisible then openAdvanced() else win:SelectTab(main) end
 end})
 if type(win._EnsureConfigTab)=='function' then
  pcall(function() win:_EnsureConfigTab() end)
 end
 -- Close always unloads, and the Unload button remains available on Autofarm.
 win:SetCloseCallback(unload)
 local function friendlyStatus()
  if not cfg.Master then return 'Stopped' end
  local phase=tostring(state.phase or '')
  if phase=='Starting' or phase=='Waiting for player data' then return 'Preparing' end
  if phase:find('Rebirth') or phase:find('rebirth') then return 'Rebirthing' end
  if phase:find('stair') or phase:find('climb') then return 'Climbing stairs' end
  if phase:find('Unlock') or phase:find('Gateway') then return 'Unlocking a new area' end
  if phase:find('Mine') or phase:find('Harvest') then return 'Gathering resources' end
  if phase:find('Glyph') then return 'Rolling glyphs' end
  if phase:find('Upgrade') or phase:find('tree') or phase:find('Improve') then return 'Buying upgrades' end
  if phase:find('Collect') or phase:find('Smelter') or phase:find('Starforge') or phase:find('Refractor') then return 'Collecting and producing' end
  if phase:find('Waiting for') then return 'Earning currency' end
  if phase:find('Progress wall') then return 'Working towards next milestone' end
  if phase:find('Travel') then return 'Moving to next activity' end
  return 'Progressing automatically'
 end
 conns[#conns+1]=RunService.Heartbeat:Connect(function()
  if not alive or not phaseLabel then return end
  if not cooldown('ui-refresh',0.7) then return end
  pcall(function()
   phaseLabel:Set('Status: '..friendlyStatus())
   infoLabel:Set('Floor '..(state.floor or currentFloor())..'  |  Stairs '..(state.step or currentStep())..'  |  Rebirths '..rebirthNumber())
  end)
 end)
end
