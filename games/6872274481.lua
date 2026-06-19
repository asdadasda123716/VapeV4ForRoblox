local run = function(func)
	local suc, res = pcall(function()
		task.spawn(func)
	end)
	if not suc then
		warn('Failed to load function? reasoning',res)
	end
end

local cloneref = cloneref or function(obj)
	return obj
end

local vapeEvents = setmetatable({}, {
	__index = function(self, index)
		self[index] = Instance.new('BindableEvent')
		return self[index]
	end
})

local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local runService = cloneref(game:GetService('RunService'))
local inputService = cloneref(game:GetService('UserInputService'))
local tweenService = cloneref(game:GetService('TweenService'))
local httpService = cloneref(game:GetService('HttpService'))
local textChatService = cloneref(game:GetService('TextChatService'))
local collectionService = cloneref(game:GetService('CollectionService'))
local contextActionService = cloneref(game:GetService('ContextActionService'))
local guiService = cloneref(game:GetService('GuiService'))
local coreGui = cloneref(game:GetService('CoreGui'))
local starterGui = cloneref(game:GetService('StarterGui'))
local lightingService = cloneref(game:GetService('Lighting'))
local virtualService = cloneref(game:GetService("VirtualInputManager"))
local isnetworkowner = identifyexecutor and table.find({'Volcano','Nihon'}, ({identifyexecutor()})[1]) and isnetworkowner or function()
	return true
end


local gameCamera = workspace.CurrentCamera
local lplr = playersService.LocalPlayer
local assetfunction = getcustomasset
local vape = shared.vape
local entitylib = vape.Libraries.entity
local targetinfo = vape.Libraries.targetinfo
local sessioninfo = vape.Libraries.sessioninfo
local uipallet = vape.Libraries.uipallet
local tween = vape.Libraries.tween
local color = vape.Libraries.color
local whitelist = vape.Libraries.whitelist
local prediction = vape.Libraries.prediction
local getfontsize = vape.Libraries.getfontsize
local getcustomasset = vape.Libraries.getcustomasset

local rankCache = {}
local store = {
	airRay = nil,
	attackReach = 0,
	attackReachUpdate = tick(),
	damageBlockFail = tick(),
	hand = {},
	inventory = {
		inventory = {
			items = {},
			armor = {}
		},
		hotbar = {}
	},
	inventories = setmetatable({}, {
		__mode = "k"
	}),
	matchState = 0,
	queueType = 'bedwars_test',
	tools = {},
	lastToolUpdate = 0,
	ranks = setmetatable({}, {
		__index = function(self, plr)
			return {
				async = function()
					if rankCache[plr] then
						return rankCache[plr]
					end

					if plr then
						local rank = bedwars.Client:Get('FetchRanks'):CallServer({plr.UserId})
						if typeof(rank) == 'table' and rank[1] and rank[1].rankDivision then
							rankCache[plr] = rank[1].rankDivision
							return rankCache[plr]
						end
					end

					return nil
				end,
			}
		end
	}),
	enchants = setmetatable({},{
		__index = function(self, plr)
			return {
				async = function()
					if plr and plr.Character then
						for i in plr.Character:GetAttributes() do
							if i:find('StatusEffect_') and not i:find('_stacks') then
								local name = bedwars.StatusEffectMeta[({i:gsub('StatusEffect_', '')})[1]]
								if bedwars.StatusEffectMeta[name] then
									name = bedwars.StatusEffectMeta[name]
									for num = 1, 3 do
										name = name:gsub(`_{num}`, '')
									end

									if bedwars.EnchantMeta[name] then
										return bedwars.EnchantMeta[name].image
									end
								end
							end
						end
					end
					return nil
				end,
			}
		end
	}),
	gloopeds = setmetatable({},{
		__index = function(self, plr)
			return {
				async = function()
					if plr and plr.Character then
						for i in plr.Character:GetAttributes() do
							return (i:find('grounded') and v > 0 or false)
						end
					end
					return nil
				end,
			}
		end
	}),
	FlaggedCheaters = {},
	lastHit = tick(),
}
getgenv().store = store
local Reach = {}
local HitBoxes = {}
local InfiniteFly = {}
local TrapDisabler
local AntiFallPart
local bedwars, remotes, sides, oldinvrender, oldSwing = {}, {}, {}
local function addBlur(parent)
	local blur = Instance.new('ImageLabel')
	blur.Name = 'Blur'
	blur.Size = UDim2.new(1, 89, 1, 52)
	blur.Position = UDim2.fromOffset(- 48, - 31)
	blur.BackgroundTransparency = 1
	blur.Image = getcustomasset('newvape/assets/new/blur.png')
	blur.ScaleType = Enum.ScaleType.Slice
	blur.SliceCenter = Rect.new(52, 31, 261, 502)
	blur.Parent = parent
	return blur
end

local function collection(tags, module, customadd, customremove)
	tags = typeof(tags) ~= 'table' and {
		tags
	} or tags
	local objs, connections = {}, {}
	for _, tag in tags do
		table.insert(connections, collectionService:GetInstanceAddedSignal(tag):Connect(function(v)
			if customadd then
				customadd(objs, v, tag)
				return
			end
			table.insert(objs, v)
		end))
		table.insert(connections, collectionService:GetInstanceRemovedSignal(tag):Connect(function(v)
			if customremove then
				customremove(objs, v, tag)
				return
			end
			v = table.find(objs, v)
			if v then
				table.remove(objs, v)
			end
		end))
		for _, v in collectionService:GetTagged(tag) do
			if customadd then
				customadd(objs, v, tag)
				continue
			end
			table.insert(objs, v)
		end
	end
	local cleanFunc = function(self)
		for _, v in connections do
			v:Disconnect()
		end
		table.clear(connections)
		table.clear(objs)
		table.clear(self)
	end
	if module then
		module:Clean(cleanFunc)
	end
	return objs, cleanFunc
end

local function getBestArmor(slot)
	local closest, mag = nil, 0
	for _, item in store.inventory.inventory.items do
		local meta = item and bedwars.ItemMeta[item.itemType] or {}
		if meta.armor and meta.armor.slot == slot then
			local newmag = (meta.armor.damageReductionMultiplier or 0)
			if newmag > mag then
				closest, mag = item, newmag
			end
		end
	end
	return closest
end

local function getBow()
	local bestBow, bestBowSlot, bestBowDamage = nil, nil, 0
	for slot, item in store.inventory.inventory.items do
		local bowMeta = bedwars.ItemMeta[item.itemType].projectileSource
		if bowMeta and table.find(bowMeta.ammoItemTypes, 'arrow') then
			local bowDamage = bedwars.ProjectileMeta[bowMeta.projectileType('arrow')].combat.damage or 0
			if bowDamage > bestBowDamage then
				bestBow, bestBowSlot, bestBowDamage = item, slot, bowDamage
			end
		end
	end
	return bestBow, bestBowSlot
end

local function getItem(itemName, inv)
	for slot, item in (inv or store.inventory.inventory.items) do
		if item.itemType == itemName then
			return item, slot
		end
	end
	return nil
end

local function getRoactRender(func)
	return debug.getupvalue(debug.getupvalue(debug.getupvalue(func, 3).render, 2).render, 1)
end

local function getSword()
	local bestSword, bestSwordSlot, bestSwordDamage = nil, nil, 0
	for slot, item in store.inventory.inventory.items do
		local swordMeta = bedwars.ItemMeta[item.itemType].sword
		if swordMeta then
			local swordDamage = swordMeta.damage or 0
			if swordDamage > bestSwordDamage then
				bestSword, bestSwordSlot, bestSwordDamage = item, slot, swordDamage
			end
		end
	end
	return bestSword, bestSwordSlot
end

local function getTool(breakType)
	local bestTool, bestToolSlot, bestToolDamage = nil, nil, 0
	for slot, item in store.inventory.inventory.items do
		local toolMeta = bedwars.ItemMeta[item.itemType].breakBlock
		if toolMeta then
			local toolDamage = toolMeta[breakType] or 0
			if toolDamage > bestToolDamage then
				bestTool, bestToolSlot, bestToolDamage = item, slot, toolDamage
			end
		end
	end
	return bestTool, bestToolSlot
end

local function getWool()
	for _, wool in (inv or store.inventory.inventory.items) do
		if wool.itemType:find('wool') then
			return wool and wool.itemType, wool and wool.amount
		end
	end
end

local function getStrength(plr)
	if not plr.Player then
		return 0
	end
	local strength = 0
	for _, v in (store.inventories[plr.Player] or {
		items = {}
	}).items do
		local itemmeta = bedwars.ItemMeta[v.itemType]
		if itemmeta and itemmeta.sword and itemmeta.sword.damage > strength then
			strength = itemmeta.sword.damage
		end
	end
	return strength
end

local function getPlacedBlock(pos)
	if not pos then
		return
	end
	local roundedPosition = bedwars.BlockController:getBlockPosition(pos)
	return bedwars.BlockController:getStore():getBlockAt(roundedPosition), roundedPosition
end

local function getBlocksInPoints(s, e)
	local blocks, list = bedwars.BlockController:getStore(), {}
	for x = s.X, e.X do
		for y = s.Y, e.Y do
			for z = s.Z, e.Z do
				local vec = Vector3.new(x, y, z)
				if blocks:getBlockAt(vec) then
					table.insert(list, vec * 3)
				end
			end
		end
	end
	return list
end

local function getNearGround(range)
	range = Vector3.new(3, 3, 3) * (range or 10)
	local localPosition, mag, closest = entitylib.character.RootPart.Position, 60
	local blocks = getBlocksInPoints(bedwars.BlockController:getBlockPosition(localPosition - range), bedwars.BlockController:getBlockPosition(localPosition + range))
	for _, v in blocks do
		if not getPlacedBlock(v + Vector3.new(0, 3, 0)) then
			local newmag = (localPosition - v).Magnitude
			if newmag < mag then
				mag, closest = newmag, v + Vector3.new(0, 3, 0)
			end
		end
	end
	table.clear(blocks)
	return closest
end

local function getShieldAttribute(char)
	local returned = 0
	for name, val in char:GetAttributes() do
		if name:find('Shield') and type(val) == 'number' and val > 0 then
			returned += val
		end
	end
	return returned
end

local function getSpeed()
	local multi, increase, modifiers = 0, true, bedwars.SprintController:getMovementStatusModifier():getModifiers()
	for v in modifiers do
		local val = v.constantSpeedMultiplier and v.constantSpeedMultiplier or 0
		if val and val > math.max(multi, 1) then
			increase = false
			multi = val - (0.06 * math.round(val))
		end
	end
	for v in modifiers do
		multi += math.max((v.moveSpeedMultiplier or 0) - 1, 0)
	end
	if multi > 0 and increase then
		multi += 0.16 + (0.02 * math.round(multi))
	end
	return 20 * (multi + 1)
end

local function getTableSize(tab)
	local ind = 0
	for _ in tab do
		ind += 1
	end
	return ind
end

local function hotbarSwitch(slot)
	if slot and store.inventory.hotbarSlot ~= slot then
		bedwars.Store:dispatch({
			type = 'InventorySelectHotbarSlot',
			slot = slot
		})
		vapeEvents.InventoryChanged.Event:Wait()
		return true
	end
	return false
end

local function isFriend(plr, recolor)
	if vape.Categories.Friends.Options['Use friends'].Enabled then
		local friend = table.find(vape.Categories.Friends.ListEnabled, plr.Name) and true
		if recolor then
			friend = friend and vape.Categories.Friends.Options['Recolor visuals'].Enabled
		end
		return friend
	end
	return nil
end

local function isTarget(plr)
	return table.find(vape.Categories.Targets.ListEnabled, plr.Name) and true
end

local function notif( ...)
	return vape:CreateNotification(...)
end

local function removeTags(str)
	str = str:gsub('<br%s*/>', '\n')
	return (str:gsub('<[^<>]->', ''))
end

local function roundPos(vec)
	return Vector3.new(math.round(vec.X / 3) * 3, math.round(vec.Y / 3) * 3, math.round(vec.Z / 3) * 3)
end

local function switchItem(tool, delayTime)
	delayTime = delayTime or 0.05
	local check = lplr.Character and lplr.Character:FindFirstChild('HandInvItem') or nil
	if check and check.Value ~= tool and tool.Parent ~= nil then
		task.spawn(function()
			bedwars.Client:Get(remotes.EquipItem):CallServerAsync({
				hand = tool
			})
		end)
		check.Value = tool
		if delayTime > 0 then
			task.wait(delayTime)
		end
		return true
	end
end

local function waitForChildOfType(obj, name, timeout, prop)
	local check, returned = tick() + timeout
	repeat
		returned = prop and obj[name] or obj:FindFirstChildOfClass(name)
		if returned and returned.Name ~= 'UpperTorso' or check < tick() then
			break
		end
		task.wait()
	until false
	return returned
end

local frictionTable, oldfrict = {}, {}
local frictionConnection
local frictionState
local function modifyVelocity(v)
	if v:IsA('BasePart') and v.Name ~= 'HumanoidRootPart' and not oldfrict[v] then
		oldfrict[v] = v.CustomPhysicalProperties or 'none'
		v.CustomPhysicalProperties = PhysicalProperties.new(0.0001, 0.2, 0.5, 1, 1)
	end
end

local function updateVelocity(force)
	local newState = getTableSize(frictionTable) > 0
	if frictionState ~= newState or force then
		if frictionConnection then
			frictionConnection:Disconnect()
		end
		if newState then
			if entitylib.isAlive then
				for _, v in entitylib.character.Character:GetDescendants() do
					modifyVelocity(v)
				end
				frictionConnection = entitylib.character.Character.DescendantAdded:Connect(modifyVelocity)
			end
		else
			for i, v in oldfrict do
				i.CustomPhysicalProperties = v ~= 'none' and v or nil
			end
			table.clear(oldfrict)
		end
	end
	frictionState = newState
end

local kitorder = {
	hannah = 5,
	spirit_assassin = 4,
	dasher = 3,
	jade = 2,
	regent = 1
}

local sortmethods = {
	Damage = function(a, b)
		return a.Entity.Character:GetAttribute('LastDamageTakenTime') < b.Entity.Character:GetAttribute('LastDamageTakenTime')
	end,
	Threat = function(a, b)
		return getStrength(a.Entity) > getStrength(b.Entity)
	end,
	Kit = function(a, b)
		return (a.Entity.Player and kitorder[a.Entity.Player:GetAttribute('PlayingAsKit')] or 0) > (b.Entity.Player and kitorder[b.Entity.Player:GetAttribute('PlayingAsKit')] or 0)
	end,
	Health = function(a, b)
		return a.Entity.Health < b.Entity.Health
	end,
	Angle = function(a, b)
		local selfrootpos = entitylib.character.RootPart.Position
		local localfacing = entitylib.character.RootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
		local angle = math.acos(localfacing:Dot(((a.Entity.RootPart.Position - selfrootpos) * Vector3.new(1, 0, 1)).Unit))
		local angle2 = math.acos(localfacing:Dot(((b.Entity.RootPart.Position - selfrootpos) * Vector3.new(1, 0, 1)).Unit))
		return angle < angle2
	end
}

run(function()
	local oldstart = entitylib.start
	local function customEntity(ent)
		if ent:HasTag('inventory-entity') and not ent:HasTag('Monster') then
			return
		end
		entitylib.addEntity(ent, nil, ent:HasTag('Drone') and function(self)
			local droneplr = playersService:GetPlayerByUserId(self.Character:GetAttribute('PlayerUserId'))
			return not droneplr or lplr:GetAttribute('Team') ~= droneplr:GetAttribute('Team')
		end or function(self)
			return lplr:GetAttribute('Team') ~= self.Character:GetAttribute('Team')
		end)
	end
	entitylib.start = function()
		if entitylib.Running then
			entitylib.stop()
		end
		local function customEntity(ent)
			if playersService:GetPlayerFromCharacter(ent) then
				return
			end
			if collectionService:HasTag(ent.Parent, 'entity') then
				return
			end
			local teamFunc = function(self)
				local npcTeam = self.Character:GetAttribute('Team')
				return lplr:GetAttribute('Team') ~= npcTeam
			end
			entitylib.addEntity(ent, nil, teamFunc)
		end
		table.insert(entitylib.Connections, playersService.PlayerAdded:Connect(function(v)
			entitylib.addPlayer(v)
		end))
		table.insert(entitylib.Connections, playersService.PlayerRemoving:Connect(function(v)
			entitylib.removePlayer(v)
		end))
		for _, v in playersService:GetPlayers() do
			entitylib.addPlayer(v)
		end
		for _, ent in collectionService:GetTagged('entity') do
			customEntity(ent)
		end
		table.insert(entitylib.Connections, collectionService:GetInstanceAddedSignal('entity'):Connect(customEntity))
		table.insert(entitylib.Connections, collectionService:GetInstanceRemovedSignal('entity'):Connect(function(ent)
			entitylib.removeEntity(ent)
		end))
		local function addDesertPot(pot)
			if not pot:IsA('Model') then
				return
			end
			entitylib.addEntity(pot, nil, function()
				return true
			end)
		end
		for _, v in collectionService:GetTagged('desert_pot') do
			addDesertPot(v)
		end
		table.insert(entitylib.Connections, collectionService:GetInstanceAddedSignal('desert_pot'):Connect(addDesertPot))
		table.insert(entitylib.Connections, collectionService:GetInstanceRemovedSignal('desert_pot'):Connect(function(v)
			entitylib.removeEntity(v)
		end))
		table.insert(entitylib.Connections, workspace:GetPropertyChangedSignal('CurrentCamera'):Connect(function()
			gameCamera = workspace.CurrentCamera or workspace:FindFirstChildWhichIsA('Camera')
		end))
		entitylib.Running = true
	end
	entitylib.addPlayer = function(plr)
		if entitylib.PlayerConnections[plr] then
			for _, conn in ipairs(entitylib.PlayerConnections[plr]) do
				if conn and typeof(conn) == "RBXScriptConnection" then
					conn:Disconnect()
				end
			end
		end
		if plr.Character then
			entitylib.refreshEntity(plr.Character, plr)
		end
		entitylib.PlayerConnections[plr] = {
			plr.CharacterAdded:Connect(function(char)
				entitylib.refreshEntity(char, plr)
			end),
			plr.CharacterRemoving:Connect(function(char)
				entitylib.removeEntity(char, plr == lplr)
			end),
			plr:GetAttributeChangedSignal('Team'):Connect(function()
				if plr == lplr then
					for _, v in entitylib.List do
						local newTargetable = entitylib.targetCheck(v)
						if v.Targetable ~= newTargetable then
							v.Targetable = newTargetable
							entitylib.Events.EntityUpdated:Fire(v)
						end
					end
				else
					entitylib.refreshEntity(plr.Character, plr)
					for _, v in entitylib.List do
						if v.Player ~= plr and v.Targetable ~= entitylib.targetCheck(v) then
							local newTargetable = entitylib.targetCheck(v)
							v.Targetable = newTargetable
							entitylib.Events.EntityUpdated:Fire(v)
						end
					end
				end
			end)
		}
	end
	entitylib.addEntity = function(char, plr, teamfunc)
		if not char then
			return
		end
		entitylib.EntityThreads[char] = task.spawn(function()
			local hum, humrootpart, head
			if plr then
				hum = waitForChildOfType(char, 'Humanoid', 10)
				humrootpart = hum and waitForChildOfType(hum, 'RootPart', workspace.StreamingEnabled and 9e9 or 10, true)
				head = char:WaitForChild('Head', 10) or humrootpart
			else
				hum = {
					HipHeight = 0.5
				}
				humrootpart = waitForChildOfType(char, 'PrimaryPart', 10, true)
				head = humrootpart
			end
			local updateobjects = {}
			if plr and plr ~= lplr then
				local names = {
					'ArmorInvItem_0',
					'ArmorInvItem_1',
					'ArmorInvItem_2',
					'HandInvItem'
				}
				for _, name in names do
					local found = char:FindFirstChild(name)
					if found then
						table.insert(updateobjects, found)
					end
				end
			end
			if hum and humrootpart then
				local entity = {
					Connections = {},
					Character = char,
					Health = (function()
						local hp = char:GetAttribute('Health') or 100
						local shield = 0
						for k, v in pairs(char:GetAttributes()) do
							if type(k) == 'string' and k:sub(1, 7) == 'Shield_' and type(v) == 'number' and v > 0 then
								shield = shield + v
							end
						end
						return hp + shield
					end)(),
					Head = head,
					Humanoid = hum,
					HumanoidRootPart = humrootpart,
					HipHeight = hum.HipHeight + (humrootpart.Size.Y / 2) + (hum.RigType == Enum.HumanoidRigType.R6 and 2 or 0),
					Jumps = 0,
					JumpTick = tick(),
					Jumping = false,
					LandTick = tick(),
					MaxHealth = char:GetAttribute('MaxHealth') or 100,
					NPC = plr == nil,
					Player = plr,
					RootPart = humrootpart,
					TeamCheck = teamfunc
				}
				if plr == lplr then
					entity.AirTime = tick()
					entitylib.character = entity
					entitylib.isAlive = true
					entitylib.Events.LocalAdded:Fire(entity)
					table.insert(entity.Connections, char.AttributeChanged:Connect(function(attr)
						vapeEvents.AttributeChanged:Fire(attr)
					end))
				else
					entity.Targetable = entitylib.targetCheck(entity)
					if not plr then
						table.insert(entity.Connections, char.AttributeChanged:Connect(function(attr)
							if attr == 'Team' then
								entity.Targetable = entitylib.targetCheck(entity)
								entitylib.Events.EntityUpdated:Fire(entity)
							end
						end))
					end
					for _, v in entitylib.getUpdateConnections(entity) do
						table.insert(entity.Connections, v:Connect(function()
							entity.Health = (char:GetAttribute('Health') or 100) + getShieldAttribute(char)
							entity.MaxHealth = char:GetAttribute('MaxHealth') or 100
							entitylib.Events.EntityUpdated:Fire(entity)
						end))
					end
					local invUpdatePending = {}
					for _, v in updateobjects do
						table.insert(entity.Connections, v:GetPropertyChangedSignal('Value'):Connect(function()
							if invUpdatePending[entity] then
								return
							end
							invUpdatePending[entity] = true
							task.delay(0.1, function()
								invUpdatePending[entity] = nil
								if bedwars.getInventory then
									store.inventories[plr] = bedwars.getInventory(plr)
									entitylib.Events.EntityUpdated:Fire(entity)
								end
							end)
						end))
					end
					if plr then
						local anim = char:FindFirstChild('Animate')
						if anim then
							pcall(function()
								local jumpAnimId = anim.jump:FindFirstChildWhichIsA('Animation').AnimationId
								table.insert(entity.Connections, hum.StateChanged:Connect(function(old, new)
									if new == Enum.HumanoidStateType.Jumping then
										entity.JumpTick = tick()
										entity.Jumps += 1
										entity.LandTick = tick() + 1
										entity.Jumping = entity.Jumps > 1
									elseif new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running or new == Enum.HumanoidStateType.Freefall then
										entity.Jumping = false
									end
								end))
							end)
						end
						task.delay(0.1, function()
							if bedwars.getInventory then
								store.inventories[plr] = bedwars.getInventory(plr)
							end
						end)
					end
					table.insert(entitylib.List, entity)
					entitylib.Events.EntityAdded:Fire(entity)
				end
				table.insert(entity.Connections, char.ChildRemoved:Connect(function(part)
					if part == humrootpart or part == hum or part == head then
						if part == humrootpart and hum.RootPart then
							humrootpart = hum.RootPart
							entity.RootPart = hum.RootPart
							entity.HumanoidRootPart = hum.RootPart
							return
						end
						entitylib.removeEntity(char, plr == lplr)
					end
				end))
			end
			entitylib.EntityThreads[char] = nil
		end)
	end
	entitylib.getUpdateConnections = function(ent)
		local char = ent.Character
		local tab = {
			char:GetAttributeChangedSignal('Health'),
			char:GetAttributeChangedSignal('MaxHealth'),
			{
				Connect = function()
					ent.Friend = ent.Player and isFriend(ent.Player) or nil
					ent.Target = ent.Player and isTarget(ent.Player) or nil
					return {
						Disconnect = function()
						end
					}
				end
			}
		}
		if ent.Player then
			table.insert(tab, ent.Player:GetAttributeChangedSignal('PlayingAsKit'))
			table.insert(tab, ent.Player:GetAttributeChangedSignal('PlayingAsKits'))
			local vkSignal = {
				Connect = function(_, func)
					local conn = ent.Player:GetAttributeChangedSignal('VoidKnightTier'):Connect(function()
						lastUpdate[ent] = 0
						func()
					end)
					return conn
				end
			}
			table.insert(tab, vkSignal)
		end
		local blockKickerSignal = {
			Connect = function(_, func)
				local conn = char.AttributeChanged:Connect(function(attr)
					if attr == 'BlockKickerKit_BlockCount' then
						lastUpdate[ent] = 0
						func()
					end
				end)
				return conn
			end
		}
		table.insert(tab, blockKickerSignal)
		local shieldSignal = {
			Connect = function(_, func)
				local conn = char.AttributeChanged:Connect(function(attr)
					if attr:find('Shield') then
						func()
					end
				end)
				return conn
			end
		}
		table.insert(tab, shieldSignal)
		return tab
	end
	entitylib.targetCheck = function(ent)
		if ent.Character and ent.Character:HasTag('petrified-player') then
			return false
		end
		if ent.TeamCheck then
			return ent:TeamCheck()
		end
		if ent.NPC then
			local npcTeam = ent.Character and ent.Character:GetAttribute('Team')
			return lplr:GetAttribute('Team') ~= npcTeam
		end
		if isFriend(ent.Player) then
			return false
		end
		return lplr:GetAttribute('Team') ~= ent.Player:GetAttribute('Team')
	end
	vape:Clean(entitylib.Events.LocalAdded:Connect(updateVelocity))
end)

entitylib.start()

local function safeGetProto(func, index)
	if not func then
		return nil
	end
	local success, proto = pcall(safeGetProto, func, index)
	if success then
		return proto
	else
		return nil
	end
end

local inventoryDebounce = false
local function fireInventoryChanged()
	if inventoryDebounce then
		return
	end
	inventoryDebounce = true
	task.spawn(function()
		task.wait()
		vapeEvents.InventoryChanged:Fire()
		inventoryDebounce = false
	end)
end

local function getWorldFolder()
	local Map = workspace:FindFirstChild("Map")
	if not Map then
		return nil
	end
	local Worlds = Map:FindFirstChild("Worlds")
	if not Worlds then
		return nil
	end
	for _, world in Worlds:GetChildren() do
		return world
	end
	return nil
end

local function getPickaxeSlot()
	for i, v in store.inventory.hotbar do
		if v.item and bedwars.ItemMeta[v.item.itemType] then
			local meta = bedwars.ItemMeta[v.item.itemType]
			if meta.breakBlock then
				return i - 1
			end
		end
	end
	return nil
end

local function getItemSlot(name)
	for i, v in store.inventory.hotbar do
		if v.item and v.item.itemType then
			if v.item.itemType == name then
				return i - 1
			end
		end
	end
	return nil
end

run(function()
	local KnitInit, Knit
	repeat
		KnitInit, Knit = pcall(function()
			return debug.getupvalue(require(lplr.PlayerScripts.TS.knit).setup, 9)
		end)
		if KnitInit then break end
		task.wait()
	until KnitInit

	if not debug.getupvalue(Knit.Start, 1) then
		repeat task.wait() until debug.getupvalue(Knit.Start, 1)
	end

	local Flamework = require(replicatedStorage['rbxts_include']['node_modules']['@flamework'].core.out).Flamework
	local InventoryUtil = require(replicatedStorage.TS.inventory['inventory-util']).InventoryUtil
	local Client = require(replicatedStorage.TS.remotes).default.Client
	local OldGet, OldBreak, OldHit = Client.Get
	local rakNet = false
	run(function()
		rakNet = typeof(raknet) == 'table'
	end)
	bedwars = setmetatable({
		EnchantMeta = require(replicatedStorage.TS.enchant['enchant-meta']).EnchantMeta,
		SummonerKitBalance = require(replicatedStorage.TS.games.bedwars.kit.kits.summoner['summoner-kit-balance']).SummonerKitBalance,
		BlockEngineClientEvents = require(replicatedStorage.rbxts_include.node_modules['@easy-games']['block-engine'].out.client['block-engine-client-events']).BlockEngineClientEvents,
		ItemSkinType = require(replicatedStorage.TS.games.bedwars["item-skin"]["item-skin-types"]).ItemSkinType,
		ItemType = require(replicatedStorage.TS.item["item-type"]).ItemType,
		RankMeta = require(replicatedStorage.TS.rank['rank-meta']).RankMeta,
		BalanceFile = require(replicatedStorage.TS.balance["balance-file"]).BalanceFile,
		ClientSyncEvents = require(lplr.PlayerScripts.TS['client-sync-events']).ClientSyncEvents,
		SyncEventPriority = require(replicatedStorage.rbxts_include.node_modules['@easy-games']['sync-event'].out),
		AbilityId = require(replicatedStorage.TS.ability['ability-id']).AbilityId,
		IdUtil = require(replicatedStorage.TS.util['id-util']).IdUtil,
		BlockSelector = require(game:GetService("ReplicatedStorage").rbxts_include.node_modules["@easy-games"]["block-engine"].out.client.select["block-selector"]).BlockSelector,
		KnockbackUtilInstance = replicatedStorage.TS.damage['knockback-util'],
		BedwarsKitSkin = require(replicatedStorage.TS.games.bedwars['kit-skin']['bedwars-kit-skin-meta']).BedwarsKitSkinMeta,
		KitController = Knit.Controllers.KitController,
		FishermanUtil = require(replicatedStorage.TS.games.bedwars.kit.kits.fisherman['fisherman-util']).FishermanUtil,
		FishMeta = require(replicatedStorage.TS.games.bedwars.kit.kits.fisherman['fish-meta']),
		MatchHistroyApp = require(lplr.PlayerScripts.TS.controllers.global["match-history"].ui["match-history-moderation-app"]).MatchHistoryModerationApp,
		MatchHistroyController = Knit.Controllers.MatchHistoryController,
		BlockEngine = require(game:GetService("ReplicatedStorage").rbxts_include.node_modules["@easy-games"]["block-engine"].out).BlockEngine,
		BlockSelectorMode = require(game:GetService("ReplicatedStorage").rbxts_include.node_modules["@easy-games"]["block-engine"].out.client.select["block-selector"]).BlockSelectorMode,
		EntityUtil = require(game:GetService("ReplicatedStorage").TS.entity["entity-util"]).EntityUtil,
		GamePlayer = require(replicatedStorage.TS.player['game-player']),
		OfflinePlayerUtil = require(replicatedStorage.TS.player['offline-player-util']),
		PlayerUtil = require(replicatedStorage.TS.player['player-util']),
		KKKnitController = require(lplr.PlayerScripts.TS.lib.knit['knit-controller']),
		AbilityController = Flamework.resolveDependency('@easy-games/game-core:client/controllers/ability/ability-controller@AbilityController'),
		CooldownController = Flamework.resolveDependency("@easy-games/game-core:client/controllers/cooldown/cooldown-controller@CooldownController"),
		CooldownIDS = require(replicatedStorage.TS.cooldown["cooldown-id"]).CooldownId,
		AnimationType = require(replicatedStorage.TS.animation['animation-type']).AnimationType,
		AnimationUtil = require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out['shared'].util['animation-util']).AnimationUtil,
		AppController = require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out.client.controllers['app-controller']).AppController,
		BedBreakEffectMeta = require(replicatedStorage.TS.locker['bed-break-effect']['bed-break-effect-meta']).BedBreakEffectMeta,
		BedwarsKitMeta = require(replicatedStorage.TS.games.bedwars.kit['bedwars-kit-meta']).BedwarsKitMeta,
		BlockBreaker = Knit.Controllers.BlockBreakController.blockBreaker,
		BlockController = require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['block-engine'].out).BlockEngine,
		BlockEngine = require(lplr.PlayerScripts.TS.lib['block-engine']['client-block-engine']).ClientBlockEngine,
		BlockPlacer = require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['block-engine'].out.client.placement['block-placer']).BlockPlacer,
		BowConstantsTable = (Knit.Controllers.ProjectileController and Knit.Controllers.ProjectileController.enableBeam) and debug.getupvalue(Knit.Controllers.ProjectileController.enableBeam, 8) or {},
		ClickHold = require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out.client.ui.lib.util['click-hold']).ClickHold,
		Client = Client,
		ClientConstructor = require(replicatedStorage['rbxts_include']['node_modules']['@rbxts'].net.out.client),
		ClientDamageBlock = require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['block-engine'].out.shared.remotes).BlockEngineRemotes.Client,
		CombatConstant = require(replicatedStorage.TS.combat['combat-constant']).CombatConstant,
		SharedConstants = require(replicatedStorage.TS['shared-constants']),
		DamageIndicator = Knit.Controllers.DamageIndicatorController.spawnDamageIndicator,
		DefaultKillEffect = require(lplr.PlayerScripts.TS.controllers.global.locker['kill-effect'].effects['default-kill-effect']),
		EmoteType = require(replicatedStorage.TS.locker.emote['emote-type']).EmoteType,
		GameAnimationUtil = require(replicatedStorage.TS.animation['animation-util']).GameAnimationUtil,
		NotificationController = Flamework.resolveDependency('@easy-games/game-core:client/controllers/notification-controller@NotificationController'),
		getIcon = function(item, showinv)
			local itemmeta = bedwars.ItemMeta[item.itemType]
			return itemmeta and showinv and itemmeta.image or ''
		end,
		getInventory = function(plr)
			local suc, res = pcall(function()
				return InventoryUtil.getInventory(plr)
			end)
			return suc and res or {
				items = {},
				armor = {}
			}
		end,
		MatchHistoryController = require(lplr.PlayerScripts.TS.controllers.global['match-history']['match-history-controller']),
		PlayerProfileUIController = require(lplr.PlayerScripts.TS.controllers.global['player-profile']['player-profile-ui-controller']),
		HudAliveCount = require(lplr.PlayerScripts.TS.controllers.global['top-bar'].ui.game['hud-alive-player-counts']).HudAlivePlayerCounts,
		ItemMeta = (function()
			local fn = require(replicatedStorage.TS.item['item-meta']).getItemMeta
			for i = 1, 6 do
				local v = debug.getupvalue(fn, i)
				if type(v) == 'table' and next(v) then
					return v
				end
			end
			return {}
		end)(),
		KillEffectMeta = require(replicatedStorage.TS.locker['kill-effect']['kill-effect-meta']).KillEffectMeta,
		KillFeedController = Flamework.resolveDependency('client/controllers/game/kill-feed/kill-feed-controller@KillFeedController'),
		Knit = Knit,
		KnockbackUtil = require(replicatedStorage.TS.damage['knockback-util']).KnockbackUtil,
		MageKitUtil = require(replicatedStorage.TS.games.bedwars.kit.kits.mage['mage-kit-util']).MageKitUtil,
		NametagController = Knit.Controllers.NametagController,
		PartyController = Flamework.resolveDependency("@easy-games/lobby:client/controllers/party-controller@PartyController"),
		ProjectileMeta = require(replicatedStorage.TS.projectile['projectile-meta']).ProjectileMeta,
		QueryUtil = require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out).GameQueryUtil,
		QueueCard = require(lplr.PlayerScripts.TS.controllers.global.queue.ui['queue-card']).QueueCard,
		QueueMeta = require(replicatedStorage.TS.game['queue-meta']).QueueMeta,
		Roact = require(replicatedStorage['rbxts_include']['node_modules']['@rbxts']['roact'].src),
		RuntimeLib = require(replicatedStorage['rbxts_include'].RuntimeLib),
		SoundList = require(replicatedStorage.TS.sound['game-sound']).GameSound,
		SoundManager = require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out.shared.sound['sound-manager']).SoundManager,
		Store = require(lplr.PlayerScripts.TS.ui.store).ClientStore,
		TeamUpgradeMeta = debug.getupvalue(require(replicatedStorage.TS.games.bedwars['team-upgrade']['team-upgrade-meta']).getTeamUpgradeMetaForQueue, 6),
		UILayers = require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out).UILayers,
		VisualizerUtils = require(lplr.PlayerScripts.TS.lib.visualizer['visualizer-utils']).VisualizerUtils,
		WeldTable = require(replicatedStorage.TS.util['weld-util']).WeldUtil,
		WinEffectMeta = require(replicatedStorage.TS.locker['win-effect']['win-effect-meta']).WinEffectMeta,
		ZapNetworking = require(lplr.PlayerScripts.TS.lib.network),
	}, {
		__index = function(self, ind)
			rawset(self, ind, Knit.Controllers[ind])
			return rawget(self, ind)
		end
	})
	getgenv().bedwars = bedwars
	local function createMethodHook(object, method)
		local original = object[method]
		local hooks, order = {}, 0
		local wrapper
		local function sync()
			if # hooks > 0 then
				object[method] = wrapper
			elseif object[method] == wrapper then
				object[method] = original
			end
		end
		wrapper = function(...)
			local index = 0
			local function nextHook( ...)
				index += 1
				local hook = hooks[index]
				if hook then
					return hook.Callback(nextHook, ...)
				end
				return original(...)
			end
			return nextHook(...)
		end
		return {
			Add = function(_, id, priority, callback)
				for i = # hooks, 1, - 1 do
					if hooks[i].Id == id then
						table.remove(hooks, i)
					end
				end
				order += 1
				local entry = {
					Id = id,
					Priority = priority or 100,
					Order = order,
					Callback = callback,
				}
				table.insert(hooks, entry)
				table.sort(hooks, function(a, b)
					return a.Priority == b.Priority and a.Order < b.Order or a.Priority < b.Priority
				end)
				sync()
				return function()
					for i = # hooks, 1, - 1 do
						if hooks[i] == entry then
							table.remove(hooks, i)
						end
					end
					sync()
				end
			end,
			Destroy = function()
				table.clear(hooks)
				sync()
			end,
		}
	end
	bedwars.ProjectileLaunchHook = createMethodHook(bedwars.ProjectileController, 'calculateImportantLaunchValues')
	vape:Clean(function()
		bedwars.ProjectileLaunchHook:Destroy()
	end)
	getgenv().bedwars = bedwars
	local remoteNames = {
		AfkStatus = safeGetProto(Knit.Controllers.AfkController.KnitStart, 1),
		AttackEntity = Knit.Controllers.SwordController.sendServerRequest,
		BeePickup = Knit.Controllers.BeeNetController.trigger,
		CannonAim = safeGetProto(Knit.Controllers.CannonController.startAiming, 5),
		CannonLaunch = Knit.Controllers.CannonHandController.launchSelf,
		ConsumeBattery = safeGetProto(Knit.Controllers.BatteryController.onKitLocalActivated, 1),
		ConsumeItem = safeGetProto(Knit.Controllers.ConsumeController.onEnable, 1),
		ConsumeSoul = Knit.Controllers.GrimReaperController.consumeSoul,
		ConsumeTreeOrb = safeGetProto(Knit.Controllers.EldertreeController.createTreeOrbInteraction, 1),
		DepositPinata = safeGetProto(safeGetProto(Knit.Controllers.PiggyBankController.KnitStart, 2), 5),
		DragonBreath = safeGetProto(Knit.Controllers.VoidDragonController.onKitLocalActivated, 5),
		DragonEndFly = safeGetProto(Knit.Controllers.VoidDragonController.flapWings, 1),
		DragonFly = Knit.Controllers.VoidDragonController.flapWings,
		DropItem = Knit.Controllers.ItemDropController.dropItemInHand,
		EquipItem = safeGetProto(require(replicatedStorage.TS.entity.entities['inventory-entity']).InventoryEntity.equipItem, 3),
		FireProjectile = debug.getupvalue(Knit.Controllers.ProjectileController.launchProjectileWithValues, 2),
		GroundHit = Knit.Controllers.FallDamageController.KnitStart,
		GuitarHeal = Knit.Controllers.GuitarController.performHeal,
		HannahKill = safeGetProto(Knit.Controllers.HannahController.registerExecuteInteractions, 1),
		HarvestCrop = safeGetProto(safeGetProto(Knit.Controllers.CropController.KnitStart, 4), 1),
		KaliyahPunch = safeGetProto(Knit.Controllers.DragonSlayerController.onKitLocalActivated, 1),
		MageSelect = safeGetProto(Knit.Controllers.MageController.registerTomeInteraction, 1),
		MinerDig = safeGetProto(Knit.Controllers.MinerController.setupMinerPrompts, 1),
		PickupItem = Knit.Controllers.ItemDropController.checkForPickup,
		PickupMetal = safeGetProto(Knit.Controllers.HiddenMetalController.onKitLocalActivated, 4),
		ReportPlayer = require(lplr.PlayerScripts.TS.controllers.global.report['report-controller']).default.reportPlayer,
		ResetCharacter = safeGetProto(Knit.Controllers.ResetController.createBindable, 1),
		SummonerClawAttack = Knit.Controllers.SummonerClawHandController.attack,
		WarlockTarget = safeGetProto(Knit.Controllers.WarlockStaffController.KnitStart, 2)
	}
	local function dumpRemote(tab)
		local ind
		for i, v in tab do
			if v == 'Client' then
				ind = i
				break
			end
		end
		return ind and tab[ind + 1] or ''
	end
	local preDumped = {
		EquipItem = 'SetInvItem',
		ActivateGravestone = 'ActivateGravestone',
		CollectCollectableEntity = 'CollectCollectableEntity',
		DefenderRequestPlaceBlock = 'DefenderRequestPlaceBlock',
		RequestDragonPunch = 'RequestDragonPunch',
		Harvest = 'CropHarvest',
		DepositCoins = 'DepositCoins',
		BedwarsPurchaseItem = 'BedwarsPurchaseItem',
		BedBreakEffectTriggered = 'BedBreakEffectTriggered',
		BloodAssassinSelectContract = 'BloodAssassinSelectContract',
		Mimic = 'MimicBlock',
		StyxPortal = 'UseStyxPortalFromClient',
		StyxExitPortal = 'StyxOpenExitPortalFromServer',
		StyxSpawnExitPortal = 'StyxSpawnExitPortalFromServer',
		StyxSpawnEntrancePortal = 'StyxSpawnEntrancePortalFromServer',
		TryOpenStyxPortalExit = 'StyxTryOpenExitPortalFromClient',
		TeleportToLobby = 'TeletoLobby',
		FishCaught = 'FishCaught',
		SpawnRaven = 'SpawnRaven',
		PaladinAbilityRequest = 'PaladinAbilityRequest',
		OwlActionAbilities = 'OwlActionAbilities',
		DrillAttack = 'DrillAttack',
		UpgradeFrostyHammer = 'UpgradeFrostyHammer',
		UpgradeFlamethrower = 'UpgradeFlamethrower',
		TryBlockKick = 'TryBlockKick',
		Ranks = 'FetchRanks',
		ResearchEnchant = 'EnchantTableResearch',
		DropDroneItem = 'DropDroneItem',
		AttemptFireOasisProjectiles = 'AttemptFireOasisProjectiles',
		WinEffectTriggered = 'WinEffectTriggered',
		ExtractFromDrill = 'ExtractFromDrill',
		HannahPromptTrigger = 'HannahPromptTrigger',
		DragonFlap = 'DragonFlap',
		DragonBreath = 'DragonBreath',
		AttemptCardThrow = 'AttemptCardThrow',
		LearnElementTome = 'LearnElementTome',
		RequestMoveSlime = 'RequestMoveSlime',
		SummonOwl = 'SummonOwl',
		RemoveOwl = 'RemoveOwl',
		OwlFireProjectile = 'OwlFireProjectile',
		OwlAiming = 'OwlAiming',
		MimicBlockPickPocketPlayer = 'MimicBlockPickPocketPlayer',
		DestroyPetrifiedPlayer = 'DestroyPetrifiedPlayer',
		UseAbility = 'useAbility',
		FishFound = 'FishFound',
	}
	for k, v in pairs(preDumped) do
		if not remotes[k] then
			remotes[k] = v
		end
	end
	for i, v in remoteNames do
		local remote
		if type(v) == "string" then
			remote = v
		elseif type(v) == "function" then
			local consts = debug.getconstants(v)
			remote = dumpRemote(consts)
		else
			remote = ""
		end
		if remote == '' or remote == nil then
			if not preDumped[i] then
				notif('Vape', 'Failed to grab remote (' .. tostring(i) .. ')', 10, 'alert')
			end
			remote = preDumped[i] or ''
		end
		remotes[i] = remote
	end
	getgenv().remotes = remotes
	OldBreak = bedwars.BlockController.isBlockBreakable
	OldHit = bedwars.BlockBreaker.hitBlock

	bedwars.BlockBreaker.hitBlock = function(...)
        store.lastHit = tick()
        return OldHit(...)
    end
	Client.Get = function(self, remoteName)
		local call = OldGet(self, remoteName)
		if remoteName == remotes.AttackEntity then
			return {
				instance = call.instance,
				SendToServer = function(_, attackTable, ...)
					local suc, plr = pcall(function()
						return playersService:GetPlayerFromCharacter(attackTable.entityInstance)
					end)

					local selfpos = attackTable.validate.selfPosition.value
					local targetpos = attackTable.validate.targetPosition.value
					store.attackReach = ((selfpos - targetpos).Magnitude * 100) // 1 / 100
					store.attackReachUpdate = tick() + 1

					if Reach.Enabled or HitBoxes.Enabled then
						attackTable.validate.raycast = attackTable.validate.raycast or {}
						attackTable.validate.selfPosition.value += CFrame.lookAt(selfpos, targetpos).LookVector * math.max((selfpos - targetpos).Magnitude - 14.399, 0)
					end

					if suc and plr then
						if not select(2, whitelist:get(plr)) then return end
					end

					return call:SendToServer(attackTable, ...)
				end
			}
		elseif remoteName == 'StepOnSnapTrap' and TrapDisabler.Enabled then
			return {SendToServer = function() end}
		end
		return call
	end
	bedwars.BlockController.isBlockBreakable = function(self, breakTable, plr)
		local obj = bedwars.BlockController:getStore():getBlockAt(breakTable.blockPosition)
		if shared.debug then
			print('breaking', (obj and obj.Name or 'nil'))
		end
		return OldBreak(self, breakTable, plr)
	end
	local cache, blockhealthbar = {}, {
		blockHealth = - 1,
		breakingBlockPosition = Vector3.zero
	}
	local cacheCleanThread = task.spawn(function()
		while vape.Loaded do
			task.wait(60)
			if vape.Loaded then
				table.clear(cache)
			end
		end
	end)
	vape:Clean(function()
		task.cancel(cacheCleanThread)
	end)
	store.blockPlacer = bedwars.BlockPlacer.new(bedwars.BlockEngine, 'wool_white')
	local function getBlockHealth(block, blockpos)
		local blockdata = bedwars.BlockController:getStore():getBlockData(blockpos)
		return (blockdata and (blockdata:GetAttribute('1') or blockdata:GetAttribute('Health')) or block:GetAttribute('Health'))
	end
	local function getBlockHits(block, blockpos)
		if not block then
			return 0
		end
		local breaktype = bedwars.ItemMeta[block.Name].block.breakType
		local tool = store.tools[breaktype]
		tool = tool and bedwars.ItemMeta[tool.itemType].breakBlock[breaktype] or 2
		return getBlockHealth(block, bedwars.BlockController:getBlockPosition(blockpos)) / tool
	end
	local function calculatePath(target, blockpos)
		if cache[blockpos] then
			if tick() - (cache[blockpos].timestamp or 0) < 2 then
				return unpack(cache[blockpos])
			else
				cache[blockpos] = nil
			end
		end
		local visited = {}
		local unvisited = {
			{
				0,
				blockpos
			}
		}
		local distances = {
			[blockpos] = 0
		}
		local air = {}
		local path = {}
		local unvisitedCount = 1
		for _ = 1, 600 do
			if unvisitedCount == 0 then
				break
			end
			local node = unvisited[1]
			unvisited[1] = unvisited[unvisitedCount]
			unvisited[unvisitedCount] = nil
			unvisitedCount = unvisitedCount - 1
			visited[node[2]] = true
			for _, side in sides do
				local neighbor = node[2] + side
				if visited[neighbor] then
					continue
				end
				local block = getPlacedBlock(neighbor)
				if not block or block:GetAttribute('NoBreak') or block == target then
					if not block then
						air[node[2]] = true
					end
					continue
				end
				local curdist = getBlockHits(block, neighbor) + node[1]
				if curdist < (distances[neighbor] or math.huge) then
					unvisitedCount = unvisitedCount + 1
					unvisited[unvisitedCount] = {
						curdist,
						neighbor
					}
					distances[neighbor] = curdist
					path[neighbor] = node[2]
				end
			end
		end
		local pos, cost = nil, math.huge
		for node in air do
			local d = distances[node]
			if d and d < cost then
				pos, cost = node, d
			end
		end
		if pos then
			local cacheEntry = {
				pos,
				cost,
				path,
				timestamp = tick()
			}
			cache[blockpos] = cacheEntry
			return pos, cost, path
		end
	end
	bedwars.placeBlock = function(pos, item)
		if getItem(item) then
			store.blockPlacer.blockType = item
			local ok, result = pcall(function()
				return store.blockPlacer:placeBlock(bedwars.BlockController:getBlockPosition(pos))
			end)
			if ok then
				return result
			end
		end
	end
	bedwars.breakBlock = function(block, effects, anim, customHealthbar, autotool, wallcheck, nobreak)
		if lplr:GetAttribute('DenyBlockBreak') or not entitylib.isAlive then
			return
		end
		local handler = bedwars.BlockController:getHandlerRegistry():getHandler(block.Name)
		local cost, pos, target, path = math.huge
		local mag = 9e9
		local positions = (handler and handler:getContainedPositions(block) or {
			block.Position / 3
		})
		for _, v in positions do
			local dpos, dcost, dpath = calculatePath(block, v * 3)
			local dmag = dpos and (entitylib.character.RootPart.Position - dpos).Magnitude
			if dpos and (bedwars.breakClosestMode and (dmag < mag or (dmag == mag and dcost < cost)) or not bedwars.breakClosestMode and (dcost < cost or (dcost == cost and dmag < mag))) then
				cost, pos, target, path, mag = dcost, dpos, v * 3, dpath, dmag
			end
		end
		if pos then
			if (entitylib.character.RootPart.Position - pos).Magnitude > 30 then
				return
			end
			local dblock, dpos = getPlacedBlock(pos)
			if not dblock then
				return
			end
			if not nobreak and (workspace:GetServerTimeNow() - bedwars.SwordController.lastAttack) > 0.2 then
				local breaktype = bedwars.ItemMeta[dblock.Name].block.breakType
				local tool = store.tools[breaktype]
				if tool then
					if autotool then
						local found = false
						for i, v in store.inventory.hotbar do
							if v.item and v.item.tool == tool.tool and i ~= (store.inventory.hotbarSlot + 1) then
								hotbarSwitch(i - 1)
								found = true
								break
							end
						end
						if not found then
							switchItem(tool.tool)
						end
					else
						switchItem(tool.tool)
					end
				end
			end
			if blockhealthbar.blockHealth == - 1 or dpos ~= blockhealthbar.breakingBlockPosition then
				blockhealthbar.blockHealth = getBlockHealth(dblock, dpos)
				blockhealthbar.breakingBlockPosition = dpos
			end
			if not nobreak then
				bedwars.ClientDamageBlock:Get('DamageBlock'):CallServerAsync({
					blockRef = {
						blockPosition = dpos
					},
					hitPosition = pos,
					hitNormal = Vector3.FromNormalId(Enum.NormalId.Top)
				}):andThen(function(result)
					if result then
						if result == 'cancelled' then
							store.damageBlockFail = tick() + 1
							table.clear(cache)
							return
						end
						if result == 'destroyed' then
							table.clear(cache)
						end
						if effects then
							local blockdmg = (blockhealthbar.blockHealth - (result == 'destroyed' and 0 or getBlockHealth(dblock, dpos)))
							customHealthbar = customHealthbar or bedwars.BlockBreaker.updateHealthbar
							customHealthbar(bedwars.BlockBreaker, {
								blockPosition = dpos
							}, blockhealthbar.blockHealth, dblock:GetAttribute('MaxHealth'), blockdmg, dblock)
							blockhealthbar.blockHealth = math.max(blockhealthbar.blockHealth - blockdmg, 0)
							pcall(function()
								if blockhealthbar.blockHealth <= 0 then
									bedwars.BlockBreaker.breakEffect:playBreak(dblock.Name, dpos, lplr)
									bedwars.BlockBreaker.healthbarMaid:DoCleaning()
									blockhealthbar.breakingBlockPosition = Vector3.zero
								else
									bedwars.BlockBreaker.breakEffect:playHit(dblock.Name, dpos, lplr)
								end
							end)
						end
						if anim then
							local animation = bedwars.AnimationUtil:playAnimation(lplr, bedwars.BlockController:getAnimationController():getAssetId(1))
							bedwars.ViewmodelController:playAnimation(15)
							task.wait(0.3)
							animation:Stop()
							animation:Destroy()
						end
					end
				end)
			end
			if effects then
				return pos, path, target
			end
		end
	end
	for _, v in Enum.NormalId:GetEnumItems() do
		table.insert(sides, Vector3.FromNormalId(v) * 3)
	end
	local function updateStore(new, old)
		if new.Bedwars ~= old.Bedwars then
			store.equippedKit = new.Bedwars.kit ~= 'none' and new.Bedwars.kit or ''
		end
		if new.Game ~= old.Game then
			store.matchState = new.Game.matchState
			store.queueType = new.Game.queueType or 'bedwars_test'
		end
		if new.Inventory ~= old.Inventory then
			local newinv = (new.Inventory and new.Inventory.observedInventory or {
				inventory = {}
			})
			local oldinv = (old.Inventory and old.Inventory.observedInventory or {
				inventory = {}
			})
			store.inventory = newinv
			if newinv ~= oldinv then
				fireInventoryChanged()
			end
			if newinv.inventory.items ~= oldinv.inventory.items then
				vapeEvents.InventoryAmountChanged:Fire()
				local now = tick()
				if not store.lastToolUpdate or now - store.lastToolUpdate > 0.5 then
					store.lastToolUpdate = now
					store.tools.sword = getSword()
					for _, v in {
						'stone',
						'wood',
						'wool'
					} do
						store.tools[v] = getTool(v)
					end
				end
			end
			if newinv.inventory.hand ~= oldinv.inventory.hand then
				local currentHand, toolType = new.Inventory.observedInventory.inventory.hand, ''
				if currentHand then
					local handData = bedwars.ItemMeta[currentHand.itemType]
					toolType = handData.sword and 'sword' or handData.block and 'block' or currentHand.itemType:find('bow') and 'bow'
				end
				store.hand = {
					tool = currentHand and currentHand.tool,
					amount = currentHand and currentHand.amount or 0,
					toolType = toolType
				}
			end
		end
	end
	local storeChanged = bedwars.Store.changed:connect(updateStore)
	vape:Clean(function()
		storeChanged:disconnect()
	end)
	updateStore(bedwars.Store:getState(), {})
	for _, event in {
		'MatchEndEvent',
		'EntityDeathEvent',
		'BedwarsBedBreak',
		'BalloonPopped',
		'AngelProgress',
		'GrapplingHookFunctions'
	} do
		if not vape.Connections then
			return
		end
		bedwars.Client:WaitFor(event):andThen(function(connection)
			vape:Clean(connection:Connect(function(...)
				vapeEvents[event]:Fire(...)
			end))
		end)
	end
	local _dmgEventData = {
		entityInstance = nil,
		damage = nil,
		damageType = nil,
		fromPosition = nil,
		fromEntity = nil,
		knockbackMultiplier = nil,
		knockbackId = nil,
		disableDamageHighlight = nil
	}
	vape:Clean(bedwars.ZapNetworking.EntityDamageEventZap.On(function(...)
		_dmgEventData.entityInstance = ...
		_dmgEventData.damage = select(2, ...)
		_dmgEventData.damageType = select(3, ...)
		_dmgEventData.fromPosition = select(4, ...)
		_dmgEventData.fromEntity = select(5, ...)
		_dmgEventData.knockbackMultiplier = select(6, ...)
		_dmgEventData.knockbackId = select(7, ...)
		_dmgEventData.disableDamageHighlight = select(13, ...)
		vapeEvents.EntityDamageEvent:Fire(_dmgEventData)
	end))
	vape:Clean(playersService.PlayerRemoving:Connect(function(plr)
		store.inventories[plr] = nil
	end))
	local _blockEventData = {
		blockRef = {
			blockPosition = nil
		},
		player = nil
	}
	for _, event in {
		'PlaceBlockEvent',
		'BreakBlockEvent'
	} do
		vape:Clean(bedwars.ZapNetworking[event .. 'Zap'].On(function(...)
			_blockEventData.blockRef.blockPosition = ...
			_blockEventData.player = select(5, ...)
			vapeEvents[event]:Fire(_blockEventData)
		end))
	end
	store.blocks = collection('block', vape)
	store.shop = collection({
		'BedwarsItemShop',
		'TeamUpgradeShopkeeper'
	}, vape, function(tab, obj)
		table.insert(tab, {
			Id = obj.Name,
			RootPart = obj,
			Shop = obj:HasTag('BedwarsItemShop'),
			Upgrades = obj:HasTag('TeamUpgradeShopkeeper')
		})
	end)
	store.enchant = collection({
		'enchant-table',
		'broken-enchant-table'
	}, vape, nil, function(tab, obj, tag)
		if obj:HasTag('enchant-table') and tag == 'broken-enchant-table' then
			return
		end
		obj = table.find(tab, obj)
		if obj then
			table.remove(tab, obj)
		end
	end)
	local kills = sessioninfo:AddItem('Kills')
	local beds = sessioninfo:AddItem('Beds')
	local wins = sessioninfo:AddItem('Wins')
	local games = sessioninfo:AddItem('Games')
	local mapname = 'Unknown'
	sessioninfo:AddItem('Map', 0, function()
		return mapname
	end, false)
	task.delay(1, function()
		games:Increment()
	end)
	task.spawn(function()
		pcall(function()
			repeat
				task.wait()
			until store.matchState ~= 0 or vape.Loaded == nil
			if vape.Loaded == nil then
				return
			end
			mapname = workspace:WaitForChild('Map', 5):WaitForChild('Worlds', 5):GetChildren()[1].Name
			mapname = string.gsub(string.split(mapname, '_')[2] or mapname, '-', '') or 'Blank'
		end)
	end)
	vape:Clean(vapeEvents.BedwarsBedBreak.Event:Connect(function(bedTable)
		if bedTable.player and bedTable.player.UserId == lplr.UserId then
			beds:Increment()
		end
	end))
	vape:Clean(vapeEvents.MatchEndEvent.Event:Connect(function(winTable)
		if (bedwars.Store:getState().Game.myTeam or {}).id == winTable.winningTeamId or lplr.Neutral then
			wins:Increment()
		end
	end))

	task.spawn(function()
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Include
		rayParams.FilterDescendantsInstances = {workspace:WaitForChild('Map', 9e9)}
		store.airRay = rayParams

		repeat
			if entitylib.isAlive then
				entitylib.character.AirTime = workspace:Raycast((store.rootpart or entitylib.character.RootPart).Position, Vector3.new(0, -4.5, 0), rayParams) and tick() or entitylib.character.AirTime
			end

			for _, v in entitylib.List do
				v.LandTick = math.abs(v.RootPart.Velocity.Y) < 0.1 and v.LandTick or tick()
				if (tick() - v.LandTick) > 0.2 and v.Jumps ~= 0 then
					v.Jumps = 0
					v.Jumping = false
				end
			end
			task.wait()
		until vape.Loaded == nil
	end)

	vape:Clean(vapeEvents.EntityDeathEvent.Event:Connect(function(deathTable)
		local killer = playersService:GetPlayerFromCharacter(deathTable.fromEntity)
		local killed = playersService:GetPlayerFromCharacter(deathTable.entityInstance)
		if not killed or not killer then
			return
		end
		if killed ~= lplr and killer == lplr then
			kills:Increment()
		end
	end))
	pcall(function()
		bedwars.Shop = require(replicatedStorage.TS.games.bedwars.shop['bedwars-shop']).BedwarsShop
		bedwars.ShopItems = bedwars.Shop.ShopItems
		bedwars.Shop.getShopItem('iron_sword', lplr)
		store.shopLoaded = true
	end)
	vape:Clean(function()
		Client.Get = OldGet
		bedwars.BlockController.isBlockBreakable = OldBreak
		store.blockPlacer:disable()
		for _, v in vapeEvents do
			v:Destroy()
		end
		for _, v in cache do
			table.clear(v[3])
			table.clear(v)
		end
		table.clear(store.blockPlacer)
		table.clear(vapeEvents)
		table.clear(bedwars)
		table.clear(store)
		table.clear(cache)
		table.clear(sides)
		table.clear(remotes)
		storeChanged:disconnect()
		storeChanged = nil
		if entitylib.Connections then
			for _, conn in ipairs(entitylib.Connections) do
				if conn and type(conn) == "userdata" and conn.Connected then
					conn:Disconnect()
				end
			end
			table.clear(entitylib.Connections)
		end
		if entitylib.PlayerConnections then
			for _, plrConns in pairs(entitylib.PlayerConnections) do
				if type(plrConns) == "table" then
					for _, conn in ipairs(plrConns) do
						if conn and type(conn) == "userdata" and conn.Connected then
							conn:Disconnect()
						end
					end
				end
			end
			table.clear(entitylib.PlayerConnections)
		end
		if entitylib.EntityThreads then
			for char, thread in pairs(entitylib.EntityThreads) do
				if thread and task.cancel then
					task.cancel(thread)
				end
			end
			table.clear(entitylib.EntityThreads)
		end
		if entitylib.List then
			for _, ent in ipairs(entitylib.List) do
				if ent.Connections then
					for _, conn in ipairs(ent.Connections) do
						if conn and type(conn) == "userdata" and conn.Connected then
							conn:Disconnect()
						end
					end
					table.clear(ent.Connections)
				end
			end
			table.clear(entitylib.List)
		end
		if entitylib.stop then
			entitylib.stop()
		end
		for playerId, data in pairs(lagConnections) do
			if data and data.connection then
				pcall(function()
					data.connection:Disconnect()
				end)
			end
		end
		table.clear(lagConnections)
	end)
end)

local function isFrozen(entity, threshold)
	threshold = threshold or 10
	local char
	if type(entity) == "table" and entity.Character then
		char = entity.Character
	elseif type(entity) == "Instance" and entity:IsA("Model") then
		char = entity
	elseif entity == nil then
		if not entitylib.isAlive then
			return false
		end
		char = entitylib.character.Character
	else
		return false
	end
	local stacks = char:GetAttribute("ColdStacks") or char:GetAttribute("FrostStacks") or char:GetAttribute("FreezeStacks") or char:GetAttribute("FROZEN_STACKS")
	if stacks and stacks >= threshold then
		return true
	end
	local statusEffects = char:GetAttribute("StatusEffects")
	if type(statusEffects) == "table" then
		for effectName, stackCount in pairs(statusEffects) do
			local nameLower = tostring(effectName):lower()
			if nameLower:match("cold") or nameLower:match("frost") or nameLower:match("freeze") then
				if type(stackCount) == "number" then
					if stackCount >= threshold then
						return true
					end
				elseif stackCount then
					return true
				end
			end
		end
	end
	if char:FindFirstChild("IceBlock") or char:FindFirstChild("FrozenBlock") or char:FindFirstChild("IceShell") then
		return true
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.WalkSpeed <= 2 then
		return true
	end
	return false
end

for _, v in {
	'Anti Ragdoll',
	'Trigger Bot',
	'Silent Aim',
	'Auto Rejoin',
	'Rejoin',
	'Disabler',
	'Timer',
	'Server Hop',
	'Mouse TP',
	'Murder Mystery'
} do
	vape:Remove(v)
end

--[[
	Combat
]]--

run(function()
	local Viewmodel
	local Depth
	local Horizontal
	local Vertical
	local NoBob
	local Rots = {}
	local old, oldc1
	Viewmodel = vape.Categories.Combat:CreateModule({
		Name = 'View Model',
		Function = function(callback)
			local viewmodel = gameCamera:FindFirstChild('Viewmodel')
			if callback then
				old = bedwars.ViewmodelController.playAnimation
				oldc1 = viewmodel and viewmodel.RightHand.RightWrist.C1 or CFrame.identity
				if NoBob.Enabled then
					bedwars.ViewmodelController.playAnimation = function(self, animtype, ...)
						if bedwars.AnimationType and animtype == bedwars.AnimationType.FP_WALK then
							return
						end
						return old(self, animtype, ...)
					end
				end
				bedwars.InventoryViewmodelController:handleStore(bedwars.Store:getState())
				if viewmodel then
					gameCamera.Viewmodel.RightHand.RightWrist.C1 = oldc1 * CFrame.Angles(math.rad(Rots[1].Value), math.rad(Rots[2].Value), math.rad(Rots[3].Value))
				end
				lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_DEPTH_OFFSET', - Depth.Value)
				lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_HORIZONTAL_OFFSET', Horizontal.Value)
				lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_VERTICAL_OFFSET', Vertical.Value)
			else
				bedwars.ViewmodelController.playAnimation = old
				if viewmodel then
					viewmodel.RightHand.RightWrist.C1 = oldc1
				end
				bedwars.InventoryViewmodelController:handleStore(bedwars.Store:getState())
				lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_DEPTH_OFFSET', 0)
				lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_HORIZONTAL_OFFSET', 0)
				lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_VERTICAL_OFFSET', 0)
				old = nil
			end
		end,
		Tooltip = 'Changes the viewmodel animations'
	})
	Depth = Viewmodel:CreateSlider({
		Name = 'Depth',
		Min = 0,
		Max = 2,
		Default = 0.8,
		Decimal = 10,
		Function = function(val)
			if Viewmodel.Enabled then
				lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_DEPTH_OFFSET', - val)
			end
		end
	})
	Horizontal = Viewmodel:CreateSlider({
		Name = 'Horizontal',
		Min = 0,
		Max = 2,
		Default = 0.8,
		Decimal = 10,
		Function = function(val)
			if Viewmodel.Enabled then
				lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_HORIZONTAL_OFFSET', val)
			end
		end
	})
	Vertical = Viewmodel:CreateSlider({
		Name = 'Vertical',
		Min = - 0.2,
		Max = 2,
		Default = - 0.2,
		Decimal = 10,
		Function = function(val)
			if Viewmodel.Enabled then
				lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_VERTICAL_OFFSET', val)
			end
		end
	})
	for _, name in {
		'Rotation X',
		'Rotation Y',
		'Rotation Z'
	} do
		table.insert(Rots, Viewmodel:CreateSlider({
			Name = name,
			Min = 0,
			Max = 360,
			Function = function(val)
				if Viewmodel.Enabled then
					gameCamera.Viewmodel.RightHand.RightWrist.C1 = oldc1 * CFrame.Angles(math.rad(Rots[1].Value), math.rad(Rots[2].Value), math.rad(Rots[3].Value))
				end
			end
		}))
	end
	NoBob = Viewmodel:CreateToggle({
		Name = 'No Bobbing',
		Default = true,
		Function = function()
			if Viewmodel.Enabled then
				Viewmodel:Toggle()
				Viewmodel:Toggle()
			end
		end
	})
end)

run(function()
	local AimAssist
	local Targets
	local Sort
	local AimSpeed
	local Distance
	local AngleSlider
	local StrafeIncrease
	local KillauraTarget
	local ClickAim
	AimAssist = vape.Categories.Combat:CreateModule({
		Name = 'Aim Assist',
		Function = function(callback)
			if callback then
				AimAssist:Clean(runService.Heartbeat:Connect(function(dt)
					if entitylib.isAlive and store.hand.toolType == 'sword' and ((not ClickAim.Enabled) or (tick() - bedwars.SwordController.lastSwing) < 0.4) then
						local ent = not KillauraTarget.Enabled and entitylib.EntityPosition({
							Range = Distance.Value,
							Part = 'RootPart',
							Wallcheck = Targets.Walls.Enabled,
							Players = Targets.Players.Enabled,
							NPCs = Targets.NPCs.Enabled,
							Sort = sortmethods[Sort.Value]
						}) or store.KillauraTarget
						if ent then
							local delta = (ent.RootPart.Position - entitylib.character.RootPart.Position)
							local localfacing = entitylib.character.RootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
							local angle = math.acos(localfacing:Dot((delta * Vector3.new(1, 0, 1)).Unit))
							if angle >= (math.rad(AngleSlider.Value) / 2) then
								return
							end
							targetinfo.Targets[ent] = tick() + 1
							gameCamera.CFrame = gameCamera.CFrame:Lerp(CFrame.lookAt(gameCamera.CFrame.p, ent.RootPart.Position), (AimSpeed.Value + (StrafeIncrease.Enabled and (inputService:IsKeyDown(Enum.KeyCode.A) or inputService:IsKeyDown(Enum.KeyCode.D)) and 10 or 0)) * dt)
						end
					end
				end))
			end
		end,
		Tooltip = 'Smoothly aims to closest valid target with sword'
	})
	Targets = AimAssist:CreateTargets({
		Players = true,
		Walls = true
	})
	local methods = {
		'Damage',
		'Distance'
	}
	for i in sortmethods do
		if not table.find(methods, i) then
			table.insert(methods, i)
		end
	end
	Sort = AimAssist:CreateDropdown({
		Name = 'Target Mode',
		List = methods
	})
	AimSpeed = AimAssist:CreateSlider({
		Name = 'Aim Speed',
		Min = 1,
		Max = 20,
		Default = 6
	})
	Distance = AimAssist:CreateSlider({
		Name = 'Distance',
		Min = 1,
		Max = 30,
		Default = 30,
		Suffx = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	AngleSlider = AimAssist:CreateSlider({
		Name = 'Max angle',
		Min = 1,
		Max = 360,
		Default = 70
	})
	ClickAim = AimAssist:CreateToggle({
		Name = 'Click Aim',
		Default = true
	})
	KillauraTarget = AimAssist:CreateToggle({
		Name = 'Use killaura target'
	})
	StrafeIncrease = AimAssist:CreateToggle({
		Name = 'Strafe increase'
	})
end)

run(function()
	local AutoClicker
	local CPS
	local BlockCPS = {}
	local Thread
	local function AutoClick()
		if Thread then
			task.cancel(Thread)
		end
		Thread = task.delay(1 / 7, function()
			repeat
				if not bedwars.AppController:isLayerOpen(bedwars.UILayers.MAIN) then
					local blockPlacer = bedwars.BlockPlacementController.blockPlacer
					if store.hand.toolType == 'block' and blockPlacer then
						if (workspace:GetServerTimeNow() - bedwars.BlockCpsController.lastPlaceTimestamp) >= ((1 / 12) * 0.5) then
							local mouseinfo = blockPlacer.clientManager:getBlockSelector():getMouseInfo(0)
							if mouseinfo and mouseinfo.placementPosition == mouseinfo.placementPosition then
								task.spawn(blockPlacer.placeBlock, blockPlacer, mouseinfo.placementPosition)
							end
						end
					elseif store.hand.toolType == 'sword' then
						bedwars.SwordController:swingSwordAtMouse(0.39)
					end
				end
				task.wait(1 / (store.hand.toolType == 'block' and BlockCPS or CPS).GetRandomValue())
			until not AutoClicker.Enabled
		end)
	end
	AutoClicker = vape.Categories.Combat:CreateModule({
		Name = 'Auto Clicker',
		Function = function(callback)
			if callback then
				AutoClicker:Clean(inputService.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						AutoClick()
					end
				end))
				AutoClicker:Clean(inputService.InputEnded:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 and Thread then
						task.cancel(Thread)
						Thread = nil
					end
				end))
				if inputService.TouchEnabled then
					pcall(function()
						AutoClicker:Clean(lplr.PlayerGui.MobileUI['2'].MouseButton1Down:Connect(AutoClick))
						AutoClicker:Clean(lplr.PlayerGui.MobileUI['2'].MouseButton1Up:Connect(function()
							if Thread then
								task.cancel(Thread)
								Thread = nil
							end
						end))
					end)
				end
			else
				if Thread then
					task.cancel(Thread)
					Thread = nil
				end
			end
		end,
		Tooltip = 'Hold attack button to automatically click'
	})
	CPS = AutoClicker:CreateTwoSlider({
		Name = 'CPS',
		Min = 1,
		Max = 9,
		DefaultMin = 7,
		DefaultMax = 7
	})
	AutoClicker:CreateToggle({
		Name = 'Place Blocks',
		Default = true,
		Function = function(callback)
			if BlockCPS.Object then
				BlockCPS.Object.Visible = callback
			end
		end
	})
	BlockCPS = AutoClicker:CreateTwoSlider({
		Name = 'Block CPS',
		Min = 1,
		Max = 12,
		DefaultMin = 12,
		DefaultMax = 12,
		Darker = true
	})
end)

run(function()
	local old
	vape.Categories.Combat:CreateModule({
		Name = 'No Click Delay',
		Function = function(callback)
			if callback then
				old = bedwars.SwordController.isClickingTooFast
				bedwars.SwordController.isClickingTooFast = function(self)
					self.lastSwing = os.clock()
					return false
				end
			else
				bedwars.SwordController.isClickingTooFast = old
			end
		end,
		Tooltip = 'Remove the CPS cap'
	})
end)

run(function()
	local AttackToggle
	local Attack
	local PlaceToggle
	local Place
	local MineToggle
	local Mine

	local olds = {
		func = nil,
		attack = nil,
		mine = nil,
		place = nil
	}

	local function resetReach()
		if olds.func then
			Attack:SetValue(olds.attack or 12.4)
			Place:SetValue(olds.place or 24)
			Mine:SetValue(olds.mine or 18)
		else
			Attack:SetValue(12.4)
			Place:SetValue(24)
			Mine:SetValue(18)
		end
	end

	Reach = vape.Categories.Combat:CreateModule({
		Name = 'Reach',
		Function = function(callback)
			if callback then
				olds.attack = CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE
				CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE = AttackToggle.Enabled and Attack.Value + 2 or olds.Attack
				olds.func = clonefunction(bedwars.BlockSelector.getMouseInfo)
				hookfunction(bedwars.BlockSelector.getMouseInfo, function(...)
					local self, sel, args = ...
					if not args then args = {} end
					if sel == 0 then
						olds.place = args.range
						args.range = PlaceToggle.Enabled and Place.Value or olds.place
					elseif sel == 1 then
						olds.mine = args.range
						args.range = MineToggle.Enabled and Mine.Value or olds.mine
					end
					return olds.func(sel, sel, args)
				end)
			else
				local suc, res = pcall(function()
					restorefunction(bedwars.BlockSelector.getMouseInfo)
				end)
				if not suc then
					bedwars.BlockSelector.getMouseInfo = olds.func
				end
				CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE = olds.attack
				olds.func = nil
				olds.attack = nil
				olds.mine = nil
				olds.place = nil
			end
			bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE = callback and Value.Value + 2 or 14.4
		end,
		Tooltip = 'Allows you to place, attack, and mine further.'
	})
	AttackToggle = Reach:CreateToggle({
		Name = 'Attack Toggle',
		Tooltip = 'Enables to change how far you can hit someone',
		Default = true,
		Function = function(callback)
			if Attack then Attack.Object.Visible = callback end
		end
	})
	Attack = Reach:CreateSlider({
		Name = 'Attack',
		Min = 0,
		Max = 20,
		Default = 18,
		Decimal = 5,
		Darker = true,
		Suffix = function(val)
			return val <= 1 and 'stud' or 'studs'
		end,
		Visible = AttackToggle.Enabled
	})
	PlaceToggle = Reach:CreateToggle({
		Name = 'Place Toggle',
		Tooltip = 'Enables to change how far you can place a block',
		Default = true,
		Function = function(callback)
			if Place then Place.Object.Visible = callback end
		end
	})
	Place = Reach:CreateSlider({
		Name = 'Place',
		Min = 0,
		Max = 60,
		Default = 30,
		Decimal = 5,
		Darker = true,
		Suffix = function(val)
			return val <= 1 and 'stud' or 'studs'
		end,
		Visible = PlaceToggle.Enabled
	})
	MineToggle = Reach:CreateToggle({
		Name = 'Mine Toggle',
		Tooltip = 'Enables to change how far you can mine a block from',
		Default = true,
		Function = function(callback)
			if Mine then Mine.Object.Visible = callback end
		end
	})
	Mine = Reach:CreateSlider({
		Name = 'Mine',
		Min = 0,
		Max = 30,
		Default = 30,
		Decimal = 5,
		Darker = true,
		Suffix = function(val)
			return val <= 1 and 'stud' or 'studs'
		end,
		Visible = MineToggle.Enabled
	})
	Reach:CreateButton({
		Name = 'Reset to default reach',
		Tooltip = 'changes everything back into default range',
		Function = resetReach
	})
end)

run(function()
	local Sprint
	local old
	Sprint = vape.Categories.Combat:CreateModule({
		Name = 'Sprint',
		Function = function(callback)
			if callback then
				if inputService.TouchEnabled then
					pcall(function()
						lplr.PlayerGui.MobileUI['4'].Visible = false
					end)
				end
				old = bedwars.SprintController.stopSprinting
				bedwars.SprintController.stopSprinting = function(...)
					local call = old(...)
					bedwars.SprintController:startSprinting()
					return call
				end
				Sprint:Clean(entitylib.Events.LocalAdded:Connect(function()
					task.delay(0.1, function()
						bedwars.SprintController:stopSprinting()
					end)
				end))
				bedwars.SprintController:stopSprinting()
			else
				if inputService.TouchEnabled then
					pcall(function()
						lplr.PlayerGui.MobileUI['4'].Visible = true
					end)
				end
				bedwars.SprintController.stopSprinting = old
				bedwars.SprintController:stopSprinting()
			end
		end,
		Tooltip = 'Sets your sprinting to true.'
	})
end)

run(function()
	local TriggerBot
	local SwordToggle
	local SwordCPS 
	local ProjectileToggle
	local ProjectileFirerate
	local ProjectileLegitSwitch
	local ProjectileDelayShoot
	local sharedRaycast = RaycastParams.new()
	sharedRaycast.FilterType = Enum.RaycastFilterType.Include
	sharedRaycast.FilterDescendantsInstances = {workspace:FindFirstChild('Map') or workspace}
	local rayparms = RaycastParams.new()
	rayparms.FilterType = sharedRaycast.FilterType
	rayparms.FilterDescendantsInstances = sharedRaycast.FilterDescendantsInstances
	rayparms.RespectCanCollide = sharedRaycast.RespectCanCollide
	rayparms.FilterDescendantsInstances = {lplr.Character}

	local lastCapture = 0
	local doAttack = false
	local lastShot = tick()
	local t = 0

	TriggerBot = vape.Categories.Combat:CreateModule({
		Name = 'Trigger Bot',
		Tooltip = 'Automatically swings when hovering over a entity',
		Disabled = canEngine,
		Function = function(callback)
			if callback then
				lastCapture = 0
				doAttack = false
				
				TriggerBot:Clean(lplr.CharacterAdded:Connect(function()
					rayparms.FilterDescendantsInstances = {lplr.Character}
				end))

				t = 0.016

				repeat
					if not entitylib.isAlive then
						t = 0.16
						task.wait(t)
						continue
					end

					if not bedwars.AppController:isLayerOpen(bedwars.UILayers.MAIN) then

						if SwordToggle.Enabled then
							if store.hand.toolType == 'sword' and bedwars.DaoController.chargingMaid == nil and not bedwars.SwordController.disableSwingState then
								local attackRange = bedwars.ItemMeta[store.hand.tool.Name].sword.attackRange
						
								local unit = lplr:GetMouse().UnitRay
								local localPos = entitylib.character.RootPart.Position
								local rayRange = (attackRange or 12.4)
								local ray = bedwars.QueryUtil:raycast(unit.Origin, unit.Direction * 200, rayparms)
								
								if ray and (localPos - ray.Instance.Position).Magnitude <= rayRange then
									for _, ent in entitylib.List do
										doAttack = ent.Targetable and ray.Instance:IsDescendantOf(ent.Character) and (localPos - ent.RootPart.Position).Magnitude <= rayRange
										if doAttack then
											break
										end
									end
								end
						
								doAttack = doAttack or bedwars.SwordController:getTargetInRegion(attackRange or 4.13 * 3, 0)
								
								if doAttack then
									t = (1 / SwordCPS.GetRandomValue())
									bedwars.SwordController:swingSwordAtMouse()
								else
									t = 0.028
								end

							elseif store.equippedKit == 'summoner' and store.hand.tool.Name:find('summoner_claw') then
								local unit = lplr:GetMouse().UnitRay
								local localPos = entitylib.character.RootPart.Position
								local rayRange = 16.4
								local ray = bedwars.QueryUtil:raycast(unit.Origin, unit.Direction * 200, rayparms)
								
								doAttack = false
								if ray and (localPos - ray.Instance.Position).Magnitude <= rayRange then
									for _, e in entitylib.List do
										if e.Targetable and ray.Instance:IsDescendantOf(e.Character) and (localPos - e.RootPart.Position).Magnitude <= rayRange then
											doAttack = true
											break
										end
									end
								end
								
								doAttack = doAttack or bedwars.SwordController:getTargetInRegion(4.8 * 3, 0)
								
								if doAttack then
									t = (1 / SwordCPS.GetRandomValue())
                                    local active = false
                                    for _, v in workspace:QueryDescendants('#Summoner_SummonCircle') do
                                        local pivot = v:FindFirstChild('Pivot')
                                        if pivot and math.floor(pivot.Position.X) == math.floor(entitylib.character.RootPart.Position.X) and math.floor(pivot.Position.Z) == math.floor(entitylib.character.RootPart.Position.Z) then
                                            active = true
                                            break
                                        end
                                    end
                                    if active then
										task.wait()
                                        continue
                                    end
									bedwars.SummonerClawController:clawAttack(lplr, entitylib.character.RootPart.Position, gameCamera.CFrame.LookVector, store.hand.tool.Name or 'summoner_claw_1')
									bedwars.Client:Get(remotes.SummonerClawAttack):SendToServer({
										position = entitylib.character.RootPart.Position,
										direction = gameCamera.CFrame.LookVector,
										clientTime = workspace:GetServerTimeNow()
									})
								else
									t = 0.065
								end
							else
								t = 0.1
							end
						end
						if ProjectileToggle.Enabled then
							local toolName = store.hand.tool.Name:lower()
							local meta = bedwars.ItemMeta[toolName]

							if meta and meta.projectileSource then
								local ping = lplr:GetNetworkPing() or 0
								local fireDelay = 0.2 + ping + (ProjectileFirerate.Value or 0.2)

								if (tick() - lastShot) >= fireDelay then
									mouse1click()
									lastShot = tick()

									t = (ProjectileDelayShoot.Value or 0.1) + 0.015
									local itemType = nil
									local items = store.inventory.inventory.items
									for _, item in items do
										local _itemMeta = bedwars.ItemMeta[item.itemType]
										local proj = _itemMeta and _itemMeta.projectileSource
										if not proj then continue end
										if not proj.ammoItemTypes then continue end
										for _, inv in items do
											if table.find(proj.ammoItemTypes, inv.itemType) then
												itemType = item.itemType
												break
											end
										end
										if itemType then break end
									end
									if ProjectileLegitSwitch.Enabled then
										task.wait(t - 0.045)
										local holdingCrossbow = itemType and itemType:find('crossbow')
										local holdingBow = itemType and itemType:find('bow') and not holdingCrossbow

										if holdingCrossbow then
											pcall(function() bedwars.ViewmodelController:playAnimation(bedwars.AnimationType.FP_CROSSBOW_FIRE) end)
											bedwars.GameAnimationUtil:playAnimation(lplr, bedwars.AnimationType.CROSSBOW_FIRE)
										elseif holdingBow then
											pcall(function() bedwars.ViewmodelController:playAnimation(bedwars.AnimationType.FP_CROSSBOW_FIRE) end)
											bedwars.GameAnimationUtil:playAnimation(lplr, bedwars.AnimationType.BOW_FIRE)
										else
											local shootAnim = (bedwars.ItemMeta[toolName].thirdPerson) and (bedwars.ItemMeta[toolName].thirdPerson.shootAnimation)
											if shootAnim then
												bedwars.GameAnimationUtil:playAnimation(lplr, shootAnim)
											end
										end
									end
								else
									t = 0.03
								end
							else
								t = 0.12
							end
						end

					else
						t = 0.1
					end

					task.wait(t)
				until not TriggerBot.Enabled
			end
		end
	})

	SwordToggle = TriggerBot:CreateToggle({
		Name = 'Sword Toggle',
		Tooltip = 'enables the sword toggle',
		Default = true,
		Function = function(callback)
			if SwordCPS then SwordCPS.Object.Visible = callback end
		end
	})

	SwordCPS = TriggerBot:CreateTwoSlider({
		Name = "Sword CPS",
		Tooltip = 'swords cps',
		Min = 0,
		Max = 24,
		DefaultMax = 7,
		DefaultMin = 7,
		Darker = true,
		Visible = SwordToggle.Enabled
	})

	if not inputService.TouchEnabled then
		ProjectileToggle = TriggerBot:CreateToggle({
			Name = 'Projectile Toggle',
			Tooltip = 'enables the projectile toggle',
			Default = false,
			Function = function(callback)
				if ProjectileFirerate then ProjectileFirerate.Object.Visible = callback end
				if ProjectileDelayShoot then ProjectileDelayShoot.Object.Visible = callback end
				if ProjectileLegitSwitch then ProjectileLegitSwitch.Object.Visible = callback end
			end
		})

		ProjectileFirerate = TriggerBot:CreateSlider({
			Name = "Projectile Fire Rate",
			Tooltip = 'projectile fire rate',
			Min = 0,
			Max = 4,
			Default = 0.2,
			Decimal = 100,
			Darker = true,
			Visible = ProjectileToggle.Enabled
		})

		ProjectileDelayShoot = TriggerBot:CreateSlider({
			Name = "Projectile Delay Shoot",
			Tooltip = 'projectile delay in shooting',
			Min = 0,
			Max = 2,
			Default = 0.1,
			Decimal = 100,
			Darker = true,
			Visible = ProjectileToggle.Enabled
		})

		ProjectileLegitSwitch = TriggerBot:CreateToggle({
			Name = "Projectile Legit Switch",
			Tooltip = 'should switch to the projectile',
			Default = false,
			Darker = true,
			Visible = ProjectileToggle.Enabled
		})
	end
end)
	
run(function()
	local Velocity
	local Horizontal
	local Vertical
	local Chance
	local TargetCheck
	local rand, old = Random.new()
	Velocity = vape.Categories.Combat:CreateModule({
		Name = 'Velocity',
		Function = function(callback)
			if callback then
				old = bedwars.KnockbackUtil.applyKnockback
				bedwars.KnockbackUtil.applyKnockback = function(root, mass, dir, knockback, ...)
					if rand:NextNumber(0, 100) > Chance.Value then
						return
					end
					local check = (not TargetCheck.Enabled) or entitylib.EntityPosition({
						Range = 50,
						Part = 'RootPart',
						Players = true
					})
					if check then
						knockback = knockback or {}
						if Horizontal.Value == 0 and Vertical.Value == 0 then
							return
						end
						knockback.horizontal = (knockback.horizontal or 1) * (Horizontal.Value / 100)
						knockback.vertical = (knockback.vertical or 1) * (Vertical.Value / 100)
					end
					return old(root, mass, dir, knockback, ...)
				end
			else
				bedwars.KnockbackUtil.applyKnockback = old
			end
		end,
		Tooltip = 'Reduces knockback taken'
	})
	Horizontal = Velocity:CreateSlider({
		Name = 'Horizontal',
		Min = 0,
		Max = 100,
		Default = 0,
		Suffix = '%'
	})
	Vertical = Velocity:CreateSlider({
		Name = 'Vertical',
		Min = 0,
		Max = 100,
		Default = 0,
		Suffix = '%'
	})
	Chance = Velocity:CreateSlider({
		Name = 'Chance',
		Min = 0,
		Max = 100,
		Default = 100,
		Suffix = '%'
	})
	TargetCheck = Velocity:CreateToggle({
		Name = 'Only when targeting'
	})
end)

run(function()
	local HitFlick
	local Flicks
	local Chance
	local TargetCheck
	local rand, old = Random.new()

    local function rotateY(v, deg)
    	local r = math.rad(deg)
    	return Vector3.new(v.X * math.cos(r) - v.Z * math.sin(r), 0, v.X * math.sin(r) + v.Z * math.cos(r))
    end

	HitFlick = vape.Categories.Combat:CreateModule({
		Name = 'Hit Flick',
		Function = function(callback)
			if callback then
				old = bedwars.KnockbackUtil.applyKnockback
				bedwars.KnockbackUtil.applyKnockback = function(root, mass, dir, knockback, ...)
					if rand:NextNumber(0, 100) > Chance.Value then
						return
					end
					local check = (not TargetCheck.Enabled) or entitylib.EntityPosition({
						Range = 50,
						Part = 'RootPart',
						Players = true
					})
					if check then
						local velocity = (root.Position * Vector3.new(1, 0, 1)) - Vector3.new(dir.X, 0, dir.Z)
						if velocity.Magnitude < 0.001 then
							return old(root, mass, dir, knockback, ...)
						end
						velocity = velocity.Unit
						local chosen = Flicks.Value == 'Random' and ({ 'Left', 'Right', 'Pull'})[rand:NextInteger(1, 3)] or Flicks.Value
						local rdir = chosen == 'Pull' and -velocity or table.find({'Left', 'Right'}, chosen) and rotateY(velocity, chosen == 'Left' and 90 or -90) or velocity
						return old(root, mass, Vector3.new(root.Position.X - rdir.X * 100, dir.Y, root.Position.Z - rdir.Z * 100), knockback, ...)
					end
					return old(root, mass, dir, knockback, ...)
				end
			else
				bedwars.KnockbackUtil.applyKnockback = old
				old = nil
			end
		end,
		Tooltip = 'Changes knockback direction'
	})
	Flicks = HitFlick:CreateDropdown({
		Name = 'Directions',
		List = {'Left', 'Right', 'Pull', 'Random'},
		Default = 'Default'
	})
	Chance = HitFlick:CreateSlider({
		Name = 'Chance',
		Min = 0,
		Max = 100,
		Default = 100,
		Suffix = '%'
	})
	TargetCheck = HitFlick:CreateToggle({
		Name = 'Only when targeting'
	})
end)

--[[
	Blatant
]]--

run(function()
	local BlockCPSRemover
	local CPS
	local function resetCPS()
		if old then
			bedwars.SharedConstants.CpsConstants.BLOCK_PLACE_CPS = old
			CPS:SetValue(old)
			old = nil
		else
			CPS:SetValue(bedwars.SharedConstants.CpsConstants.BLOCK_PLACE_CPS or 12)
		end
	end
	local old = 12
	BlockCPSRemover = vape.Categories.Blatant:CreateModule({
		Name = 'Block CPS Remover',
		Tooltip = 'allows you to edit t he cps cap (I CREATED THIS METHOD EVERY1 SKIDDED lOL)',
		Function = function(callback)
			if callback then
				if not old then
					old = bedwars.SharedConstants.CpsConstants.BLOCK_PLACE_CPS or 12
				end
				bedwars.SharedConstants.CpsConstants.BLOCK_PLACE_CPS = (CPS.Value == 0 and math.huge or CPS.Value)
			else
				if old then
					bedwars.SharedConstants.CpsConstants.BLOCK_PLACE_CPS = old
					old = nil
				else
					bedwars.SharedConstants.CpsConstants.BLOCK_PLACE_CPS = bedwars.SharedConstants.CpsConstants.BLOCK_PLACE_CPS
				end
			end
		end
	})
	CPS = BlockCPSRemover:CreateSlider({
		Name = 'CPS',
		Min = 0,
		Max = (12 ^ 2),
		Default = 12,
		Decimal = 100,
		Tooltip = '0 = infinite cps btw.',
		Function = function(val)
			if BlockCPSRemover.Enabled then
				if not old then
					old = bedwars.SharedConstants.CpsConstants.BLOCK_PLACE_CPS or 12
				end
				bedwars.SharedConstants.CpsConstants.BLOCK_PLACE_CPS = (val == 0 and math.huge or val)
			end
		end
	})
	BlockCPSRemover:CreateButton({
		Name = 'Reset CPS',
		Function = resetCPS
	})
end)

local AntiFallDirection
run(function()
	local AntiFall
	local Mode
	local Material
	local Color
	local rayCheck = RaycastParams.new()
	rayCheck.RespectCanCollide = true
	local function getLowGround()
		local mag = math.huge
		for _, pos in bedwars.BlockController:getStore():getAllBlockPositions() do
			pos = pos * 3
			if pos.Y < mag and not getPlacedBlock(pos + Vector3.new(0, 3, 0)) then
				mag = pos.Y
			end
		end
		return mag
	end
	AntiFall = vape.Categories.Blatant:CreateModule({
		Name = 'Anti Fall',
		Function = function(callback)
			if callback then
				repeat
					task.wait()
				until store.matchState ~= 0 or (not AntiFall.Enabled)
				if not AntiFall.Enabled then
					return
				end
				local pos, debounce = getLowGround(), tick()
				if pos ~= math.huge then
					AntiFallPart = Instance.new('Part')
					AntiFallPart.Size = Vector3.new(10000, 1, 10000)
					AntiFallPart.Transparency = 1 - Color.Opacity
					AntiFallPart.Material = Enum.Material[Material.Value]
					AntiFallPart.Color = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
					AntiFallPart.Position = Vector3.new(0, pos - 2, 0)
					AntiFallPart.CanCollide = Mode.Value == 'Collide'
					AntiFallPart.Anchored = true
					AntiFallPart.CanQuery = false
					AntiFallPart.Parent = workspace
					AntiFall:Clean(AntiFallPart)
					AntiFall:Clean(AntiFallPart.Touched:Connect(function(touched)
						if touched.Parent == lplr.Character and entitylib.isAlive and debounce < tick() then
							debounce = tick() + 0.1
							if Mode.Value == 'Normal' then
								local top = getNearGround()
								if top then
									local lastTeleport = lplr:GetAttribute('LastTeleported')
									local connection
									connection = runService.PreSimulation:Connect(function()
										if vape.Modules.Fly.Enabled or vape.Modules.InfiniteFly.Enabled or vape.Modules.LongJump.Enabled then
											connection:Disconnect()
											AntiFallDirection = nil
											return
										end
										if entitylib.isAlive and lplr:GetAttribute('LastTeleported') == lastTeleport then
											local delta = ((top - entitylib.character.RootPart.Position) * Vector3.new(1, 0, 1))
											local root = entitylib.character.RootPart
											AntiFallDirection = delta.Unit == delta.Unit and delta.Unit or Vector3.zero
											root.Velocity *= Vector3.new(1, 0, 1)
											rayCheck.FilterDescendantsInstances = {
												gameCamera,
												lplr.Character
											}
											rayCheck.CollisionGroup = root.CollisionGroup
											local ray = workspace:Raycast(root.Position, AntiFallDirection, rayCheck)
											if ray then
												for _ = 1, 10 do
													local dpos = roundPos(ray.Position + ray.Normal * 1.5) + Vector3.new(0, 3, 0)
													if not getPlacedBlock(dpos) then
														top = Vector3.new(top.X, pos.Y, top.Z)
														break
													end
												end
											end
											root.CFrame += Vector3.new(0, top.Y - root.Position.Y, 0)
											if not frictionTable.Speed then
												root.AssemblyLinearVelocity = (AntiFallDirection * getSpeed()) + Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
											end
											if delta.Magnitude < 1 then
												connection:Disconnect()
												AntiFallDirection = nil
											end
										else
											connection:Disconnect()
											AntiFallDirection = nil
										end
									end)
									AntiFall:Clean(connection)
								end
							elseif Mode.Value == 'Velocity' then
								entitylib.character.RootPart.Velocity = Vector3.new(entitylib.character.RootPart.Velocity.X, 100, entitylib.character.RootPart.Velocity.Z)
							end
						end
					end))
				end
			else
				AntiFallDirection = nil
			end
		end,
		Tooltip = 'Help\'s you with your Parkinson\'s\nPrevents you from falling into the void.'
	})
	Mode = AntiFall:CreateDropdown({
		Name = 'Move Mode',
		List = {
			'Normal',
			'Collide',
			'Velocity'
		},
		Function = function(val)
			if AntiFallPart then
				AntiFallPart.CanCollide = val == 'Collide'
			end
		end,
		Tooltip = 'Normal - Smoothly moves you towards the nearest safe point\nVelocity - Launches you upward after touching\nCollide - Allows you to walk on the part'
	})
	local materials = {
		'ForceField'
	}
	for _, v in Enum.Material:GetEnumItems() do
		if v.Name ~= 'ForceField' then
			table.insert(materials, v.Name)
		end
	end
	Material = AntiFall:CreateDropdown({
		Name = 'Material',
		List = materials,
		Function = function(val)
			if AntiFallPart then
				AntiFallPart.Material = Enum.Material[val]
			end
		end
	})
	Color = AntiFall:CreateColorSlider({
		Name = 'Color',
		DefaultOpacity = 0.5,
		Function = function(h, s, v, o)
			if AntiFallPart then
				AntiFallPart.Color = Color3.fromHSV(h, s, v)
				AntiFallPart.Transparency = 1 - o
			end
		end
	})
end)

run(function()
	local FastBreak
	local Blacklist
	local List
	local Time
	local old = nil

	local function blacklisted(blockName)
		if not Blacklist.Enabled then return false end
		for _, entry in List.ListEnabled do
			if entry:find(blockName) then
				return true
			end
		end
		return false
	end

	FastBreak = vape.Categories.Blatant:CreateModule({
		Name = 'Fast Break',
		Function = function(callback)
			if callback then
				old = clonefunction(bedwars.BlockBreaker.hitBlock)
				hookfunction(bedwars.BlockBreaker.hitBlock, function(self, maid, raycastparms, ...)
					local block = self.clientManager:getBlockSelector():getMouseInfo(1, {
						ray = raycastparms
					})
					if block then
						block = block.target and block.target.blockInstance
						if not blacklisted(block.Name) then
							bedwars.BlockBreakController.blockBreaker:setCooldown(Time.Value)
						else
							bedwars.BlockBreakController.blockBreaker:setCooldown(0.3)	
						end
					end

					return old(self, maid, raycastparms, ...)
				end)
				repeat
					if tick() - store.lastHit > 0.3 then
						bedwars.BlockBreakController.blockBreaker:setCooldown(0.3)
					end
					task.wait()
				until not FastBreak.Enabled
			else
				local suc, res = pcall(function()
					restorefunction(bedwars.BlockBreaker.hitBlock)
				end)
				if not suc then
					bedwars.BlockBreaker.hitBlock = old
				end
				old = nil
			end
		end,
		Tooltip = 'allows you to edit block hit cooldown'
	})
	Blacklist = FastBreak:CreateToggle({
		Name = 'Blacklist',
		Tooltip = 'Enables the blacklist on breaking blocks faster',
		Function = function(callback)
			if List then List.Object.Visible = callback end
		end
	})
	List = FastBreak:CreateTextList({
		Name = 'List',
		Tooltip = 'To blacklist beds type "bed" in order to blacklist all beds',
		Darker = true,
		Visible = Blacklist.Enabled
	})
	Time = FastBreak:CreateSlider({
		Name = 'Break speed',
		Min = 0,
		Max = 0.3,
		Default = 0.25,
		Decimal = 100,
		Suffix = 'seconds'
	})
end)

local Fly
local LongJump
run(function()
	local Value
	local VerticalValue
	local WallCheck
	local PopBalloons
	local TP
	local rayCheck = RaycastParams.new()
	rayCheck.RespectCanCollide = true
	local up, down, old = 0, 0
	Fly = vape.Categories.Blatant:CreateModule({
		Name = 'Fly',
		Function = function(callback)
			frictionTable.Fly = callback or nil
			updateVelocity()
			if callback then
				up, down, old = 0, 0, bedwars.BalloonController.deflateBalloon
				bedwars.BalloonController.deflateBalloon = function()
				end
				local tpTick, tpToggle, oldy = tick(), true
				if lplr.Character and (lplr.Character:GetAttribute('InflatedBalloons') or 0) == 0 and getItem('balloon') then
					bedwars.BalloonController:inflateBalloon()
				end
				Fly:Clean(vapeEvents.AttributeChanged.Event:Connect(function(changed)
					if changed == 'InflatedBalloons' and (lplr.Character:GetAttribute('InflatedBalloons') or 0) == 0 and getItem('balloon') then
						bedwars.BalloonController:inflateBalloon()
					end
				end))
				Fly:Clean(runService.PreSimulation:Connect(function(dt)
					if entitylib.isAlive and not InfiniteFly.Enabled and isnetworkowner(entitylib.character.RootPart) then
						local flyAllowed = (lplr.Character:GetAttribute('InflatedBalloons') and lplr.Character:GetAttribute('InflatedBalloons') > 0) or store.matchState == 2
						local mass = (1.5 + (flyAllowed and 6 or 0) * (tick() % 0.4 < 0.2 and - 1 or 1)) + ((up + down) * VerticalValue.Value)
						local root, moveDirection = entitylib.character.RootPart, entitylib.character.Humanoid.MoveDirection
						local velo = getSpeed()
						local destination = (moveDirection * math.max(Value.Value - velo, 0) * dt)
						rayCheck.FilterDescendantsInstances = {
							lplr.Character,
							gameCamera,
							AntiFallPart
						}
						rayCheck.CollisionGroup = root.CollisionGroup
						if WallCheck.Enabled then
							local ray = workspace:Raycast(root.Position, destination, rayCheck)
							if ray then
								destination = ((ray.Position + ray.Normal) - root.Position)
							end
						end
						if not flyAllowed then
							if tpToggle then
								local airleft = (tick() - entitylib.character.AirTime)
								if airleft > 2 then
									if not oldy then
										local ray = workspace:Raycast(root.Position, Vector3.new(0, - 1000, 0), rayCheck)
										if ray and TP.Enabled then
											tpToggle = false
											oldy = root.Position.Y
											tpTick = tick() + 0.11
											root.CFrame = CFrame.lookAlong(Vector3.new(root.Position.X, ray.Position.Y + entitylib.character.HipHeight, root.Position.Z), root.CFrame.LookVector)
										end
									end
								end
							else
								if oldy then
									if tpTick < tick() then
										local newpos = Vector3.new(root.Position.X, oldy, root.Position.Z)
										root.CFrame = CFrame.lookAlong(newpos, root.CFrame.LookVector)
										tpToggle = true
										oldy = nil
									else
										mass = 0
									end
								end
							end
						end
						root.CFrame += destination
						root.AssemblyLinearVelocity = (moveDirection * velo) + Vector3.new(0, mass, 0)
					end
				end))
				Fly:Clean(inputService.InputBegan:Connect(function(input)
					if not inputService:GetFocusedTextBox() then
						if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
							up = 1
						elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL2 then
							down = - 1
						end
					end
				end))
				Fly:Clean(inputService.InputEnded:Connect(function(input)
					if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
						up = 0
					elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL2 then
						down = 0
					end
				end))
				if inputService.TouchEnabled then
					pcall(function()
						local jumpButton = lplr.PlayerGui.TouchGui.TouchControlFrame.JumpButton
						Fly:Clean(jumpButton:GetPropertyChangedSignal('ImageRectOffset'):Connect(function()
							up = jumpButton.ImageRectOffset.X == 146 and 1 or 0
						end))
					end)
				end
			else
				bedwars.BalloonController.deflateBalloon = old
				if PopBalloons.Enabled and entitylib.isAlive and (lplr.Character:GetAttribute('InflatedBalloons') or 0) > 0 then
					for _ = 1, 3 do
						bedwars.BalloonController:deflateBalloon()
					end
				end
			end
		end,
		ExtraText = function()
			return 'Heatseeker'
		end,
		Tooltip = 'Makes you go zoom.'
	})
	Value = Fly:CreateSlider({
		Name = 'Speed',
		Min = 1,
		Max = 23,
		Default = 23,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	VerticalValue = Fly:CreateSlider({
		Name = 'Vertical Speed',
		Min = 1,
		Max = 150,
		Default = 50,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	WallCheck = Fly:CreateToggle({
		Name = 'Wall Check',
		Default = true
	})
	PopBalloons = Fly:CreateToggle({
		Name = 'Pop Balloons',
		Default = true
	})
	TP = Fly:CreateToggle({
		Name = 'TP Down',
		Default = true
	})
end)

run(function()
	local Mode
	local Expand
	local objects, set = {}
	local function createHitbox(ent)
		if ent.Targetable and ent.Player then
			local hitbox = Instance.new('Part')
			hitbox.Size = Vector3.new(3, 6, 3) + Vector3.one * (Expand.Value / 5)
			hitbox.Position = ent.RootPart.Position
			hitbox.CanCollide = false
			hitbox.Massless = true
			hitbox.Transparency = 1
			hitbox.Parent = ent.Character
			local weld = Instance.new('Motor6D')
			weld.Part0 = hitbox
			weld.Part1 = ent.RootPart
			weld.Parent = hitbox
			objects[ent] = hitbox
		end
	end
	HitBoxes = vape.Categories.Blatant:CreateModule({
		Name = 'Hit Boxes',
		Function = function(callback)
			if callback then
				if Mode.Value == 'Sword' then
					debug.setconstant(bedwars.SwordController.swingSwordInRegion, 6, (Expand.Value / 3))
					set = true
				else
					HitBoxes:Clean(entitylib.Events.EntityAdded:Connect(createHitbox))
					HitBoxes:Clean(entitylib.Events.EntityRemoving:Connect(function(ent)
						if objects[ent] then
							objects[ent]:Destroy()
							objects[ent] = nil
						end
					end))
					for _, ent in entitylib.List do
						createHitbox(ent)
					end
				end
			else
				if set then
					debug.setconstant(bedwars.SwordController.swingSwordInRegion, 6, 3.8)
					set = nil
				end
				for _, part in objects do
					part:Destroy()
				end
				table.clear(objects)
			end
		end,
		Tooltip = 'Expands attack hitbox'
	})
	Mode = HitBoxes:CreateDropdown({
		Name = 'Mode',
		List = {
			'Sword',
			'Player'
		},
		Function = function()
			if HitBoxes.Enabled then
				HitBoxes:Toggle()
				HitBoxes:Toggle()
			end
		end,
		Tooltip = 'Sword - Increases the range around you to hit entities\nPlayer - Increases the players hitbox'
	})
	Expand = HitBoxes:CreateSlider({
		Name = 'Expand amount',
		Min = 0,
		Max = 14.4,
		Default = 14.4,
		Decimal = 10,
		Function = function(val)
			if HitBoxes.Enabled then
				if Mode.Value == 'Sword' then
					debug.setconstant(bedwars.SwordController.swingSwordInRegion, 6, (val / 3))
				else
					for _, part in objects do
						part.Size = Vector3.new(3, 6, 3) + Vector3.one * (val / 5)
					end
				end
			end
		end,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
end)

run(function()
	vape.Categories.Blatant:CreateModule({
		Name = 'Keep Sprint',
		Function = function(callback)
			debug.setconstant(bedwars.SprintController.startSprinting, 5, callback and 'blockSprinting' or 'blockSprint')
			bedwars.SprintController:stopSprinting()
		end,
		Tooltip = 'Lets you sprint with a speed potion.'
	})
end)

local Attacking
run(function()
	local Killaura
	local Targets
	local Sort
	local SwingRange
	local AttackRange
	local ChargeTime
	local UpdateRate
	local AngleSlider
	local MaxTargets
	local AirChance
	local Mouse
	local Swing
	local GUI
	local BoxSwingColor
	local BoxAttackColor
	local ParticleTexture
	local ParticleColor1
	local ParticleColor2
	local ParticleSize
	local Face
	local Animation
	local AnimationMode
	local AnimationSpeed
	local AnimationTween
	local Limit
	local LegitAura = {}
	local Particles, Boxes = {}, {}
	local anims, AnimDelay, AnimTween, armC0 = vape.Libraries.auraanims, tick()
	local AttackRemote = {
		FireServer = function()
		end
	}
	local kitChecks
	local AttackCheck
	task.spawn(function()
		AttackRemote = bedwars.Client:Get(remotes.AttackEntity).instance
	end)
	local function getAttackData()
		if AttackCheck and AttackCheck.Enabled then
			local stunTime = lplr.Character and lplr.Character:GetAttribute('StunnedUntilTime')
			if stunTime and stunTime > workspace:GetServerTimeNow() then
				return false
			end
			if kitChecks then
				for _, check in pairs(kitChecks) do
					if check() then
						return false
					end
				end
			end
		end
		if Mouse.Enabled then
			if not inputService:IsMouseButtonPressed(0) then
				return false
			end
		end
		if GUI.Enabled then
			if bedwars.AppController:isLayerOpen(bedwars.UILayers.MAIN) then
				return false
			end
		end
		local sword = Limit.Enabled and store.hand or store.tools.sword
		if not sword or not sword.tool then
			return false
		end
		local meta = bedwars.ItemMeta[sword.tool.Name]
		if Limit.Enabled then
			if store.hand.toolType ~= 'sword' or bedwars.DaoController.chargingMaid then
				return false
			end
		end
		if LegitAura.Enabled then
			if (tick() - bedwars.SwordController.lastSwing) > 0.15 then
				return false
			end
		end
		return sword, meta
	end
	Killaura = vape.Categories.Blatant:CreateModule({
		Name = 'Killaura',
		Function = function(callback)
			if callback then
				if inputService.TouchEnabled then
					pcall(function()
						lplr.PlayerGui.MobileUI['2'].Visible = Limit.Enabled
					end)
				end
				if Animation.Enabled and not (identifyexecutor and table.find({
					'Argon',
					'Delta',
					'Codex',
					'Krampus',
					'Solara',
					'Xeno'
				}, ({
					identifyexecutor()
				})[1])) then
					local fake = {
						Controllers = {
							ViewmodelController = {
								isVisible = function()
									return not Attacking
								end,
								playAnimation = function(...)
									if not Attacking then
										bedwars.ViewmodelController:playAnimation(select(2, ...))
									end
								end
							}
						}
					}
					debug.setupvalue(oldSwing or bedwars.SwordController.playSwordEffect, 6, fake)
					debug.setupvalue(bedwars.ScytheController.playLocalAnimation, 3, fake)
					task.spawn(function()
						local started = false
						repeat
							if Attacking then
								if not armC0 then
									armC0 = gameCamera.Viewmodel.RightHand.RightWrist.C0
								end
								local first = not started
								started = true
								if AnimationMode.Value == 'Random' then
									anims.Random = {
										{
											CFrame = CFrame.Angles(math.rad(math.random(1, 360)), math.rad(math.random(1, 360)), math.rad(math.random(1, 360))),
											Time = 0.12
										}
									}
								end
								for _, v in anims[AnimationMode.Value] do
									AnimTween = tweenService:Create(gameCamera.Viewmodel.RightHand.RightWrist, TweenInfo.new(first and (AnimationTween.Enabled and 0.001 or 0.1) or v.Time / AnimationSpeed.Value, Enum.EasingStyle.Linear), {
										C0 = armC0 * v.CFrame
									})
									AnimTween:Play()
									AnimTween.Completed:Wait()
									first = false
									if (not Killaura.Enabled) or (not Attacking) then
										break
									end
								end
							elseif started then
								started = false
								AnimTween = tweenService:Create(gameCamera.Viewmodel.RightHand.RightWrist, TweenInfo.new(AnimationTween.Enabled and 0.001 or 0.3, Enum.EasingStyle.Exponential), {
									C0 = armC0
								})
								AnimTween:Play()
							end
							if not started then
								task.wait(1 / UpdateRate.Value)
							end
						until (not Killaura.Enabled) or (not Animation.Enabled)
					end)
				end
				local swingCooldown = 0
				repeat
					if AttackCheck and AttackCheck.Enabled then
						local stunTime = lplr.Character and lplr.Character:GetAttribute('StunnedUntilTime')
						if stunTime and stunTime > workspace:GetServerTimeNow() then
							Attacking = false
							store.KillauraTarget = nil
							task.wait(0.3)
							continue
						end
						if kitChecks then
							local blocked = false
							for _, check in pairs(kitChecks) do
								if check() then
									blocked = true
									break
								end
							end
							if blocked then
								Attacking = false
								store.KillauraTarget = nil
								task.wait(0.3)
								continue
							end
						end
					end
					local attacked, sword, meta = {}, getAttackData()
					Attacking = false
					store.KillauraTarget = nil
					if sword then
						local plrs = entitylib.AllPosition({
							Range = SwingRange.Value,
							Wallcheck = Targets.Walls.Enabled or nil,
							Part = 'RootPart',
							Players = Targets.Players.Enabled,
							NPCs = Targets.NPCs.Enabled,
							Limit = MaxTargets.Value,
							Sort = sortmethods[Sort.Value]
						})
						if # plrs > 0 then
							switchItem(sword.tool, 0)
							local selfpos = entitylib.character.RootPart.Position
							local localfacing = entitylib.character.RootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
							for _, v in plrs do
								local delta = (v.RootPart.Position - selfpos)
								local angle = math.acos(localfacing:Dot((delta * Vector3.new(1, 0, 1)).Unit))
								if angle > (math.rad(AngleSlider.Value) / 2) then
									continue
								end
								table.insert(attacked, {
									Entity = v,
									Check = delta.Magnitude > AttackRange.Value and BoxSwingColor or BoxAttackColor
								})
								targetinfo.Targets[v] = tick() + 1
								if not Attacking then
									Attacking = true
									store.KillauraTarget = v
									if not Swing.Enabled and AnimDelay < tick() and not LegitAura.Enabled then
										AnimDelay = tick() + (meta.sword.respectAttackSpeedForEffects and meta.sword.attackSpeed or math.max(ChargeTime.Value, 0.11))
										bedwars.SwordController:playSwordEffect(meta, false)
										if meta.displayName:find(' Scythe') then
											bedwars.ScytheController:playLocalAnimation()
										end
										if vape.ThreadFix then
											setthreadidentity(8)
										end
									end
								end
								if delta.Magnitude > AttackRange.Value then
									continue
								end
								if delta.Magnitude < 14.4 and (tick() - swingCooldown) < math.max(ChargeTime.Value, 0.02) then
									continue
								end
								local actualRoot = v.Character.PrimaryPart
								if actualRoot and (v.Humanoid.FloorMaterial ~= Enum.Material.Air or math.random(1, 100) < AirChance.Value) then
									local dir = CFrame.lookAt(selfpos, actualRoot.Position).LookVector
									local pos = selfpos + dir * math.max(delta.Magnitude - 14.399, 0)
									swingCooldown = tick()
									bedwars.SwordController.lastAttack = workspace:GetServerTimeNow()
									store.attackReach = (delta.Magnitude * 100) // 1 / 100
									store.attackReachUpdate = tick() + 1
									if delta.Magnitude < 14.4 and ChargeTime.Value > 0.11 then
										AnimDelay = tick()
									end
									AttackRemote:FireServer({
										weapon = sword.tool,
										chargedAttack = {
											chargeRatio = 0
										},
										lastSwingServerTimeDelta = 0.5,
										entityInstance = v.Character,
										validate = {
											raycast = {
												cameraPosition = {
													value = pos
												},
												cursorDirection = {
													value = dir
												}
											},
											targetPosition = {
												value = actualRoot.Position
											},
											selfPosition = {
												value = pos
											}
										}
									})
								end
							end
						end
					end
					for i, v in Boxes do
						v.Adornee = attacked[i] and attacked[i].Entity.RootPart or nil
						if v.Adornee then
							v.Color3 = Color3.fromHSV(attacked[i].Check.Hue, attacked[i].Check.Sat, attacked[i].Check.Value)
							v.Transparency = 1 - attacked[i].Check.Opacity
						end
					end
					for i, v in Particles do
						v.Position = attacked[i] and attacked[i].Entity.RootPart.Position or Vector3.new(9e9, 9e9, 9e9)
						v.Parent = attacked[i] and gameCamera or nil
					end
					if Face.Enabled and attacked[1] then
						local vec = attacked[1].Entity.RootPart.Position * Vector3.new(1, 0, 1)
						entitylib.character.RootPart.CFrame = CFrame.lookAt(entitylib.character.RootPart.Position, Vector3.new(vec.X, entitylib.character.RootPart.Position.Y + 0.001, vec.Z))
					end

						--#attacked > 0 and #attacked * 0.02 or
					task.wait(1 / UpdateRate.Value)
				until not Killaura.Enabled
			else
				store.KillauraTarget = nil
				for _, v in Boxes do
					v.Adornee = nil
				end
				for _, v in Particles do
					v.Parent = nil
				end
				if inputService.TouchEnabled then
					pcall(function()
						lplr.PlayerGui.MobileUI['2'].Visible = true
					end)
				end
				Attacking = false
				if armC0 then
					if AnimTween then
						AnimTween:Destroy()
						AnimTween = nil
					end
					AnimTween = tweenService:Create(gameCamera.Viewmodel.RightHand.RightWrist, TweenInfo.new(AnimationTween and AnimationTween.Enabled and 0.001 or 0.3, Enum.EasingStyle.Exponential), {
						C0 = armC0
					})
					AnimTween:Play()
				end
			end
		end,
		Tooltip = 'Attack players around you\nwithout aiming at them.'
	})
	Targets = Killaura:CreateTargets({
		Players = true,
		NPCs = true
	})
	local methods = {
		'Damage',
		'Distance'
	}
	for i in sortmethods do
		if not table.find(methods, i) then
			table.insert(methods, i)
		end
	end
	AirChance = Killaura:CreateSlider({
		Name = 'Air Chance',
		Tooltip = 'The chance that yuo can hit someone in the air',
		Min = 0,
		Max = 100,
		Default = 100,
		Suffix = '%',
		Decimal = 10
	})
	SwingRange = Killaura:CreateSlider({
		Name = 'Swing range',
		Min = 1,
		Max = 18,
		Default = 18,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	AttackRange = Killaura:CreateSlider({
		Name = 'Attack range',
		Min = 1,
		Max = 20,
		Default = 18,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	ChargeTime = Killaura:CreateSlider({
		Name = 'Swing time',
		Min = 0,
		Max = 0.5,
		Default = 0.42,
		Decimal = 100
	})
	AngleSlider = Killaura:CreateSlider({
		Name = 'Max angle',
		Min = 1,
		Max = 360,
		Default = 360
	})
	UpdateRate = Killaura:CreateSlider({
		Name = 'Update rate',
		Min = 1,
		Max = 120,
		Default = 60,
		Suffix = 'hz'
	})
	MaxTargets = Killaura:CreateSlider({
		Name = 'Max targets',
		Min = 1,
		Max = 5,
		Default = 5
	})
	Sort = Killaura:CreateDropdown({
		Name = 'Target Mode',
		List = methods
	})
	Mouse = Killaura:CreateToggle({
		Name = 'Require mouse down'
	})
	Swing = Killaura:CreateToggle({
		Name = 'No Swing'
	})
	GUI = Killaura:CreateToggle({
		Name = 'GUI check'
	})
	kitChecks = {
		['Sophia'] = function()
			return isFrozen(nil, FROZEN_THRESHOLD)
		end,
		['Sigrid'] = function()
			return entitylib.isAlive and lplr.Character and lplr.Character:FindFirstChild('elk') ~= nil
		end,
	}
	AttackCheck = Killaura:CreateToggle({
		Name = 'Attack Check',
		Tooltip = 'Stops Killaura when a kit ability is detected (Sophia, etc) or when asleep',
		Function = function(callback)
		end,
		Default = false
	})
	Killaura:CreateToggle({
		Name = 'Show target',
		Function = function(callback)
			BoxSwingColor.Object.Visible = callback
			BoxAttackColor.Object.Visible = callback
			if callback then
				for i = 1, 10 do
					local box = Instance.new('BoxHandleAdornment')
					box.Adornee = nil
					box.AlwaysOnTop = true
					box.Size = Vector3.new(3, 5, 3)
					box.CFrame = CFrame.new(0, - 0.5, 0)
					box.ZIndex = 0
					box.Parent = vape.gui
					Boxes[i] = box
				end
			else
				for _, v in Boxes do
					v:Destroy()
				end
				table.clear(Boxes)
			end
		end
	})
	BoxSwingColor = Killaura:CreateColorSlider({
		Name = 'Target Color',
		Darker = true,
		DefaultHue = 0.6,
		DefaultOpacity = 0.5,
		Visible = false
	})
	BoxAttackColor = Killaura:CreateColorSlider({
		Name = 'Attack Color',
		Darker = true,
		DefaultOpacity = 0.5,
		Visible = false
	})
	Killaura:CreateToggle({
		Name = 'Target particles',
		Function = function(callback)
			ParticleTexture.Object.Visible = callback
			ParticleColor1.Object.Visible = callback
			ParticleColor2.Object.Visible = callback
			ParticleSize.Object.Visible = callback
			if callback then
				for i = 1, 10 do
					local part = Instance.new('Part')
					part.Size = Vector3.new(2, 4, 2)
					part.Anchored = true
					part.CanCollide = false
					part.Transparency = 1
					part.CanQuery = false
					part.Parent = Killaura.Enabled and gameCamera or nil
					local particles = Instance.new('ParticleEmitter')
					particles.Brightness = 1.5
					particles.Size = NumberSequence.new(ParticleSize.Value)
					particles.Shape = Enum.ParticleEmitterShape.Sphere
					particles.Texture = ParticleTexture.Value
					particles.Transparency = NumberSequence.new(0)
					particles.Lifetime = NumberRange.new(0.4)
					particles.Speed = NumberRange.new(16)
					particles.Rate = 128
					particles.Drag = 16
					particles.ShapePartial = 1
					particles.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromHSV(ParticleColor1.Hue, ParticleColor1.Sat, ParticleColor1.Value)),
						ColorSequenceKeypoint.new(1, Color3.fromHSV(ParticleColor2.Hue, ParticleColor2.Sat, ParticleColor2.Value))
					})
					particles.Parent = part
					Particles[i] = part
				end
			else
				for _, v in Particles do
					v:Destroy()
				end
				table.clear(Particles)
			end
		end
	})
	ParticleTexture = Killaura:CreateTextBox({
		Name = 'Texture',
		Default = 'rbxassetid://14736249347',
		Function = function()
			for _, v in Particles do
				v.ParticleEmitter.Texture = ParticleTexture.Value
			end
		end,
		Darker = true,
		Visible = false
	})
	ParticleColor1 = Killaura:CreateColorSlider({
		Name = 'Color Begin',
		Function = function(hue, sat, val)
			for _, v in Particles do
				v.ParticleEmitter.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromHSV(hue, sat, val)),
					ColorSequenceKeypoint.new(1, Color3.fromHSV(ParticleColor2.Hue, ParticleColor2.Sat, ParticleColor2.Value))
				})
			end
		end,
		Darker = true,
		Visible = false
	})
	ParticleColor2 = Killaura:CreateColorSlider({
		Name = 'Color End',
		Function = function(hue, sat, val)
			for _, v in Particles do
				v.ParticleEmitter.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromHSV(ParticleColor1.Hue, ParticleColor1.Sat, ParticleColor1.Value)),
					ColorSequenceKeypoint.new(1, Color3.fromHSV(hue, sat, val))
				})
			end
		end,
		Darker = true,
		Visible = false
	})
	ParticleSize = Killaura:CreateSlider({
		Name = 'Size',
		Min = 0,
		Max = 1,
		Default = 0.2,
		Decimal = 100,
		Function = function(val)
			for _, v in Particles do
				v.ParticleEmitter.Size = NumberSequence.new(val)
			end
		end,
		Darker = true,
		Visible = false
	})
	Face = Killaura:CreateToggle({
		Name = 'Face target'
	})
	Animation = Killaura:CreateToggle({
		Name = 'Custom Animation',
		Function = function(callback)
			AnimationMode.Object.Visible = callback
			AnimationTween.Object.Visible = callback
			AnimationSpeed.Object.Visible = callback
			if Killaura.Enabled then
				Killaura:Toggle()
				Killaura:Toggle()
			end
		end
	})
	local animnames = {}
	for i in anims do
		table.insert(animnames, i)
	end
	AnimationMode = Killaura:CreateDropdown({
		Name = 'Animation Mode',
		List = animnames,
		Darker = true,
		Visible = false
	})
	AnimationSpeed = Killaura:CreateSlider({
		Name = 'Animation Speed',
		Min = 0,
		Max = 2,
		Default = 1,
		Decimal = 10,
		Darker = true,
		Visible = false
	})
	AnimationTween = Killaura:CreateToggle({
		Name = 'No Tween',
		Darker = true,
		Visible = false
	})
	Limit = Killaura:CreateToggle({
		Name = 'Limit to items',
		Function = function(callback)
			if inputService.TouchEnabled and Killaura.Enabled then
				pcall(function()
					lplr.PlayerGui.MobileUI['2'].Visible = callback
				end)
			end
		end,
		Tooltip = 'Only attacks when the sword is held'
	})
	LegitAura = Killaura:CreateToggle({
		Name = 'Swing only',
		Tooltip = 'Only attacks while swinging manually'
	})
end)

run(function()
	local Value
	local CameraDir
	local start
	local JumpTick, JumpSpeed, Direction = tick(), 0
	local projectileRemote = {
		InvokeServer = function()
		end
	}
	task.spawn(function()
		projectileRemote = bedwars.Client:Get(remotes.FireProjectile).instance
	end)
	local function launchProjectile(item, pos, proj, speed, dir)
		if not pos then
			return
		end
		pos = pos - dir * 0.1
		local shootPosition = (CFrame.lookAlong(pos, Vector3.new(0, - speed, 0)) * CFrame.new(Vector3.new(- bedwars.BowConstantsTable.RelX, - bedwars.BowConstantsTable.RelY, - bedwars.BowConstantsTable.RelZ)))
		switchItem(item.tool, 0)
		task.wait(0.1)
		bedwars.ProjectileController:createLocalProjectile(bedwars.ProjectileMeta[proj], proj, proj, shootPosition.Position, '', shootPosition.LookVector * speed, {
			drawDurationSeconds = 1
		})
		if projectileRemote:InvokeServer(item.tool, proj, proj, shootPosition.Position, pos, shootPosition.LookVector * speed, httpService:GenerateGUID(true), {
			drawDurationSeconds = 1
		}, workspace:GetServerTimeNow() - 0.045) then
			local shoot = bedwars.ItemMeta[item.itemType].projectileSource.launchSound
			shoot = shoot and shoot[math.random(1, # shoot)] or nil
			if shoot then
				bedwars.SoundManager:playSound(shoot)
			end
		end
	end
	local LongJumpMethods = {
		cannon = function(_, pos, dir)
			pos = pos - Vector3.new(0, (entitylib.character.HipHeight + (entitylib.character.RootPart.Size.Y / 2)) - 3, 0)
			local rounded = Vector3.new(math.round(pos.X / 3) * 3, math.round(pos.Y / 3) * 3, math.round(pos.Z / 3) * 3)
			bedwars.placeBlock(rounded, 'cannon', false)
			task.delay(0, function()
				local block, blockpos = getPlacedBlock(rounded)
				if block and block.Name == 'cannon' and (entitylib.character.RootPart.Position - block.Position).Magnitude < 20 then
					local breaktype = bedwars.ItemMeta[block.Name].block.breakType
					local tool = store.tools[breaktype]
					if tool then
						switchItem(tool.tool)
					end
					bedwars.Client:Get(remotes.CannonAim):SendToServer({
						cannonBlockPos = blockpos,
						lookVector = dir
					})
					local broken = 0.1
					if bedwars.BlockController:calculateBlockDamage(lplr, {
						blockPosition = blockpos
					}) < block:GetAttribute('Health') then
						broken = 0.4
						bedwars.breakBlock(block, true, true)
					end
					task.delay(broken, function()
						for _ = 1, 3 do
							local call = bedwars.Client:Get(remotes.CannonLaunch):CallServer({
								cannonBlockPos = blockpos
							})
							if call then
								bedwars.breakBlock(block, true, true)
								JumpSpeed = 5.25 * Value.Value
								JumpTick = tick() + 2.3
								Direction = Vector3.new(dir.X, 0, dir.Z).Unit
								break
							end
							task.wait(0.1)
						end
					end)
				end
			end)
		end,
		cat = function(_, _, dir)
			LongJump:Clean(vapeEvents.CatPounce.Event:Connect(function()
				JumpSpeed = 4 * Value.Value
				JumpTick = tick() + 2.5
				Direction = Vector3.new(dir.X, 0, dir.Z).Unit
				entitylib.character.RootPart.Velocity = Vector3.zero
			end))
			if not bedwars.AbilityController:canUseAbility('CAT_POUNCE') then
				repeat
					task.wait()
				until bedwars.AbilityController:canUseAbility('CAT_POUNCE') or not LongJump.Enabled
			end
			if bedwars.AbilityController:canUseAbility('CAT_POUNCE') and LongJump.Enabled then
				bedwars.AbilityController:useAbility('CAT_POUNCE')
			end
		end,
		fireball = function(item, pos, dir)
			launchProjectile(item, pos, 'fireball', 60, dir)
		end,
		grappling_hook = function(item, pos, dir)
			launchProjectile(item, pos, 'grappling_hook_projectile', 140, dir)
		end,
		jade_hammer = function(item, _, dir)
			if not bedwars.AbilityController:canUseAbility(item.itemType .. '_jump') then
				repeat
					task.wait()
				until bedwars.AbilityController:canUseAbility(item.itemType .. '_jump') or not LongJump.Enabled
			end
			if bedwars.AbilityController:canUseAbility(item.itemType .. '_jump') and LongJump.Enabled then
				bedwars.AbilityController:useAbility(item.itemType .. '_jump')
				JumpSpeed = 1.4 * Value.Value
				JumpTick = tick() + 2.5
				Direction = Vector3.new(dir.X, 0, dir.Z).Unit
			end
		end,
		tnt = function(item, pos, dir)
			pos = pos - Vector3.new(0, (entitylib.character.HipHeight + (entitylib.character.RootPart.Size.Y / 2)) - 3, 0)
			local rounded = Vector3.new(math.round(pos.X / 3) * 3, math.round(pos.Y / 3) * 3, math.round(pos.Z / 3) * 3)
			start = Vector3.new(rounded.X, start.Y, rounded.Z) + (dir * (item.itemType == 'pirate_gunpowder_barrel' and 2.6 or 0.2))
			bedwars.placeBlock(rounded, item.itemType, false)
		end,
		wood_dao = function(item, pos, dir)
			if (lplr.Character:GetAttribute('CanDashNext') or 0) > workspace:GetServerTimeNow() or not bedwars.AbilityController:canUseAbility('dash') then
				repeat
					task.wait()
				until (lplr.Character:GetAttribute('CanDashNext') or 0) < workspace:GetServerTimeNow() and bedwars.AbilityController:canUseAbility('dash') or not LongJump.Enabled
			end
			if LongJump.Enabled then
				bedwars.SwordController.lastAttack = workspace:GetServerTimeNow()
				switchItem(item.tool, 0.1)
				replicatedStorage['events-@easy-games/game-core:shared/game-core-networking@getEvents.Events'].useAbility:FireServer('dash', {
					direction = dir,
					origin = pos,
					weapon = item.itemType
				})
				JumpSpeed = 4.5 * Value.Value
				JumpTick = tick() + 2.4
				Direction = Vector3.new(dir.X, 0, dir.Z).Unit
			end
		end
	}
	for _, v in {
		'stone_dao',
		'iron_dao',
		'diamond_dao',
		'emerald_dao'
	} do
		LongJumpMethods[v] = LongJumpMethods.wood_dao
	end
	LongJumpMethods.void_axe = LongJumpMethods.jade_hammer
	LongJumpMethods.siege_tnt = LongJumpMethods.tnt
	LongJumpMethods.pirate_gunpowder_barrel = LongJumpMethods.tnt
	LongJump = vape.Categories.Blatant:CreateModule({
		Name = 'Long Jump',
		Function = function(callback)
			frictionTable.LongJump = callback or nil
			updateVelocity()
			if callback then
				LongJump:Clean(vapeEvents.EntityDamageEvent.Event:Connect(function(damageTable)
					if damageTable.entityInstance == lplr.Character and damageTable.fromEntity == lplr.Character and (not damageTable.knockbackMultiplier or not damageTable.knockbackMultiplier.disabled) then
						local knockbackBoost = bedwars.KnockbackUtil.calculateKnockbackVelocity(Vector3.one, 1, {
							vertical = 0,
							horizontal = (damageTable.knockbackMultiplier and damageTable.knockbackMultiplier.horizontal or 1)
						}).Magnitude * 1.1
						if knockbackBoost >= JumpSpeed then
							local pos = damageTable.fromPosition and Vector3.new(damageTable.fromPosition.X, damageTable.fromPosition.Y, damageTable.fromPosition.Z) or damageTable.fromEntity and damageTable.fromEntity.PrimaryPart.Position
							if not pos then
								return
							end
							local vec = (entitylib.character.RootPart.Position - pos)
							JumpSpeed = knockbackBoost
							JumpTick = tick() + 2.5
							Direction = Vector3.new(vec.X, 0, vec.Z).Unit
						end
					end
				end))
				LongJump:Clean(vapeEvents.GrapplingHookFunctions.Event:Connect(function(dataTable)
					if dataTable.hookFunction == 'PLAYER_IN_TRANSIT' then
						local vec = entitylib.character.RootPart.CFrame.LookVector
						JumpSpeed = 2.5 * Value.Value
						JumpTick = tick() + 2.5
						Direction = Vector3.new(vec.X, 0, vec.Z).Unit
					end
				end))
				start = entitylib.isAlive and entitylib.character.RootPart.Position or nil
				LongJump:Clean(runService.PreSimulation:Connect(function(dt)
					local root = entitylib.isAlive and entitylib.character.RootPart or nil
					if root and isnetworkowner(root) then
						if JumpTick > tick() then
							root.AssemblyLinearVelocity = Direction * (getSpeed() + ((JumpTick - tick()) > 1.1 and JumpSpeed or 0)) + Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
							if entitylib.character.Humanoid.FloorMaterial == Enum.Material.Air and not start then
								root.AssemblyLinearVelocity += Vector3.new(0, dt * (workspace.Gravity - 23), 0)
							else
								root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 15, root.AssemblyLinearVelocity.Z)
							end
							start = nil
						else
							if start then
								root.CFrame = CFrame.lookAlong(start, root.CFrame.LookVector)
							end
							root.AssemblyLinearVelocity = Vector3.zero
							JumpSpeed = 0
						end
					else
						start = nil
					end
				end))
				if store.hand and LongJumpMethods[store.hand.tool.Name] then
					task.spawn(LongJumpMethods[store.hand.tool.Name], getItem(store.hand.tool.Name), start, (CameraDir.Enabled and gameCamera or entitylib.character.RootPart).CFrame.LookVector)
					return
				end
				for i, v in LongJumpMethods do
					local item = getItem(i)
					if item or store.equippedKit == i then
						task.spawn(v, item, start, (CameraDir.Enabled and gameCamera or entitylib.character.RootPart).CFrame.LookVector)
						break
					end
				end
			else
				JumpTick = tick()
				Direction = nil
				JumpSpeed = 0
			end
		end,
		ExtraText = function()
			return 'Heatseeker'
		end,
		Tooltip = 'Lets you jump farther'
	})
	Value = LongJump:CreateSlider({
		Name = 'Speed',
		Min = 1,
		Max = 37,
		Default = 37,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	CameraDir = LongJump:CreateToggle({
		Name = 'Camera Direction'
	})
end)

run(function()
	local NoFall
	local HealthCheck
	local HealthThreshold
	local function rakNetCheck(module)
		if not (raknet and raknet.add_send_hook and pcall(raknet.add_send_hook, function()
		end)) then
			vape:CreateNotification('Vape', 'This feature requires raknet!!!!', 10, 'warning')
			return false
		end
		return true
	end
	local function func(packet)
		if packet.AsArray[1] ~= 0x1b then
			return
		end
		local data = packet.AsBuffer
		buffer.writef32(data, 13, 0)
		buffer.writef32(data, 17, 0)
		buffer.writef32(data, 21, 0)
		buffer.writef32(data, 25, 0)
		buffer.writef32(data, 29, 0)
		buffer.writef32(data, 33, 0)
		packet:SetData(data)
	end
	NoFall = vape.Categories.Blatant:CreateModule({
		Name = 'No Fall',
		Function = function(callback)
			if callback then
				if rakNetCheck('NoFall') then
					NoFall:Clean(lplr.Character.Humanoid.StateChanged:Connect(function(old, new)
						if new == Enum.HumanoidStateType.FallingDown or new == Enum.HumanoidStateType.Freefall or new == Enum.HumanoidStateType.Jumping then
							raknet.add_send_hook(func)
						else
							task.wait(lplr:GetNetworkPing() or 0.1 + 0.05)
							pcall(raknet.remove_send_hook, func)
						end
					end))
				else
					vape:Remove('NoFall')
				end
			else
				pcall(raknet.remove_send_hook, func)
			end
		end
	})
end)

run(function()
	local old
	vape.Categories.Blatant:CreateModule({
		Name = 'No Slowdown',
		Function = function(callback)
			local modifier = bedwars.SprintController:getMovementStatusModifier()
			if callback then
				old = modifier.addModifier
				modifier.addModifier = function(self, tab)
					if tab.moveSpeedMultiplier then
						tab.moveSpeedMultiplier = math.max(tab.moveSpeedMultiplier, 1)
					end
					return old(self, tab)
				end
				for i in modifier.modifiers do
					if (i.moveSpeedMultiplier or 1) < 1 then
						modifier:removeModifier(i)
					end
				end
			else
				modifier.addModifier = old
				old = nil
			end
		end,
		Tooltip = 'Prevents slowing down when using items.'
	})
end)

run(function()
	local Prediction
	local AutoCharge
	local AutoChargePerceft
	local TargetPart
	local Targets
	local FOV
	local Sort
	local OtherProjectiles
	local Blacklist
	local rayCheck = RaycastParams.new()
	rayCheck.FilterType = Enum.RaycastFilterType.Include
	rayCheck.FilterDescendantsInstances = {
		workspace:FindFirstChild('Map')
	}
	local launchHook, oldd
	local function getMousePosition()
		if inputService.TouchEnabled then
			return gameCamera.ViewportSize / 2
		end
		return inputService.GetMouseLocation(inputService)
	end
	local function getPosition(ent, proj)
		if TargetPart.Value == 'Closest' then
			local localPosition, magnitude, part = getMousePosition(), 9e9, nil
			for _, v in ent:GetChildren() do
				if pcall(function()
					return v.Position;
				end) then
					local position, vis = gameCamera.WorldToViewportPoint(gameCamera, v.Position)
					if vis then
						local mag = (localPosition - Vector2.new(position.x, position.y)).Magnitude
						if mag < magnitude then
							magnitude = mag
							part = v
						end
					end
				end
			end
			return part and part.Position or ent.PrimaryPart.Position
		elseif TargetPart.Value == 'Dynamic' then
			local tool = store.hand.tool
			if tool and tool.Name:find('headhunter') then
				return ent.Head.Position
			end
			return ent.PrimaryPart.Position
		end
		return
	end
	local ProjectileAimbot
	ProjectileAimbot = vape.Categories.Blatant:CreateModule({
		Name = 'Projectile Aimbot',
		Function = function(callback)
			if callback then
				oldd = bedwars.BlockKickerKitController.getKickBlockProjectileOriginPosition
				launchHook = bedwars.ProjectileLaunchHook:Add('ProjectileAimbot', 100, function(nextLaunch, ...)
					local self, projmeta, worldmeta, origin, shootpos = ...
					local plr = entitylib.EntityMouse({
						Part = 'RootPart',
						Range = TargetPart.Value == 'Dynamic' and projmeta.projectile:find('lasso') and 23 or FOV.Value,
						Players = Targets.Players.Enabled,
						NPCs = Targets.NPCs.Enabled,
						Wallcheck = Targets.Walls.Enabled,
						Sort = sortmethods[Sort.Value or 'Distance'],
						Origin = entitylib.isAlive and (shootpos or entitylib.character.RootPart.Position) or Vector3.zero,
					})
					if plr then
						local pos = shootpos or self:getLaunchPosition(origin)
						if not pos then
							return nextLaunch(...)
						end
						if (not OtherProjectiles.Enabled) and not projmeta.projectile:find('arrow') then
							return nextLaunch(...)
						end
						if table.find(Blacklist.ListEnabled or {}, ((projmeta.projectile == 'glue_trap' or projmeta.projectile == 'glue_projectile') and 'gloop' or projmeta.projectile)) then
							return nextLaunch(...)
						end
						local meta = projmeta:getProjectileMeta()
						local lifetime = (worldmeta and meta.predictionLifetimeSec or meta.lifetimeSec or 3)
						local gravity = (meta.gravitationalAcceleration or 196.2) * projmeta.gravityMultiplier
						local projSpeed = (meta.launchVelocity or 100)
						local offsetpos = pos + (projmeta.projectile == 'owl_projectile' and Vector3.zero or projmeta.fromPositionOffset)
						local balloons = plr.Character:GetAttribute('InflatedBalloons')
						local playerGravity = workspace.Gravity
						if balloons and balloons > 0 then
							playerGravity = (workspace.Gravity * (1 - (balloons >= 4 and 1.2 or balloons >= 3 and 1 or 0.975)))
						end
						if plr.Character.PrimaryPart:FindFirstChild('rbxassetid://8200754399') then
							playerGravity = 6
						end
						if plr.Player and plr.Player:GetAttribute('IsOwlTarget') then
							for _, owl in collectionService:GetTagged('Owl') do
								if owl:GetAttribute('Target') == plr.Player.UserId and owl:GetAttribute('Status') == 2 then
									playerGravity = 0
								end
							end
						end
						local draw = projmeta.drawDurationSeconds
						toclipboard(projmeta.projectile)
						if AutoCharge.Enabled then
							if projmeta.projectile:find('arrow') then
								draw = 0.58 * (AutoChargePerceft.Value / 100)
							elseif projmeta.projectile:find('frosty_snowball') then
								draw = 0.75 * (AutoChargePerceft.Value / 100)
							elseif projmeta.projectile:find('lasso') then
								draw = 0.02 * (AutoChargePerceft.Value / 100)
							end
						else
							draw = projmeta.drawDurationSeconds
						end
						local targetpos = getPosition(plr.Character) or plr[TargetPart.Value].Position
						local newlook = CFrame.new(offsetpos, targetpos) * CFrame.new(projmeta.projectile == 'owl_projectile' and Vector3.zero or Vector3.new(bedwars.BowConstantsTable.RelX, bedwars.BowConstantsTable.RelY, bedwars.BowConstantsTable.RelZ))
						local v = plr.RootPart.Velocity
						local newv = v:Lerp(plr.RootPart.Velocity, 0.5)
						pos = entitylib.character.RootPart.Position
						local ps = math.min(lplr:GetNetworkPing(), 0.5)
						if ps > 0.06 then
							targetpos = targetpos + (v * ps)
						end
						local calc = prediction.SolveTrajectory(newlook.p, projSpeed * Prediction.Value, gravity, targetpos, projmeta.projectile == 'telepearl' and Vector3.zero or newv, playerGravity, plr.HipHeight, plr.Jumping and 42.6 or nil, rayCheck)
						if calc then
							targetinfo.Targets[plr] = tick() + 1
							return {
								initialVelocity = CFrame.new(newlook.Position, calc).LookVector * (projSpeed * (AutoCharge.Enabled and 1 or projmeta.velocityMultiplier)),
								positionFrom = offsetpos,
								deltaT = lifetime,
								gravitationalAcceleration = gravity,
								drawDurationSeconds = draw
							}
						end
					end
					return nextLaunch(...)
				end)
				bedwars.BlockKickerKitController.getKickBlockProjectileOriginPosition = function(...)
					local origin, dir = select(2, ...)
					local plr = entitylib.EntityMouse({
						Part = 'RootPart',
						Range = FOV.Value,
						Players = Targets.Players.Enabled,
						NPCs = Targets.NPCs.Enabled,
						Wallcheck = Targets.Walls.Enabled,
						Sort = sortmethods[Sort.Value or 'Distance'],
						Origin = origin,
					})
					if plr then
						local calc = prediction.SolveTrajectory(origin, 100, 20, plr[TargetPart.Value].Position, plr.RootPart.Velocity, workspace.Gravity, plr.HipHeight, plr.Jumping and 42.6 or nil)
						if calc then
							for i, v in debug.getstack(2) do
								if v == dir then
									debug.setstack(2, i, CFrame.lookAt(origin, calc).LookVector)
								end
							end
						end
					end
					return oldd(...)
				end
			else
				bedwars.BlockKickerKitController.getKickBlockProjectileOriginPosition = oldd
				if launchHook then
					launchHook()
					launchHook = nil
				end
			end
		end,
		Tooltip = 'Silently adjusts your aim towards the enemy',
	})
	Targets = ProjectileAimbot:CreateTargets({
		Players = true,
		Walls = true,
	})
	TargetPart = ProjectileAimbot:CreateDropdown({
		Name = 'Part',
		List = {
			'RootPart',
			'Head',
			'Dynamic',
			'Closest'
		},
	})
	local methods = {
		'Damage',
		'Distance'
	}
	for i in sortmethods do
		if not table.find(methods, i) then
			table.insert(methods, i)
		end
	end
	Sort = ProjectileAimbot:CreateDropdown({
		Name = 'Target Mode',
		List = methods,
		Default = 'Distance',
	})
	Prediction = ProjectileAimbot:CreateSlider({
		Name = 'Prediction',
		Min = 0.1,
		Max = 2,
		Default = 1,
		Decimal = 10,
	})
	FOV = ProjectileAimbot:CreateSlider({
		Name = 'FOV',
		Min = 1,
		Max = 1000,
		Default = 1000,
	})
	AutoCharge = ProjectileAimbot:CreateToggle({
		Name = 'Auto Charge',
		Default = true,
		Tooltip = 'Fully charges your bow, Allowing your projectile to deal more damage',
		Function = function(callback)
			if AutoChargePerceft then
				AutoChargePerceft.Object.Visible = callback
			end
		end
	})
	AutoChargePerceft = ProjectileAimbot:CreateSlider({
		Name = 'Auto Charge Percect',
		Min = 0,
		Max = 100,
		Default = 100,
		Darker = true,
		Visible = AutoCharge.Enabled
	})
	OtherProjectiles = ProjectileAimbot:CreateToggle({
		Name = 'Other Projectiles',
		Default = true,
		Function = function(call)
			if Blacklist and Blacklist.Object then
				Blacklist.Object.Visible = call
			end
		end,
	})
	Blacklist = ProjectileAimbot:CreateTextList({
		Name = 'Blacklist',
		Default = {
			'gloop',
			'telepearl'
		},
		Darker = true,
		Placeholder = 'projectile',
	})
end)

run(function()
	local ProjectileAura
	local Targets
	local Range
	local List
	local rayCheck = RaycastParams.new()
	rayCheck.FilterType = Enum.RaycastFilterType.Include
	local projectileRemote = {
		InvokeServer = function()
		end
	}
	local FireDelays = {}
	task.spawn(function()
		projectileRemote = bedwars.Client:Get(remotes.FireProjectile).instance
	end)
	local function getAmmo(check)
		for _, item in store.inventory.inventory.items do
			if check.ammoItemTypes and table.find(check.ammoItemTypes, item.itemType) then
				return item.itemType
			end
		end
	end
	local function getProjectiles()
		local items = {}
		for _, item in store.inventory.inventory.items do
			local proj = bedwars.ItemMeta[item.itemType].projectileSource
			local ammo = proj and getAmmo(proj)
			if ammo and table.find(List.ListEnabled, ammo) then
				table.insert(items, {
					item,
					ammo,
					proj.projectileType(ammo),
					proj
				})
			end
		end
		return items
	end
	ProjectileAura = vape.Categories.Blatant:CreateModule({
		Name = 'Projectile Aura',
		Function = function(callback)
			if callback then
				repeat
					if (workspace:GetServerTimeNow() - bedwars.SwordController.lastAttack) > 0.5 then
						local ent = entitylib.EntityPosition({
							Part = 'RootPart',
							Range = Range.Value,
							Players = Targets.Players.Enabled,
							NPCs = Targets.NPCs.Enabled,
							Wallcheck = Targets.Walls.Enabled
						})
						if ent then
							local pos = entitylib.character.RootPart.Position
							for _, data in getProjectiles() do
								local item, ammo, projectile, itemMeta = unpack(data)
								if (FireDelays[item.itemType] or 0) < tick() then
									rayCheck.FilterDescendantsInstances = {
										workspace.Map
									}
									local meta = bedwars.ProjectileMeta[projectile]
									local projSpeed, gravity = meta.launchVelocity, meta.gravitationalAcceleration or 196.2
									local calc = prediction.SolveTrajectory(pos, projSpeed, gravity, ent.RootPart.Position, ent.RootPart.Velocity, workspace.Gravity, ent.HipHeight, ent.Jumping and 42.6 or nil, rayCheck)
									if calc then
										targetinfo.Targets[ent] = tick() + 1
										local switched = switchItem(item.tool)
										task.spawn(function()
											local dir, id = CFrame.lookAt(pos, calc).LookVector, httpService:GenerateGUID(true)
											local shootPosition = (CFrame.new(pos, calc) * CFrame.new(Vector3.new(- bedwars.BowConstantsTable.RelX, - bedwars.BowConstantsTable.RelY, - bedwars.BowConstantsTable.RelZ))).Position
											bedwars.ProjectileController:createLocalProjectile(meta, ammo, projectile, shootPosition, id, dir * projSpeed, {
												drawDurationSeconds = 1
											})
											local res = projectileRemote:InvokeServer(item.tool, ammo, projectile, shootPosition, pos, dir * projSpeed, id, {
												drawDurationSeconds = 1,
												shotId = httpService:GenerateGUID(false)
											}, workspace:GetServerTimeNow() - 0.045)
											if not res then
												FireDelays[item.itemType] = tick()
											else
												local shoot = itemMeta.launchSound
												shoot = shoot and shoot[math.random(1, # shoot)] or nil
												if shoot then
													bedwars.SoundManager:playSound(shoot)
												end
											end
										end)
										FireDelays[item.itemType] = tick() + itemMeta.fireDelaySec
										if switched then
											task.wait(0.05)
										end
									end
								end
							end
						end
					end
					task.wait(0.1)
				until not ProjectileAura.Enabled
			end
		end,
		Tooltip = 'Shoots people around you'
	})
	Targets = ProjectileAura:CreateTargets({
		Players = true,
		Walls = true
	})
	List = ProjectileAura:CreateTextList({
		Name = 'Projectiles',
		Default = {
			'arrow',
			'snowball'
		}
	})
	Range = ProjectileAura:CreateSlider({
		Name = 'Range',
		Min = 1,
		Max = 50,
		Default = 50,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
end)

run(function()
	local Speed
	local Value
	local WallCheck
	local AutoJump
	local AlwaysJump
	local rayCheck = RaycastParams.new()
	rayCheck.RespectCanCollide = true
	Speed = vape.Categories.Blatant:CreateModule({
		Name = 'Speed',
		Function = function(callback)
			frictionTable.Speed = callback or nil
			updateVelocity()
			pcall(function()
				debug.setconstant(bedwars.WindWalkerController.updateSpeed, 7, callback and 'constantSpeedMultiplier' or 'moveSpeedMultiplier')
			end)
			if callback then
				Speed:Clean(runService.PreSimulation:Connect(function(dt)
					bedwars.StatefulEntityKnockbackController.lastImpulseTime = callback and math.huge or time()
					if entitylib.isAlive and not Fly.Enabled and not InfiniteFly.Enabled and not LongJump.Enabled and isnetworkowner(entitylib.character.RootPart) then
						local state = entitylib.character.Humanoid:GetState()
						if state == Enum.HumanoidStateType.Climbing then
							return
						end
						local root, velo = entitylib.character.RootPart, getSpeed()
						local moveDirection = AntiFallDirection or entitylib.character.Humanoid.MoveDirection
						local destination = (moveDirection * math.max(Value.Value - velo, 0) * dt)
						if WallCheck.Enabled then
							rayCheck.FilterDescendantsInstances = {
								lplr.Character,
								gameCamera
							}
							rayCheck.CollisionGroup = root.CollisionGroup
							local ray = workspace:Raycast(root.Position, destination, rayCheck)
							if ray then
								destination = ((ray.Position + ray.Normal) - root.Position)
							end
						end
						root.CFrame += destination
						root.AssemblyLinearVelocity = (moveDirection * velo) + Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
						if AutoJump.Enabled and (state == Enum.HumanoidStateType.Running or state == Enum.HumanoidStateType.Landed) and moveDirection ~= Vector3.zero and (Attacking or AlwaysJump.Enabled) then
							entitylib.character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
						end
					end
				end))
			end
		end,
		ExtraText = function()
			return 'Heatseeker'
		end,
		Tooltip = 'Increases your movement with various methods.'
	})
	Value = Speed:CreateSlider({
		Name = 'Speed',
		Min = 1,
		Max = 23,
		Default = 23,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	WallCheck = Speed:CreateToggle({
		Name = 'Wall Check',
		Default = true
	})
	AutoJump = Speed:CreateToggle({
		Name = 'AutoJump',
		Function = function(callback)
			AlwaysJump.Object.Visible = callback
		end
	})
	AlwaysJump = Speed:CreateToggle({
		Name = 'Always Jump',
		Visible = false,
		Darker = true
	})
end)

--[[
	Render
]]--

run(function()
	local BedESP
	local Reference = {}
	local Folder = Instance.new('Folder')
	Folder.Parent = vape.gui
	local function Added(bed)
		if not BedESP.Enabled then
			return
		end
		local BedFolder = Instance.new('Folder')
		BedFolder.Parent = Folder
		Reference[bed] = BedFolder
		local parts = bed:GetChildren()
		table.sort(parts, function(a, b)
			return a.Name > b.Name
		end)
		for _, part in parts do
			if part:IsA('BasePart') and part.Name ~= 'Blanket' then
				local handle = Instance.new('BoxHandleAdornment')
				handle.Size = part.Size + Vector3.new(.01, .01, .01)
				handle.AlwaysOnTop = true
				handle.ZIndex = 2
				handle.Visible = true
				handle.Adornee = part
				handle.Color3 = part.Color
				if part.Name == 'Legs' then
					handle.Color3 = Color3.fromRGB(167, 112, 64)
					handle.Size = part.Size + Vector3.new(.01, - 1, .01)
					handle.CFrame = CFrame.new(0, - 0.4, 0)
					handle.ZIndex = 0
				end
				handle.Parent = BedFolder
			end
		end
		table.clear(parts)
	end
	BedESP = vape.Categories.Render:CreateModule({
		Name = 'Bed ESP',
		Function = function(callback)
			if callback then
				BedESP:Clean(collectionService:GetInstanceAddedSignal('bed'):Connect(function(bed)
					task.delay(0.2, Added, bed)
				end))
				BedESP:Clean(collectionService:GetInstanceRemovedSignal('bed'):Connect(function(bed)
					if Reference[bed] then
						Reference[bed]:Destroy()
						Reference[bed] = nil
					end
				end))
				for _, bed in collectionService:GetTagged('bed') do
					Added(bed)
				end
			else
				Folder:ClearAllChildren()
				table.clear(Reference)
			end
		end,
		Tooltip = 'Render Beds through walls'
	})
end)

run(function()
	local Health
	Health = vape.Categories.Render:CreateModule({
		Name = 'Health',
		Function = function(callback)
			if callback then
				local label = Instance.new('TextLabel')
				label.Size = UDim2.fromOffset(100, 20)
				label.Position = UDim2.new(0.5, 6, 0.5, 30)
				label.BackgroundTransparency = 1
				label.AnchorPoint = Vector2.new(0.5, 0)
				label.Text = entitylib.isAlive and math.round(lplr.Character:GetAttribute('Health')) .. ' ❤️' or ''
				label.TextColor3 = entitylib.isAlive and Color3.fromHSV((lplr.Character:GetAttribute('Health') / lplr.Character:GetAttribute('MaxHealth')) / 2.8, 0.86, 1) or Color3.new()
				label.TextSize = 18
				label.Font = Enum.Font.Arial
				label.Parent = vape.gui
				Health:Clean(label)
				Health:Clean(vapeEvents.AttributeChanged.Event:Connect(function()
					label.Text = entitylib.isAlive and math.round(lplr.Character:GetAttribute('Health')) .. ' ❤️' or ''
					label.TextColor3 = entitylib.isAlive and Color3.fromHSV((lplr.Character:GetAttribute('Health') / lplr.Character:GetAttribute('MaxHealth')) / 2.8, 0.86, 1) or Color3.new()
				end))
			end
		end,
		Tooltip = 'Displays your health in the center of your screen.'
	})
end)

run(function()
    local NameTags
    local Targets
    local Color
    local Background
    local DisplayName
    local Health
    local Distance
    local Equipment
    local Rank
    local Enchant
    local DrawingToggle
    local Scale
    local FontOption
    local Teammates
    local DistanceCheck
    local DistanceLimit
    local Strings, Sizes, Reference = {}, {}, {}
    local Folder = Instance.new('Folder')
    Folder.Parent = vape.gui
    local methodused

    local Added = {
    	Normal = function(ent)
    		if not Targets.Players.Enabled and ent.Player then
    			return
    		end
    		if not Targets.NPCs.Enabled and ent.NPC then
    			return
    		end
    		if Teammates.Enabled and not ent.Targetable and not ent.Friend then
    			return
    		end

    		local nametag = Instance.new('TextLabel')
    		Strings[ent] = ent.Player
    				and whitelist:tag(ent.Player, true, true) .. (DisplayName.Enabled and ent.Player.DisplayName or ent.Player.Name)
    			or ent.Character.Name

    		if Health.Enabled then
    			local healthColor = Color3.fromHSV(math.clamp(ent.Health / ent.MaxHealth, 0, 1) / 2.5, 0.89, 0.75)
    			Strings[ent] = Strings[ent]
    				.. ' <font color="rgb('
    				.. tostring(math.floor(healthColor.R * 255))
    				.. ','
    				.. tostring(math.floor(healthColor.G * 255))
    				.. ','
    				.. tostring(math.floor(healthColor.B * 255))
    				.. ')">'
    				.. math.round(ent.Health)
    				.. '</font>'
    		end

    		if Distance.Enabled then
    			Strings[ent] = '<font color="rgb(85, 255, 85)">[</font><font color="rgb(255, 255, 255)">%s</font><font color="rgb(85, 255, 85)">]</font> '
    				.. Strings[ent]
    		end

    		if Equipment.Enabled then
    			for i, v in {'Hand', 'Helmet', 'Chestplate', 'Boots', 'Kit'} do
    				local Icon = Instance.new('ImageLabel')
    				Icon.Name = v
    				Icon.Size = UDim2.fromOffset(30, 30)
    				Icon.Position = UDim2.fromOffset(-60 + (i * 30), -30)
    				Icon.BackgroundTransparency = 1
    				Icon.Image = ''
    				Icon.Parent = nametag
    			end
    		end

    		nametag.TextSize = 14 * Scale.Value
    		nametag.FontFace = FontOption.Value
    		local size =
    			getfontsize(removeTags(Strings[ent]), nametag.TextSize, nametag.FontFace, Vector2.new(100000, 100000))
    		nametag.Name = ent.Player and ent.Player.Name or ent.Character.Name
    		nametag.Size = UDim2.fromOffset(size.X + 8, size.Y + 7)
    		nametag.AnchorPoint = Vector2.new(0.5, 1)
    		nametag.BackgroundColor3 = Color3.new()
    		nametag.BackgroundTransparency = Background.Value
    		nametag.BorderSizePixel = 0
    		nametag.Visible = false
    		nametag.Text = Strings[ent]
    		nametag.TextColor3 = entitylib.getEntityColor(ent) or Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
    		nametag.RichText = true
    		nametag.Parent = Folder
    		task.spawn(function()
    			if Rank.Enabled and ent.Player then
    				local Icon = Instance.new('ImageLabel')
    				Icon.Name = 'RankIcon'
    				Icon.Size = UDim2.fromOffset(30, 30)
    				Icon.Position = UDim2.fromOffset(size.X + 10, -4)
    				Icon.BackgroundTransparency = 1
    				Icon.Image = store.ranks[ent.Player]:async() and bedwars.RankMeta[store.ranks[ent.Player]:async()].image
    					or ''
    				Icon.Parent = nametag
    			end
    		end)
    		task.spawn(function()
    			if Enchant.Enabled and ent.Player then
    				local Icon = Instance.new('ImageLabel')
    				Icon.Name = 'EnchantIcon'
    				Icon.Size = UDim2.fromOffset(30, 30)
    				Icon.Position = UDim2.fromOffset(-30, -4)
    				Icon.BackgroundTransparency = 1
    				Icon.Image = store.enchants[ent.Player]:async() or ''
    				Icon.Parent = nametag
    			end
    		end)
    		Reference[ent] = nametag
    	end,
    	Drawing = function(ent)
    		if not Targets.Players.Enabled and ent.Player then
    			return
    		end
    		if not Targets.NPCs.Enabled and ent.NPC then
    			return
    		end
    		if Teammates.Enabled and not ent.Targetable and not ent.Friend then
    			return
    		end

    		local nametag = {}
    		nametag.BG = Drawing.new('Square')
    		nametag.BG.Filled = true
    		nametag.BG.Transparency = 1 - Background.Value
    		nametag.BG.Color = Color3.new()
    		nametag.BG.ZIndex = 1
    		nametag.Text = Drawing.new('Text')
    		nametag.Text.Size = 15 * Scale.Value
    		nametag.Text.Font = 0
    		nametag.Text.ZIndex = 2
    		Strings[ent] = ent.Player
    				and whitelist:tag(ent.Player, true) .. (DisplayName.Enabled and ent.Player.DisplayName or ent.Player.Name)
    			or ent.Character.Name

    		if Health.Enabled then
    			Strings[ent] = Strings[ent] .. ' ' .. math.round(ent.Health)
    		end

    		if Distance.Enabled then
    			Strings[ent] = '[%s] ' .. Strings[ent]
    		end

    		nametag.Text.Text = Strings[ent]
    		nametag.Text.Color = entitylib.getEntityColor(ent) or Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
    		nametag.BG.Size = Vector2.new(nametag.Text.TextBounds.X + 8, nametag.Text.TextBounds.Y + 7)
    		Reference[ent] = nametag
    	end,
    }

    local Removed = {
    	Normal = function(ent)
    		local v = Reference[ent]
    		if v then
    			Reference[ent] = nil
    			Strings[ent] = nil
    			Sizes[ent] = nil
    			v:Destroy()
    		end
    	end,
    	Drawing = function(ent)
    		local v = Reference[ent]
    		if v then
    			Reference[ent] = nil
    			Strings[ent] = nil
    			Sizes[ent] = nil
    			for _, obj in v do
    				pcall(function()
    					obj.Visible = false
    					obj:Remove()
    				end)
    			end
    		end
    	end,
    }

    local Updated = {
    	Normal = function(ent)
    		local nametag = Reference[ent]
    		if nametag then
    			Sizes[ent] = nil
    			Strings[ent] = ent.Player
    					and whitelist:tag(ent.Player, true, true) .. (DisplayName.Enabled and ent.Player.DisplayName or ent.Player.Name)
    				or ent.Character.Name

    			if Health.Enabled then
    				local healthColor = Color3.fromHSV(math.clamp(ent.Health / ent.MaxHealth, 0, 1) / 2.5, 0.89, 0.75)
    				Strings[ent] = Strings[ent]
    					.. ' <font color="rgb('
    					.. tostring(math.floor(healthColor.R * 255))
    					.. ','
    					.. tostring(math.floor(healthColor.G * 255))
    					.. ','
    					.. tostring(math.floor(healthColor.B * 255))
    					.. ')">'
    					.. math.round(ent.Health)
    					.. '</font>'
    			end

    			if Distance.Enabled then
    				Strings[ent] = '<font color="rgb(85, 255, 85)">[</font><font color="rgb(255, 255, 255)">%s</font><font color="rgb(85, 255, 85)">]</font> '
    					.. Strings[ent]
    			end

    			if Equipment.Enabled and store.inventories[ent.Player] then
    				local kit = ent.Player:GetAttribute('PlayingAsKit')
    				local inventory = store.inventories[ent.Player]
    				nametag.Hand.Image = bedwars.getIcon(inventory.hand or {itemType = ''}, true)
    				nametag.Helmet.Image = bedwars.getIcon(inventory.armor[4] or {itemType = ''}, true)
    				nametag.Chestplate.Image = bedwars.getIcon(inventory.armor[5] or {itemType = ''}, true)
    				nametag.Boots.Image = bedwars.getIcon(inventory.armor[6] or {itemType = ''}, true)
    				nametag.Kit.Image = kit and bedwars.BedwarsKitMeta[kit].renderImage or ''
    			end

    			if Enchant.Enabled and nametag:FindFirstChild('EnchantIcon') then
    				nametag.EnchantIcon.Image = store.enchants[ent.Player]:async() or ''
    			end

    			local size = getfontsize(removeTags(Strings[ent]), nametag.TextSize, nametag.FontFace, Vector2.new(100000, 100000))
    			nametag.Size = UDim2.fromOffset(size.X + 8, size.Y + 7)
    			nametag.Text = Strings[ent]
    		end
    	end,
    	Drawing = function(ent)
    		local nametag = Reference[ent]
    		if nametag then
    			if vape.ThreadFix then
    				setthreadidentity(8)
    			end
    			Sizes[ent] = nil
    			Strings[ent] = ent.Player
    					and whitelist:tag(ent.Player, true) .. (DisplayName.Enabled and ent.Player.DisplayName or ent.Player.Name)
    				or ent.Character.Name

    			if Health.Enabled then
    				Strings[ent] = Strings[ent] .. ' ' .. math.round(ent.Health)
    			end

    			if Distance.Enabled then
    				Strings[ent] = '[%s] ' .. Strings[ent]
    				nametag.Text.Text = entitylib.isAlive and string.format(Strings[ent], math.floor((entitylib.character.RootPart.Position - ent.RootPart.Position).Magnitude)) or Strings[ent]
    			else
    				nametag.Text.Text = Strings[ent]
    			end

    			nametag.BG.Size = Vector2.new(nametag.Text.TextBounds.X + 8, nametag.Text.TextBounds.Y + 7)
    			nametag.Text.Color = entitylib.getEntityColor(ent) or Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
    		end
    	end,
    }

    local ColorFunc = {
    	Normal = function(hue, sat, val)
    		local color = Color3.fromHSV(hue, sat, val)
    		for i, v in Reference do
    			v.TextColor3 = entitylib.getEntityColor(i) or color
    		end
    	end,
    	Drawing = function(hue, sat, val)
    		local color = Color3.fromHSV(hue, sat, val)
    		for i, v in Reference do
    			v.Text.Color = entitylib.getEntityColor(i) or color
    		end
    	end,
    }

    local Loop = {
    	Normal = function()
    		local alive = entitylib.isAlive
    		local localPosition = alive and entitylib.character.RootPart.Position
    		for ent, nametag in Reference do
    			local distance
    			if alive and (DistanceCheck.Enabled or Distance.Enabled) then
    				distance = (localPosition - ent.RootPart.Position).Magnitude
    			end

    			if DistanceCheck.Enabled then
    				distance = distance or math.huge
    				if distance < DistanceLimit.ValueMin or distance > DistanceLimit.ValueMax then
    					nametag.Visible = false
    					continue
    				end
    			end

    			local headPos, headVis = gameCamera:WorldToViewportPoint(ent.RootPart.Position + Vector3.new(0, ent.HipHeight + 1, 0))
    			nametag.Visible = headVis
    			if not headVis then
    				continue
    			end

    			if Distance.Enabled then
    				local mag = alive and math.floor(distance) or 0
    				if Sizes[ent] ~= mag then
    					nametag.Text = string.format(Strings[ent], mag)
    					local ize = getfontsize(
    						removeTags(nametag.Text),
    						nametag.TextSize,
    						nametag.FontFace,
    						Vector2.new(100000, 100000)
    					)
    					nametag.Size = UDim2.fromOffset(ize.X + 8, ize.Y + 7)
    					Sizes[ent] = mag
    				end
    			end
    			nametag.Position = UDim2.fromOffset(headPos.X, headPos.Y)
    		end
    	end,
    	Drawing = function()
    		local alive = entitylib.isAlive
    		local localPosition = alive and entitylib.character.RootPart.Position
    		for ent, nametag in Reference do
    			local distance
    			if alive and (DistanceCheck.Enabled or Distance.Enabled) then
    				distance = (localPosition - ent.RootPart.Position).Magnitude
    			end

    			if DistanceCheck.Enabled then
    				distance = distance or math.huge
    				if distance < DistanceLimit.ValueMin or distance > DistanceLimit.ValueMax then
    					nametag.Text.Visible = false
    					nametag.BG.Visible = false
    					continue
    				end
    			end

    			local headPos, headVis = gameCamera:WorldToViewportPoint(ent.RootPart.Position + Vector3.new(0, ent.HipHeight + 1, 0))
    			nametag.Text.Visible = headVis
    			nametag.BG.Visible = headVis
    			if not headVis then
    				continue
    			end

    			if Distance.Enabled then
    				local mag = alive and math.floor(distance) or 0
    				if Sizes[ent] ~= mag then
    					nametag.Text.Text = string.format(Strings[ent], mag)
    					nametag.BG.Size = Vector2.new(nametag.Text.TextBounds.X + 8, nametag.Text.TextBounds.Y + 7)
    					Sizes[ent] = mag
    				end
    			end
    			nametag.BG.Position = Vector2.new(headPos.X - (nametag.BG.Size.X / 2), headPos.Y - nametag.BG.Size.Y)
    			nametag.Text.Position = nametag.BG.Position + Vector2.new(4, 3)
    		end
    	end,
    }

    NameTags = vape.Categories.Render:CreateModule({
    	Name = 'Name Tags',
    	Function = function(callback)
    		if callback then
    			methodused = DrawingToggle.Enabled and 'Drawing' or 'Normal'
    			if Removed[methodused] then
    				NameTags:Clean(entitylib.Events.EntityRemoved:Connect(Removed[methodused]))
    			end
    			if Added[methodused] then
    				for _, v in entitylib.List do
    					if Reference[v] then
    						Removed[methodused](v)
    					end
    					Added[methodused](v)
    				end
    				NameTags:Clean(entitylib.Events.EntityAdded:Connect(function(ent)
    					if Reference[ent] then
    						Removed[methodused](ent)
    					end
    					Added[methodused](ent)
    				end))
    			end
    			if Updated[methodused] then
    				NameTags:Clean(entitylib.Events.EntityUpdated:Connect(Updated[methodused]))
    				for _, v in entitylib.List do
    					Updated[methodused](v)
    				end
    			end
    			if ColorFunc[methodused] then
    				NameTags:Clean(vape.Categories.Friends.ColorUpdate.Event:Connect(function()
    					ColorFunc[methodused](Color.Hue, Color.Sat, Color.Value)
    				end))
    			end
    			if Loop[methodused] then
    				NameTags:Clean(runService.RenderStepped:Connect(Loop[methodused]))
    			end
    		else
    			if Removed[methodused] then
    				for i in Reference do
    					Removed[methodused](i)
    				end
    			end
    		end
    	end,
    	Tooltip = 'Renders nametags on entities through walls.'
    })
    Targets = NameTags:CreateTargets({
    	Players = true,
    	Function = function()
    		if NameTags.Enabled then
    			NameTags:Toggle()
    			NameTags:Toggle()
    		end
    	end,
    })
    FontOption = NameTags:CreateFont({
    	Name = 'Font',
    	Blacklist = 'Arial',
    	Function = function()
    		if NameTags.Enabled then
    			NameTags:Toggle()
    			NameTags:Toggle()
    		end
    	end,
    })
    Color = NameTags:CreateColorSlider({
    	Name = 'Player Color',
    	Function = function(hue, sat, val)
    		if NameTags.Enabled and ColorFunc[methodused] then
    			ColorFunc[methodused](hue, sat, val)
    		end
    	end,
    })
    Scale = NameTags:CreateSlider({
    	Name = 'Scale',
    	Function = function()
    		if NameTags.Enabled then
    			NameTags:Toggle()
    			NameTags:Toggle()
    		end
    	end,
    	Default = 1,
    	Min = 0.1,
    	Max = 1.5,
    	Decimal = 10,
    })
    Background = NameTags:CreateSlider({
    	Name = 'Transparency',
    	Function = function()
    		if NameTags.Enabled then
    			NameTags:Toggle()
    			NameTags:Toggle()
    		end
    	end,
    	Default = 0.5,
    	Min = 0,
    	Max = 1,
    	Decimal = 10,
    })
    Health = NameTags:CreateToggle({
    	Name = 'Health',
    	Function = function()
    		if NameTags.Enabled then
    			NameTags:Toggle()
    			NameTags:Toggle()
    		end
    	end,
    })
    Distance = NameTags:CreateToggle({
    	Name = 'Distance',
    	Function = function()
    		if NameTags.Enabled then
    			NameTags:Toggle()
    			NameTags:Toggle()
    		end
    	end,
    })
    Rank = NameTags:CreateToggle({
    	Name = 'Rank',
    	Tooltip = "Displays player's rank",
    })
    Enchant = NameTags:CreateToggle({
    	Name = 'Enchant',
    	Tooltip = "Displays player's enchant",
    	Default = true,
    })
    Equipment = NameTags:CreateToggle({
    	Name = 'Equipment',
    	Function = function()
    		if NameTags.Enabled then
    			NameTags:Toggle()
    			NameTags:Toggle()
    		end
    	end,
    })
    DisplayName = NameTags:CreateToggle({
    	Name = 'Use Displayname',
    	Function = function()
    		if NameTags.Enabled then
    			NameTags:Toggle()
    			NameTags:Toggle()
    		end
    	end,
    	Default = true,
    })
    Teammates = NameTags:CreateToggle({
    	Name = 'Priority Only',
    	Function = function()
    		if NameTags.Enabled then
    			NameTags:Toggle()
    			NameTags:Toggle()
    		end
    	end,
    	Default = true,
    })
    DrawingToggle = NameTags:CreateToggle({
    	Name = 'Drawing',
    	Function = function()
    		if NameTags.Enabled then
    			NameTags:Toggle()
    			NameTags:Toggle()
    		end
    	end,
    })
    DistanceCheck = NameTags:CreateToggle({
    	Name = 'Distance Check',
    	Function = function(callback)
    		DistanceLimit.Object.Visible = callback
    	end,
    })
    DistanceLimit = NameTags:CreateTwoSlider({
    	Name = 'Player Distance',
    	Min = 0,
    	Max = 256,
    	DefaultMin = 0,
    	DefaultMax = 64,
    	Darker = true,
    	Visible = false,
    })
end)

run(function()
	local StorageESP
	local List
	local Background
	local Color = {}
	local Reference = {}
	local Folder = Instance.new('Folder')
	Folder.Parent = vape.gui
	local function nearStorageItem(item)
		for _, v in List.ListEnabled do
			if item:find(v) then
				return v
			end
		end
	end
	local function refreshAdornee(v)
		local chest = v.Adornee:FindFirstChild('ChestFolderValue')
		chest = chest and chest.Value or nil
		if not chest then
			v.Enabled = false
			return
		end
		local chestitems = chest and chest:GetChildren() or {}
		for _, obj in v.Frame:GetChildren() do
			if obj:IsA('ImageLabel') and obj.Name ~= 'Blur' then
				obj:Destroy()
			end
		end
		v.Enabled = false
		local alreadygot = {}
		for _, item in chestitems do
			if not alreadygot[item.Name] and (table.find(List.ListEnabled, item.Name) or nearStorageItem(item.Name)) then
				alreadygot[item.Name] = true
				v.Enabled = true
				local blockimage = Instance.new('ImageLabel')
				blockimage.Size = UDim2.fromOffset(32, 32)
				blockimage.BackgroundTransparency = 1
				blockimage.Image = bedwars.getIcon({
					itemType = item.Name
				}, true)
				blockimage.Parent = v.Frame
			end
		end
		table.clear(chestitems)
	end
	local function Added(v)
		local chest = v:WaitForChild('ChestFolderValue', 3)
		if not (chest and StorageESP.Enabled) then
			return
		end
		chest = chest.Value
		local billboard = Instance.new('BillboardGui')
		billboard.Parent = Folder
		billboard.Name = 'chest'
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
		billboard.Size = UDim2.fromOffset(36, 36)
		billboard.AlwaysOnTop = true
		billboard.ClipsDescendants = false
		billboard.Adornee = v
		local blur = addBlur(billboard)
		blur.Visible = Background.Enabled
		local frame = Instance.new('Frame')
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
		frame.BackgroundTransparency = 1 - (Background.Enabled and Color.Opacity or 0)
		frame.Parent = billboard
		local layout = Instance.new('UIListLayout')
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.Padding = UDim.new(0, 4)
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
			billboard.Size = UDim2.fromOffset(math.max(layout.AbsoluteContentSize.X + 4, 36), 36)
		end)
		layout.Parent = frame
		local corner = Instance.new('UICorner')
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = frame
		Reference[v] = billboard
		StorageESP:Clean(chest.ChildAdded:Connect(function(item)
			if table.find(List.ListEnabled, item.Name) or nearStorageItem(item.Name) then
				refreshAdornee(billboard)
			end
		end))
		StorageESP:Clean(chest.ChildRemoved:Connect(function(item)
			if table.find(List.ListEnabled, item.Name) or nearStorageItem(item.Name) then
				refreshAdornee(billboard)
			end
		end))
		task.spawn(refreshAdornee, billboard)
	end
	StorageESP = vape.Categories.Render:CreateModule({
		Name = 'Storage ESP',
		Function = function(callback)
			if callback then
				StorageESP:Clean(collectionService:GetInstanceAddedSignal('chest'):Connect(Added))
				for _, v in collectionService:GetTagged('chest') do
					task.spawn(Added, v)
				end
			else
				table.clear(Reference)
				Folder:ClearAllChildren()
			end
		end,
		Tooltip = 'Displays items in chests'
	})
	List = StorageESP:CreateTextList({
		Name = 'Item',
		Function = function()
			for _, v in Reference do
				task.spawn(refreshAdornee, v)
			end
		end
	})
	Background = StorageESP:CreateToggle({
		Name = 'Background',
		Function = function(callback)
			if Color.Object then
				Color.Object.Visible = callback
			end
			for _, v in Reference do
				v.Frame.BackgroundTransparency = 1 - (callback and Color.Opacity or 0)
				v.Blur.Visible = callback
			end
		end,
		Default = true
	})
	Color = StorageESP:CreateColorSlider({
		Name = 'Background Color',
		DefaultValue = 0,
		DefaultOpacity = 0.5,
		Function = function(hue, sat, val, opacity)
			for _, v in Reference do
				v.Frame.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
				v.Frame.BackgroundTransparency = 1 - opacity
			end
		end,
		Darker = true
	})
end)

run(function()
	local ClientPack
	local Players = playersService
	local RunService = runService
	local LocalPlayer = Players.LocalPlayer
	local RS = replicatedStorage
	local CURRENT_ITEM_SKIN = "Victorious Lyla"
	local CURRENT_SKIN_TYPE = "Nightmare"
	local ok1, ItemType = pcall(function()
		return require(RS.TS.item["item-type"]).ItemType
	end)
	if not ok1 then
		ItemType = {}
	end
	local ok2, ItemSkinType = pcall(function()
		return
	end)
	if not ok2 then
		ItemSkinType = {}
	end
	local KitSkinCtrl
	pcall(function()
		local KC = require(RS.rbxts_include.node_modules["@easy-games"].knit.src).KnitClient
		KitSkinCtrl = bedwars.KitSkinController
	end)
	local BOW_ROT = CFrame.Angles(0, math.rad(- 90), 0)
	local CROSSBOW_ROT = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(- 360), 0)
	local LUNAR_CROSSBOW_ROT = CFrame.new(0, 0, 0) * CFrame.Angles(0, - 190, math.rad(- 180))
	local VICTORIOUS_ARCHER_BOW_ROT = CFrame.new(0, 0, 0) * CFrame.Angles(0, - 52, math.rad(90))
	local VICTORIOUS_ARCHER_CROSSBOW_ROT = CFrame.new(0, 0, 0) * CFrame.Angles(0, - 190, math.rad(- 180))
	local VICTORIOUS_ARCHER_HEADHUNTER_ROT = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(180), 0)
	local HEADHUNTER_ROT = CFrame.new(0.4, 0, 0) * CFrame.Angles(0, math.rad(360), 0)
	local AXE_ROT = CFrame.new(0, 0, - 0.4) * CFrame.Angles(0, math.rad(90), 0)
	local PICKAXE_ROT = CFrame.new(0, 0, - 0.1) * CFrame.Angles(0, math.rad(110), 0)
	local LASSO_ROT = CFrame.Angles(0, math.rad(90), 0)
	local STAFF_ROT = CFrame.Angles(0, math.rad(90), 0)
	local SWORD_ROT = CFrame.new(0, - 1.7, 0) * CFrame.Angles(0, math.rad(- 180), 0)
	local HEARTBEAM_SWORD_ROT = CFrame.new(0, - 1.2, 0) * CFrame.Angles(0, math.rad(0), 0)
	local LIFE_BOW_ROT = CFrame.Angles(0, math.rad(- 20), 0)
	local DAO_ROT = CFrame.new(0, - 1.7, 0) * CFrame.Angles(0, math.rad(- 180), 0)
	local VIC_ROT = CFrame.new(0, - 1.9, 0) * CFrame.Angles(0, math.rad(360), 0)
	local HEXED_DAO_ROT = CFrame.new(0, 0, 0) * CFrame.Angles(0, 160, math.rad(- 180))
	local SNOW_DAO_ROT = CFrame.new(- 0.2, - 0.9, 0) * CFrame.Angles(0, math.rad(- 180), 0)
	local HARPOON_ROT = CFrame.new(0, - 1.4, - 0.15) * CFrame.Angles(0, math.rad(180), 0)
	local TRIDENT_ROT = CFrame.new(0, 0.5, 0.05) * CFrame.Angles(0, math.rad(180), 0)
	local LYLA_BOW_ROT = CFrame.new(0, 0, 0) * CFrame.Angles(30, - 30, 183.56)
	local LYLA_CROSSBOW_ROT = CFrame.Angles(math.rad(0), math.rad(180), math.rad(0))
	local LYLA_HEADHUNTER_ROT = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(0), 0)
	local CANNON_HAND_SCALE = 0.34
	local CANNON_PLACED_OFFSET = CFrame.new(0, - 1.0, 0)
	local CANNON_TOOL_NAME = "cannon"
	local CANNON_SKIN_NAMES = {
		["Victorious Cannon"] = {
			Gold = "cannon_gold_victorious",
			Platinum = "cannon_platinum_victorious",
			Diamond = "cannon_diamond_victorious",
			Emerald = "cannon_emerald_victorious",
			Nightmare = "cannon_nightmare_victorious",
		},
		["Ghost Cannon"] = {
			Default = "cannon_ghost"
		},
		["Deep Sea Cannon"] = {
			Default = "cannon_deepsea"
		},
	}
	local CANNON_SOUND_NAMES = {
		Gold = "CANNON_FIRE_VICTORIOUS_GOLD",
		Platinum = "CANNON_FIRE_VICTORIOUS_PLATINUM",
		Diamond = "CANNON_FIRE_VICTORIOUS_DIAMOND",
		Emerald = "CANNON_FIRE_VICTORIOUS_EMERALD",
		Nightmare = "CANNON_FIRE_VICTORIOUS_NIGHTMARE",
	}
	local ELDER_ORBS_SOUND_NAMES = {
		Gold = "ELDERTREE_VICTORIOUS_GOLD_PICKUP",
		Platinum = "ELDERTREE_VICTORIOUS_PLATINUM_PICKUP",
		Diamond = "ELDERTREE_VICTORIOUS_DIAMOND_PICKUP",
		Emerald = "ELDERTREE_VICTORIOUS_EMERALD_PICKUP",
		Nightmare = 'ELDERTREE_VICTORIOUS_NIGHTMARE_PICKUP'
	}
	local ELDER_ORBS_SKINS_NAME = {
		["Victorious Orb"] = {
			Gold = "GoldTreeOrb",
			Platinum = "PlatinumTreeOrb",
			Diamond = "DiamondTreeOrb",
			Emerald = "EmeraldTreeOrb",
			Nightmare = "NightmareTreeOrb",
		},
	}
	local SKIN_OFFSETS = {
		["nightmare_victorious_flower_bow"] = LYLA_BOW_ROT,
		["emerald_victorious_flower_bow"] = LYLA_BOW_ROT,
		["diamond_victorious_flower_bow"] = LYLA_BOW_ROT,
		["platinum_victorious_flower_bow"] = LYLA_BOW_ROT,
		["gold_victorious_flower_bow"] = LYLA_BOW_ROT,
		["nightmare_victorious_flower_crossbow"] = LYLA_CROSSBOW_ROT,
		["emerald_victorious_flower_crossbow"] = LYLA_CROSSBOW_ROT,
		["diamond_victorious_flower_crossbow"] = LYLA_CROSSBOW_ROT,
		["platinum_victorious_flower_crossbow"] = LYLA_CROSSBOW_ROT,
		["gold_victorious_flower_crossbow"] = LYLA_CROSSBOW_ROT,
		["nightmare_victorious_flower_headhunter"] = LYLA_HEADHUNTER_ROT,
		["emerald_victorious_flower_headhunter"] = LYLA_HEADHUNTER_ROT,
		["diamond_victorious_flower_headhunter"] = LYLA_HEADHUNTER_ROT,
		["platinum_victorious_flower_headhunter"] = LYLA_HEADHUNTER_ROT,
		["gold_victorious_flower_headhunter"] = LYLA_HEADHUNTER_ROT,
		["tactical_headhunter_victorious_nightmare"] = VICTORIOUS_ARCHER_HEADHUNTER_ROT,
		["tactical_headhunter_victorious_emerald"] = VICTORIOUS_ARCHER_HEADHUNTER_ROT,
		["tactical_headhunter_victorious_diamond"] = VICTORIOUS_ARCHER_HEADHUNTER_ROT,
		["tactical_headhunter_victorious_platinum"] = VICTORIOUS_ARCHER_HEADHUNTER_ROT,
		["tactical_headhunter_victorious_gold"] = VICTORIOUS_ARCHER_HEADHUNTER_ROT,
		["flower_bow_frost_queen"] = BOW_ROT,
		["tactical_crossbow_lunar_dragon"] = LUNAR_CROSSBOW_ROT,
		["life_bow_mummy"] = LIFE_BOW_ROT,
		["flower_headhunter_frost_queen"] = HEADHUNTER_ROT,
		["wood_sword_darkvalentine"] = SWORD_ROT,
		["stone_sword_darkvalentine"] = SWORD_ROT,
		["iron_sword_darkvalentine"] = SWORD_ROT,
		["diamond_sword_darkvalentine"] = SWORD_ROT,
		["emerald_sword_darkvalentine"] = SWORD_ROT,
		["wood_sword_heartbeam"] = HEARTBEAM_SWORD_ROT,
		["stone_sword_heartbeam"] = HEARTBEAM_SWORD_ROT,
		["iron_sword_heartbeam"] = HEARTBEAM_SWORD_ROT,
		["diamond_sword_heartbeam"] = HEARTBEAM_SWORD_ROT,
		["emerald_sword_heartbeam"] = HEARTBEAM_SWORD_ROT,
		["wood_bow_victorious_nightmare"] = VICTORIOUS_ARCHER_BOW_ROT,
		["wood_bow_victorious_emerald"] = VICTORIOUS_ARCHER_BOW_ROT,
		["wood_bow_victorious_diamond"] = VICTORIOUS_ARCHER_BOW_ROT,
		["wood_bow_victorious_platinum"] = VICTORIOUS_ARCHER_BOW_ROT,
		["wood_bow_victorious_gold"] = VICTORIOUS_ARCHER_BOW_ROT,
		["tactical_crossbow_victorious_nightmare"] = VICTORIOUS_ARCHER_CROSSBOW_ROT,
		["tactical_crossbow_victorious_emerald"] = VICTORIOUS_ARCHER_CROSSBOW_ROT,
		["tactical_crossbow_victorious_diamond"] = VICTORIOUS_ARCHER_CROSSBOW_ROT,
		["tactical_crossbow_victorious_platinum"] = VICTORIOUS_ARCHER_CROSSBOW_ROT,
		["tactical_crossbow_victorious_gold"] = VICTORIOUS_ARCHER_CROSSBOW_ROT,
		["life_crossbow_mummy"] = CROSSBOW_ROT,
		["life_headhunter_mummy"] = HEADHUNTER_ROT,
		["victorious_gold_triton"] = TRIDENT_ROT,
		["victorious_platinum_triton"] = TRIDENT_ROT,
		["victorious_diamond_triton"] = TRIDENT_ROT,
		["victorious_emerald_triton"] = TRIDENT_ROT,
		["victorious_nightmare_triton"] = TRIDENT_ROT,
		["demon_triton"] = HARPOON_ROT,
		["lasso_mummy"] = LASSO_ROT,
		["lasso_wrangler_reindeer_lassy"] = LASSO_ROT,
		["lasso_lifeguard"] = LASSO_ROT,
		["wood_axe_darkvalentine"] = AXE_ROT,
		["stone_axe_darkvalentine"] = AXE_ROT,
		["iron_axe_darkvalentine"] = AXE_ROT,
		["diamond_axe_darkvalentine"] = AXE_ROT,
		["wood_axe_valentine"] = AXE_ROT,
		["stone_axe_valentine"] = AXE_ROT,
		["iron_axe_valentine"] = AXE_ROT,
		["diamond_axe_valentine"] = AXE_ROT,
		["wood_pickaxe_darkvalentine"] = PICKAXE_ROT,
		["stone_pickaxe_darkvalentine"] = PICKAXE_ROT,
		["iron_pickaxe_darkvalentine"] = PICKAXE_ROT,
		["diamond_pickaxe_darkvalentine"] = PICKAXE_ROT,
		["wood_pickaxe_valentine"] = PICKAXE_ROT,
		["stone_pickaxe_valentine"] = PICKAXE_ROT,
		["iron_pickaxe_valentine"] = PICKAXE_ROT,
		["diamond_pickaxe_valentine"] = PICKAXE_ROT,
		["gold_victorious_wizard_staff"] = STAFF_ROT,
		["gold_victorious_wizard_staff_2"] = STAFF_ROT,
		["gold_victorious_wizard_staff_3"] = STAFF_ROT,
		["platinum_victorious_wizard_staff"] = STAFF_ROT,
		["platinum_victorious_wizard_staff_2"] = STAFF_ROT,
		["platinum_victorious_wizard_staff_3"] = STAFF_ROT,
		["diamond_victorious_wizard_staff"] = STAFF_ROT,
		["diamond_victorious_wizard_staff_2"] = STAFF_ROT,
		["diamond_victorious_wizard_staff_3"] = STAFF_ROT,
		["emerald_victorious_wizard_staff"] = STAFF_ROT,
		["emerald_victorious_wizard_staff_2"] = STAFF_ROT,
		["emerald_victorious_wizard_staff_3"] = STAFF_ROT,
		["nightmare_victorious_wizard_staff"] = STAFF_ROT,
		["nightmare_victorious_wizard_staff_2"] = STAFF_ROT,
		["nightmare_victorious_wizard_staff_3"] = STAFF_ROT,
		["wood_dao_victorious"] = VIC_ROT,
		["stone_dao_victorious"] = VIC_ROT,
		["iron_dao_victorious"] = VIC_ROT,
		["diamond_dao_victorious"] = VIC_ROT,
		["emerald_dao_victorious"] = VIC_ROT,
		["wood_dao_cursed"] = HEXED_DAO_ROT,
		["stone_dao_cursed"] = HEXED_DAO_ROT,
		["iron_dao_cursed"] = HEXED_DAO_ROT,
		["diamond_dao_cursed"] = HEXED_DAO_ROT,
		["emerald_dao_cursed"] = HEXED_DAO_ROT,
		["wood_dao_tiger"] = DAO_ROT,
		["stone_dao_tiger"] = DAO_ROT,
		["iron_dao_tiger"] = DAO_ROT,
		["diamond_dao_tiger"] = DAO_ROT,
		["emerald_dao_tiger"] = DAO_ROT,
		["wood_dao_snow_rabbit"] = SNOW_DAO_ROT,
		["stone_dao_snow_rabbit"] = SNOW_DAO_ROT,
		["iron_dao_snow_rabbit"] = SNOW_DAO_ROT,
		["diamond_dao_snow_rabbit"] = SNOW_DAO_ROT,
		["emerald_dao_snow_rabbit"] = SNOW_DAO_ROT,
	}
	local KIT_SKIN_MAP = {
		["Victorious Lyla"] = {
			Gold = "gold_victorious_lyla",
			Platinum = "platinum_victorious_lyla",
			Diamond = "diamond_victorious_lyla",
			Emerald = "emerald_victorious_lyla",
			Nightmare = "nightmare_victorious_lyla"
		},
		["Frost Queen Lyla"] = {
			Default = "flower_bee_frost_queen"
		},
		["Victorious Archer"] = {
			Gold = "archer_victorious_gold",
			Platinum = "archer_victorious_platinum",
			Diamond = "archer_victorious_diamond",
			Emerald = "archer_victorious_emerald",
			Nightmare = "archer_victorious_nightmare"
		},
		["Lunar Dragon Archer"] = {
			Default = "archer_lunar_dragon"
		},
		["Victorious Yuzi"] = {
			Default = "yuzi_victorious"
		},
		["Hexed Yuzi"] = {
			Default = "dasher_cursed"
		},
		["Tiger Yuzi"] = {
			Default = "dasher_tiger"
		},
		["Snow Rabbit Yuzi"] = {
			Default = "dasher_snow_rabbit"
		},
		["Victorious Zeno"] = {
			Gold = "gold_victorious_wizard",
			Platinum = "platinum_victorious_wizard",
			Diamond = "diamond_victorious_wizard",
			Emerald = "emerald_victorious_wizard",
			Nightmare = "nightmare_victorious_wizard"
		},
		["Victorious Triton"] = {
			Gold = "victorious_gold_triton",
			Platinum = "victorious_platinum_triton",
			Diamond = "victorious_diamond_triton",
			Emerald = "victorious_emerald_triton",
			Nightmare = "victorious_nightmare_triton"
		},
		["Demon Triton"] = {
			Default = "demon_triton"
		},
		["Mummy Life Bow"] = {
			Default = "mummy_nazar"
		},
		["Mummy Lasso"] = {
			Default = "cowgirl_mummy"
		},
		["Victorious Cannon"] = {
			Gold = "gold_victorious_davey",
			Platinum = "platinum_victorious_davey",
			Diamond = "diamond_victorious_davey",
			Emerald = "emerald_victorious_davey",
			Nightmare = "nightmare_victorious_davey"
		},
		["Ghost Cannon"] = {
			Default = "davey_ghost"
		},
		["Deep Sea Cannon"] = {
			Default = "davey_deepsea"
		},
	}
	local STORE_SKIN_MAP = {
		["Balloon Swords"] = function()
			return {
				{
					ItemType.WOOD_SWORD,
					ItemSkinType.BALLOON_WOOD_SWORD
				},
				{
					ItemType.STONE_SWORD,
					ItemSkinType.BALLOON_STONE_SWORD
				},
				{
					ItemType.IRON_SWORD,
					ItemSkinType.BALLOON_IRON_SWORD
				},
				{
					ItemType.DIAMOND_SWORD,
					ItemSkinType.BALLOON_DIAMOND_SWORD
				},
				{
					ItemType.EMERALD_SWORD,
					ItemSkinType.BALLOON_EMERALD_SWORD
				}
			}
		end,
		["Banana Swords"] = function()
			return {
				{
					ItemType.WOOD_SWORD,
					ItemSkinType.BANANA_WOOD_SWORD
				},
				{
					ItemType.STONE_SWORD,
					ItemSkinType.BANANA_STONE_SWORD
				},
				{
					ItemType.IRON_SWORD,
					ItemSkinType.BANANA_IRON_SWORD
				},
				{
					ItemType.DIAMOND_SWORD,
					ItemSkinType.BANANA_DIAMOND_SWORD
				},
				{
					ItemType.EMERALD_SWORD,
					ItemSkinType.BANANA_EMERALD_SWORD
				}
			}
		end,
		["Valentine Pack"] = function()
			return {
				{
					ItemType.WOOD_SWORD,
					ItemSkinType.VALENTINE_WOOD_SWORD
				},
				{
					ItemType.STONE_SWORD,
					ItemSkinType.VALENTINE_STONE_SWORD
				},
				{
					ItemType.IRON_SWORD,
					ItemSkinType.VALENTINE_IRON_SWORD
				},
				{
					ItemType.DIAMOND_SWORD,
					ItemSkinType.VALENTINE_DIAMOND_SWORD
				},
				{
					ItemType.EMERALD_SWORD,
					ItemSkinType.VALENTINE_EMERALD_SWORD
				},
				{
					ItemType.WOOD_PICKAXE,
					ItemSkinType.VALENTINE_WOOD_PICKAXE
				},
				{
					ItemType.STONE_PICKAXE,
					ItemSkinType.VALENTINE_STONE_PICKAXE
				},
				{
					ItemType.IRON_PICKAXE,
					ItemSkinType.VALENTINE_IRON_PICKAXE
				},
				{
					ItemType.DIAMOND_PICKAXE,
					ItemSkinType.VALENTINE_DIAMOND_PICKAXE
				},
				{
					ItemType.WOOD_AXE,
					ItemSkinType.VALENTINE_WOOD_AXE
				},
				{
					ItemType.STONE_AXE,
					ItemSkinType.VALENTINE_STONE_AXE
				},
				{
					ItemType.IRON_AXE,
					ItemSkinType.VALENTINE_IRON_AXE
				},
				{
					ItemType.DIAMOND_AXE,
					ItemSkinType.VALENTINE_DIAMOND_AXE
				}
			}
		end,
		["Darkheart Pack"] = function()
			return {
				{
					ItemType.WOOD_SWORD,
					ItemSkinType.DARKVALENTINE_WOOD_SWORD
				},
				{
					ItemType.STONE_SWORD,
					ItemSkinType.DARKVALENTINE_STONE_SWORD
				},
				{
					ItemType.IRON_SWORD,
					ItemSkinType.DARKVALENTINE_IRON_SWORD
				},
				{
					ItemType.DIAMOND_SWORD,
					ItemSkinType.DARKVALENTINE_DIAMOND_SWORD
				},
				{
					ItemType.EMERALD_SWORD,
					ItemSkinType.DARKVALENTINE_EMERALD_SWORD
				},
				{
					ItemType.WOOD_PICKAXE,
					ItemSkinType.DARKVALENTINE_WOOD_PICKAXE
				},
				{
					ItemType.STONE_PICKAXE,
					ItemSkinType.DARKVALENTINE_STONE_PICKAXE
				},
				{
					ItemType.IRON_PICKAXE,
					ItemSkinType.DARKVALENTINE_IRON_PICKAXE
				},
				{
					ItemType.DIAMOND_PICKAXE,
					ItemSkinType.DARKVALENTINE_DIAMOND_PICKAXE
				},
				{
					ItemType.WOOD_AXE,
					ItemSkinType.DARKVALENTINE_WOOD_AXE
				},
				{
					ItemType.STONE_AXE,
					ItemSkinType.DARKVALENTINE_STONE_AXE
				},
				{
					ItemType.IRON_AXE,
					ItemSkinType.DARKVALENTINE_IRON_AXE
				},
				{
					ItemType.DIAMOND_AXE,
					ItemSkinType.DARKVALENTINE_DIAMOND_AXE
				}
			}
		end,
		["Heartbeam Swords"] = function()
			return {
				{
					ItemType.WOOD_SWORD,
					ItemSkinType.HEARTBEAM_WOOD_SWORD
				},
				{
					ItemType.STONE_SWORD,
					ItemSkinType.HEARTBEAM_STONE_SWORD
				},
				{
					ItemType.IRON_SWORD,
					ItemSkinType.HEARTBEAM_IRON_SWORD
				},
				{
					ItemType.DIAMOND_SWORD,
					ItemSkinType.HEARTBEAM_DIAMOND_SWORD
				},
				{
					ItemType.EMERALD_SWORD,
					ItemSkinType.HEARTBEAM_EMERALD_SWORD
				}
			}
		end,
		["Mummy Life Bow"] = function()
			return {
				{
					ItemType.LIFE_BOW,
					ItemSkinType.LIFE_BOW_MUMMY
				},
				{
					ItemType.LIFE_CROSSBOW,
					ItemSkinType.LIFE_CROSSBOW_MUMMY
				},
				{
					ItemType.LIFE_HEADHUNTER,
					ItemSkinType.LIFE_HEADHUNTER_MUMMY
				}
			}
		end,
		["Mummy Lasso"] = function()
			return {
				{
					ItemType.LASSO,
					ItemSkinType.LASSO_MUMMY
				}
			}
		end,
	}
	local function yuziDaoMap(suffix)
		return {
			wood_dao = "wood_dao_" .. suffix,
			stone_dao = "stone_dao_" .. suffix,
			iron_dao = "iron_dao_" .. suffix,
			diamond_dao = "diamond_dao_" .. suffix,
			emerald_dao = "emerald_dao_" .. suffix,
		}
	end
	local SKIN_DATA = {
		["Victorious Lyla"] = function(t)
			local lt = t:lower()
			return {
				flower_bow = lt .. "_victorious_flower_bow",
				flower_crossbow = lt .. "_victorious_flower_crossbow",
				flower_headhunter = lt .. "_victorious_flower_headhunter",
			}
		end,
		["Frost Queen Lyla"] = function()
			return {
				flower_bow = "flower_bow_frost_queen",
				flower_crossbow = "flower_crossbow_frost_queen",
				flower_headhunter = "flower_headhunter_frost_queen",
			}
		end,
		["Victorious Archer"] = function(t)
			local lt = t:lower()
			return {
				wood_bow = "wood_bow_victorious_" .. lt,
				tactical_crossbow = "tactical_crossbow_victorious_" .. lt,
				tactical_headhunter = "tactical_headhunter_victorious_" .. lt,
			}
		end,
		["Lunar Dragon Archer"] = function()
			return {
				wood_bow = "wood_bow_lunar_dragon",
				tactical_crossbow = "tactical_crossbow_lunar_dragon",
				tactical_headhunter = "tactical_headhunter_lunar_dragon",
			}
		end,
		["Victorious Triton"] = function(t)
			return {
				harpoon = "victorious_" .. t:lower() .. "_triton"
			}
		end,
		["Demon Triton"] = function()
			return {
				harpoon = "demon_triton"
			}
		end,
		["Victorious Yuzi"] = function()
			return yuziDaoMap("victorious")
		end,
		["Hexed Yuzi"] = function()
			return yuziDaoMap("cursed")
		end,
		["Tiger Yuzi"] = function()
			return yuziDaoMap("tiger")
		end,
		["Snow Rabbit Yuzi"] = function()
			return yuziDaoMap("snow_rabbit")
		end,
		["Victorious Zeno"] = function(t)
			local lt = t:lower()
			return {
				wizard_staff = lt .. "_victorious_wizard_staff",
				wizard_staff_2 = lt .. "_victorious_wizard_staff_2",
				wizard_staff_3 = lt .. "_victorious_wizard_staff_3",
			}
		end,
		["Balloon Swords"] = function()
			return {
				wood_sword = "balloon_wood_sword",
				stone_sword = "balloon_stone_sword",
				iron_sword = "balloon_iron_sword",
				diamond_sword = "balloon_diamond_sword",
				emerald_sword = "balloon_emerald_sword"
			}
		end,
		["Banana Swords"] = function()
			return {
				wood_sword = "banana_wood_sword",
				stone_sword = "banana_stone_sword",
				iron_sword = "banana_iron_sword",
				diamond_sword = "banana_diamond_sword",
				emerald_sword = "banana_emerald_sword"
			}
		end,
		["Valentine Pack"] = function()
			return {
				wood_sword = "wood_sword_valentine",
				stone_sword = "stone_sword_valentine",
				iron_sword = "iron_sword_valentine",
				diamond_sword = "diamond_sword_valentine",
				emerald_sword = "emerald_sword_valentine",
				wood_pickaxe = "wood_pickaxe_valentine",
				stone_pickaxe = "stone_pickaxe_valentine",
				iron_pickaxe = "iron_pickaxe_valentine",
				diamond_pickaxe = "diamond_pickaxe_valentine",
				wood_axe = "wood_axe_valentine",
				stone_axe = "stone_axe_valentine",
				iron_axe = "iron_axe_valentine",
				diamond_axe = "diamond_axe_valentine"
			}
		end,
		["Darkheart Pack"] = function()
			return {
				wood_sword = "wood_sword_darkvalentine",
				stone_sword = "stone_sword_darkvalentine",
				iron_sword = "iron_sword_darkvalentine",
				diamond_sword = "diamond_sword_darkvalentine",
				emerald_sword = "emerald_sword_darkvalentine",
				wood_pickaxe = "wood_pickaxe_darkvalentine",
				stone_pickaxe = "stone_pickaxe_darkvalentine",
				iron_pickaxe = "iron_pickaxe_darkvalentine",
				diamond_pickaxe = "diamond_pickaxe_darkvalentine",
				wood_axe = "wood_axe_darkvalentine",
				stone_axe = "stone_axe_darkvalentine",
				iron_axe = "iron_axe_darkvalentine",
				diamond_axe = "diamond_axe_darkvalentine"
			}
		end,
		["Heartbeam Swords"] = function()
			return {
				wood_sword = "wood_sword_heartbeam",
				stone_sword = "stone_sword_heartbeam",
				iron_sword = "iron_sword_heartbeam",
				diamond_sword = "diamond_sword_heartbeam",
				emerald_sword = "emerald_sword_heartbeam"
			}
		end,
		["Mummy Lasso"] = function()
			return {
				lasso = "lasso_mummy"
			}
		end,
		["Mummy Life Bow"] = function()
			return {
				life_bow = "life_bow_mummy",
				life_crossbow = "life_crossbow_mummy",
				life_headhunter = "life_headhunter_mummy"
			}
		end,
	}
	local TIERED_SKINS = {
		["Victorious Lyla"] = true,
		["Victorious Archer"] = true,
		["Victorious Zeno"] = true,
		["Victorious Triton"] = true,
		["Victorious Cannon"] = true,
	}
	local function normalizeName(s)
		return s:lower():gsub("[_%s%-]", "")
	end
	local function isCannonSkin()
		return CANNON_SKIN_NAMES[CURRENT_ITEM_SKIN] ~= nil
	end
	local function getCurrentCannonSkinName()
		local tbl = CANNON_SKIN_NAMES[CURRENT_ITEM_SKIN]
		if not tbl then
			return nil
		end
		return tbl[CURRENT_SKIN_TYPE] or tbl.Default
	end
	local function getCannonSkinSource(skinName)
		local assets = RS:FindFirstChild("Assets")
		if not assets then
			return nil
		end
		local blocks = assets:FindFirstChild("Blocks")
		if not blocks then
			return nil
		end
		return blocks:FindFirstChild(skinName)
	end
	local function keepOriginalInvisible(tool)
		local conn
		conn = RunService.RenderStepped:Connect(function()
			if not tool or not tool.Parent then
				conn:Disconnect()
				return
			end
			for _, d in ipairs(tool:GetDescendants()) do
				if d:IsA("BasePart") and not d:IsDescendantOf(tool:FindFirstChild("LOCAL_ITEM_RESKIN") or game) then
					d.LocalTransparencyModifier = 1
					d.Transparency = 1
				elseif (d:IsA("Decal") or d:IsA("Texture")) and not d:IsDescendantOf(tool:FindFirstChild("LOCAL_ITEM_RESKIN") or game) then
					d.Transparency = 1
				end
			end
		end)
		table.insert(connections, conn)
	end
	local function getCurrentMappings()
		local fn = SKIN_DATA[CURRENT_ITEM_SKIN]
		if not fn then
			return {}
		end
		return fn(CURRENT_SKIN_TYPE) or {}
	end
	local function getKitSkinValue()
		local m = KIT_SKIN_MAP[CURRENT_ITEM_SKIN]
		if not m then
			return nil
		end
		return m[CURRENT_SKIN_TYPE] or m.Default
	end
	local function getStoreSkins()
		local fn = STORE_SKIN_MAP[CURRENT_ITEM_SKIN]
		if not fn then
			return {}
		end
		return fn() or {}
	end
	local tagged = setmetatable({}, {
		__mode = "k"
	})
	local connections = {}
	local oldGetKitSkin = nil
	local savedStoreSkins = {}
	local cannonTagged = setmetatable({}, {
		__mode = "k"
	})
	local cannonConnections = {}
	local cannonRenderConns = {}
	local oldFireCannon, oldLaunchSelf
	local soundsHooked = false
	local function firstBasePart(root)
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") then
				return d
			end
		end
	end
	local function makeInvisible(root)
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 1
				d.Transparency = 1
			elseif d:IsA("Decal") or d:IsA("Texture") then
				d.Transparency = 1
			end
		end
	end
	local function restoreVisibility(root)
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 0
				d.Transparency = 0
			elseif d:IsA("Decal") or d:IsA("Texture") then
				d.Transparency = 0
			end
		end
	end
	local function setNoCollide(model)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
				d.Massless = true
				d.Anchored = false
			end
		end
	end
	local function weldAllTo(anchor, container)
		for _, d in ipairs(container:GetDescendants()) do
			if d:IsA("BasePart") and d ~= anchor then
				local wc = Instance.new("WeldConstraint")
				wc.Part0 = anchor
				wc.Part1 = d
				wc.Parent = anchor
			end
		end
	end
	local function attachReskin(tool, skinName)
		if not tool or tagged[tool] then
			return
		end
		tagged[tool] = true
		local origHandle = tool:FindFirstChild("Handle")
		if not (origHandle and origHandle:IsA("BasePart")) then
			origHandle = firstBasePart(tool)
		end
		if not origHandle then
			tagged[tool] = nil;
			return
		end
		local itemsFolder = RS:FindFirstChild("Items")
		if not itemsFolder then
			tagged[tool] = nil;
			return
		end
		local source = itemsFolder:FindFirstChild(skinName)
		if not source then
			tagged[tool] = nil;
			return
		end
		makeInvisible(tool)
		local clone = source:Clone()
		clone.Name = "LOCAL_ITEM_RESKIN"
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
				pcall(d.Destroy, d)
			end
		end
		setNoCollide(clone)
		clone.Parent = tool
		local cloneAnchor = clone:FindFirstChild("Handle")
		if not (cloneAnchor and cloneAnchor:IsA("BasePart")) then
			if clone:IsA("Model") then
				if not clone.PrimaryPart then
					local p = firstBasePart(clone)
					if p then
						pcall(function()
							clone.PrimaryPart = p
						end)
					end
				end
				cloneAnchor = clone.PrimaryPart
			end
			cloneAnchor = cloneAnchor or firstBasePart(clone)
		end
		if not cloneAnchor then
			clone:Destroy();
			restoreVisibility(tool);
			tagged[tool] = nil;
			return
		end
		pcall(function()
			cloneAnchor.CFrame = origHandle.CFrame
		end)
		weldAllTo(cloneAnchor, clone)
		local w = Instance.new("Weld")
		w.Part0 = origHandle
		w.Part1 = cloneAnchor
		w.C0 = SKIN_OFFSETS[skinName] or CFrame.identity
		w.C1 = CFrame.identity
		w.Parent = cloneAnchor
	end
	local function weldAllToPrimary(model)
		local primary = model.PrimaryPart
		if not primary then
			return
		end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d ~= primary then
				local wc = Instance.new("WeldConstraint")
				wc.Part0 = primary
				wc.Part1 = d
				wc.Parent = primary
			end
		end
	end
	local function attachCannonReskin(targetRoot, posOffset, heldScale)
		if not targetRoot or cannonTagged[targetRoot] then
			return
		end
		cannonTagged[targetRoot] = true
		local targetPart = targetRoot:FindFirstChild("Handle")
		if not (targetPart and targetPart:IsA("BasePart")) then
			targetPart = firstBasePart(targetRoot)
		end
		if not targetPart then
			cannonTagged[targetRoot] = nil;
			return
		end
		local skinName = getCurrentCannonSkinName()
		if not skinName then
			cannonTagged[targetRoot] = nil;
			return
		end
		local source = getCannonSkinSource(skinName)
		if not source then
			cannonTagged[targetRoot] = nil;
			return
		end
		makeInvisible(targetRoot)
		local clone = source:Clone()
		clone.Name = "LOCAL_CANNON_RESKIN"
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
				pcall(d.Destroy, d)
			end
		end
		if not clone:IsA("Model") then
			setNoCollide(clone)
			clone.Parent = targetRoot
			return
		end
		if not clone.PrimaryPart then
			local p = firstBasePart(clone)
			if p then
				pcall(function()
					clone.PrimaryPart = p
				end)
			end
		end
		if not clone.PrimaryPart then
			clone:Destroy();
			cannonTagged[targetRoot] = nil;
			return
		end
		if heldScale and heldScale ~= 1 then
			pcall(function()
				clone:ScaleTo(heldScale)
			end)
		end
		setNoCollide(clone)
		clone.Parent = targetRoot
		local offset = posOffset or CFrame.identity
		pcall(function()
			clone:PivotTo(targetPart.CFrame * offset)
		end)
		weldAllToPrimary(clone)
		local wc = Instance.new("WeldConstraint")
		wc.Part0 = targetPart
		wc.Part1 = clone.PrimaryPart
		wc.Parent = clone.PrimaryPart
	end
	local function hookCannonThirdPerson(character)
		local function onChildAdded(child)
			if not (child:IsA("Tool") and child.Name == CANNON_TOOL_NAME) then
				return
			end
			task.wait()
			local handle = child:FindFirstChild("Handle") or firstBasePart(child)
			if not handle then
				return
			end
			local existing = child:FindFirstChild("LOCAL_CANNON_RESKIN")
			if existing then
				existing:Destroy();
				cannonTagged[child] = nil
			end
			attachCannonReskin(child, CFrame.identity, CANNON_HAND_SCALE)
			local start = time()
			local conn
			conn = RunService.RenderStepped:Connect(function()
				if not child.Parent then
					conn:Disconnect();
					return
				end
				makeInvisible(child)
				if time() - start > 3 then
					conn:Disconnect()
				end
			end)
			table.insert(cannonRenderConns, conn)
		end
		for _, c in ipairs(character:GetChildren()) do
			onChildAdded(c)
		end
		local conn = character.ChildAdded:Connect(onChildAdded)
		table.insert(cannonConnections, conn)
	end
	local function hookCannonViewmodel()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local function hookVM(vm)
			for _, child in ipairs(vm:GetChildren()) do
				if child.Name == CANNON_TOOL_NAME then
					attachCannonReskin(child, CFrame.identity, CANNON_HAND_SCALE)
				end
			end
			local conn = vm.ChildAdded:Connect(function(child)
				if child.Name == CANNON_TOOL_NAME then
					task.wait()
					attachCannonReskin(child, CFrame.identity, CANNON_HAND_SCALE)
				end
			end)
			table.insert(cannonConnections, conn)
		end
		local vm = cam:FindFirstChild("Viewmodel")
		if vm then
			hookVM(vm)
		end
		local conn = cam.ChildAdded:Connect(function(child)
			if child.Name == "Viewmodel" then
				task.wait();
				hookVM(child)
			end
		end)
		table.insert(cannonConnections, conn)
	end
	local function hookCannonContainer(container)
		if not container then
			return
		end
		for _, child in ipairs(container:GetChildren()) do
			if child.Name == CANNON_TOOL_NAME then
				attachCannonReskin(child, CFrame.identity, CANNON_HAND_SCALE)
			end
		end
		local conn = container.ChildAdded:Connect(function(child)
			if child.Name == CANNON_TOOL_NAME then
				task.wait()
				attachCannonReskin(child, CFrame.identity, CANNON_HAND_SCALE)
			end
		end)
		table.insert(cannonConnections, conn)
	end
	local function hookCannonBlocksFolder(blocksFolder)
		for _, child in ipairs(blocksFolder:GetChildren()) do
			if child.Name == CANNON_TOOL_NAME then
				attachCannonReskin(child, CANNON_PLACED_OFFSET, 1)
			end
		end
		local conn = blocksFolder.ChildAdded:Connect(function(child)
			if child.Name == CANNON_TOOL_NAME then
				task.wait()
				attachCannonReskin(child, CANNON_PLACED_OFFSET, 1)
			end
		end)
		table.insert(cannonConnections, conn)
	end
	local function hookAllWorldCannons()
		local map = workspace:FindFirstChild("Map")
		if not map then
			return
		end
		local worlds = map:FindFirstChild("Worlds")
		if not worlds then
			return
		end
		for _, world in ipairs(worlds:GetChildren()) do
			local blocks = world:FindFirstChild("Blocks")
			if blocks then
				hookCannonBlocksFolder(blocks)
			end
		end
		local conn = worlds.ChildAdded:Connect(function(world)
			task.wait()
			local blocks = world:FindFirstChild("Blocks")
			if blocks then
				hookCannonBlocksFolder(blocks)
			end
		end)
		table.insert(cannonConnections, conn)
	end
	local function hookCannonSounds()
		if soundsHooked then
			return
		end
		if not (bedwars and bedwars.CannonHandController) then
			return
		end
		soundsHooked = true
		oldFireCannon = bedwars.CannonHandController.fireCannon
		oldLaunchSelf = bedwars.CannonHandController.launchSelf
		local function replaceSound()
			for _, v in ipairs(workspace.SoundPool:GetChildren()) do
				if v:IsA("Sound") and v.SoundId == "rbxassetid://7121064180" then
					v:Destroy()
				end
			end
			local key = CANNON_SOUND_NAMES[CURRENT_SKIN_TYPE] or CANNON_SOUND_NAMES.Nightmare
			if bedwars.SoundManager and bedwars.SoundList and bedwars.SoundList[key] then
				bedwars.SoundManager:playSound(bedwars.SoundList[key])
			end
		end
		bedwars.CannonHandController.fireCannon = function(...)
			replaceSound();
			return oldFireCannon(...)
		end
		bedwars.CannonHandController.launchSelf = function(...)
			replaceSound();
			return oldLaunchSelf(...)
		end
	end
	local function unhookCannonSounds()
		if soundsHooked and bedwars and bedwars.CannonHandController then
			if oldFireCannon then
				bedwars.CannonHandController.fireCannon = oldFireCannon
			end
			if oldLaunchSelf then
				bedwars.CannonHandController.launchSelf = oldLaunchSelf
			end
		end
		oldFireCannon = nil;
		oldLaunchSelf = nil;
		soundsHooked = false
	end
	local function cleanupCannons()
		for _, c in pairs(cannonConnections) do
			pcall(function()
				c:Disconnect()
			end)
		end
		for _, c in pairs(cannonRenderConns) do
			pcall(function()
				c:Disconnect()
			end)
		end
		table.clear(cannonConnections)
		table.clear(cannonRenderConns)
		for root in pairs(cannonTagged) do
			if root and root.Parent then
				local r = root:FindFirstChild("LOCAL_CANNON_RESKIN")
				if r then
					r:Destroy()
				end
				restoreVisibility(root)
			end
		end
		table.clear(cannonTagged)
		local map = workspace:FindFirstChild("Map")
		if map then
			local worlds = map:FindFirstChild("Worlds")
			if worlds then
				for _, world in ipairs(worlds:GetChildren()) do
					local blocks = world:FindFirstChild("Blocks")
					if blocks then
						for _, child in ipairs(blocks:GetChildren()) do
							if child.Name == CANNON_TOOL_NAME then
								local r = child:FindFirstChild("LOCAL_CANNON_RESKIN")
								if r then
									r:Destroy()
								end
								restoreVisibility(child)
							end
						end
					end
				end
			end
		end
		unhookCannonSounds()
	end
	local function applyKitSkinHook()
		if not KitSkinCtrl then
			return
		end
		local val = getKitSkinValue()
		if not val then
			return
		end
		if not oldGetKitSkin then
			oldGetKitSkin = KitSkinCtrl.getKitSkin
		end
		KitSkinCtrl.getKitSkin = function(self, char)
			if char == LocalPlayer.Character then
				return val
			end
			return oldGetKitSkin(self, char)
		end
	end
	local function removeKitSkinHook()
		if KitSkinCtrl and oldGetKitSkin then
			KitSkinCtrl.getKitSkin = oldGetKitSkin
			oldGetKitSkin = nil
		end
	end
	local function applyStoreSkins()
		if not (bedwars and bedwars.Store) then
			return
		end
		local skins = getStoreSkins()
		savedStoreSkins = {}
		local state = bedwars.Store:getState()
		for _, pair in ipairs(skins) do
			if pair[1] and pair[2] then
				local prev = state.Locker and state.Locker.selectedItemSkins and state.Locker.selectedItemSkins[pair[1]]
				table.insert(savedStoreSkins, {
					pair[1],
					prev
				})
				pcall(function()
					bedwars.Store:dispatch({
						type = "LockerSetItemSkin",
						itemType = pair[1],
						itemSkin = pair[2]
					})
				end)
			end
		end
	end
	local function clearStoreSkins()
		if not (bedwars and bedwars.Store) then
			return
		end
		for _, saved in ipairs(savedStoreSkins) do
			pcall(function()
				bedwars.Store:dispatch({
					type = "LockerSetItemSkin",
					itemType = saved[1],
					itemSkin = saved[2]
				})
			end)
		end
		savedStoreSkins = {}
	end
	local function tryApply(child)
		if isCannonSkin() then
			return
		end
		local mappings = getCurrentMappings()
		local skinName = mappings[child.Name:lower()]
		if not skinName then
			local childNorm = normalizeName(child.Name)
			for k, v in pairs(mappings) do
				if normalizeName(k) == childNorm then
					skinName = v;
					break
				end
			end
		end
		if not skinName then
			return
		end
		task.wait()
		if child.Parent then
			attachReskin(child, skinName)
		end
	end
	local function hookViewmodel()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local function hookVM(vm)
			for _, child in ipairs(vm:GetChildren()) do
				tryApply(child)
			end
			table.insert(connections, vm.ChildAdded:Connect(tryApply))
		end
		local vm = cam:FindFirstChild("Viewmodel")
		if vm then
			hookVM(vm)
		end
		table.insert(connections, cam.ChildAdded:Connect(function(child)
			if child.Name == "Viewmodel" then
				task.wait();
				hookVM(child)
			end
		end))
	end
	local function hookContainer(container)
		if not container then
			return
		end
		for _, child in ipairs(container:GetChildren()) do
			tryApply(child)
		end
		table.insert(connections, container.ChildAdded:Connect(tryApply))
	end
	local function onCharacterAdded(character)
		task.wait(0.2)
		applyKitSkinHook()
		if isCannonSkin() then
			hookCannonContainer(LocalPlayer.Backpack)
			hookCannonContainer(character)
			hookCannonThirdPerson(character)
		else
			hookContainer(LocalPlayer.Backpack)
			hookContainer(character)
		end
	end
	local function cleanup()
		for _, c in pairs(connections) do
			pcall(function()
				c:Disconnect()
			end)
		end
		table.clear(connections)
		for root in pairs(tagged) do
			if root and root.Parent then
				local r = root:FindFirstChild("LOCAL_ITEM_RESKIN")
				if r then
					r:Destroy()
				end
				restoreVisibility(root)
			end
		end
		table.clear(tagged)
		removeKitSkinHook()
		clearStoreSkins()
		cleanupCannons()
	end
	local skinNames = {}
	for name in pairs(SKIN_DATA) do
		table.insert(skinNames, name)
	end
	for name in pairs(CANNON_SKIN_NAMES) do
		table.insert(skinNames, name)
	end
	table.sort(skinNames)
	local SkinTypeDropdown
	KitSkins = vape.Categories.Render:CreateModule({
		Name = "Client Packs",
		Function = function(enabled)
			if enabled then
				if store.equippedKit == 'bigman' then
					hookAllOrbs()
					return
				end
				if isCannonSkin() then
					hookCannonViewmodel()
					hookAllWorldCannons()
					hookCannonSounds()
					applyKitSkinHook()
					if LocalPlayer.Character then
						hookCannonContainer(LocalPlayer.Backpack)
						hookCannonContainer(LocalPlayer.Character)
						hookCannonThirdPerson(LocalPlayer.Character)
					end
				else
					hookViewmodel()
					applyKitSkinHook()
					applyStoreSkins()
					if LocalPlayer.Character then
						onCharacterAdded(LocalPlayer.Character)
					end
				end
				table.insert(connections, LocalPlayer.CharacterAdded:Connect(onCharacterAdded))
			else
				cleanup()
			end
		end,
		Tooltip = "Client-sided item skin changer",
	})
	KitSkins:CreateDropdown({
		Name = "Item Skin",
		List = skinNames,
		Default = CURRENT_ITEM_SKIN,
		Function = function(val)
			CURRENT_ITEM_SKIN = val
			if SkinTypeDropdown and SkinTypeDropdown.Object then
				SkinTypeDropdown.Object.Visible = TIERED_SKINS[val] == true
			end
			if KitSkins.Enabled then
				KitSkins:Toggle();
				KitSkins:Toggle()
			end
		end,
	})
	SkinTypeDropdown = KitSkins:CreateDropdown({
		Name = "Skin Type",
		List = {
			"Gold",
			"Platinum",
			"Diamond",
			"Emerald",
			"Nightmare",
			"Default"
		},
		Default = CURRENT_SKIN_TYPE,
		Function = function(val)
			CURRENT_SKIN_TYPE = val
			if KitSkins.Enabled then
				KitSkins:Toggle();
				KitSkins:Toggle()
			end
		end,
	})
	task.defer(function()
		if SkinTypeDropdown and SkinTypeDropdown.Object then
			SkinTypeDropdown.Object.Visible = TIERED_SKINS[CURRENT_ITEM_SKIN] == true
		end
		if SkinTypeDropdown and SkinTypeDropdown.Set then
			SkinTypeDropdown:Set(CURRENT_SKIN_TYPE)
		end
	end)
end)

run(function()
	local KitRender
	local lastupdate = 0
	local g = '5'
	local function getKitMeta(player, kit)
		kit = kit or player:GetAttribute('PlayingAsKits') or 'none'
		return bedwars.BedwarsKitMeta[kit] or bedwars.BedwarsKitMeta.none
	end

	local function refreshRenders(app)
		print('yo')
		for _, obj in app:GetDescendants() do
			local render = obj:FindFirstChild("PlayerRender", true)
			if not render then
				warn('no render')
				continue
			end
			local player = getPlayerFromDraft(render.Image, getPlayerName(obj))
			if not player then
				print('no player')
				continue
			end
			local kitmeta = getKitMeta(player)
			local kitRender = obj:FindFirstChild("KitRenderImage")
			if not kitRender then
				(g == "5" and callback5v5 or callbacksquad)(obj, player)
				kitRender = obj:FindFirstChild("KitRenderImage")
			end
			if kitRender then
				print('founded asnd resteddd')
				kitRender.Image = kitmeta.renderImage
			end
		end
	end

	local function getPlayerFromDraft(render, name)
		local id = render and render:match('id=(%d+)')
		if id then
			local player = playersService:GetPlayerByUserId(tonumber(id))
			if player then
				return player
			end
		end
		for _, v in playersService:GetPlayers() do
			if render and render:find('id=' .. v.UserId, 1, true) then
				return v
			end
			if name and (v.Name == name or v.DisplayName == name or v:GetAttribute('DisguiseDisplayName') == name) then
				return v
			end
			local displayName
			pcall(function()
				displayName = bedwars.StreamerModeController:getDisplayName(v)
			end)
			if name and displayName == name then
				return v
			end
		end
		return nil
	end
	local waitForChild = function(start, ...)
		local timeout = 12
		local parent = start
		for _, v in {
			...
		} do
			parent = parent and parent:WaitForChild(v, timeout)
			if not parent then
				break
			end
		end
		return parent
	end
	local function getPlayerName(card)
		local textbar = card and card:FindFirstChild('TextBackgroundBar')
		local label = textbar and textbar:FindFirstChild('PlayerName') or card and card:FindFirstChild('PlayerName', true)
		return label and label.Text or ''
	end
	local function getDraftCard(container)
		if not container then
			return
		end
		return container.Name == 'MatchDraftPlayerCard' and container or container:FindFirstChild('MatchDraftPlayerCard', true)
	end
	local function callback5v5(v, plr)
		if not v then
			return
		end
		local render = v:FindFirstChild('PlayerRender', true)
		local player = plr or getPlayerFromDraft(render and render.Image or '', getPlayerName(v))
		if player then
			local kitImage = getKitMeta(player)
			local roact = v:FindFirstChild('KitRenderImage')
			if not roact then
				roact = Instance.new('ImageLabel', v)
				roact.BackgroundTransparency = 1
				roact.AnchorPoint = Vector2.new(1, 0.5)
				roact.Position = UDim2.fromScale(1.05, 0.5)
				roact.Name = 'KitRenderImage'
				roact.Size = UDim2.fromScale(1.5, 1.5)
				roact.ZIndex = 1
				roact.ImageTransparency = 0.4
				roact.SliceCenter = Rect.new(0, 0, 0, 0)
				roact.SliceScale = 1
				roact.ScaleType = Enum.ScaleType.Crop
				KitRender:Clean(roact)
				local ratio = Instance.new('UIAspectRatioConstraint', roact)
				ratio.Name = '1'
				ratio.AspectRatio = 1
				ratio.AspectType = Enum.AspectType.FitWithinMaxSize
				ratio.DominantAxis = Enum.DominantAxis.Width
			end
			roact.Image = kitImage.renderImage
			roact.Position = UDim2.fromScale(1.05, 0)
			tweenService:Create(roact, TweenInfo.new(0.2, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
				Position = UDim2.fromScale(1.05, 0.4)
			}):Play()
			local function update()
				lastupdate = tick()
				roact.Position = UDim2.fromScale(1.05, 0)
				kitImage = getKitMeta(player)
				task.wait(lplr:GetNetworkPing())
				tweenService:Create(roact, TweenInfo.new(0.2, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
					Position = UDim2.fromScale(1.05, 0.4)
				}):Play()
				roact.Image = kitImage.renderImage
			end
			KitRender:Clean(player:GetAttributeChangedSignal('PlayingAsKits'):Connect(update))
			repeat
				refreshRenders(v)
				task.wait(3)
			until not KitRender.Enabled
		end
	end
	local function callbacksquad(v)
		if not v then
			return
		end
		local render = v:FindFirstChild('PlayerRender', true)
		local player = render and getPlayerFromDraft(render.Image, '') or nil
		if player then
			local kitImage = getKitMeta(player)
			local Roact = v:FindFirstChild('KitRenderImage')
			if not Roact then
				local base = v:FindFirstChild('3') or v:WaitForChild('3', 5)
				if not base then
					return
				end
				Roact = base:Clone()
				Roact.Parent = v
				Roact.Name = 'KitRenderImage'
				KitRender:Clean(Roact)
			end
			Roact.Image = kitImage.renderImage
			KitRender:Clean(render:GetPropertyChangedSignal('Image'):Connect(function()
				local newplayer = getPlayerFromDraft(render.Image, '')
				if newplayer then
					player = newplayer
					kitImage = getKitMeta(player)
					Roact.Image = kitImage.renderImage
				end
			end))
			local function update()
				lastupdate = tick()
				kitImage = getKitMeta(player)
				task.wait(lplr:GetNetworkPing())
				roact.Image = kitImage.renderImage
			end
			KitRender:Clean(player:GetAttributeChangedSignal('PlayingAsKits'):Connect(update))
			repeat
				refreshRenders(v)
				task.wait(3)
			until not KitRender.Enabled
		end
	end
	local function setup5v5(DraftApp)
		local Background = DraftApp:FindFirstChild('DraftAppBackground')
		if not Background then
			return
		end
		local BodyContainer = Background and Background:FindFirstChild('1') and Background['1']:FindFirstChild('BodyContainer')
		if not BodyContainer then
			return
		end
		local hooked = false
		local dtc = BodyContainer and BodyContainer:FindFirstChild('Team2Column')
		if dtc then
			hooked = true
			KitRender:Clean(dtc.ChildAdded:Connect(function(child)
				task.delay(0.135, function()
					if KitRender.Enabled then
						callback5v5(getDraftCard(child))
					end
				end)
			end))
			for _, v in dtc:GetChildren() do
				if v:IsA('Frame') then
					callback5v5(getDraftCard(v))
				end
			end
		end
		if not hooked then
			for _, label in DraftApp:GetDescendants() do
				if label:IsA('TextLabel') and label.Name == 'PlayerName' then
					local container = label.Parent
					for _ = 1, 6 do
						container = container and container.Parent
					end
					if container then
						callback5v5(getDraftCard(container))
					end
				end
			end
		end
		KitRender:Clean(DraftApp.DescendantAdded:Connect(function(child)
			if child:IsA('TextLabel') and child.Name == 'PlayerName' then
				task.delay(0.145, function()
					local container = child.Parent
					for _ = 1, 6 do
						container = container and container.Parent
					end
					if KitRender.Enabled and container then
						callback5v5(getDraftCard(container))
					end
				end)
			end
		end))

		return hooked
	end
	local function setupSquad(DraftApp)
		local Background = DraftApp:FindFirstChild('DraftAppBackground')
		local BodyContainer = Background and Background:FindFirstChild('1') and Background['1']:FindFirstChild('BodyContainer')
		local TeamsColumn = BodyContainer and BodyContainer:FindFirstChild('TeamsColumn')
		if not TeamsColumn then
			return
		end
		for _, v in TeamsColumn:GetChildren() do
			if v:IsA('Frame') then
				local plrframe = waitForChild(v, '1', '2', '4')
				if plrframe then
					for _, plr in plrframe:GetChildren() do
						callbacksquad(plr)
					end
					KitRender:Clean(plrframe.ChildAdded:Connect(function(plr)
						task.delay(.15, function()
							callbacksquad(plr)
						end)
					end))
				end
			end
		end
	end
	local function clearrenders(app)
		for i, v in app:GetDescendants() do
			if v:IsA('ImageLabel') then
				if v.Name == 'KitRenderImage' then
					pcall(function()
						v:Destroy()
					end)
				end
			end
		end
	end

	KitRender = vape.Categories.Render:CreateModule({
		Name = 'Kit Render',
		Function = function(callback)
			if callback then
				repeat
					task.wait(0.08)
				until isrbxactive()
				local DraftApp = waitForChild(lplr.PlayerGui, 'MatchDraftApp')
				setup5v5(DraftApp)
				setupSquad(DraftApp)
			else
				local DraftApp = waitForChild(lplr.PlayerGui, 'MatchDraftApp')
				clearrenders(DraftApp)
			end
		end,
		Tooltip = 'Allows you to see the other opponent kits'
	})
end)

run(function() -- pasted but who cares lol added gold so ez
	local GeneratorESP
	DiamondToggle = nil
	EmeraldToggle = nil
	GoldToggle = nil
	TeamGenToggle = nil
	ShowOwnTeamGen = nil
	ShowEnemyTeamGen = nil
	local UIStyle
	local CompactDiamondToggle
	local CompactEmeraldToggle
	local CompactGoldToggle
	local CollectionService = collectionService
	local RunService = runService
	local Reference = {}
	local Folder = Instance.new('Folder')
	Folder.Parent = vape.gui
	local CompactFolder = Instance.new('Folder')
	CompactFolder.Parent = vape.gui
	local teamColors = {
		[1] = {
			name = "Blue",
			color = Color3.fromRGB(85, 150, 255)
		},
		[2] = {
			name = "Orange",
			color = Color3.fromRGB(255, 150, 50)
		},
		[3] = {
			name = "Pink",
			color = Color3.fromRGB(255, 100, 200)
		},
		[4] = {
			name = "Yellow",
			color = Color3.fromRGB(255, 255, 50)
		}
	}
	local generatorTypes = {
		diamond = {
			keywords = {
				'diamond'
			},
			color = Color3.fromRGB(85, 200, 255),
			icon = 'diamond',
			displayName = 'Diamond',
			isTeamGen = false
		},
		emerald = {
			keywords = {
				'emerald'
			},
			color = Color3.fromRGB(0, 255, 100),
			icon = 'emerald',
			displayName = 'Emerald',
			isTeamGen = false
		},
		gold = {
			keywords = {
				'gold'
			},
			color = Color3.fromRGB(255, 0, 85),
			icon = 'gold',
			displayName = 'Gold',
			isTeamGen = false
		}
	}
	local compactUI = Instance.new('ScreenGui')
	compactUI.Name = 'GeneratorCompactUI'
	compactUI.Parent = vape.gui
	compactUI.Enabled = false
	compactUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	compactUI.DisplayOrder = 10
	compactUI.ResetOnSpawn = false
	local mainFrame = Instance.new('Frame')
	mainFrame.Name = 'MainFrame'
	mainFrame.Parent = compactUI
	mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	mainFrame.BackgroundTransparency = 0.3
	mainFrame.BorderSizePixel = 0
	mainFrame.Position = UDim2.new(1, - 8, 1, - 8)
	mainFrame.Size = UDim2.new(0, 145, 0, 145)
	mainFrame.AnchorPoint = Vector2.new(1, 1)
	local uicorner = Instance.new('UICorner')
	uicorner.CornerRadius = UDim.new(0, 8)
	uicorner.Parent = mainFrame
	local title = Instance.new('TextLabel')
	title.Name = 'Title'
	title.Parent = mainFrame
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 25)
	title.Position = UDim2.new(0, 0, 0, 5)
	title.Text = "GEN ESP"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 14
	title.Font = Enum.Font.GothamBold
	title.TextStrokeTransparency = 0.5
	title.TextStrokeColor3 = Color3.new(0, 0, 0)
	local diamondFrame = Instance.new('Frame')
	diamondFrame.Name = 'DiamondFrame'
	diamondFrame.Parent = mainFrame
	diamondFrame.BackgroundTransparency = 1
	diamondFrame.Size = UDim2.new(1, - 20, 0, 25)
	diamondFrame.Position = UDim2.new(0, 10, 0, 35)
	local diamondIcon = Instance.new('ImageLabel')
	diamondIcon.Name = 'DiamondIcon'
	diamondIcon.Parent = diamondFrame
	diamondIcon.BackgroundTransparency = 1
	diamondIcon.Size = UDim2.new(0, 18, 0, 18)
	diamondIcon.Position = UDim2.new(0, 0, 0.5, - 9)
	diamondIcon.Image = bedwars.getIcon({
		itemType = 'diamond'
	}, true)
	local diamondTimer = Instance.new('TextLabel')
	diamondTimer.Name = 'DiamondTimer'
	diamondTimer.Parent = diamondFrame
	diamondTimer.BackgroundTransparency = 1
	diamondTimer.Size = UDim2.new(1, - 25, 1, 0)
	diamondTimer.Position = UDim2.new(0, 25, 0, 0)
	diamondTimer.Text = "00"
	diamondTimer.TextColor3 = Color3.fromRGB(85, 200, 255)
	diamondTimer.TextSize = 18
	diamondTimer.Font = Enum.Font.GothamBold
	diamondTimer.TextXAlignment = Enum.TextXAlignment.Left
	local emeraldFrame = Instance.new('Frame')
	emeraldFrame.Name = 'EmeraldFrame'
	emeraldFrame.Parent = mainFrame
	emeraldFrame.BackgroundTransparency = 1
	emeraldFrame.Size = UDim2.new(1, - 20, 0, 25)
	emeraldFrame.Position = UDim2.new(0, 10, 0, 65)
	local emeraldIcon = Instance.new('ImageLabel')
	emeraldIcon.Name = 'EmeraldIcon'
	emeraldIcon.Parent = emeraldFrame
	emeraldIcon.BackgroundTransparency = 1
	emeraldIcon.Size = UDim2.new(0, 18, 0, 18)
	emeraldIcon.Position = UDim2.new(0, 0, 0.5, - 9)
	emeraldIcon.Image = bedwars.getIcon({
		itemType = 'emerald'
	}, true)
	local emeraldTimer = Instance.new('TextLabel')
	emeraldTimer.Name = 'EmeraldTimer'
	emeraldTimer.Parent = emeraldFrame
	emeraldTimer.BackgroundTransparency = 1
	emeraldTimer.Size = UDim2.new(1, - 25, 1, 0)
	emeraldTimer.Position = UDim2.new(0, 25, 0, 0)
	emeraldTimer.Text = "00"
	emeraldTimer.TextColor3 = Color3.fromRGB(0, 255, 100)
	emeraldTimer.TextSize = 18
	emeraldTimer.Font = Enum.Font.GothamBold
	emeraldTimer.TextXAlignment = Enum.TextXAlignment.Left
	local goldFrame = Instance.new('Frame')
	goldFrame.Name = 'GoldFrame'
	goldFrame.Parent = mainFrame
	goldFrame.BackgroundTransparency = 1
	goldFrame.Size = UDim2.new(1, - 20, 0, 25)
	goldFrame.Position = UDim2.new(0, 10, 0, 65)
	local goldIcon = Instance.new('ImageLabel')
	goldIcon.Name = 'GoldIcon'
	goldIcon.Parent = goldFrame
	goldIcon.BackgroundTransparency = 1
	goldIcon.Size = UDim2.new(0, 18, 0, 18)
	goldIcon.Position = UDim2.new(0, 0, 0.5, - 9)
	goldIcon.Image = bedwars.getIcon({
		itemType = 'gold'
	}, true)
	local goldTimer = Instance.new('TextLabel')
	goldTimer.Name = 'GoldTimer'
	goldTimer.Parent = goldFrame
	goldTimer.BackgroundTransparency = 1
	goldTimer.Size = UDim2.new(1, - 25, 1, 0)
	goldTimer.Position = UDim2.new(0, 25, 0, 0)
	goldTimer.Text = "00"
	goldTimer.TextColor3 = Color3.fromRGB(0, 255, 100)
	goldTimer.TextSize = 18
	goldTimer.Font = Enum.Font.GothamBold
	goldTimer.TextXAlignment = Enum.TextXAlignment.Left
	local diamondTimes = {}
	local emeraldTimes = {}
	local goldTimes = {}
	local function getMyTeamId()
		local myTeam = lplr:GetAttribute('Team')
		if myTeam == nil then
			return nil
		end
		return tonumber(myTeam)
	end
	local function getGeneratorTeamId(generatorId)
		local teamNum = string.match(generatorId, "^(%d+)_generator")
		if teamNum then
			return tonumber(teamNum)
		end
		return nil
	end
	local function isTeamGenerator(generatorId)
		return string.match(generatorId, "^%d+_generator") ~= nil
	end
	local function getGeneratorType(generatorId)
		local idLower = string.lower(generatorId)
		if isTeamGenerator(generatorId) then
			return 'teamgen', {
				color = Color3.fromRGB(200, 200, 200),
				icon = 'iron',
				displayName = 'Team Gen',
				isTeamGen = true
			}
		end
		for genType, config in pairs(generatorTypes) do
			for _, keyword in ipairs(config.keywords) do
				if idLower:find(keyword) then
					return genType, config
				end
			end
		end
		return nil, nil
	end
	local function isGeneratorEnabled(genType, teamId)
		if genType == 'diamond' then
			return DiamondToggle.Enabled
		elseif genType == 'emerald' then
			return EmeraldToggle.Enabled
		elseif genType == 'gold' then
			return GoldToggle.Enabled
		elseif genType == 'teamgen' then
			if not TeamGenToggle.Enabled then
				return false
			end
			local myTeamId = getMyTeamId()
			if not myTeamId or not teamId then
				return TeamGenToggle.Enabled
			end
			if teamId == myTeamId then
				return ShowOwnTeamGen.Enabled
			else
				return ShowEnemyTeamGen.Enabled
			end
		end
		return false
	end
	local function getProperIcon(iconType)
		local icon = bedwars.getIcon({
			itemType = iconType
		}, true)
		if not icon or icon == "" then
			return nil
		end
		return icon
	end
	local function getTierText(generatorAdornee)
		if not generatorAdornee then
			return nil
		end
		if generatorAdornee.Name ~= 'GeneratorAdornee' then
			return nil
		end
		local reactTree = generatorAdornee:FindFirstChild('RoactTree')
		if not reactTree then
			return nil
		end
		local teamApp = reactTree:FindFirstChild('TeamOreGeneratorApp')
		if not teamApp then
			return nil
		end
		local globalGen = teamApp:FindFirstChild('GlobalOreGenerator')
		if globalGen then
			for _, child in pairs(globalGen:GetDescendants()) do
				if child:IsA('TextLabel') then
					local text = child.Text
					if text:find("Tier") or text:match("^[IVX]+$") or text == "0" then
						return child
					end
				end
			end
		end
		local teamGenMain = teamApp:FindFirstChild('TeamGenMain')
		if teamGenMain then
			for _, child in pairs(teamGenMain:GetDescendants()) do
				if child:IsA('TextLabel') then
					local text = child.Text
					if text:find("Tier") or text:match("^[IVX]+$") or text == "0" then
						return child
					end
				end
			end
		end
		return nil
	end
	local function extractTierLevel(tierText)
		if not tierText or tierText == "" then
			return "0"
		end
		if tierText == "0" then
			return "0"
		end
		local tierMatch = tierText:match("Tier%s+([IVX]+)")
		if tierMatch then
			return tierMatch
		end
		if tierText:match("^[IVX]+$") then
			return tierText
		end
		local numTier = tierText:match("Tier%s+(%d+)")
		if numTier then
			local num = tonumber(numTier)
			if num == 0 then
				return "0"
			elseif num == 1 then
				return "I"
			elseif num == 2 then
				return "II"
			elseif num == 3 then
				return "III"
			end
		end
		return "0"
	end
	local function getCountdownText(generatorAdornee)
		if not generatorAdornee then
			return nil
		end
		if generatorAdornee.Name ~= 'GeneratorAdornee' then
			return nil
		end
		local reactTree = generatorAdornee:FindFirstChild('RoactTree')
		if not reactTree then
			return nil
		end
		local teamApp = reactTree:FindFirstChild('TeamOreGeneratorApp')
		if not teamApp then
			return nil
		end
		local globalGen = teamApp:FindFirstChild('GlobalOreGenerator')
		if not globalGen then
			return nil
		end
		local countdown = globalGen:FindFirstChild('Countdown')
		if not countdown then
			return nil
		end
		local textLabel = countdown:FindFirstChild('Text')
		if not textLabel then
			if countdown:IsA('TextLabel') then
				return countdown
			end
			return nil
		end
		return textLabel
	end
	local function extractSecondsFromText(text)
		if not text or text == "" then
			return 0
		end
		local seconds = text:match("%[(%d+)%]")
		if seconds then
			return tonumber(seconds) or 0
		end
		local justNumber = text:match("(%d+)")
		if justNumber then
			return tonumber(justNumber) or 0
		end
		return 0
	end
	local function getResourceCount(position, resourceType)
		local count = 0
		for _, drop in pairs(CollectionService:GetTagged('ItemDrop')) do
			if drop:FindFirstChild('Handle') then
				local dropName = drop.Name:lower()
				if dropName:find(resourceType) then
					local dist = (drop.Handle.Position - position).Magnitude
					if dist <= 10 then
						local amount = drop:GetAttribute('Amount') or 1
						count = count + amount
					end
				end
			end
		end
		return count
	end
	local CompactGenerators = {}
	local function rebuildCompactGenerators()
		table.clear(CompactGenerators)
		for _, obj in pairs(workspace:GetDescendants()) do
			if obj.Name == 'GeneratorAdornee' then
				local ok, generatorId = pcall(function()
					return obj:GetAttribute('Id')
				end)
				if ok and generatorId and type(generatorId) == 'string' and generatorId ~= '' then
					local genType = getGeneratorType(generatorId)
					if genType == 'diamond' or genType == 'emerald' or genType == 'gold' then
						table.insert(CompactGenerators, {
							obj = obj,
							genType = genType
						})
					end
				end
			end
		end
	end
	local function updateCompactUI()
		if not GeneratorESP.Enabled or UIStyle.Value ~= 'Compact' then
			compactUI.Enabled = false
			return
		end
		compactUI.Enabled = true
		local bestDiamondTime = math.huge
		local bestEmeraldTime = math.huge
		local bestGoldTime = math.huge
		for i = # CompactGenerators, 1, - 1 do
			local entry = CompactGenerators[i]
			if not entry.obj or not entry.obj.Parent then
				table.remove(CompactGenerators, i)
				continue
			end
			local countdownText = getCountdownText(entry.obj)
			if countdownText and countdownText.Text then
				local timeLeft = extractSecondsFromText(countdownText.Text)
				if entry.genType == 'diamond' and timeLeft > 0 and timeLeft < bestDiamondTime then
					bestDiamondTime = timeLeft
				elseif entry.genType == 'emerald' and timeLeft > 0 and timeLeft < bestEmeraldTime then
					bestEmeraldTime = timeLeft
				elseif entry.genType == 'gold' and timeLeft > 0 and timeLeft < bestGoldTime then
					bestGoldTime = timeLeft
				end
			end
		end
		local showDiamond = CompactDiamondToggle and CompactDiamondToggle.Enabled
		local showEmerald = CompactEmeraldToggle and CompactEmeraldToggle.Enabled
		local showGold = CompactGoldToggle and CompactGoldToggle.Enabled
		if not showDiamond and not showEmerald and not showGold then
			compactUI.Enabled = false
			return
		end
		diamondFrame.Visible = showDiamond
		emeraldFrame.Visible = showEmerald
		goldFrame.Visible = showGold
		if showDiamond then
			diamondFrame.Position = UDim2.new(0, 10, 0, 35)
		end
		if showEmerald then
			emeraldFrame.Position = UDim2.new(0, 10, 0, showDiamond and 65 or 35)
		end
		if showGold then
			goldFrame.Position = UDim2.new(0, 10, 0, showDiamond and not showEmerald and 65 or showEmerald and not showDiamond or showEmerald and showDiamond and 95 or 35)
		end
		diamondTimes[1] = bestDiamondTime ~= math.huge and bestDiamondTime or 0
		emeraldTimes[1] = bestEmeraldTime ~= math.huge and bestEmeraldTime or 0
		goldTimes[1] = bestGoldTime ~= math.huge and bestGoldTime or 0
		if bestDiamondTime == math.huge then
			diamondTimer.Text = "00"
		else
			diamondTimer.Text = string.format("%02d", bestDiamondTime)
			if bestDiamondTime <= 5 then
				diamondTimer.TextColor3 = Color3.fromRGB(255, 50, 50)
			elseif bestDiamondTime <= 10 then
				diamondTimer.TextColor3 = Color3.fromRGB(255, 165, 0)
			else
				diamondTimer.TextColor3 = Color3.fromRGB(85, 200, 255)
			end
		end
		if bestEmeraldTime == math.huge then
			emeraldTimer.Text = "00"
		else
			emeraldTimer.Text = string.format("%02d", bestEmeraldTime)
			if bestEmeraldTime <= 5 then
				emeraldTimer.TextColor3 = Color3.fromRGB(255, 50, 50)
			elseif bestEmeraldTime <= 10 then
				emeraldTimer.TextColor3 = Color3.fromRGB(255, 165, 0)
			else
				emeraldTimer.TextColor3 = Color3.fromRGB(0, 255, 100)
			end
		end
		if bestGoldTime == math.huge then
			goldTimer.Text = "00"
		else
			goldTimer.Text = string.format("%02d", bestGoldTime)
			if bestGoldTime <= 5 then
				goldTimer.TextColor3 = Color3.fromRGB(255, 50, 50)
			elseif bestGoldTime <= 10 then
				goldTimer.TextColor3 = Color3.fromRGB(255, 165, 0)
			else
				goldTimer.TextColor3 = Color3.fromRGB(0, 255, 100)
			end
		end
	end
	local function clearAllESP()
		Folder:ClearAllChildren()
		table.clear(Reference)
		compactUI.Enabled = false
	end
	local function createESP(generatorAdornee, genType, config, position, teamId)
		if not isGeneratorEnabled(genType, teamId) then
			return
		end
		if Reference[generatorAdornee] then
			return
		end
		if UIStyle.Value == 'Compact' then
			Reference[generatorAdornee] = {
				genType = genType,
				position = position,
				teamId = teamId,
				isTeamGen = config.isTeamGen
			}
			return
		end
		local displayColor = config.color
		local teamName = nil
		if config.isTeamGen and teamId and teamColors[teamId] then
			displayColor = teamColors[teamId].color
			teamName = teamColors[teamId].name
		end
		local billboard = Instance.new('BillboardGui')
		billboard.Parent = Folder
		billboard.Name = 'generator-esp-' .. genType
		billboard.AlwaysOnTop = true
		billboard.ClipsDescendants = false
		billboard.Adornee = generatorAdornee
		if config.isTeamGen then
			billboard.Size = UDim2.fromOffset(180, 55)
			billboard.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
		else
			billboard.Size = UDim2.fromOffset(80, 30)
			billboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
		end
		local blur = addBlur(billboard)
		blur.Visible = true
		if config.isTeamGen and teamName then
			local dot = Instance.new('Frame')
			dot.Name = 'TeamDot'
			dot.Parent = billboard
			dot.Size = UDim2.fromOffset(8, 8)
			dot.Position = UDim2.new(0, 10, 0, 5)
			dot.BackgroundColor3 = displayColor
			dot.BorderSizePixel = 0
			local dotCorner = Instance.new('UICorner')
			dotCorner.CornerRadius = UDim.new(1, 0)
			dotCorner.Parent = dot
			local teamLabel = Instance.new('TextLabel')
			teamLabel.Name = 'TeamLabel'
			teamLabel.Parent = billboard
			teamLabel.BackgroundTransparency = 1
			teamLabel.Size = UDim2.new(1, 0, 0, 18)
			teamLabel.Position = UDim2.new(0, 0, 0, 0)
			teamLabel.Text = teamName
			teamLabel.TextColor3 = displayColor
			teamLabel.TextSize = 13
			teamLabel.Font = Enum.Font.GothamBold
			teamLabel.TextStrokeTransparency = 0.4
			teamLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
			teamLabel.TextXAlignment = Enum.TextXAlignment.Center
		end
		local frame = Instance.new('Frame')
		frame.Size = config.isTeamGen and UDim2.new(1, 0, 0, 35) or UDim2.fromScale(1, 1)
		frame.Position = config.isTeamGen and UDim2.new(0, 0, 0, 20) or UDim2.new(0, 0, 0, 0)
		frame.BackgroundColor3 = Color3.new(0, 0, 0)
		frame.BackgroundTransparency = 0.3
		frame.BorderSizePixel = 0
		frame.Parent = billboard
		if config.isTeamGen and teamId and teamColors[teamId] then
			local stripe = Instance.new('Frame')
			stripe.Name = 'TeamStripe'
			stripe.Parent = frame
			stripe.Size = UDim2.new(0, 3, 1, 0)
			stripe.Position = UDim2.new(0, 0, 0, 0)
			stripe.BackgroundColor3 = displayColor
			stripe.BorderSizePixel = 0
			local stripeCorner = Instance.new('UICorner')
			stripeCorner.CornerRadius = UDim.new(0, 3)
			stripeCorner.Parent = stripe
		end
		local uicorner2 = Instance.new('UICorner')
		uicorner2.CornerRadius = UDim.new(0, 6)
		uicorner2.Parent = frame
		if config.isTeamGen then
			local tierLabel = Instance.new('TextLabel')
			tierLabel.Name = 'Tier'
			tierLabel.Size = UDim2.new(0, 25, 1, 0)
			tierLabel.Position = UDim2.new(0, 8, 0, 0)
			tierLabel.BackgroundTransparency = 1
			tierLabel.Text = "0"
			tierLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
			tierLabel.TextSize = 16
			tierLabel.Font = Enum.Font.GothamBold
			tierLabel.TextStrokeTransparency = 0.5
			tierLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
			tierLabel.Parent = frame
			local resources = {
				{
					name = 'iron',
					color = Color3.fromRGB(200, 200, 200),
					icon = 'iron',
					xOffset = 35
				},
				{
					name = 'diamond',
					color = Color3.fromRGB(85, 200, 255),
					icon = 'diamond',
					xOffset = 85
				},
				{
					name = 'emerald',
					color = Color3.fromRGB(0, 255, 100),
					icon = 'emerald',
					xOffset = 135
				},
				{
					name = 'gold',
					color = Color3.fromRGB(255, 0, 85),
					icon = 'gold',
					xOffset = 185
				},
			}
			local resourceLabels = {}
			for _, resource in ipairs(resources) do
				local iconImage = getProperIcon(resource.icon)
				if iconImage then
					local image = Instance.new('ImageLabel')
					image.Size = UDim2.fromOffset(18, 18)
					image.Position = UDim2.new(0, resource.xOffset, 0.5, 0)
					image.AnchorPoint = Vector2.new(0, 0.5)
					image.BackgroundTransparency = 1
					image.Image = iconImage
					image.Parent = frame
				end
				local countLabel = Instance.new('TextLabel')
				countLabel.Name = resource.name .. '_count'
				countLabel.Size = UDim2.new(0, 25, 1, 0)
				countLabel.Position = UDim2.new(0, resource.xOffset + 20, 0, 0)
				countLabel.BackgroundTransparency = 1
				countLabel.Text = "0"
				countLabel.TextColor3 = resource.color
				countLabel.TextSize = 16
				countLabel.Font = Enum.Font.GothamBold
				countLabel.TextStrokeTransparency = 0.5
				countLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
				countLabel.TextXAlignment = Enum.TextXAlignment.Left
				countLabel.Parent = frame
				resourceLabels[resource.name] = countLabel
			end
			Reference[generatorAdornee] = {
				billboard = billboard,
				tierLabel = tierLabel,
				ironLabel = resourceLabels.iron,
				diamondLabel = resourceLabels.diamond,
				emeraldLabel = resourceLabels.emerald,
				goldLabel = resourceLabels.gold,
				genType = genType,
				position = position,
				teamId = teamId,
				isTeamGen = true
			}
		else
			local iconImage = getProperIcon(config.icon)
			if iconImage then
				local image = Instance.new('ImageLabel')
				image.Size = UDim2.fromOffset(20, 20)
				image.Position = UDim2.new(0, 5, 0.5, 0)
				image.AnchorPoint = Vector2.new(0, 0.5)
				image.BackgroundTransparency = 1
				image.Image = iconImage
				image.Parent = frame
			end
			local timerLabel = Instance.new('TextLabel')
			timerLabel.Name = 'Timer'
			timerLabel.Size = UDim2.new(0, 30, 1, 0)
			timerLabel.Position = UDim2.new(0.5, 0, 0, 0)
			timerLabel.AnchorPoint = Vector2.new(0.5, 0)
			timerLabel.BackgroundTransparency = 1
			timerLabel.Text = "00"
			timerLabel.TextColor3 = displayColor
			timerLabel.TextSize = 18
			timerLabel.Font = Enum.Font.GothamBold
			timerLabel.TextStrokeTransparency = 0.5
			timerLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
			timerLabel.Parent = frame
			local amountLabel = Instance.new('TextLabel')
			amountLabel.Name = 'Amount'
			amountLabel.Size = UDim2.new(0, 20, 1, 0)
			amountLabel.Position = UDim2.new(1, - 20, 0, 0)
			amountLabel.BackgroundTransparency = 1
			amountLabel.Text = "0"
			amountLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			amountLabel.TextSize = 16
			amountLabel.Font = Enum.Font.GothamBold
			amountLabel.TextStrokeTransparency = 0.5
			amountLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
			amountLabel.Parent = frame
			Reference[generatorAdornee] = {
				billboard = billboard,
				timerLabel = timerLabel,
				amountLabel = amountLabel,
				genType = genType,
				position = position,
				teamId = teamId,
				isTeamGen = false
			}
		end
	end
	local function updateESP(generatorAdornee)
		local ref = Reference[generatorAdornee]
		if not ref then
			return
		end
		if UIStyle.Value == 'Compact' then
			return
		end
		if ref.isTeamGen then
			if ref.tierLabel then
				local tierTextLabel = getTierText(generatorAdornee)
				if tierTextLabel and tierTextLabel.Text then
					ref.tierLabel.Text = extractTierLevel(tierTextLabel.Text)
				else
					ref.tierLabel.Text = "0"
				end
			end
			if ref.ironLabel then
				ref.ironLabel.Text = tostring(getResourceCount(ref.position, 'iron'))
			end
			if ref.diamondLabel then
				ref.diamondLabel.Text = tostring(getResourceCount(ref.position, 'diamond'))
			end
			if ref.emeraldLabel then
				ref.emeraldLabel.Text = tostring(getResourceCount(ref.position, 'emerald'))
			end
			if ref.goldLabel then
				ref.goldLabel.Text = tostring(getResourceCount(ref.position, 'gold'))
			end
		else
			local countdownText = getCountdownText(generatorAdornee)
			if countdownText and countdownText.Text then
				local timeLeft = extractSecondsFromText(countdownText.Text)
				if ref.timerLabel then
					ref.timerLabel.Text = string.format("%02d", timeLeft)
					if timeLeft <= 5 then
						ref.timerLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
					elseif timeLeft <= 10 then
						ref.timerLabel.TextColor3 = Color3.fromRGB(255, 165, 0)
					else
						ref.timerLabel.TextColor3 = generatorTypes[ref.genType].color
					end
				end
			else
				if ref.timerLabel then
					ref.timerLabel.Text = "00"
					ref.timerLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
				end
			end
			if ref.amountLabel then
				ref.amountLabel.Text = tostring(getResourceCount(ref.position, ref.genType))
			end
		end
	end
	local function processGeneratorAdornee(obj)
		if obj.Name ~= 'GeneratorAdornee' then
			return
		end
		local ok, generatorId = pcall(function()
			return obj:GetAttribute('Id')
		end)
		if not ok then
			return
		end
		if generatorId == nil then
			return
		end
		if type(generatorId) ~= 'string' then
			return
		end
		if generatorId == '' then
			return
		end
		local position = obj:GetPivot().Position
		local genType, config = getGeneratorType(generatorId)
		if not genType or not config then
			return
		end
		local teamId = getGeneratorTeamId(generatorId)
		if isGeneratorEnabled(genType, teamId) then
			createESP(obj, genType, config, position, teamId)
		end
	end
	local function findAllGenerators()
		for _, obj in pairs(workspace:GetDescendants()) do
			pcall(processGeneratorAdornee, obj)
		end
	end
	local function refreshESP()
		clearAllESP()
		if GeneratorESP.Enabled then
			findAllGenerators()
		end
	end
	local updateTimer = 0
	GeneratorESP = vape.Categories.Render:CreateModule({
		Name = 'Generator ESP',
		Function = function(callback)
			if callback then
				findAllGenerators()
				rebuildCompactGenerators()
				GeneratorESP:Clean(workspace.DescendantAdded:Connect(function(obj)
					if not GeneratorESP.Enabled then
						return
					end
					task.wait(0.2)
					pcall(processGeneratorAdornee, obj)
					if obj.Name == 'GeneratorAdornee' then
						rebuildCompactGenerators()
					end
				end))
				GeneratorESP:Clean(runService.Heartbeat:Connect(function(dt)
					if not GeneratorESP.Enabled then
						return
					end
					updateTimer = updateTimer + dt
					if updateTimer < 0.2 then
						return
					end
					updateTimer = 0
					for generatorAdornee, ref in pairs(Reference) do
						if generatorAdornee and generatorAdornee.Parent then
							updateESP(generatorAdornee)
						else
							if ref.billboard then
								ref.billboard:Destroy()
							end
							Reference[generatorAdornee] = nil
						end
					end
					updateCompactUI()
				end))
				GeneratorESP:Clean(workspace.DescendantRemoving:Connect(function(obj)
					if not GeneratorESP.Enabled then
						return
					end
					if Reference[obj] then
						if Reference[obj].billboard then
							Reference[obj].billboard:Destroy()
						end
						Reference[obj] = nil
					end
				end))
			else
				clearAllESP()
			end
		end,
		Tooltip = 'ESP for generators showing timer and item counts'
	})
	UIStyle = GeneratorESP:CreateDropdown({
		Name = 'UI Style',
		List = {
			'Original',
			'Compact'
		},
		Default = 'Original',
		Function = function(val)
			local isOriginal = val == 'Original'
			if DiamondToggle then
				DiamondToggle.Object.Visible = isOriginal
			end
			if EmeraldToggle then
				EmeraldToggle.Object.Visible = isOriginal
			end
			if GoldToggle then
				GoldToggle.Object.Visible = isOriginal
			end
			if TeamGenToggle then
				TeamGenToggle.Object.Visible = isOriginal
			end
			if ShowOwnTeamGen then
				ShowOwnTeamGen.Object.Visible = isOriginal and TeamGenToggle.Enabled
			end
			if ShowEnemyTeamGen then
				ShowEnemyTeamGen.Object.Visible = isOriginal and TeamGenToggle.Enabled
			end
			if CompactDiamondToggle then
				CompactDiamondToggle.Object.Visible = not isOriginal
			end
			if CompactEmeraldToggle then
				CompactEmeraldToggle.Object.Visible = not isOriginal
			end
			if CompactGoldToggle then
				CompactGoldToggle.Object.Visible = not isOriginal
			end
			refreshESP()
		end,
		Tooltip = 'Choose between original billboard ESP or compact side UI'
	})
	DiamondToggle = GeneratorESP:CreateToggle({
		Name = 'Diamond',
		Function = function()
			refreshESP()
		end,
		Default = false,
		Visible = true
	})
	EmeraldToggle = GeneratorESP:CreateToggle({
		Name = 'Emerald',
		Function = function()
			refreshESP()
		end,
		Default = false,
		Visible = true
	})
	GoldToggle = GeneratorESP:CreateToggle({
		Name = 'Gold',
		Function = function()
			refreshESP()
		end,
		Default = false,
		Visible = true
	})
	CompactDiamondToggle = GeneratorESP:CreateToggle({
		Name = 'Compact Diamond',
		Default = false,
		Visible = false,
		Function = function()
			refreshESP()
		end
	})
	CompactEmeraldToggle = GeneratorESP:CreateToggle({
		Name = 'Compact Emerald',
		Default = false,
		Visible = false,
		Function = function()
			refreshESP()
		end
	})
	CompactGoldToggle = GeneratorESP:CreateToggle({
		Name = 'Compact Gold',
		Default = false,
		Visible = false,
		Function = function()
			refreshESP()
		end
	})
	TeamGenToggle = GeneratorESP:CreateToggle({
		Name = 'Team Generators',
		Function = function(callback)
			if ShowOwnTeamGen then
				ShowOwnTeamGen.Object.Visible = callback
			end
			if ShowEnemyTeamGen then
				ShowEnemyTeamGen.Object.Visible = callback
			end
			refreshESP()
		end,
		Default = true
	})
	ShowOwnTeamGen = GeneratorESP:CreateToggle({
		Name = 'Show Own Team',
		Function = function()
			refreshESP()
		end,
		Default = false,
		Visible = true
	})
	ShowEnemyTeamGen = GeneratorESP:CreateToggle({
		Name = 'Show Enemy Teams',
		Function = function()
			refreshESP()
		end,
		Default = true,
		Visible = true
	})
end)

--[[
	Utility
]]--

run(function()
	local AutoBalloon
	AutoBalloon = vape.Categories.Utility:CreateModule({
		Name = 'Auto Balloon',
		Function = function(callback)
			if callback then
				repeat
					task.wait()
				until store.matchState ~= 0 or (not AutoBalloon.Enabled)
				if not AutoBalloon.Enabled then
					return
				end
				local lowestpoint = math.huge
				for _, v in store.blocks do
					local point = (v.Position.Y - (v.Size.Y / 2)) - 50
					if point < lowestpoint then
						lowestpoint = point
					end
				end
				repeat
					if entitylib.isAlive then
						if entitylib.character.RootPart.Position.Y < lowestpoint and (lplr.Character:GetAttribute('InflatedBalloons') or 0) < 3 then
							local balloon = getItem('balloon')
							if balloon then
								for _ = 1, 3 do
									bedwars.BalloonController:inflateBalloon()
								end
							end
							task.wait(0.1)
						end
					end
					task.wait(0.1)
				until not AutoBalloon.Enabled
			end
		end,
		Tooltip = 'Inflates when you fall into the void'
	})
end)

run(function()
	local AutoPearl
	local rayCheck = RaycastParams.new()
	rayCheck.RespectCanCollide = true
	local projectileRemote = {
		InvokeServer = function()
		end
	}
	task.spawn(function()
		projectileRemote = bedwars.Client:Get(remotes.FireProjectile).instance
	end)
	local function firePearl(pos, spot, item)
		switchItem(item.tool)
		local meta = bedwars.ProjectileMeta.telepearl
		local calc = prediction.SolveTrajectory(pos, meta.launchVelocity, meta.gravitationalAcceleration, spot, Vector3.zero, workspace.Gravity, 0, 0)
		if calc then
			local dir = CFrame.lookAt(pos, calc).LookVector * meta.launchVelocity
			bedwars.ProjectileController:createLocalProjectile(meta, 'telepearl', 'telepearl', pos, nil, dir, {
				drawDurationSeconds = 1
			})
			projectileRemote:InvokeServer(item.tool, 'telepearl', 'telepearl', pos, pos, dir, httpService:GenerateGUID(true), {
				drawDurationSeconds = 1,
				shotId = httpService:GenerateGUID(false)
			}, workspace:GetServerTimeNow() - 0.045)
		end
		if store.hand then
			switchItem(store.hand.tool)
		end
	end
	AutoPearl = vape.Categories.Utility:CreateModule({
		Name = 'Auto Pearl',
		Function = function(callback)
			if callback then
				local check
				repeat
					if entitylib.isAlive then
						local root = entitylib.character.RootPart
						local pearl = getItem('telepearl')
						rayCheck.FilterDescendantsInstances = {
							lplr.Character,
							gameCamera,
							AntiFallPart
						}
						rayCheck.CollisionGroup = root.CollisionGroup
						if pearl and root.Velocity.Y < - 100 and not workspace:Raycast(root.Position, Vector3.new(0, - 200, 0), rayCheck) then
							if not check then
								check = true
								local ground = getNearGround(20)
								if ground then
									firePearl(root.Position, ground, pearl)
								end
							end
						else
							check = false
						end
					end
					task.wait(0.1)
				until not AutoPearl.Enabled
			end
		end,
		Tooltip = 'Automatically throws a pearl onto nearby ground after\nfalling a certain distance.'
	})
end)

run(function()
	local AutoPlay
	local Random
	local function isEveryoneDead()
		return # bedwars.Store:getState().Party.members <= 0
	end
	local function joinQueue()
		if not bedwars.Store:getState().Game.customMatch and bedwars.Store:getState().Party.leader.userId == lplr.UserId and bedwars.Store:getState().Party.queueState == 0 then
			if Random.Enabled then
				local listofmodes = {}
				for i, v in bedwars.QueueMeta do
					if not v.disabled and not v.voiceChatOnly and not v.rankCategory then
						table.insert(listofmodes, i)
					end
				end
				bedwars.QueueController:joinQueue(listofmodes[math.random(1, # listofmodes)])
			else
				bedwars.QueueController:joinQueue(store.queueType)
			end
		end
	end
	AutoPlay = vape.Categories.Utility:CreateModule({
		Name = 'Auto Play',
		Function = function(callback)
			if callback then
				AutoPlay:Clean(vapeEvents.EntityDeathEvent.Event:Connect(function(deathTable)
					if deathTable.finalKill and deathTable.entityInstance == lplr.Character and isEveryoneDead() and store.matchState ~= 2 then
						joinQueue()
					end
				end))
				AutoPlay:Clean(vapeEvents.MatchEndEvent.Event:Connect(joinQueue))
			end
		end,
		Tooltip = 'Automatically queues after the match ends.'
	})
	Random = AutoPlay:CreateToggle({
		Name = 'Random',
		Tooltip = 'Chooses a random mode'
	})
end)

run(function()
	local shooting, old = false
	local function getCrossbows()
		local crossbows = {}
		for i, v in store.inventory.hotbar do
			if v.item and v.item.itemType:find('crossbow') and i ~= (store.inventory.hotbarSlot + 1) then
				table.insert(crossbows, i - 1)
			end
		end
		return crossbows
	end
	vape.Categories.Utility:CreateModule({
		Name = 'Auto Shoot',
		Function = function(callback)
			if callback then
				old = bedwars.ProjectileController.createLocalProjectile
				bedwars.ProjectileController.createLocalProjectile = function(...)
					local source, data, proj = ...
					if source and (proj == 'arrow' or proj == 'fireball') and not shooting then
						task.spawn(function()
							local bows = getCrossbows()
							if # bows > 0 then
								shooting = true
								task.wait(0.15)
								local selected = store.inventory.hotbarSlot
								for _, v in getCrossbows() do
									if hotbarSwitch(v) then
										task.wait(0.05)
										mouse1click()
										task.wait(0.05)
									end
								end
								hotbarSwitch(selected)
								shooting = false
							end
						end)
					end
					return old(...)
				end
			else
				bedwars.ProjectileController.createLocalProjectile = old
			end
		end,
		Tooltip = 'Automatically crossbow macro\'s'
	})
end)

run(function()
	local AutoToxic
	local GG
	local Toggles, Lists, said, dead = {}, {}, {}
	local function sendMessage(name, obj, default)
		local tab = Lists[name].ListEnabled
		local custommsg = # tab > 0 and tab[math.random(1, # tab)] or default
		if not custommsg then
			return
		end
		if # tab > 1 and custommsg == said[name] then
			repeat
				task.wait()
				custommsg = tab[math.random(1, # tab)]
			until custommsg ~= said[name]
		end
		said[name] = custommsg
		custommsg = custommsg and custommsg:gsub('<obj>', obj or '') or ''
		if textChatService.ChatVersion == Enum.ChatVersion.TextChatService then
			textChatService.ChatInputBarConfiguration.TargetTextChannel:SendAsync(custommsg)
		else
			replicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer(custommsg, 'All')
		end
	end
	AutoToxic = vape.Categories.Utility:CreateModule({
		Name = 'Auto Toxic',
		Function = function(callback)
			if callback then
				AutoToxic:Clean(vapeEvents.BedwarsBedBreak.Event:Connect(function(bedTable)
					if Toggles.BedDestroyed.Enabled and bedTable.brokenBedTeam.id == lplr:GetAttribute('Team') then
						sendMessage('BedDestroyed', (bedTable.player.DisplayName or bedTable.player.Name), 'how dare you >:( | <obj>')
					elseif Toggles.Bed.Enabled and bedTable.player.UserId == lplr.UserId then
						local team = bedwars.QueueMeta[store.queueType].teams[tonumber(bedTable.brokenBedTeam.id)]
						sendMessage('Bed', team and team.displayName:lower() or 'white', 'nice bed lul | <obj>')
					end
				end))
				AutoToxic:Clean(vapeEvents.EntityDeathEvent.Event:Connect(function(deathTable)
					if deathTable.finalKill then
						local killer = playersService:GetPlayerFromCharacter(deathTable.fromEntity)
						local killed = playersService:GetPlayerFromCharacter(deathTable.entityInstance)
						if not killed or not killer then
							return
						end
						if killed == lplr then
							if (not dead) and killer ~= lplr and Toggles.Death.Enabled then
								dead = true
								sendMessage('Death', (killer.DisplayName or killer.Name), 'my gaming chair subscription expired :( | <obj>')
							end
						elseif killer == lplr and Toggles.Kill.Enabled then
							sendMessage('Kill', (killed.DisplayName or killed.Name), 'vxp on top | <obj>')
						end
					end
				end))
				AutoToxic:Clean(vapeEvents.MatchEndEvent.Event:Connect(function(winstuff)
					if GG.Enabled then
						if textChatService.ChatVersion == Enum.ChatVersion.TextChatService then
							textChatService.ChatInputBarConfiguration.TargetTextChannel:SendAsync('gg')
						else
							replicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer('gg', 'All')
						end
					end
					local myTeam = bedwars.Store:getState().Game.myTeam
					if myTeam and myTeam.id == winstuff.winningTeamId or lplr.Neutral then
						if Toggles.Win.Enabled then
							sendMessage('Win', nil, 'yall garbage')
						end
					end
				end))
			end
		end,
		Tooltip = 'Says a message after a certain action'
	})
	GG = AutoToxic:CreateToggle({
		Name = 'AutoGG',
		Default = true
	})
	for _, v in {
		'Kill',
		'Death',
		'Bed',
		'BedDestroyed',
		'Win'
	} do
		Toggles[v] = AutoToxic:CreateToggle({
			Name = v .. ' ',
			Function = function(callback)
				if Lists[v] then
					Lists[v].Object.Visible = callback
				end
			end
		})
		Lists[v] = AutoToxic:CreateTextList({
			Name = v,
			Darker = true,
			Visible = false
		})
	end
end)

run(function()
	local AutoVoidDrop
	local OwlCheck
	AutoVoidDrop = vape.Categories.Utility:CreateModule({
		Name = 'Auto Void Drop',
		Function = function(callback)
			if callback then
				repeat
					task.wait()
				until store.matchState ~= 0 or (not AutoVoidDrop.Enabled)
				if not AutoVoidDrop.Enabled then
					return
				end
				local lowestpoint = math.huge
				for _, v in store.blocks do
					local point = (v.Position.Y - (v.Size.Y / 2)) - 50
					if point < lowestpoint then
						lowestpoint = point
					end
				end
				repeat
					if entitylib.isAlive then
						local root = entitylib.character.RootPart
						if root.Position.Y < lowestpoint and (lplr.Character:GetAttribute('InflatedBalloons') or 0) <= 0 and not getItem('balloon') then
							if not OwlCheck.Enabled or not root:FindFirstChild('OwlLiftForce') then
								for _, item in {
									'iron',
									'diamond',
									'emerald',
									'gold'
								} do
									item = getItem(item)
									if item then
										item = bedwars.Client:Get(remotes.DropItem):CallServer({
											item = item.tool,
											amount = item.amount
										})
										if item then
											item:SetAttribute('ClientDropTime', tick() + 100)
										end
									end
								end
							end
						end
					end
					task.wait(0.1)
				until not AutoVoidDrop.Enabled
			end
		end,
		Tooltip = 'Drops resources when you fall into the void'
	})
	OwlCheck = AutoVoidDrop:CreateToggle({
		Name = 'Owl check',
		Default = true,
		Tooltip = 'Refuses to drop items if being picked up by an owl'
	})
end)

run(function()
	local MissileTP
	MissileTP = vape.Categories.Utility:CreateModule({
		Name = 'Missile TP',
		Function = function(callback)
			if callback then
				MissileTP:Toggle()
				local plr = entitylib.EntityMouse({
					Range = 1000,
					Players = true,
					Part = 'RootPart'
				})
				if getItem('guided_missile') and plr then
					local projectile = bedwars.RuntimeLib.await(bedwars.GuidedProjectileController.fireGuidedProjectile:CallServerAsync('guided_missile'))
					if projectile then
						local projectilemodel = projectile.model
						if not projectilemodel.PrimaryPart then
							projectilemodel:GetPropertyChangedSignal('PrimaryPart'):Wait()
						end
						local bodyforce = Instance.new('BodyForce')
						bodyforce.Force = Vector3.new(0, projectilemodel.PrimaryPart.AssemblyMass * workspace.Gravity, 0)
						bodyforce.Name = 'AntiGravity'
						bodyforce.Parent = projectilemodel.PrimaryPart
						repeat
							projectile.model:SetPrimaryPartCFrame(CFrame.lookAlong(plr.RootPart.CFrame.p, gameCamera.CFrame.LookVector))
							task.wait(0.1)
						until not projectile.model or not projectile.model.Parent
					else
						notif('MissileTP', 'Missile on cooldown.', 3)
					end
				end
			end
		end,
		Tooltip = 'Spawns and teleports a missile to a player\nnear your mouse.'
	})
end)

run(function()
	local PickupRange
	local Range
	local Network
	local Lower
	PickupRange = vape.Categories.Utility:CreateModule({
		Name = 'Pickup Range',
		Function = function(callback)
			if callback then
				local items = collection('ItemDrop', PickupRange)
				repeat
					if entitylib.isAlive then
						local localPosition = entitylib.character.RootPart.Position
						for _, v in items do
							if tick() - (v:GetAttribute('ClientDropTime') or 0) < 2 then
								continue
							end
							if isnetworkowner(v) and Network.Enabled and entitylib.character.Humanoid.Health > 0 then
								v.CFrame = CFrame.new(localPosition - Vector3.new(0, 3, 0))
							end
							if (localPosition - v.Position).Magnitude <= Range.Value then
								if Lower.Enabled and (localPosition.Y - v.Position.Y) < (entitylib.character.HipHeight - 1) then
									continue
								end
								task.spawn(function()
									bedwars.Client:Get(remotes.PickupItem):CallServerAsync({
										itemDrop = v
									}):andThen(function(suc)
										if suc and bedwars.SoundList then
											bedwars.SoundManager:playSound(bedwars.SoundList.PICKUP_ITEM_DROP)
											local sound = bedwars.ItemMeta[v.Name].pickUpOverlaySound
											if sound then
												bedwars.SoundManager:playSound(sound, {
													position = v.Position,
													volumeMultiplier = 0.9
												})
											end
										end
									end)
								end)
							end
						end
					end
					task.wait(0.1)
				until not PickupRange.Enabled
			end
		end,
		Tooltip = 'Picks up items from a farther distance'
	})
	Range = PickupRange:CreateSlider({
		Name = 'Range',
		Min = 1,
		Max = 10,
		Default = 10,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	Network = PickupRange:CreateToggle({
		Name = 'Network TP',
		Default = true
	})
	Lower = PickupRange:CreateToggle({
		Name = 'Feet Check'
	})
end)

run(function()
	local RavenTP
	RavenTP = vape.Categories.Utility:CreateModule({
		Name = 'Raven TP',
		Function = function(callback)
			if callback then
				RavenTP:Toggle()
				local plr = entitylib.EntityMouse({
					Range = 1000,
					Players = true,
					NPCs = true,
					Part = 'RootPart'
				})
				if getItem('raven') and plr then
					bedwars.Client:Get(remotes.SpawnRaven):CallServerAsync():andThen(function(projectile)
						if projectile then
							local bodyforce = Instance.new('BodyForce')
							bodyforce.Force = Vector3.new(0, projectile.PrimaryPart.AssemblyMass * workspace.Gravity, 0)
							bodyforce.Parent = projectile.PrimaryPart
							if plr then
								task.spawn(function()
									for _ = 1, 20 do
										if plr.RootPart and projectile then
											projectile:SetPrimaryPartCFrame(CFrame.lookAlong(plr.RootPart.Position, gameCamera.CFrame.LookVector))
										end
										task.wait(0.05)
									end
								end)
								task.wait(0.3)
								bedwars.RavenController:detonateRaven()
							end
						end
					end)
				end
			end
		end,
		Tooltip = 'Spawns and teleports a raven to a player\nnear your mouse.'
	})
end)

run(function()
	local Scaffold
	local Expand
	local Tower
	local Downwards
	local Diagonal
	local LimitItem
	local Mouse
	local adjacent, lastpos, label = {}, Vector3.zero
	for x = - 3, 3, 3 do
		for y = - 3, 3, 3 do
			for z = - 3, 3, 3 do
				local vec = Vector3.new(x, y, z)
				if vec ~= Vector3.zero then
					table.insert(adjacent, vec)
				end
			end
		end
	end
	local function nearCorner(poscheck, pos)
		local startpos = poscheck - Vector3.new(3, 3, 3)
		local endpos = poscheck + Vector3.new(3, 3, 3)
		local check = poscheck + (pos - poscheck).Unit * 100
		return Vector3.new(math.clamp(check.X, startpos.X, endpos.X), math.clamp(check.Y, startpos.Y, endpos.Y), math.clamp(check.Z, startpos.Z, endpos.Z))
	end
	local function blockProximity(pos)
		local mag, returned = 60
		local tab = getBlocksInPoints(bedwars.BlockController:getBlockPosition(pos - Vector3.new(21, 21, 21)), bedwars.BlockController:getBlockPosition(pos + Vector3.new(21, 21, 21)))
		for _, v in tab do
			local blockpos = nearCorner(v, pos)
			local newmag = (pos - blockpos).Magnitude
			if newmag < mag then
				mag, returned = newmag, blockpos
			end
		end
		table.clear(tab)
		return returned
	end
	local function checkAdjacent(pos)
		for _, v in adjacent do
			if getPlacedBlock(pos + v) then
				return true
			end
		end
		return false
	end
	local function getScaffoldBlock()
		if store.hand.toolType == 'block' then
			return store.hand.tool.Name, store.hand.amount
		elseif (not LimitItem.Enabled) then
			local wool, amount = getWool()
			if wool then
				return wool, amount
			else
				for _, item in store.inventory.inventory.items do
					if bedwars.ItemMeta[item.itemType].block then
						return item.itemType, item.amount
					end
				end
			end
		end
		return nil, 0
	end
	Scaffold = vape.Categories.Utility:CreateModule({
		Name = 'Scaffold',
		Function = function(callback)
			if label then
				label.Visible = callback
			end
			if callback then
				repeat
					if entitylib.isAlive then
						local wool, amount = getScaffoldBlock()
						if Mouse.Enabled then
							if not inputService:IsMouseButtonPressed(0) then
								wool = nil
							end
						end
						if label then
							amount = amount or 0
							label.Text = amount .. ' <font color="rgb(170, 170, 170)">(Scaffold)</font>'
							label.TextColor3 = Color3.fromHSV((amount / 128) / 2.8, 0.86, 1)
						end
						if wool then
							local root = entitylib.character.RootPart
							if Tower.Enabled and inputService:IsKeyDown(Enum.KeyCode.Space) and (not inputService:GetFocusedTextBox()) then
								root.Velocity = Vector3.new(root.Velocity.X, 38, root.Velocity.Z)
							end
							for i = Expand.Value, 1, - 1 do
								local currentpos = roundPos(root.Position - Vector3.new(0, entitylib.character.HipHeight + (Downwards.Enabled and inputService:IsKeyDown(Enum.KeyCode.LeftShift) and 4.5 or 1.5), 0) + entitylib.character.Humanoid.MoveDirection * (i * 3))
								if Diagonal.Enabled then
									if math.abs(math.round(math.deg(math.atan2(- entitylib.character.Humanoid.MoveDirection.X, - entitylib.character.Humanoid.MoveDirection.Z)) / 45) * 45) % 90 == 45 then
										local dt = (lastpos - currentpos)
										if ((dt.X == 0 and dt.Z ~= 0) or (dt.X ~= 0 and dt.Z == 0)) and ((lastpos - root.Position) * Vector3.new(1, 0, 1)).Magnitude < 2.5 then
											currentpos = lastpos
										end
									end
								end
								local block, blockpos = getPlacedBlock(currentpos)
								if not block then
									blockpos = checkAdjacent(blockpos * 3) and blockpos * 3 or blockProximity(currentpos)
									if blockpos then
										task.spawn(bedwars.placeBlock, blockpos, wool, false)
									end
								end
								lastpos = currentpos
							end
						end
					end
					task.wait(0.03)
				until not Scaffold.Enabled
			else
				Label = nil
			end
		end,
		Tooltip = 'Helps you make bridges/scaffold walk.'
	})
	Expand = Scaffold:CreateSlider({
		Name = 'Expand',
		Min = 1,
		Max = 6
	})
	Tower = Scaffold:CreateToggle({
		Name = 'Tower',
		Default = true
	})
	Downwards = Scaffold:CreateToggle({
		Name = 'Downwards',
		Default = true
	})
	Diagonal = Scaffold:CreateToggle({
		Name = 'Diagonal',
		Default = true
	})
	LimitItem = Scaffold:CreateToggle({
		Name = 'Limit to items'
	})
	Mouse = Scaffold:CreateToggle({
		Name = 'Require mouse down'
	})
	Count = Scaffold:CreateToggle({
		Name = 'Block Count',
		Function = function(callback)
			if callback then
				label = Instance.new('TextLabel')
				label.Size = UDim2.fromOffset(100, 20)
				label.Position = UDim2.new(0.5, 6, 0.5, 60)
				label.BackgroundTransparency = 1
				label.AnchorPoint = Vector2.new(0.5, 0)
				label.Text = '0'
				label.TextColor3 = Color3.new(0, 1, 0)
				label.TextSize = 18
				label.RichText = true
				label.Font = Enum.Font.Arial
				label.Visible = Scaffold.Enabled
				label.Parent = vape.gui
			else
				label:Destroy()
				label = nil
			end
		end
	})
end)

run(function() -- pasted and fix bugs, but the dev is to slow to understand why pepople crash LO
	local ShopTierBypass
	local tiered, nexttier = {}, {}
	local originalGetShop
	local shopItemsTracked = {}
	local function applyBypassToItem(item)
		if item and type(item) == "table" then
			if not tiered[item] then
				tiered[item] = item.tiered
			end
			if not nexttier[item] then
				nexttier[item] = item.nextTier
			end
			item.nextTier = nil
			item.tiered = nil
			shopItemsTracked[item] = true
		end
	end
	local function applyBypassToTable(tbl)
		if tbl and type(tbl) == "table" then
			for _, item in pairs(tbl) do
				if type(item) == "table" then
					applyBypassToItem(item)
				end
			end
		end
	end
	ShopTierBypass = vape.Categories.Utility:CreateModule({
		Name = 'Shop Tier Bypass',
		Function = function(callback)
			if callback then
				local function collectAndBypass()
					local itemsSeen = {}
					if bedwars.Shop and bedwars.Shop.ShopItems then
						for _, v in pairs(bedwars.Shop.ShopItems) do
							itemsSeen[v] = true
						end
					end
					if bedwars.ShopItems then
						for _, v in pairs(bedwars.ShopItems) do
							itemsSeen[v] = true
						end
					end
					local shopController = bedwars.Shop
					if shopController and shopController and shopController.getShop then
						local shopTable = shopController.getShop()
						if type(shopTable) == "table" then
							for _, v in pairs(shopTable) do
								itemsSeen[v] = true
							end
						end
					end
					for item, _ in pairs(itemsSeen) do
						applyBypassToItem(item)
					end
				end
				collectAndBypass()
				if bedwars.Shop and bedwars.Shop.getShop and not originalGetShop then
					originalGetShop = bedwars.Shop.getShop
					bedwars.Shop.getShop = function(...)
						local result = originalGetShop(...)
						if type(result) == "table" then
							applyBypassToTable(result)
						end
						return result
					end
				end
				local shopController = bedwars.Shop
				if shopController and shopController and shopController.getShop then
					if not tiered["shopControllerHooked"] then
						tiered["shopControllerHooked"] = true
						local originalControllerGetShop = shopController.getShop
						shopController.getShop = function(...)
							local result = originalControllerGetShop(...)
							if type(result) == "table" then
								applyBypassToTable(result)
							end
							return result
						end
					end
				end
			else
				for item, _ in pairs(shopItemsTracked) do
					if item and type(item) == "table" then
						if tiered[item] ~= nil then
							item.tiered = tiered[item]
						end
						if nexttier[item] ~= nil then
							item.nextTier = nexttier[item]
						end
					end
				end
				if tiered["shopControllerHooked"] then
					tiered["shopControllerHooked"] = nil
				end
				if originalGetShop then
					bedwars.Shop.getShop = originalGetShop
					originalGetShop = nil
				end
				table.clear(tiered)
				table.clear(nexttier)
				table.clear(shopItemsTracked)
			end
		end,
		Tooltip = 'Lets you buy things like armor and tools early.'
	})
end)

run(function()
	local StaffDetector
	local Mode
	local Clans
	local Party
	local Profile
	local Users
	local AlertDuration
	local ClosetDetect
	local blacklistedclans = {
		'gg',
		'gg2',
		'DV',
		'DV2',
		'nwr',
		'6_lyz',
		'nwrr'
	}
	local blacklisteduserids = {
		1502104539,
		3826146717,
		4531785383,
		1049767300,
		4926350670,
		653085195,
		184655415,
		2752307430,
		5087196317,
		5744061325,
		1536265275
	}
	local blacklistedusernames = {}
	local apiModNames = {}
	local teamNameMap = {
		[1] = 'Blue',
		[2] = 'Orange',
		[3] = 'Pink',
		[4] = 'Yellow'
	}
	local joined = {}
	local detectedPlayers = {}
	local processing = {}
	local _req = request or function()
		return {
			Body = '{}'
		}
	end
	if not getgenv()._granddad_getBackendUrl then
		local _cachedUrl
		getgenv()._granddad_getBackendUrl = function()
			if _cachedUrl then
				return _cachedUrl
			end
			local ok, res = pcall(function()
				return _req({
					Url = 'https://gist.githubusercontent.com/poopparty/a817668f8805b6d44fa54ff13dc8edf4/raw/url.txt',
					Method = 'GET'
				})
			end)
			if ok and res and res.StatusCode == 200 then
				_cachedUrl = res.Body:match('^%s*(.-)%s*$')
			end
			return _cachedUrl
		end
	end
	local _bu = getgenv()._granddad_getBackendUrl
	local listsLoaded = false
	task.spawn(function()
		local ok1, res1 = pcall(function()
			return _req({
				Url = _bu(),
				Method = 'POST',
				Headers = {
					['Content-Type'] = 'application/json',
					['ngrok-skip-browser-warning'] = 'true'
				},
				Body = httpService:JSONEncode({
					action = 'cheaters'
				})
			})
		end)
		if ok1 and res1 and res1.StatusCode == 200 then
			local dok, data = pcall(function()
				return httpService:JSONDecode(res1.Body)
			end)
			if dok and data and data.activeCheaters then
				for _, name in ipairs(data.activeCheaters) do
					blacklistedusernames[name:lower()] = true
				end
			end
		end
		local ok2, res2 = pcall(function()
			return _req({
				Url = _bu(),
				Method = 'POST',
				Headers = {
					['Content-Type'] = 'application/json',
					['ngrok-skip-browser-warning'] = 'true'
				},
				Body = httpService:JSONEncode({
					action = 'mods'
				})
			})
		end)
		if ok2 and res2 and res2.StatusCode == 200 then
			local dok, data = pcall(function()
				return httpService:JSONDecode(res2.Body)
			end)
			if dok and data and data.activeMods then
				for _, name in ipairs(data.activeMods) do
					apiModNames[name:lower()] = true
				end
			end
		end
		listsLoaded = true
	end)
	getgenv()._granddad_staffCounts = {
		spec = 0,
		closet = 0,
		mod = 0,
		impossible = 0
	}
	local function refreshStaffCounts()
		local c = {
			spec = 0,
			closet = 0,
			mod = 0,
			impossible = 0
		}
		for _, data in pairs(detectedPlayers) do
			local ct = data.checktype
			if ct == 'spectator' then
				c.spec += 1
			elseif ct == 'closet' then
				c.closet += 1
			elseif ct == 'impossible_join' then
				c.impossible += 1
			else
				c.mod += 1
			end
		end
		getgenv()._granddad_staffCounts = c
		vapeEvents.StaffCountUpdate:Fire()
	end
	local function staffFunction(plr, checktype)
		if detectedPlayers[plr.UserId] then
			return
		end
		if not vape.Loaded then
			repeat
				task.wait()
			until vape.Loaded
		end
		local duration = AlertDuration.Value
		local playerName = plr.Name
		local playerId = plr.UserId
		detectedPlayers[playerId] = {
			name = playerName,
			checktype = checktype,
			detectedTime = tick()
		}
		notif('StaffDetector', 'Staff Detected (' .. checktype .. '): ' .. playerName .. ' (' .. playerId .. ')', duration, 'alert')
		whitelist.customtags[playerName] = {
			{
				text = 'GAME STAFF',
				color = Color3.new(1, 0, 0)
			}
		}
		local isClanCheck = checktype:find('clan')
		if Party.Enabled and not isClanCheck then
			pcall(bedwars.PartyController.leaveParty)
		end
		local modeValue = Mode.Value
		if modeValue == 'Uninject' then
			task.spawn(function()
				vape:Uninject()
			end)
			game:GetService('StarterGui'):SetCore('SendNotification', {
				Title = 'StaffDetector',
				Text = 'Staff Detected (' .. checktype .. ')\n' .. playerName .. ' (' .. playerId .. ')',
				Duration = duration
			})
		elseif modeValue == 'Requeue' then
			pcall(bedwars.QueueController.leaveQueue)
			bedwars.QueueController:joinQueue(store.queueType)
		elseif modeValue == 'Profile' then
			vape.Save = function()
			end
			if vape.Profile ~= Profile.Value then
				vape:Load(true, Profile.Value)
			end
		elseif modeValue == 'AutoConfig' then
			local safe = {
				AutoClicker = true,
				Reach = true,
				Sprint = true,
				HitFix = true,
				StaffDetector = true
			}
			vape.Save = function()
			end
			for i, v in vape.Modules do
				if not (safe[i] or v.Category == 'Render') then
					if v.Enabled then
						v:Toggle()
					end
					v:SetBind('')
				end
			end
		end
		refreshStaffCounts()
	end
	local function closetFunction(plr)
		if detectedPlayers[plr.UserId] then
			return
		end
		if not vape.Loaded then
			repeat
				task.wait()
			until vape.Loaded
		end
		local teamNum = tonumber(plr:GetAttribute('Team'))
		local team = teamNum and teamNameMap[teamNum] or 'Unknown'
		detectedPlayers[plr.UserId] = {
			name = plr.Name,
			checktype = 'closet',
			detectedTime = tick()
		}
		notif('StaffDetector', 'KNOWN CLOSETCHEATER: ' .. plr.Name .. ' | Team: ' .. team, AlertDuration.Value, 'alert')
		whitelist.customtags[plr.Name] = {
			{
				text = 'CHEATER',
				color = Color3.fromRGB(255, 140, 0)
			}
		}
		refreshStaffCounts()
	end
	local function checkCloset(plr)
		if not ClosetDetect or not ClosetDetect.Enabled then
			return false
		end
		if plr == lplr then
			return false
		end
		if blacklistedusernames[plr.Name:lower()] then
			task.spawn(function()
				local waited = 0
				while not plr:GetAttribute('Team') and waited < 10 do
					task.wait(0.5)
					waited += 0.5
				end
				closetFunction(plr)
			end)
			return true
		end
		return false
	end
	local function playerAdded(plr)
		joined[plr.UserId] = plr.Name
		if plr == lplr then
			return
		end
		if processing[plr.UserId] then
			return
		end
		processing[plr.UserId] = true
		if not listsLoaded then
			local t = tick()
			repeat
				task.wait(0.1)
			until listsLoaded or (tick() - t > 3)
		end
		if checkCloset(plr) then
			processing[plr.UserId] = nil
			return
		end
		if table.find(blacklisteduserids, plr.UserId) or (Users and table.find(Users.ListEnabled, tostring(plr.UserId))) then
			staffFunction(plr, 'blacklisted_user')
			processing[plr.UserId] = nil
			return
		end
		if apiModNames[plr.Name:lower()] then
			staffFunction(plr, 'known_mod')
			processing[plr.UserId] = nil
			return
		end
		local function spectatorFunction(plr)
			if detectedPlayers[plr.UserId] then
				return
			end
			if not vape.Loaded then
				repeat
					task.wait()
				until vape.Loaded
			end
			detectedPlayers[plr.UserId] = {
				name = plr.Name,
				checktype = 'spectator',
				detectedTime = tick()
			}
			notif('StaffDetector', 'Spectator: ' .. plr.Name .. ' (' .. tostring(plr.UserId) .. ') [Has friend in server]', AlertDuration.Value, 'warning')
			refreshStaffCounts()
		end
		local function checkJoin()
			if not plr:GetAttribute('Team') and plr:GetAttribute('Spectator') then
				local hasFriend = false
				for _, sp in ipairs(playersService:GetPlayers()) do
					if sp ~= plr then
						local ok, res = pcall(function()
							return plr:IsFriendsWith(sp.UserId)
						end)
						if ok and res then
							hasFriend = true
							break
						end
					end
				end
				if hasFriend then
					spectatorFunction(plr)
				else
					staffFunction(plr, 'impossible_join')
				end
				return true
			end
			return false
		end
		local spectatorConnection
		spectatorConnection = plr:GetAttributeChangedSignal('Spectator'):Connect(function()
			if checkJoin() then
				spectatorConnection:Disconnect()
				processing[plr.UserId] = nil
			end
		end)
		StaffDetector:Clean(spectatorConnection)
		if checkJoin() then
			processing[plr.UserId] = nil
			return
		end
		if Clans.Enabled then
			local function checkClanTag()
				local clanTag = plr:GetAttribute('ClanTag')
				if clanTag and table.find(blacklistedclans, clanTag) then
					staffFunction(plr, 'blacklisted_clan_' .. clanTag:lower())
				end
			end
			if plr:GetAttribute('ClanTag') then
				checkClanTag()
			else
				local clanConnection
				clanConnection = plr:GetAttributeChangedSignal('ClanTag'):Connect(function()
					clanConnection:Disconnect()
					checkClanTag()
				end)
				StaffDetector:Clean(clanConnection)
				task.delay(5, function()
					if clanConnection then
						clanConnection:Disconnect()
					end
				end)
			end
		end
		processing[plr.UserId] = nil
	end
	local function playerRemoving(plr)
		local userId = plr.UserId
		joined[userId] = nil
		processing[userId] = nil
		if detectedPlayers[userId] then
			local data = detectedPlayers[userId]
			notif('StaffDetector', data.name .. ' (' .. data.checktype .. ') has left the server', AlertDuration.Value, 'warning')
			if whitelist.customtags[data.name] then
				whitelist.customtags[data.name] = nil
			end
			detectedPlayers[userId] = nil
			refreshStaffCounts()
		end
	end
	StaffDetector = vape.Categories.Utility:CreateModule({
		Name = 'Staff Detector',
		Function = function(callback)
			if callback then
				StaffDetector:Clean(playersService.PlayerAdded:Connect(playerAdded))
				StaffDetector:Clean(playersService.PlayerRemoving:Connect(playerRemoving))
				for _, v in playersService:GetPlayers() do
					task.spawn(playerAdded, v)
				end
			else
				table.clear(joined)
				table.clear(processing)
				table.clear(detectedPlayers)
				refreshStaffCounts()
			end
		end,
		Tooltip = 'Detects people with a staff rank ingame'
	})
	Mode = StaffDetector:CreateDropdown({
		Name = 'Mode',
		List = {
			'Uninject',
			'Profile',
			'Requeue',
			'AutoConfig',
			'Notify'
		},
		Function = function(val)
			if Profile.Object then
				Profile.Object.Visible = val == 'Profile'
			end
		end
	})
	AlertDuration = StaffDetector:CreateSlider({
		Name = 'Alert Duration',
		Min = 5,
		Max = 120,
		Default = 60,
		Suffix = 's',
		Tooltip = 'How long the alert notification stays on screen'
	})
	Clans = StaffDetector:CreateToggle({
		Name = 'Blacklist clans',
		Default = true
	})
	Party = StaffDetector:CreateToggle({
		Name = 'Leave party'
	})
	ClosetDetect = StaffDetector:CreateToggle({
		Name = 'Known Cheaters',
		Default = true,
		Tooltip = 'Alerts when a known closet cheater joins your game'
	})
	Profile = StaffDetector:CreateTextBox({
		Name = 'Profile',
		Default = 'default',
		Darker = true,
		Visible = false
	})
	Users = StaffDetector:CreateTextList({
		Name = 'Users',
		Placeholder = 'player (userid)',
		Function = function()
		end
	})
	task.defer(function()
		if Profile and Profile.Object then
			Profile.Object.Visible = (Mode.Value == 'Profile')
		end
	end)
end)

run(function()
	TrapDisabler = vape.Categories.Utility:CreateModule({
		Name = 'Trap Disabler',
		Tooltip = 'Disables Snap Traps'
	})
end)

run(function()
	local BlockIn
	local SpeedSlider
	local DelaySlider
	local AutoSwitch
	local HandCheck
	local StrongestOnly
	local CpsConstants = nil
	local originalCPS = 12
	local placing = false
	local buildThread = nil
	local facesOnly = {
		Vector3.new(3, 0, 0),
		Vector3.new(- 3, 0, 0),
		Vector3.new(0, 3, 0),
		Vector3.new(0, - 3, 0),
		Vector3.new(0, 0, 3),
		Vector3.new(0, 0, - 3)
	}
	local function checkFaceAdjacent(pos)
		for _, v in facesOnly do
			if getPlacedBlock(pos + v) then
				return true
			end
		end
		return false
	end
	local function hasFaceBelowOrSide(pos)
		if getPlacedBlock(pos - Vector3.new(0, 3, 0)) then
			return true
		end
		for _, v in facesOnly do
			if v.Y == 0 and getPlacedBlock(pos + v) then
				return true
			end
		end
		return false
	end
	local function canPlaceAtPosition(blockpos)
		if not checkFaceAdjacent(blockpos) then
			return false
		end
		local checkBelow = blockpos - Vector3.new(0, 3, 0)
		local hasSupport = false
		for i = 1, 10 do
			if getPlacedBlock(checkBelow) then
				hasSupport = true
				break
			end
			checkBelow = checkBelow - Vector3.new(0, 3, 0)
		end
		return hasSupport or hasFaceBelowOrSide(blockpos)
	end
	local function initCPS()
		pcall(function()
			CpsConstants = bedwars.SharedConstants.CpsConstants
		end)
		if not CpsConstants then
			pcall(function()
				CpsConstants = bedwars.SharedConstants.CpsConstants
			end)
		end
		if CpsConstants then
			originalCPS = CpsConstants.BLOCK_PLACE_CPS
		end
	end
	local function setCPS(value)
		if CpsConstants then
			CpsConstants.BLOCK_PLACE_CPS = value
		end
	end
	local function getBlocks()
		local blocks = {}
		for _, item in pairs(store.inventory.inventory.items) do
			if bedwars.ItemMeta[item.itemType] and bedwars.ItemMeta[item.itemType].block then
				local meta = bedwars.ItemMeta[item.itemType]
				table.insert(blocks, {
					itemType = item.itemType,
					health = meta.block.health or 0,
					tool = item.tool
				})
			end
		end
		table.sort(blocks, function(a, b)
			return a.health > b.health
		end)
		return blocks
	end
	local function getHotbarSlotForBlock(blockTool)
		for i, v in pairs(store.inventory.hotbar) do
			if v.item and v.item.tool == blockTool then
				return i - 1
			end
		end
		return nil
	end
	local function hasBlockAt(pos)
		local block, blockpos = getPlacedBlock(pos)
		return block ~= nil
	end
	local function getScaffoldBlock()
		if HandCheck.Enabled then
			if store.hand and store.hand.toolType == 'block' then
				return store.hand.tool.Name
			end
			return nil
		else
			local blocks = getBlocks()
			if # blocks == 0 then
				return nil
			end
			if StrongestOnly.Enabled then
				return blocks[1].itemType
			else
				local weakestInHotbar = nil
				local weakestHealth = math.huge
				for _, block in ipairs(blocks) do
					local slot = getHotbarSlotForBlock(block.tool)
					if slot then
						if block.health < weakestHealth then
							weakestHealth = block.health
							weakestInHotbar = block
						end
					end
				end
				if weakestInHotbar then
					return weakestInHotbar.itemType
				else
					return blocks[1].itemType
				end
			end
		end
	end
	local function findGaps(origin)
		local gaps = {}
		local offsets = {
			Vector3.new(3, 0, 0),
			Vector3.new(- 3, 0, 0),
			Vector3.new(0, 3, 0),
			Vector3.new(0, - 3, 0),
			Vector3.new(0, 0, 3),
			Vector3.new(0, 0, - 3),
			Vector3.new(3, 3, 0),
			Vector3.new(- 3, 3, 0),
			Vector3.new(0, 3, 3),
			Vector3.new(0, 3, - 3),
			Vector3.new(0, 6, 0),
		}
		for _, offset in ipairs(offsets) do
			local pos = origin + offset
			if not hasBlockAt(pos) then
				table.insert(gaps, pos)
			end
		end
		return gaps
	end
	local function hasMovedSignificantly(startPos, currentPos)
		local distance = (startPos - currentPos).Magnitude
		return distance > 2
	end
	local function executeBlockIn()
		if placing then
			return
		end
		placing = true
		buildThread = task.spawn(function()
			while BlockIn.Enabled and placing do
				if not entitylib.isAlive then
					notif('BlockIn', 'Not alive', 2)
					placing = false
					BlockIn:Toggle()
					return
				end
				local blockToUse = getScaffoldBlock()
				if not blockToUse then
					task.wait(0.1)
					continue
				end
				setCPS(SpeedSlider.Value)
				local startOrigin = entitylib.character.RootPart.Position
				local gaps = findGaps(startOrigin)
				if # gaps == 0 then
					if AutoSwitch.Enabled and not HandCheck.Enabled then
						pcall(function()
							hotbarSwitch(store.inventory.hotbarSlot)
						end)
					end
					setCPS(originalCPS)
					placing = false
					task.wait(0.1)
					if BlockIn.Enabled then
						BlockIn:Toggle()
					end
					return
				end
				local originalSlot = store.inventory.hotbarSlot
				local delay = DelaySlider.Value / 1000
				local function restoreSlot()
					if AutoSwitch.Enabled and not HandCheck.Enabled and originalSlot then
						pcall(function()
							hotbarSwitch(originalSlot)
						end)
					end
				end
				if AutoSwitch.Enabled and not HandCheck.Enabled then
					local blocks = getBlocks()
					if # blocks > 0 then
						local targetBlock = nil
						if StrongestOnly.Enabled then
							targetBlock = blocks[1]
						else
							local weakestInHotbar = nil
							local weakestHealth = math.huge
							for _, block in ipairs(blocks) do
								local slot = getHotbarSlotForBlock(block.tool)
								if slot then
									if block.health < weakestHealth then
										weakestHealth = block.health
										weakestInHotbar = block
									end
								end
							end
							targetBlock = weakestInHotbar or blocks[1]
						end
						if targetBlock then
							local slot = getHotbarSlotForBlock(targetBlock.tool)
							if slot then
								hotbarSwitch(slot)
								task.wait(0.05)
							end
						end
					end
				end
				for i, pos in ipairs(gaps) do
					if not BlockIn.Enabled or not placing then
						break
					end
					local currentBlock = getScaffoldBlock()
					if not currentBlock then
						break
					end
					if not entitylib.isAlive then
						break
					end
					local currentPos = entitylib.character.RootPart.Position
					if hasMovedSignificantly(startOrigin, currentPos) then
					end
					if not hasBlockAt(pos) then
						if hasFaceBelowOrSide(pos) then
							if canPlaceAtPosition(pos) then
								pcall(bedwars.placeBlock, pos, currentBlock, false)
							end
						else
							local nearestBlock = blockProximity(pos)
							if nearestBlock and canPlaceAtPosition(nearestBlock) then
								pcall(bedwars.placeBlock, nearestBlock, currentBlock, false)
							end
						end
					end
					if i < # gaps then
						task.wait(delay)
					end
				end
				restoreSlot()
				task.wait(0.1)
			end
			restoreSlot()
			setCPS(originalCPS)
			placing = false
		end)
	end
	BlockIn = vape.Categories.Utility:CreateModule({
		Name = 'Block In',
		Function = function(callback)
			if callback then
				initCPS()
				executeBlockIn()
			else
				placing = false
				if buildThread then
					pcall(function()
						task.cancel(buildThread)
					end)
					buildThread = nil
				end
				setCPS(originalCPS)
			end
		end,
		Tooltip = 'Surrounds you with blocks (real-time gap detection)'
	})
	SpeedSlider = BlockIn:CreateSlider({
		Name = 'Speed',
		Min = 1,
		Max = 12,
		Default = 12,
		Suffix = ' CPS',
		Function = function(val)
			if BlockIn.Enabled then
				setCPS(val)
			end
		end,
		Tooltip = 'Block placement speed'
	})
	DelaySlider = BlockIn:CreateSlider({
		Name = 'Delay',
		Min = 0,
		Max = 200,
		Default = 50,
		Suffix = 'ms',
		Function = function(val)
		end,
		Tooltip = 'Delay between blocks'
	})
	AutoSwitch = BlockIn:CreateToggle({
		Name = 'Auto Switch',
		Default = true,
		Function = function(val)
		end,
		Tooltip = 'Auto switch to blocks'
	})
	HandCheck = BlockIn:CreateToggle({
		Name = 'Hand Check',
		Default = false,
		Function = function(val)
		end,
		Tooltip = 'Only build when holding block'
	})
	StrongestOnly = BlockIn:CreateToggle({
		Name = 'Strongest Only',
		Default = false,
		Function = function(val)
		end,
		Tooltip = 'Use strongest block only (obsidian)'
	})
end)

run(function()
	local BedAlarm
	local Range
	local Volume
	local Ticks
	local Highlight
	local bedcache, cachedelay = nil, 0
	local function getBed()
		if bedcache and bedcache.Parent and cachedelay > tick() then
			return bedcache
		end
		if entitylib.isAlive then
			local id = lplr.Character:GetAttribute('Team')
			for i, v in collectionService:GetTagged('bed') do
				if tonumber(id) == tonumber(v:GetAttribute('TeamId')) then
					bedcache, cachedelay = v, tick() + (Ticks.Value * Ticks.Value)
					return v
				end
			end
		end
		return
	end
	BedAlarm = vape.Categories.Utility:CreateModule({
		Name = 'Bed Alarm',
		Function = function(callback)
			if callback then
				local Notifytick = os.clock()
				local highlight = {}
				repeat
					local bed, localpos = getBed(), nil
					if bed then
						localpos = bed:GetPivot().Position
					end
					if localpos then
						local ent = localpos and entitylib.AllPosition({
							Origin = localpos,
							Range = Range.Value,
							Part = 'RootPart',
							Players = true,
						})
						if ent and # ent > 0 and os.clock() > Notifytick then
							Notifytick = os.clock() + Ticks.Value
							if Highlight.Enabled then
								for _, v in ent do
									if not highlight[v.Character] then
										highlight[v.Character] = true
										bedwars.BedAlarmController:addIntruderPlayerHighlight(v.Player)
									end
								end
							end
							bedwars.NotificationController:sendInfoNotification({
								message = '[Bed Alarm]: An intruder is near your bed!',
							})
							bedwars.SoundManager:playSound(bedwars.SoundList.BED_ALARM, {
								volumeMultiplier = Volume.Value,
							})
						end
					end
					task.wait(0.1)
				until not BedAlarm.Enabled
			end
		end,
		Tooltip = 'Notifies when theres an enemy near bed',
	})
	Highlight = BedAlarm:CreateToggle({
		Name = 'Highlight intruders',
		Tooltip = "Shows where the intruders are\n(just like bedwar's bed alarm)",
		Default = true,
	})
	Range = BedAlarm:CreateSlider({
		Name = 'Range',
		Min = 1,
		Max = 100,
		Default = 70,
		Suffix = function(val)
			return val <= 1 and 'stud' or 'studs'
		end,
	})
	Volume = BedAlarm:CreateSlider({
		Name = 'Volume multiplier',
		Min = 0.1,
		Max = 2,
		Default = 1.4,
		Decimal = 100,
	})
	Ticks = BedAlarm:CreateSlider({
		Name = 'Tick',
		Min = 0,
		Max = 8,
		Default = 3.05,
		Decimal = 100,
	})
end)

run(function()
	local Party
	Party = vape.Categories.Utility:CreateModule({
		Name = "Leave Party",
		Function = function(callback)
			if not callback then
				return
			end
			Party:Toggle()
			bedwars.PartyController:leaveParty()
		end
	})
end)

--[[
	World
]]--

run(function()
	vape.Categories.World:CreateModule({
		Name = 'Anti AFK',
		Function = function(callback)
			if callback then
				for _, v in getconnections(lplr.Idled) do
					v:Disconnect()
				end
				bedwars.Client:Get('AfkInfo'):SendToServer({
					afk = false
				})
			end
		end,
		Tooltip = 'Lets you stay ingame without getting kicked'
	})
end)

run(function() -- had to fix this shit dev nocollision from strachLOL
	local NoCollision
	local defaults = {}
	local tracked = {}
	local function removeCollision()
		for _, ent in entitylib.List do
			if not ent.Character then
				continue
			end
			for _, obj in ent.Character:GetDescendants() do
				if not obj:IsA("BasePart") then
					continue
				end
				if not tracked[obj] then
					tracked[obj] = true
					table.insert(defaults, {
						obj = obj,
						origColl = obj.CanCollide,
						origQuery = obj.CanQuery,
					})
				end
				obj.CanCollide = false
				obj.CanQuery = false
			end
		end
	end
	local function reAddCollisions()
		for i = # defaults, 1, - 1 do
			local val = defaults[i]
			if val.obj and val.obj.Parent then
				val.obj.CanCollide = val.origColl
				val.obj.CanQuery = val.origQuery
			end
			defaults[i] = nil
		end
	end
	NoCollision = vape.Categories.World:CreateModule({
		Name = 'No Collision',
		Function = function(callback)
			if callback then
				removeCollision()
				NoCollision:Clean(entitylib.Events.EntityAdded:Connect(removeCollision))
				NoCollision:Clean(entitylib.Events.EntityRemoved:Connect(removeCollision))
				NoCollision:Clean(entitylib.Events.EntityUpdated:Connect(removeCollision))
			else
				reAddCollisions()
			end
		end
	})
end)

run(function()
	local AutoSuffocate
	local Range
	local LimitItem
	local function fixPosition(pos)
		return bedwars.BlockController:getBlockPosition(pos) * 3
	end
	AutoSuffocate = vape.Categories.World:CreateModule({
		Name = 'Auto Suffocate',
		Function = function(callback)
			if callback then
				repeat
					local item = store.hand.toolType == 'block' and store.hand.tool.Name or not LimitItem.Enabled and getWool()
					if item then
						local plrs = entitylib.AllPosition({
							Part = 'RootPart',
							Range = Range.Value,
							Players = true
						})
						for _, ent in plrs do
							local needPlaced = {}
							for _, side in Enum.NormalId:GetEnumItems() do
								side = Vector3.fromNormalId(side)
								if side.Y ~= 0 then
									continue
								end
								side = fixPosition(ent.RootPart.Position + side * 2)
								if not getPlacedBlock(side) then
									table.insert(needPlaced, side)
								end
							end
							if # needPlaced < 3 then
								table.insert(needPlaced, fixPosition(ent.Head.Position))
								table.insert(needPlaced, fixPosition(ent.RootPart.Position - Vector3.new(0, 1, 0)))
								for _, pos in needPlaced do
									if not getPlacedBlock(pos) then
										task.spawn(bedwars.placeBlock, pos, item)
										break
									end
								end
							end
						end
					end
					task.wait(0.09)
				until not AutoSuffocate.Enabled
			end
		end,
		Tooltip = 'Places blocks on nearby confined entities'
	})
	Range = AutoSuffocate:CreateSlider({
		Name = 'Range',
		Min = 1,
		Max = 20,
		Default = 20,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	LimitItem = AutoSuffocate:CreateToggle({
		Name = 'Limit to Items',
		Default = true
	})
end)

run(function()
	local AutoTool
	local Click
	local Select
	local old, event
	local function switchHotbarItem(block)
		if block and not block:GetAttribute('NoBreak') and not block:GetAttribute('Team' .. (lplr:GetAttribute('Team') or 0) .. 'NoBreak') then
			local tool, slot = store.tools[bedwars.ItemMeta[block.Name].block.breakType], nil
			if tool then
				for i, v in store.inventory.hotbar do
					if v.item and v.item.itemType == tool.itemType then
						slot = i - 1
						break
					end
				end
				if hotbarSwitch(slot) then
					if Click.Enabled then
						if inputService:IsMouseButtonPressed(0) then
							event:Fire()
						end
					end
					return true
				end
			end
		end
	end
	AutoTool = vape.Categories.World:CreateModule({
		Name = 'Auto Tool',
		Function = function(callback)
			if callback then
				event = Instance.new('BindableEvent')
				AutoTool:Clean(event)
				AutoTool:Clean(event.Event:Connect(function()
					contextActionService:CallFunction('block-break', Enum.UserInputState.Begin, newproxy(true))
				end))
				if not Select.Enabled then
					if old then
						pcall(function()
							old:destroyFunction()
						end)
						old = nil
					end
					old = bedwars.BlockBreaker.hitBlock
					bedwars.BlockBreaker.hitBlock = function(self, maid, raycastparams, ...)
						local block = self.clientManager:getBlockSelector():getMouseInfo(1, {
							ray = raycastparams
						})
						if switchHotbarItem(block and block.target and block.target.blockInstance or nil) then
							return
						end
						return old(self, maid, raycastparams, ...)
					end
				else
					if old then
						bedwars.BlockBreaker.hitBlock = old
						old = nil
					end
					old = bedwars.BlockEngineClientEvents.BeforeHighlightBlock:connect(function(self)
						if store.hand.tool and bedwars.ItemMeta[store.hand.tool.Name].breakBlock then
							if self.mouseInfo.target then
								local block = self.mouseInfo.target.blockInstance
								if switchHotbarItem(block) then
									return
								end
							end
						end
					end)
				end
			else
				if typeof(old) == 'table' then
					old:destroyFunction()
				else
					bedwars.BlockBreaker.hitBlock = old
				end
				old = nil
			end
		end,
		Tooltip = 'Automatically selects the correct tool'
	})
	Click = AutoTool:CreateToggle({
		Name = "Should Click",
		Default = true,
		Tooltip = 'should mine when clicked?'
	})
	Select = AutoTool:CreateToggle({
		Name = "On Select",
		Default = false,
		Tooltip = 'should swap when hovering over the block',
		Function = function()
			AutoTool:Toggle()
			AutoTool:Toggle()
		end
	})
end)

run(function()
	local BedProtector
	local Range
	local UpdateRate
	local function getBedNear()
		local localPosition = entitylib.isAlive and entitylib.character.RootPart.Position or Vector3.zero
		for _, v in collectionService:GetTagged('bed') do
			if (localPosition - v.Position).Magnitude < math.clamp(Range.Value, 3, 30) and v:GetAttribute('Team' .. (lplr:GetAttribute('Team') or - 1) .. 'NoBreak') then
				return v
			end
		end
	end
	local function getBlocks()
		local blocks = {}
		for _, item in store.inventory.inventory.items do
			local block = bedwars.ItemMeta[item.itemType].block
			if block then
				table.insert(blocks, {
					item.itemType,
					block.health
				})
			end
		end
		table.sort(blocks, function(a, b)
			return a[2] > b[2]
		end)
		return blocks
	end
	local function getPyramid(size, grid)
		local positions = {}
		local pos = {}
		for h = size, 0, - 1 do
			for w = h, 0, - 1 do
				local new = {
					[1] = Vector3.new(- 3, 0, - 0),
					[2] = Vector3.new(3, 0, 3),
					[3] = Vector3.new(- 0, 0, - 3),
					[4] = Vector3.new(0, 0, 3),
					[5] = Vector3.new(3, 0, - 3),
					[6] = Vector3.new(- 0, 3, - 0),
					[7] = Vector3.new(3, 3, 0),
					[8] = Vector3.new(6, 0, 0),
				}
				for i, v in new do
					table.insert(positions, v)
				end
			end
		end
		return positions
	end
	BedProtector = vape.Categories.World:CreateModule({
		Name = 'Bed Protector',
		Function = function(callback)
			if callback then
				local bed = getBedNear()
				bed = bed and bed.Position or nil
				if bed then
					for i, block in getBlocks() do
						for _, pos in getPyramid(i, 3) do
							if not BedProtector.Enabled then
								break
							end
							if getPlacedBlock(bed + pos) then
								continue
							end
							bedwars.placeBlock(bed + pos, block[1], false)
							task.wait(1 / UpdateRate.Value)
						end
					end
					if BedProtector.Enabled then
						BedProtector:Toggle()
					end
				else
					notif('BedProtector', 'Unable to locate bed', 5)
					BedProtector:Toggle()
				end
			end
		end,
		Tooltip = 'Automatically places strong blocks around the bed.'
	})
	UpdateRate = BedProtector:CreateSlider({
		Name = 'Rate',
		Min = 0,
		Max = 360,
		Default = 60,
		Suffix = 'hz'
	})
	Range = BedProtector:CreateSlider({
		Name = 'Bed Range',
		Min = 3,
		Max = 30,
		Default = 20,
		Suffix = function (val)
			return val == 1 and 'stud' or 'studs'
		end
	})
end)

run(function()
	local ChestSteal
	local Range
	local Open
	local Skywars
	local Delays = {}
	local function lootChest(chest)
		chest = chest and chest.Value or nil
		local chestitems = chest and chest:GetChildren() or {}
		if # chestitems > 1 and (Delays[chest] or 0) < tick() then
			Delays[chest] = tick() + 0.2
			bedwars.Client:GetNamespace('Inventory'):Get('SetObservedChest'):SendToServer(chest)
			for _, v in chestitems do
				if v:IsA('Accessory') then
					task.spawn(function()
						pcall(function()
							bedwars.Client:GetNamespace('Inventory'):Get('ChestGetItem'):CallServer(chest, v)
						end)
					end)
				end
			end
			bedwars.Client:GetNamespace('Inventory'):Get('SetObservedChest'):SendToServer(nil)
		end
	end
	ChestSteal = vape.Categories.World:CreateModule({
		Name = 'Chest Steal',
		Function = function(callback)
			if callback then
				local chests = collection('chest', ChestSteal)
				repeat
					task.wait()
				until store.queueType ~= 'bedwars_test'
				if (not Skywars.Enabled) or store.queueType:find('skywars') then
					repeat
						if entitylib.isAlive and store.matchState ~= 2 then
							if Open.Enabled then
								if bedwars.AppController:isAppOpen('ChestApp') then
									lootChest(lplr.Character:FindFirstChild('ObservedChestFolder'))
								end
							else
								local localPosition = entitylib.character.RootPart.Position
								for _, v in chests do
									if (localPosition - v.Position).Magnitude <= Range.Value then
										lootChest(v:FindFirstChild('ChestFolderValue'))
									end
								end
							end
						end
						task.wait(0.1)
					until not ChestSteal.Enabled
				end
			end
		end,
		Tooltip = 'Grabs items from near chests.'
	})
	Range = ChestSteal:CreateSlider({
		Name = 'Range',
		Min = 0,
		Max = 18,
		Default = 18,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	Open = ChestSteal:CreateToggle({
		Name = 'GUI Check'
	})
	Skywars = ChestSteal:CreateToggle({
		Name = 'Only Skywars',
		Function = function()
			if ChestSteal.Enabled then
				ChestSteal:Toggle()
				ChestSteal:Toggle()
			end
		end,
		Default = true
	})
end)

run(function()
	local Schematica
	local File
	local Mode
	local Transparency
	local parts, guidata, poschecklist = {}, {}, {}
	local point1, point2
	for x = - 3, 3, 3 do
		for y = - 3, 3, 3 do
			for z = - 3, 3, 3 do
				if Vector3.new(x, y, z) ~= Vector3.zero then
					table.insert(poschecklist, Vector3.new(x, y, z))
				end
			end
		end
	end
	local function checkAdjacent(pos)
		for _, v in poschecklist do
			if getPlacedBlock(pos + v) then
				return true
			end
		end
		return false
	end
	local function getPlacedBlocksInPoints(s, e)
		local list, blocks = {}, bedwars.BlockController:getStore()
		for x = (e.X > s.X and s.X or e.X), (e.X > s.X and e.X or s.X) do
			for y = (e.Y > s.Y and s.Y or e.Y), (e.Y > s.Y and e.Y or s.Y) do
				for z = (e.Z > s.Z and s.Z or e.Z), (e.Z > s.Z and e.Z or s.Z) do
					local vec = Vector3.new(x, y, z)
					local block = blocks:getBlockAt(vec)
					if block and block:GetAttribute('PlacedByUserId') == lplr.UserId then
						list[vec] = block
					end
				end
			end
		end
		return list
	end
	local function loadMaterials()
		for _, v in guidata do
			v:Destroy()
		end
		local suc, read = pcall(function()
			return isfile(File.Value) and httpService:JSONDecode(readfile(File.Value))
		end)
		if suc and read then
			local items = {}
			for _, v in read do
				items[v[2]] = (items[v[2]] or 0) + 1
			end
			for i, v in items do
				local holder = Instance.new('Frame')
				holder.Size = UDim2.new(1, 0, 0, 32)
				holder.BackgroundTransparency = 1
				holder.Parent = Schematica.Children
				local icon = Instance.new('ImageLabel')
				icon.Size = UDim2.fromOffset(24, 24)
				icon.Position = UDim2.fromOffset(4, 4)
				icon.BackgroundTransparency = 1
				icon.Image = bedwars.getIcon({
					itemType = i
				}, true)
				icon.Parent = holder
				local text = Instance.new('TextLabel')
				text.Size = UDim2.fromOffset(100, 32)
				text.Position = UDim2.fromOffset(32, 0)
				text.BackgroundTransparency = 1
				text.Text = (bedwars.ItemMeta[i] and bedwars.ItemMeta[i].displayName or i) .. ': ' .. v
				text.TextXAlignment = Enum.TextXAlignment.Left
				text.TextColor3 = uipallet.Text
				text.TextSize = 14
				text.FontFace = uipallet.Font
				text.Parent = holder
				table.insert(guidata, holder)
			end
			table.clear(read)
			table.clear(items)
		end
	end
	local function save()
		if point1 and point2 then
			local tab = getPlacedBlocksInPoints(point1, point2)
			local savetab = {}
			point1 = point1 * 3
			for i, v in tab do
				i = bedwars.BlockController:getBlockPosition(CFrame.lookAlong(point1, entitylib.character.RootPart.CFrame.LookVector):PointToObjectSpace(i * 3)) * 3
				table.insert(savetab, {
					{
						x = i.X,
						y = i.Y,
						z = i.Z
					},
					v.Name
				})
			end
			point1, point2 = nil, nil
			writefile(File.Value, httpService:JSONEncode(savetab))
			notif('Schematica', 'Saved ' .. getTableSize(tab) .. ' blocks', 5)
			loadMaterials()
			table.clear(tab)
			table.clear(savetab)
		else
			local mouseinfo = bedwars.BlockBreaker.clientManager:getBlockSelector():getMouseInfo(0)
			if mouseinfo and mouseinfo.target then
				if point1 then
					point2 = mouseinfo.target.blockRef.blockPosition
					notif('Schematica', 'Selected position 2, toggle again near position 1 to save it', 3)
				else
					point1 = mouseinfo.target.blockRef.blockPosition
					notif('Schematica', 'Selected position 1', 3)
				end
			end
		end
	end
	local function load(read)
		local mouseinfo = bedwars.BlockBreaker.clientManager:getBlockSelector():getMouseInfo(0)
		if mouseinfo and mouseinfo.target then
			local position = CFrame.new(mouseinfo.placementPosition * 3) * CFrame.Angles(0, math.rad(math.round(math.deg(math.atan2(- entitylib.character.RootPart.CFrame.LookVector.X, - entitylib.character.RootPart.CFrame.LookVector.Z)) / 45) * 45), 0)
			for _, v in read do
				local blockpos = bedwars.BlockController:getBlockPosition((position * CFrame.new(v[1].x, v[1].y, v[1].z)).p) * 3
				if parts[blockpos] then
					continue
				end
				local handler = bedwars.BlockController:getHandlerRegistry():getHandler(v[2]:find('wool') and getWool() or v[2])
				if handler then
					local part = handler:place(blockpos / 3, 0)
					part.Transparency = Transparency.Value
					part.CanCollide = false
					part.Anchored = true
					part.Parent = workspace
					parts[blockpos] = part
				end
			end
			table.clear(read)
			repeat
				if entitylib.isAlive then
					local localPosition = entitylib.character.RootPart.Position
					for i, v in parts do
						if (i - localPosition).Magnitude < 60 and checkAdjacent(i) then
							if not Schematica.Enabled then
								break
							end
							if not getItem(v.Name) then
								continue
							end
							bedwars.placeBlock(i, v.Name, false)
							task.delay(0.1, function()
								local block = getPlacedBlock(i)
								if block then
									v:Destroy()
									parts[i] = nil
								end
							end)
						end
					end
				end
				task.wait()
			until getTableSize(parts) <= 0
			if getTableSize(parts) <= 0 and Schematica.Enabled then
				notif('Schematica', 'Finished building', 5)
				Schematica:Toggle()
			end
		end
	end
	Schematica = vape.Categories.World:CreateModule({
		Name = 'Schematica',
		Function = function(callback)
			if callback then
				if not File.Value:find('.json') then
					notif('Schematica', 'Invalid file', 3)
					Schematica:Toggle()
					return
				end
				if Mode.Value == 'Save' then
					save()
					Schematica:Toggle()
				else
					local suc, read = pcall(function()
						return isfile(File.Value) and httpService:JSONDecode(readfile(File.Value))
					end)
					if suc and read then
						load(read)
					else
						notif('Schematica', 'Missing / corrupted file', 3)
						Schematica:Toggle()
					end
				end
			else
				for _, v in parts do
					v:Destroy()
				end
				table.clear(parts)
			end
		end,
		Tooltip = 'Save and load placements of buildings'
	})
	File = Schematica:CreateTextBox({
		Name = 'File',
		Function = function()
			loadMaterials()
			point1, point2 = nil, nil
		end
	})
	Mode = Schematica:CreateDropdown({
		Name = 'Mode',
		List = {
			'Load',
			'Save'
		}
	})
	Transparency = Schematica:CreateSlider({
		Name = 'Transparency',
		Min = 0,
		Max = 1,
		Default = 0.7,
		Decimal = 10,
		Function = function(val)
			for _, v in parts do
				v.Transparency = val
			end
		end
	})
end)

--[[
	Inventory
]]--

run(function()
	local AutoFish
	local ESP
	local Blacklist
	local List
	local Minigame
	local Delay
	local AutoCast
	local CastingDelay

	local old
	local function getRod()
		for _, obj in workspace:GetChildren() do
			if obj.Name == 'fisherman_bobber' and v:GetAttribute('ProjectileShooter') == lplr.UserId then
				return v
			end
		end	
		return
	end

	AutoFish = vape.Categories.Inventory:CreateModule({
		Name = 'Auto Fish',
		Function = function(callback)
			if callback then
				if Minigame.Enabled then
					old = clonefunction(bedwars.FishingMinigameController.startMinigame)
					hookfunction(bedwars.FishingMinigameController.startMinigame, function(_, _, func)
						if Minigame.Enabled then
							task.delay(Delay:GetRandomValue() + lplr:GetNetworkPing(), function()
								func({win = true})
							end)
						end
					end)
				end
				AutoFish:Clean(bedwars.Client:Get('FishFound'):Connect(function(data)
					if data.dropData and data.dropData.drops then
						for _, v in data.dropData.drops do
							if ESP.Enabled then
								local itemDisplay = bedwars.ItemMeta[v.itemType] and bedwars.ItemMeta[v.itemType].displayName or v.itemType
								local amount = math.ceil(v.amount) * 1.4
								notif('Auto Fish',`You can get {amount} {itemDisplay:lower()}{amount ~= 1 and 's' or ''} on ur next fish`,20,'info')
							end

							if entitylib.isAlive and Blacklist.Enabled and table.find(List.ListEnabled, v.itemType) then
								lplr.Character.Humanoid.Jump = true
							end
						end
					end
				end))
    			repeat
    				if entitylib.isAlive and AutoCast.Enabled and (store.hand.tool and store.hand.tool.Name == 'fishing_rod') then
    					local position = workspace.CurrentCamera.ViewportSize / 2
    					local ray = cloneref(lplr:GetMouse()).UnitRay
    					if not getRod() and not workspace:Raycast(entitylib.character.Head.Position + (ray.Direction * 6), Vector3.new(0, -20, 0)) then
    						task.delay(CastingDelay:GetRandomValue() + lplr:GetNetworkPing(), function()
								for _, v in {true, false} do
									VirtualService:SendMouseButtonEvent(position.X, position.Y, 0, v, game, 1)
									task.wait()
								end
								task.wait(0.5)
							end)
    					end
    				end
    				task.wait(0.1)
    			until not AutoFish.Enabled
			else
				local suc, res = pcall(function()
					restorefunction(bedwars.FishingMinigameController.startMinigame)
				end)
				if not suc then
					bedwars.FishingMinigameController.startMinigame = old
				end
				old = nil
			end
		end
	})

	ESP = AutoFish:CreateToggle({
		Name = 'Show fish loot',
		Tooltip = 'Tells you your next lootdrop',
	})
	Blacklist = AutoFish:CreateToggle({
		Name = 'Blacklist',
		Tooltip = 'Enables the blacklist fish',
		Default = true,
		Function = function(callback)
			if List then List.Object.Visible = callback end
		end
	})
	List = AutoFish:CreateTextList({
    	Name = 'Blacklisted loot',
    	Tooltip = 'Automatically jumps if u found a fish with the blacklisted item',
    	Default = {'iron'},
		Darker = true,
		Visible = Blacklist.Enabled
    })
    Minigame = AutoFish:CreateToggle({
    	Name = 'Auto Minigame',
    	Tooltip = 'Automatically completes the minigame',
    	Default = true,
    	Function = function(call)
    		pcall(function()
    			CompleteDelay.Object.Visible = call
    		end)
    	end,
    })
    Delay = AutoFish:CreateTwoSlider({
    	Name = 'Complete delay',
    	Min = 0,
    	Max = 25,
    	Decimal = 5,
    	DefaultMin = 0.1,
    	DefaultMax = 0.9,
    	Darker = true,
    })
    AutoCast = AutoFish:CreateToggle({
    	Name = 'Auto Cast',
    	Tooltip = 'Automatically casts ur fishng rod',
    	Function = function(call)
    		pcall(function()
    			CastingDelay.Object.Visible = call
    		end)
    	end,
    })
    CastingDelay = AutoFish:CreateTwoSlider({
    	Name = 'Cast delay',
    	Min = 0,
    	Max = 5,
    	Decimal = 5,
    	DefaultMin = 0.3,
    	DefaultMax = 1.2,
    	Darker = true,
    	Visible = false,
    })
end)

run(function()
	local ArmorSwitch
	local Mode
	local Targets
	local Range
	ArmorSwitch = vape.Categories.Inventory:CreateModule({
		Name = 'Armor Switch',
		Function = function(callback)
			if callback then
				if Mode.Value == 'Toggle' then
					repeat
						local state = entitylib.EntityPosition({
							Part = 'RootPart',
							Range = Range.Value,
							Players = Targets.Players.Enabled,
							NPCs = Targets.NPCs.Enabled,
							Wallcheck = Targets.Walls.Enabled
						}) and true or false
						for i = 0, 2 do
							if (store.inventory.inventory.armor[i + 1] ~= 'empty') ~= state and ArmorSwitch.Enabled then
								bedwars.Store:dispatch({
									type = 'InventorySetArmorItem',
									item = store.inventory.inventory.armor[i + 1] == 'empty' and state and getBestArmor(i) or nil,
									armorSlot = i
								})
								vapeEvents.InventoryChanged.Event:Wait()
							end
						end
						task.wait(0.1)
					until not ArmorSwitch.Enabled
				else
					ArmorSwitch:Toggle()
					for i = 0, 2 do
						bedwars.Store:dispatch({
							type = 'InventorySetArmorItem',
							item = store.inventory.inventory.armor[i + 1] == 'empty' and getBestArmor(i) or nil,
							armorSlot = i
						})
						vapeEvents.InventoryChanged.Event:Wait()
					end
				end
			end
		end,
		Tooltip = 'Puts on / takes off armor when toggled for baiting.'
	})
	Mode = ArmorSwitch:CreateDropdown({
		Name = 'Mode',
		List = {
			'Toggle',
			'On Key'
		}
	})
	Targets = ArmorSwitch:CreateTargets({
		Players = true,
		NPCs = true
	})
	Range = ArmorSwitch:CreateSlider({
		Name = 'Range',
		Min = 1,
		Max = 30,
		Default = 30,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
end)

run(function()
	local AutoBank
	local UIToggle
	local UI
	local Chests
	local Items = {}
	local function addItem(itemType, shop)
		local item = Instance.new('ImageLabel')
		item.Image = bedwars.getIcon({
			itemType = itemType
		}, true)
		item.Size = UDim2.fromOffset(32, 32)
		item.Name = itemType
		item.BackgroundTransparency = 1
		item.LayoutOrder = # UI:GetChildren()
		item.Parent = UI
		local itemtext = Instance.new('TextLabel')
		itemtext.Name = 'Amount'
		itemtext.Size = UDim2.fromScale(1, 1)
		itemtext.BackgroundTransparency = 1
		itemtext.Text = ''
		itemtext.TextColor3 = Color3.new(1, 1, 1)
		itemtext.TextSize = 16
		itemtext.TextStrokeTransparency = 0.3
		itemtext.Font = Enum.Font.Arial
		itemtext.Parent = item
		Items[itemType] = {
			Object = itemtext,
			Type = shop
		}
	end
	local function refreshBank(echest)
		for i, v in Items do
			local item = echest:FindFirstChild(i)
			v.Object.Text = item and item:GetAttribute('Amount') or ''
		end
	end
	local function nearChest()
		if entitylib.isAlive then
			local pos = entitylib.character.RootPart.Position
			for _, chest in Chests do
				if (chest.Position - pos).Magnitude < 20 then
					return true
				end
			end
		end
	end
	local function handleState()
		local chest = replicatedStorage.Inventories:FindFirstChild(lplr.Name .. '_personal')
		if not chest then
			return
		end
		local mapCF = workspace.MapCFrames:FindFirstChild((lplr:GetAttribute('Team') or 1) .. '_spawn')
		if mapCF and (entitylib.character.RootPart.Position - mapCF.Value.Position).Magnitude < 80 then
			for _, v in chest:GetChildren() do
				local item = Items[v.Name]
				if item then
					task.spawn(function()
						bedwars.Client:GetNamespace('Inventory'):Get('ChestGetItem'):CallServer(chest, v)
						refreshBank(chest)
					end)
				end
			end
		else
			for _, v in store.inventory.inventory.items do
				local item = Items[v.itemType]
				if item then
					task.spawn(function()
						bedwars.Client:GetNamespace('Inventory'):Get('ChestGiveItem'):CallServer(chest, v.tool)
						refreshBank(chest)
					end)
				end
			end
		end
	end
	AutoBank = vape.Categories.Inventory:CreateModule({
		Name = 'Auto Bank',
		Function = function(callback)
			if callback then
				Chests = collection('personal-chest', AutoBank)
				UI = Instance.new('Frame')
				UI.Size = UDim2.new(1, 0, 0, 32)
				UI.Position = UDim2.fromOffset(0, - 240)
				UI.BackgroundTransparency = 1
				UI.Visible = UIToggle.Enabled
				UI.Parent = vape.gui
				AutoBank:Clean(UI)
				local Sort = Instance.new('UIListLayout')
				Sort.FillDirection = Enum.FillDirection.Horizontal
				Sort.HorizontalAlignment = Enum.HorizontalAlignment.Center
				Sort.SortOrder = Enum.SortOrder.LayoutOrder
				Sort.Parent = UI
				addItem('iron', true)
				addItem('gold', true)
				addItem('diamond', false)
				addItem('emerald', true)
				addItem('void_crystal', true)
				repeat
					local hotbar = lplr.PlayerGui:FindFirstChild('hotbar')
					hotbar = hotbar and hotbar['1']:FindFirstChild('HotbarHealthbarContainer')
					if hotbar then
						UI.Position = UDim2.fromOffset(0, (hotbar.AbsolutePosition.Y + guiService:GetGuiInset().Y) - 40)
					end
					local newState = nearChest()
					if newState then
						handleState()
					end
					task.wait(0.1)
				until (not AutoBank.Enabled)
			else
				table.clear(Items)
			end
		end,
		Tooltip = 'Automatically puts resources in ender chest'
	})
	UIToggle = AutoBank:CreateToggle({
		Name = 'UI',
		Function = function(callback)
			if AutoBank.Enabled then
				UI.Visible = callback
			end
		end,
		Default = true
	})
end)

run(function()
	local AutoBuy
	local Sword
	local Armor
	local Upgrades
	local TierCheck
	local BedwarsCheck
	local GUI
	local SmartCheck
	local Custom = {}
	local CustomPost = {}
	local UpgradeToggles = {}
	local Functions, id = {}
	local Callbacks = {
		Custom,
		Functions,
		CustomPost
	}
	local npctick = tick()
	local swords = {
		'wood_sword',
		'stone_sword',
		'iron_sword',
		'diamond_sword',
		'emerald_sword'
	}
	local armors = {
		'none',
		'leather_chestplate',
		'iron_chestplate',
		'diamond_chestplate',
		'emerald_chestplate'
	}
	local axes = {
		'none',
		'wood_axe',
		'stone_axe',
		'iron_axe',
		'diamond_axe'
	}
	local pickaxes = {
		'none',
		'wood_pickaxe',
		'stone_pickaxe',
		'iron_pickaxe',
		'diamond_pickaxe'
	}
	local function getShopNPC()
		local shop, items, upgrades, newid = nil, false, false, nil
		if entitylib.isAlive then
			local localPosition = entitylib.character.RootPart.Position
			for _, v in store.shop do
				if (v.RootPart.Position - localPosition).Magnitude <= 20 then
					shop = v.Upgrades or v.Shop or nil
					upgrades = upgrades or v.Upgrades
					items = items or v.Shop
					newid = v.Shop and v.Id or newid
				end
			end
		end
		return shop, items, upgrades, newid
	end
	local function canBuy(item, currencytable, amount)
		amount = amount or 1
		if not currencytable[item.currency] then
			local currency = getItem(item.currency)
			currencytable[item.currency] = currency and currency.amount or 0
		end
		if item.ignoredByKit and table.find(item.ignoredByKit, store.equippedKit or '') then
			return false
		end
		if item.lockedByForge or item.disabled then
			return false
		end
		if item.require and item.require.teamUpgrade then
			if (bedwars.Store:getState().Bedwars.teamUpgrades[item.require.teamUpgrade.upgradeId] or - 1) < item.require.teamUpgrade.lowestTierIndex then
				return false
			end
		end
		return currencytable[item.currency] >= (item.price * amount)
	end
	local function buyItem(item, currencytable)
		if not id then
			return
		end
		notif('AutoBuy', 'Bought ' .. bedwars.ItemMeta[item.itemType].displayName, 3)
		bedwars.Client:Get('BedwarsPurchaseItem'):CallServerAsync({
			shopItem = item,
			shopId = id
		}):andThen(function(suc)
			if suc then
				bedwars.SoundManager:playSound(bedwars.SoundList.BEDWARS_PURCHASE_ITEM)
				bedwars.Store:dispatch({
					type = 'BedwarsAddItemPurchased',
					itemType = item.itemType
				})
				bedwars.BedwarsShopController.alreadyPurchasedMap[item.itemType] = true
			end
		end)
		currencytable[item.currency] -= item.price
	end
	local function buyUpgrade(upgradeType, currencytable)
		if not Upgrades.Enabled then
			return
		end
		local upgrade = bedwars.TeamUpgradeMeta[upgradeType]
		local currentUpgrades = bedwars.Store:getState().Bedwars.teamUpgrades[lplr:GetAttribute('Team')] or {}
		local currentTier = (currentUpgrades[upgradeType] or 0) + 1
		local bought = false
		for i = currentTier, # upgrade.tiers do
			local tier = upgrade.tiers[i]
			if tier.availableOnlyInQueue and not table.find(tier.availableOnlyInQueue, store.queueType) then
				continue
			end
			if canBuy({
				currency = 'diamond',
				price = tier.cost
			}, currencytable) then
				notif('AutoBuy', 'Bought ' .. (upgrade.name == 'Armor' and 'Protection' or upgrade.name) .. ' ' .. i, 3)
				bedwars.Client:Get('RequestPurchaseTeamUpgrade'):CallServerAsync(upgradeType)
				currencytable.diamond -= tier.cost
				bought = true
			else
				break
			end
		end
		return bought
	end
	local function buyTool(tool, tools, currencytable)
		local bought, buyable = false
		tool = tool and table.find(tools, tool.itemType) and table.find(tools, tool.itemType) + 1 or math.huge
		for i = tool, # tools do
			local v = bedwars.Shop.getShopItem(tools[i], lplr)
			if canBuy(v, currencytable) then
				if SmartCheck.Enabled and bedwars.ItemMeta[tools[i]].breakBlock and i > 2 then
					if Armor.Enabled then
						local currentarmor = store.inventory.inventory.armor[2]
						currentarmor = currentarmor and currentarmor ~= 'empty' and currentarmor.itemType or 'none'
						if (table.find(armors, currentarmor) or 3) < 3 then
							break
						end
					end
					if Sword.Enabled then
						if store.tools.sword and (table.find(swords, store.tools.sword.itemType) or 2) < 2 then
							break
						end
					end
				end
				bought = true
				buyable = v
			end
			if TierCheck.Enabled and v.nextTier then
				break
			end
		end
		if buyable then
			buyItem(buyable, currencytable)
		end
		return bought
	end
	AutoBuy = vape.Categories.Inventory:CreateModule({
		Name = 'Auto Buy',
		Function = function(callback)
			if callback then
				repeat
					task.wait()
				until store.queueType ~= 'bedwars_test'
				if BedwarsCheck.Enabled and not store.queueType:find('bedwars') then
					return
				end
				local lastupgrades
				AutoBuy:Clean(vapeEvents.InventoryAmountChanged.Event:Connect(function()
					if (npctick - tick()) > 1 then
						npctick = tick()
					end
				end))
				repeat
					local npc, shop, upgrades, newid = getShopNPC()
					id = newid
					if GUI.Enabled then
						if not (bedwars.AppController:isAppOpen('BedwarsItemShopApp') or bedwars.AppController:isAppOpen('TeamUpgradeApp')) then
							npc = nil
						end
					end
					if npc and lastupgrades ~= upgrades then
						if (npctick - tick()) > 1 then
							npctick = tick()
						end
						lastupgrades = upgrades
					end
					if npc and npctick <= tick() and store.matchState ~= 2 and store.shopLoaded then
						local currencytable = {}
						local waitcheck
						for _, tab in Callbacks do
							for _, callback in tab do
								if callback(currencytable, shop, upgrades) then
									waitcheck = true
								end
							end
						end
						npctick = tick() + (waitcheck and 0.4 or math.huge)
					end
					task.wait(0.1)
				until not AutoBuy.Enabled
			else
				npctick = tick()
			end
		end,
		Tooltip = 'Automatically buys items when you go near the shop'
	})
	Sword = AutoBuy:CreateToggle({
		Name = 'Buy Sword',
		Function = function(callback)
			npctick = tick()
			Functions[2] = callback and function(currencytable, shop)
				if not shop then
					return
				end
				if store.equippedKit == 'dasher' then
					swords = {
						[1] = 'wood_dao',
						[2] = 'stone_dao',
						[3] = 'iron_dao',
						[4] = 'diamond_dao',
						[5] = 'emerald_dao'
					}
				elseif store.equippedKit == 'ice_queen' then
					swords[5] = 'ice_sword'
				elseif store.equippedKit == 'ember' then
					swords[5] = 'infernal_saber'
				elseif store.equippedKit == 'lumen' then
					swords[5] = 'light_sword'
				end
				return buyTool(store.tools.sword, swords, currencytable)
			end or nil
		end
	})
	Armor = AutoBuy:CreateToggle({
		Name = 'Buy Armor',
		Function = function(callback)
			npctick = tick()
			Functions[1] = callback and function(currencytable, shop)
				if not shop then
					return
				end
				local currentarmor = store.inventory.inventory.armor[2] ~= 'empty' and store.inventory.inventory.armor[2] or getBestArmor(1)
				currentarmor = currentarmor and currentarmor.itemType or 'none'
				return buyTool({
					itemType = currentarmor
				}, armors, currencytable)
			end or nil
		end,
		Default = true
	})
	AutoBuy:CreateToggle({
		Name = 'Buy Axe',
		Function = function(callback)
			npctick = tick()
			Functions[3] = callback and function(currencytable, shop)
				if not shop then
					return
				end
				return buyTool(store.tools.wood or {
					itemType = 'none'
				}, axes, currencytable)
			end or nil
		end
	})
	AutoBuy:CreateToggle({
		Name = 'Buy Pickaxe',
		Function = function(callback)
			npctick = tick()
			Functions[4] = callback and function(currencytable, shop)
				if not shop then
					return
				end
				return buyTool(store.tools.stone, pickaxes, currencytable)
			end or nil
		end
	})
	Upgrades = AutoBuy:CreateToggle({
		Name = 'Buy Upgrades',
		Function = function(callback)
			for _, v in UpgradeToggles do
				v.Object.Visible = callback
			end
		end,
		Default = true
	})
	local count = 0
	for i, v in bedwars.TeamUpgradeMeta do
		local toggleCount = count
		table.insert(UpgradeToggles, AutoBuy:CreateToggle({
			Name = 'Buy ' .. (v.name == 'Armor' and 'Protection' or v.name),
			Function = function(callback)
				npctick = tick()
				Functions[5 + toggleCount + (v.name == 'Armor' and 20 or 0)] = callback and function(currencytable, shop, upgrades)
					if not upgrades then
						return
					end
					if v.disabledInQueue and table.find(v.disabledInQueue, store.queueType) then
						return
					end
					return buyUpgrade(i, currencytable)
				end or nil
			end,
			Darker = true,
			Default = (i == 'ARMOR' or i == 'DAMAGE')
		}))
		count += 1
	end
	TierCheck = AutoBuy:CreateToggle({
		Name = 'Tier Check'
	})
	BedwarsCheck = AutoBuy:CreateToggle({
		Name = 'Only Bedwars',
		Function = function()
			if AutoBuy.Enabled then
				AutoBuy:Toggle()
				AutoBuy:Toggle()
			end
		end,
		Default = true
	})
	GUI = AutoBuy:CreateToggle({
		Name = 'GUI check'
	})
	SmartCheck = AutoBuy:CreateToggle({
		Name = 'Smart check',
		Default = true,
		Tooltip = 'Buys iron armor before iron axe'
	})
	AutoBuy:CreateTextList({
		Name = 'Item',
		Placeholder = 'priority/item/amount/after',
		Function = function(list)
			table.clear(Custom)
			table.clear(CustomPost)
			for _, entry in list do
				local tab = entry:split('/')
				local ind = tonumber(tab[1])
				if ind then
					(tab[4] and CustomPost or Custom)[ind] = function(currencytable, shop)
						if not shop then
							return
						end
						local v = bedwars.Shop.getShopItem(tab[2], lplr)
						if v then
							local item = getItem(tab[2] == 'wool_white' and bedwars.Shop.getTeamWool(lplr:GetAttribute('Team')) or tab[2])
							item = (item and tonumber(tab[3]) - item.amount or tonumber(tab[3])) // v.amount
							if item > 0 and canBuy(v, currencytable, item) then
								for _ = 1, item do
									buyItem(v, currencytable)
								end
								return true
							end
						end
					end
				end
			end
		end
	})
end)

run(function()
	local AutoConsume
	local Health
	local SpeedPotion
	local Apple
	local GodApple
	local Orange
	local Delay
	local Limit
	local ShieldPotion
	local function consumeCheck(attribute)
		if entitylib.isAlive then
			task.wait(Delay.Value - lplr:GetNetworkPing())
			if SpeedPotion.Enabled and (not attribute or attribute == 'StatusEffect_speed') then
				local speedpotion = getItem('speed_potion')
				if speedpotion and (not lplr.Character:GetAttribute('StatusEffect_speed')) then
					if Limit.Enabled and not store.hand.tool.Name == 'speed_potion' then return end
					for _ = 1, 4 do
						if bedwars.Client:Get(remotes.ConsumeItem):CallServer({
							item = speedpotion.tool
						}) then
							break
						end
					end
				end
			end
			if Apple.Enabled and (not attribute or attribute:find('Health')) then
				if (lplr.Character:GetAttribute('Health') / lplr.Character:GetAttribute('MaxHealth')) <= (Health.Value / 100) then
					local apple = getItem('apple')
					if apple then
						if Limit.Enabled and not store.hand.tool.Name == 'apple' then return end
						bedwars.Client:Get(remotes.ConsumeItem):CallServerAsync({
							item = apple.tool
						})
					end
				end
			end
			if ShieldPotion.Enabled and (not attribute or attribute:find('Shield')) then
				if (lplr.Character:GetAttribute('Shield_POTION') or 0) == 0 then
					local shield = getItem('big_shield') or getItem('mini_shield')
					if shield then
						if Limit.Enabled and not store.hand.tool.Name == 'big_shield' or not store.hand.tool.Name == 'mini_shield' then return end
						bedwars.Client:Get(remotes.ConsumeItem):CallServerAsync({
							item = shield.tool
						})
					end
				end
			end
			if GodApple.Enabled and (not attribute or attribute:find('Health')) then
				if (lplr.Character:GetAttribute('Health') / lplr.Character:GetAttribute('MaxHealth')) <= (Health.Value / 100) then
					local apple = getItem('golden_apple')
					if apple then
						if Limit.Enabled and not store.hand.tool.Name == 'golden_apple' then return end
						bedwars.Client:Get('ConsumeItem'):CallServerAsync({
							item = apple.tool
						})
					end
				end
			end
			if Orange.Enabled and (not attribute or attribute:find('Health')) then
				if (lplr.Character:GetAttribute('Health') / lplr.Character:GetAttribute('MaxHealth')) <= (Health.Value / 100) then
					local orange = getItem('orange')
					if orange then
						if Limit.Enabled and not store.hand.tool.Name == 'orange' then return end
						bedwars.Client:Get(remotes.ConsumeItem):CallServerAsync({
							item = orange.tool
						})
					end
				end
			end
		end
	end
	AutoConsume = vape.Categories.Inventory:CreateModule({
		Name = 'Auto Consume',
		Function = function(callback)
			if callback then
				AutoConsume:Clean(vapeEvents.InventoryAmountChanged.Event:Connect(consumeCheck))
				AutoConsume:Clean(vapeEvents.AttributeChanged.Event:Connect(function(attribute)
					if attribute:find('Shield') or attribute:find('Health') or attribute == 'StatusEffect_speed' then
						consumeCheck(attribute)
					end
				end))
				consumeCheck()
			end
		end,
		Tooltip = 'Automatically heals for you when health or shield is under threshold.'
	})
	Delay = AutoConsume:CreateSlider({
		Name = 'Delay',
		Min = 0,
		Max = 2,
		Default = 0.8,
		Decimal = 100,
		Suffix = 's'
	})
	Limit = AutoConsume:CreateToggle({
		Name = 'Limit to items',
		Default = true
	})
	Health = AutoConsume:CreateSlider({
		Name = 'Health Percent',
		Min = 1,
		Max = 99,
		Default = 70,
		Suffix = '%'
	})
	SpeedPotion = AutoConsume:CreateToggle({
		Name = 'Speed Potions',
		Default = true
	})
	Apple = AutoConsume:CreateToggle({
		Name = 'Apple',
		Default = false
	})
	GodApple = AutoConsume:CreateToggle({
		Name = 'God Apple',
		Default = true
	})
	Orange = AutoConsume:CreateToggle({
		Name = 'Orange',
		Default = true
	})
	ShieldPotion = AutoConsume:CreateToggle({
		Name = 'Shield Potions',
		Default = true
	})
end)

run(function()
	local AutoHotbar
	local Mode
	local Clear
	local List
	local Active
	local function CreateWindow(self)
		local selectedslot = 1
		local window = Instance.new('Frame')
		window.Name = 'HotbarGUI'
		window.Size = UDim2.fromOffset(660, 465)
		window.Position = UDim2.fromScale(0.5, 0.5)
		window.BackgroundColor3 = uipallet.Main
		window.AnchorPoint = Vector2.new(0.5, 0.5)
		window.Visible = false
		window.Parent = vape.gui.ScaledGui
		local title = Instance.new('TextLabel')
		title.Name = 'Title'
		title.Size = UDim2.new(1, - 10, 0, 20)
		title.Position = UDim2.fromOffset(math.abs(title.Size.X.Offset), 12)
		title.BackgroundTransparency = 1
		title.Text = 'AutoHotbar'
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextColor3 = uipallet.Text
		title.TextSize = 13
		title.FontFace = uipallet.Font
		title.Parent = window
		local divider = Instance.new('Frame')
		divider.Name = 'Divider'
		divider.Size = UDim2.new(1, 0, 0, 1)
		divider.Position = UDim2.fromOffset(0, 40)
		divider.BackgroundColor3 = color.Light(uipallet.Main, 0.04)
		divider.BorderSizePixel = 0
		divider.Parent = window
		addBlur(window)
		local modal = Instance.new('TextButton')
		modal.Text = ''
		modal.BackgroundTransparency = 1
		modal.Modal = true
		modal.Parent = window
		local corner = Instance.new('UICorner')
		corner.CornerRadius = UDim.new(0, 5)
		corner.Parent = window
		local close = Instance.new('ImageButton')
		close.Name = 'Close'
		close.Size = UDim2.fromOffset(24, 24)
		close.Position = UDim2.new(1, - 35, 0, 9)
		close.BackgroundColor3 = Color3.new(1, 1, 1)
		close.BackgroundTransparency = 1
		close.Image = getcustomasset('newvape/assets/new/close.png')
		close.ImageColor3 = color.Light(uipallet.Text, 0.2)
		close.ImageTransparency = 0.5
		close.AutoButtonColor = false
		close.Parent = window
		close.MouseEnter:Connect(function()
			close.ImageTransparency = 0.3
			tween:Tween(close, TweenInfo.new(0.2), {
				BackgroundTransparency = 0.6
			})
		end)
		close.MouseLeave:Connect(function()
			close.ImageTransparency = 0.5
			tween:Tween(close, TweenInfo.new(0.2), {
				BackgroundTransparency = 1
			})
		end)
		close.MouseButton1Click:Connect(function()
			window.Visible = false
			vape.gui.ScaledGui.ClickGui.Visible = true
		end)
		local closecorner = Instance.new('UICorner')
		closecorner.CornerRadius = UDim.new(1, 0)
		closecorner.Parent = close
		local bigslot = Instance.new('Frame')
		bigslot.Size = UDim2.fromOffset(110, 111)
		bigslot.Position = UDim2.fromOffset(11, 71)
		bigslot.BackgroundColor3 = color.Dark(uipallet.Main, 0.02)
		bigslot.Parent = window
		local bigslotcorner = Instance.new('UICorner')
		bigslotcorner.CornerRadius = UDim.new(0, 4)
		bigslotcorner.Parent = bigslot
		local bigslotstroke = Instance.new('UIStroke')
		bigslotstroke.Color = color.Light(uipallet.Main, 0.034)
		bigslotstroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		bigslotstroke.Parent = bigslot
		local slotnum = Instance.new('TextLabel')
		slotnum.Size = UDim2.fromOffset(80, 20)
		slotnum.Position = UDim2.fromOffset(25, 200)
		slotnum.BackgroundTransparency = 1
		slotnum.Text = 'SLOT 1'
		slotnum.TextColor3 = color.Dark(uipallet.Text, 0.1)
		slotnum.TextSize = 12
		slotnum.FontFace = uipallet.Font
		slotnum.Parent = window
		for i = 1, 9 do
			local slotbkg = Instance.new('TextButton')
			slotbkg.Name = 'Slot' .. i
			slotbkg.Size = UDim2.fromOffset(51, 52)
			slotbkg.Position = UDim2.fromOffset(89 + (i * 55), 382)
			slotbkg.BackgroundColor3 = color.Dark(uipallet.Main, 0.02)
			slotbkg.Text = ''
			slotbkg.AutoButtonColor = false
			slotbkg.Parent = window
			local slotimage = Instance.new('ImageLabel')
			slotimage.Size = UDim2.fromOffset(32, 32)
			slotimage.Position = UDim2.new(0.5, - 16, 0.5, - 16)
			slotimage.BackgroundTransparency = 1
			slotimage.Image = ''
			slotimage.Parent = slotbkg
			local slotcorner = Instance.new('UICorner')
			slotcorner.CornerRadius = UDim.new(0, 4)
			slotcorner.Parent = slotbkg
			local slotstroke = Instance.new('UIStroke')
			slotstroke.Color = color.Light(uipallet.Main, 0.04)
			slotstroke.Thickness = 2
			slotstroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			slotstroke.Enabled = i == selectedslot
			slotstroke.Parent = slotbkg
			slotbkg.MouseEnter:Connect(function()
				slotbkg.BackgroundColor3 = color.Light(uipallet.Main, 0.034)
			end)
			slotbkg.MouseLeave:Connect(function()
				slotbkg.BackgroundColor3 = color.Dark(uipallet.Main, 0.02)
			end)
			slotbkg.MouseButton1Click:Connect(function()
				window['Slot' .. selectedslot].UIStroke.Enabled = false
				selectedslot = i
				slotstroke.Enabled = true
				slotnum.Text = 'SLOT ' .. selectedslot
			end)
			slotbkg.MouseButton2Click:Connect(function()
				local obj = self.Hotbars[self.Selected]
				if obj then
					window['Slot' .. i].ImageLabel.Image = ''
					obj.Hotbar[tostring(i)] = nil
					obj.Object['Slot' .. i].Image = '	'
				end
			end)
		end
		local searchbkg = Instance.new('Frame')
		searchbkg.Size = UDim2.fromOffset(496, 31)
		searchbkg.Position = UDim2.fromOffset(142, 80)
		searchbkg.BackgroundColor3 = color.Light(uipallet.Main, 0.034)
		searchbkg.Parent = window
		local search = Instance.new('TextBox')
		search.Size = UDim2.new(1, - 10, 0, 31)
		search.Position = UDim2.fromOffset(10, 0)
		search.BackgroundTransparency = 1
		search.Text = ''
		search.PlaceholderText = ''
		search.TextXAlignment = Enum.TextXAlignment.Left
		search.TextColor3 = uipallet.Text
		search.TextSize = 12
		search.FontFace = uipallet.Font
		search.ClearTextOnFocus = false
		search.Parent = searchbkg
		local searchcorner = Instance.new('UICorner')
		searchcorner.CornerRadius = UDim.new(0, 4)
		searchcorner.Parent = searchbkg
		local searchicon = Instance.new('ImageLabel')
		searchicon.Size = UDim2.fromOffset(14, 14)
		searchicon.Position = UDim2.new(1, - 26, 0, 8)
		searchicon.BackgroundTransparency = 1
		searchicon.Image = getcustomasset('newvape/assets/new/search.png')
		searchicon.ImageColor3 = color.Light(uipallet.Main, 0.37)
		searchicon.Parent = searchbkg
		local children = Instance.new('ScrollingFrame')
		children.Name = 'Children'
		children.Size = UDim2.fromOffset(500, 240)
		children.Position = UDim2.fromOffset(144, 122)
		children.BackgroundTransparency = 1
		children.BorderSizePixel = 0
		children.ScrollBarThickness = 2
		children.ScrollBarImageTransparency = 0.75
		children.CanvasSize = UDim2.new()
		children.Parent = window
		local windowlist = Instance.new('UIGridLayout')
		windowlist.SortOrder = Enum.SortOrder.LayoutOrder
		windowlist.FillDirectionMaxCells = 9
		windowlist.CellSize = UDim2.fromOffset(51, 52)
		windowlist.CellPadding = UDim2.fromOffset(4, 3)
		windowlist.Parent = children
		windowlist:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
			if vape.ThreadFix then
				setthreadidentity(8)
			end
			children.CanvasSize = UDim2.fromOffset(0, windowlist.AbsoluteContentSize.Y / vape.guiscale.Scale)
		end)
		table.insert(vape.Windows, window)
		local function createitem(id, image)
			local slotbkg = Instance.new('TextButton')
			slotbkg.BackgroundColor3 = color.Light(uipallet.Main, 0.02)
			slotbkg.Text = ''
			slotbkg.AutoButtonColor = false
			slotbkg.Parent = children
			local slotimage = Instance.new('ImageLabel')
			slotimage.Size = UDim2.fromOffset(32, 32)
			slotimage.Position = UDim2.new(0.5, - 16, 0.5, - 16)
			slotimage.BackgroundTransparency = 1
			slotimage.Image = image
			slotimage.Parent = slotbkg
			local slotcorner = Instance.new('UICorner')
			slotcorner.CornerRadius = UDim.new(0, 4)
			slotcorner.Parent = slotbkg
			slotbkg.MouseEnter:Connect(function()
				slotbkg.BackgroundColor3 = color.Light(uipallet.Main, 0.04)
			end)
			slotbkg.MouseLeave:Connect(function()
				slotbkg.BackgroundColor3 = color.Light(uipallet.Main, 0.02)
			end)
			slotbkg.MouseButton1Click:Connect(function()
				local obj = self.Hotbars[self.Selected]
				if obj then
					window['Slot' .. selectedslot].ImageLabel.Image = image
					obj.Hotbar[tostring(selectedslot)] = id
					obj.Object['Slot' .. selectedslot].Image = image
				end
			end)
		end
		local function indexSearch(text)
			for _, v in children:GetChildren() do
				if v:IsA('TextButton') then
					v:ClearAllChildren()
					v:Destroy()
				end
			end
			if text == '' then
				for _, v in {
					'diamond_sword',
					'diamond_pickaxe',
					'diamond_axe',
					'shears',
					'wood_bow',
					'wool_white',
					'fireball',
					'apple',
					'iron',
					'gold',
					'diamond',
					'emerald'
				} do
					createitem(v, bedwars.ItemMeta[v].image)
				end
				return
			end
			for i, v in bedwars.ItemMeta do
				if text:lower() == i:lower():sub(1, text:len()) then
					if not v.image then
						continue
					end
					createitem(i, v.image)
				end
			end
		end
		search:GetPropertyChangedSignal('Text'):Connect(function()
			indexSearch(search.Text)
		end)
		indexSearch('')
		return window
	end
	vape.Components.HotbarList = function(optionsettings, children, api)
		if vape.ThreadFix then
			setthreadidentity(8)
		end
		local optionapi = {
			Type = 'HotbarList',
			Hotbars = {},
			Selected = 1
		}
		local hotbarlist = Instance.new('TextButton')
		hotbarlist.Name = 'HotbarList'
		hotbarlist.Size = UDim2.fromOffset(220, 40)
		hotbarlist.BackgroundColor3 = optionsettings.Darker and (children.BackgroundColor3 == color.Dark(uipallet.Main, 0.02) and color.Dark(uipallet.Main, 0.04) or color.Dark(uipallet.Main, 0.02)) or children.BackgroundColor3
		hotbarlist.Text = ''
		hotbarlist.BorderSizePixel = 0
		hotbarlist.AutoButtonColor = false
		hotbarlist.Parent = children
		local textbkg = Instance.new('Frame')
		textbkg.Name = 'BKG'
		textbkg.Size = UDim2.new(1, - 20, 0, 31)
		textbkg.Position = UDim2.fromOffset(10, 4)
		textbkg.BackgroundColor3 = color.Light(uipallet.Main, 0.034)
		textbkg.Parent = hotbarlist
		local textbkgcorner = Instance.new('UICorner')
		textbkgcorner.CornerRadius = UDim.new(0, 4)
		textbkgcorner.Parent = textbkg
		local textbutton = Instance.new('TextButton')
		textbutton.Name = 'HotbarList'
		textbutton.Size = UDim2.new(1, - 2, 1, - 2)
		textbutton.Position = UDim2.fromOffset(1, 1)
		textbutton.BackgroundColor3 = uipallet.Main
		textbutton.Text = ''
		textbutton.AutoButtonColor = false
		textbutton.Parent = textbkg
		textbutton.MouseEnter:Connect(function()
			tween:Tween(textbkg, TweenInfo.new(0.2), {
				BackgroundColor3 = color.Light(uipallet.Main, 0.14)
			})
		end)
		textbutton.MouseLeave:Connect(function()
			tween:Tween(textbkg, TweenInfo.new(0.2), {
				BackgroundColor3 = color.Light(uipallet.Main, 0.034)
			})
		end)
		local textbuttoncorner = Instance.new('UICorner')
		textbuttoncorner.CornerRadius = UDim.new(0, 4)
		textbuttoncorner.Parent = textbutton
		local textbuttonicon = Instance.new('ImageLabel')
		textbuttonicon.Size = UDim2.fromOffset(12, 12)
		textbuttonicon.Position = UDim2.fromScale(0.5, 0.5)
		textbuttonicon.AnchorPoint = Vector2.new(0.5, 0.5)
		textbuttonicon.BackgroundTransparency = 1
		textbuttonicon.Image = getcustomasset('newvape/assets/new/add.png')
		textbuttonicon.ImageColor3 = Color3.fromHSV(0.46, 0.96, 0.52)
		textbuttonicon.Parent = textbutton
		local childrenlist = Instance.new('Frame')
		childrenlist.Size = UDim2.new(1, 0, 1, - 40)
		childrenlist.Position = UDim2.fromOffset(0, 40)
		childrenlist.BackgroundTransparency = 1
		childrenlist.Parent = hotbarlist
		local windowlist = Instance.new('UIListLayout')
		windowlist.SortOrder = Enum.SortOrder.LayoutOrder
		windowlist.HorizontalAlignment = Enum.HorizontalAlignment.Center
		windowlist.Padding = UDim.new(0, 3)
		windowlist.Parent = childrenlist
		windowlist:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
			if vape.ThreadFix then
				setthreadidentity(8)
			end
			hotbarlist.Size = UDim2.fromOffset(220, math.min(43 + windowlist.AbsoluteContentSize.Y / vape.guiscale.Scale, 603))
		end)
		textbutton.MouseButton1Click:Connect(function()
			optionapi:AddHotbar()
		end)
		optionapi.Window = CreateWindow(optionapi)
		function optionapi:Save(savetab)
			local hotbars = {}
			for _, v in self.Hotbars do
				table.insert(hotbars, v.Hotbar)
			end
			savetab.HotbarList = {
				Selected = self.Selected,
				Hotbars = hotbars
			}
		end
		function optionapi:Load(savetab)
			for _, v in self.Hotbars do
				v.Object:ClearAllChildren()
				v.Object:Destroy()
				table.clear(v.Hotbar)
			end
			table.clear(self.Hotbars)
			for _, v in savetab.Hotbars do
				self:AddHotbar(v)
			end
			self.Selected = savetab.Selected or 1
		end
		function optionapi:AddHotbar(data)
			local hotbardata = {
				Hotbar = data or {}
			}
			table.insert(self.Hotbars, hotbardata)
			local hotbar = Instance.new('TextButton')
			hotbar.Size = UDim2.fromOffset(200, 27)
			hotbar.BackgroundColor3 = table.find(self.Hotbars, hotbardata) == self.Selected and color.Light(uipallet.Main, 0.034) or uipallet.Main
			hotbar.Text = ''
			hotbar.AutoButtonColor = false
			hotbar.Parent = childrenlist
			hotbardata.Object = hotbar
			local hotbarcorner = Instance.new('UICorner')
			hotbarcorner.CornerRadius = UDim.new(0, 4)
			hotbarcorner.Parent = hotbar
			for i = 1, 9 do
				local slot = Instance.new('ImageLabel')
				slot.Name = 'Slot' .. i
				slot.Size = UDim2.fromOffset(17, 18)
				slot.Position = UDim2.fromOffset(- 7 + (i * 18), 5)
				slot.BackgroundColor3 = color.Dark(uipallet.Main, 0.02)
				slot.Image = hotbardata.Hotbar[tostring(i)] and bedwars.getIcon({
					itemType = hotbardata.Hotbar[tostring(i)]
				}, true) or ''
				slot.BorderSizePixel = 0
				slot.Parent = hotbar
			end
			hotbar.MouseButton1Click:Connect(function()
				local ind = table.find(optionapi.Hotbars, hotbardata)
				if ind == optionapi.Selected then
					vape.gui.ScaledGui.ClickGui.Visible = false
					optionapi.Window.Visible = true
					for i = 1, 9 do
						optionapi.Window['Slot' .. i].ImageLabel.Image = hotbardata.Hotbar[tostring(i)] and bedwars.getIcon({
							itemType = hotbardata.Hotbar[tostring(i)]
						}, true) or ''
					end
				else
					if optionapi.Hotbars[optionapi.Selected] then
						optionapi.Hotbars[optionapi.Selected].Object.BackgroundColor3 = uipallet.Main
					end
					hotbar.BackgroundColor3 = color.Light(uipallet.Main, 0.034)
					optionapi.Selected = ind
				end
			end)
			local close = Instance.new('ImageButton')
			close.Name = 'Close'
			close.Size = UDim2.fromOffset(16, 16)
			close.Position = UDim2.new(1, - 23, 0, 6)
			close.BackgroundColor3 = Color3.new(1, 1, 1)
			close.BackgroundTransparency = 1
			close.Image = getcustomasset('newvape/assets/new/closemini.png')
			close.ImageColor3 = color.Light(uipallet.Text, 0.2)
			close.ImageTransparency = 0.5
			close.AutoButtonColor = false
			close.Parent = hotbar
			local closecorner = Instance.new('UICorner')
			closecorner.CornerRadius = UDim.new(1, 0)
			closecorner.Parent = close
			close.MouseEnter:Connect(function()
				close.ImageTransparency = 0.3
				tween:Tween(close, TweenInfo.new(0.2), {
					BackgroundTransparency = 0.6
				})
			end)
			close.MouseLeave:Connect(function()
				close.ImageTransparency = 0.5
				tween:Tween(close, TweenInfo.new(0.2), {
					BackgroundTransparency = 1
				})
			end)
			close.MouseButton1Click:Connect(function()
				local ind = table.find(self.Hotbars, hotbardata)
				local obj = self.Hotbars[self.Selected]
				local obj2 = self.Hotbars[ind]
				if obj and obj2 then
					obj2.Object:ClearAllChildren()
					obj2.Object:Destroy()
					table.remove(self.Hotbars, ind)
					ind = table.find(self.Hotbars, obj)
					self.Selected = table.find(self.Hotbars, obj) or 1
				end
			end)
		end
		api.Options.HotbarList = optionapi
		return optionapi
	end
	local function getBlock()
		local clone = table.clone(store.inventory.inventory.items)
		table.sort(clone, function(a, b)
			return a.amount < b.amount
		end)
		for _, item in clone do
			local block = bedwars.ItemMeta[item.itemType].block
			if block and not block.seeThrough then
				return item
			end
		end
	end
	local function getCustomItem(v)
		if v == 'diamond_sword' then
			local sword = store.tools.sword
			v = sword and sword.itemType or 'wood_sword'
		elseif v == 'diamond_pickaxe' then
			local pickaxe = store.tools.stone
			v = pickaxe and pickaxe.itemType or 'wood_pickaxe'
		elseif v == 'diamond_axe' then
			local axe = store.tools.wood
			v = axe and axe.itemType or 'wood_axe'
		elseif v == 'wood_bow' then
			local bow = getBow()
			v = bow and bow.itemType or 'wood_bow'
		elseif v == 'wool_white' then
			local block = getBlock()
			v = block and block.itemType or 'wool_white'
		end
		return v
	end
	local function findItemInTable(tab, item)
		for slot, v in tab do
			if item.itemType == getCustomItem(v) then
				return tonumber(slot)
			end
		end
	end
	local function findInHotbar(item)
		for i, v in store.inventory.hotbar do
			if v.item and v.item.itemType == item.itemType then
				return i - 1, v.item
			end
		end
	end
	local function findInInventory(item)
		for _, v in store.inventory.inventory.items do
			if v.itemType == item.itemType then
				return v
			end
		end
	end
	local function dispatch( ...)
		bedwars.Store:dispatch(...)
		vapeEvents.InventoryChanged.Event:Wait()
	end
	local function sortCallback()
		if Active then
			return
		end
		Active = true
		local items = (List.Hotbars[List.Selected] and List.Hotbars[List.Selected].Hotbar or {})
		for _, v in store.inventory.inventory.items do
			local slot = findItemInTable(items, v)
			if slot then
				local olditem = store.inventory.hotbar[slot]
				if olditem.item and olditem.item.itemType == v.itemType then
					continue
				end
				if olditem.item then
					dispatch({
						type = 'InventoryRemoveFromHotbar',
						slot = slot - 1
					})
				end
				local newslot = findInHotbar(v)
				if newslot then
					dispatch({
						type = 'InventoryRemoveFromHotbar',
						slot = newslot
					})
					if olditem.item then
						dispatch({
							type = 'InventoryAddToHotbar',
							item = findInInventory(olditem.item),
							slot = newslot
						})
					end
				end
				dispatch({
					type = 'InventoryAddToHotbar',
					item = findInInventory(v),
					slot = slot - 1
				})
			elseif Clear.Enabled then
				local newslot = findInHotbar(v)
				if newslot then
					dispatch({
						type = 'InventoryRemoveFromHotbar',
						slot = newslot
					})
				end
			end
		end
		Active = false
	end
	AutoHotbar = vape.Categories.Inventory:CreateModule({
		Name = 'Auto Hotbar',
		Function = function(callback)
			if callback then
				task.spawn(sortCallback)
				if Mode.Value == 'On Key' then
					AutoHotbar:Toggle()
					return
				end
				AutoHotbar:Clean(vapeEvents.InventoryAmountChanged.Event:Connect(sortCallback))
			end
		end,
		Tooltip = 'Automatically arranges hotbar to your liking.'
	})
	Mode = AutoHotbar:CreateDropdown({
		Name = 'Activation',
		List = {
			'Toggle',
			'On Key'
		},
		Function = function()
			if AutoHotbar.Enabled then
				AutoHotbar:Toggle()
				AutoHotbar:Toggle()
			end
		end
	})
	Clear = AutoHotbar:CreateToggle({
		Name = 'Clear Hotbar'
	})
	List = AutoHotbar:CreateHotbarList({})
end)

run(function()
	local Value
	local oldclickhold, oldshowprogress
	local FastConsume = vape.Categories.Inventory:CreateModule({
		Name = 'Fast Consume',
		Function = function(callback)
			if callback then
				oldclickhold = bedwars.ClickHold.startClick
				oldshowprogress = bedwars.ClickHold.showProgress
				bedwars.ClickHold.startClick = function(self)
					self.startedClickTime = tick()
					local handle = self:showProgress()
					local clicktime = self.startedClickTime
					bedwars.RuntimeLib.Promise.defer(function()
						task.wait(self.durationSeconds * (Value.Value / 40))
						if handle == self.handle and clicktime == self.startedClickTime and self.closeOnComplete then
							self:hideProgress()
							if self.onComplete then
								self.onComplete()
							end
							if self.onPartialComplete then
								self.onPartialComplete(1)
							end
							self.startedClickTime = - 1
						end
					end)
				end
				bedwars.ClickHold.showProgress = function(self)
					local roact = debug.getupvalue(oldshowprogress, 1)
					local countdown = roact.mount(roact.createElement('ScreenGui', {}, {
						roact.createElement('Frame', {
							[roact.Ref] = self.wrapperRef,
							Size = UDim2.new(),
							Position = UDim2.fromScale(0.5, 0.55),
							AnchorPoint = Vector2.new(0.5, 0),
							BackgroundColor3 = Color3.fromRGB(0, 0, 0),
							BackgroundTransparency = 0.8
						}, {
							roact.createElement('Frame', {
								[roact.Ref] = self.progressRef,
								Size = UDim2.fromScale(0, 1),
								BackgroundColor3 = Color3.new(1, 1, 1),
								BackgroundTransparency = 0.5
							})
						})
					}), lplr:FindFirstChild('PlayerGui'))
					self.handle = countdown
					local sizetween = tweenService:Create(self.wrapperRef:getValue(), TweenInfo.new(0.1), {
						Size = UDim2.fromScale(0.11, 0.005)
					})
					local countdowntween = tweenService:Create(self.progressRef:getValue(), TweenInfo.new(self.durationSeconds * (Value.Value / 100), Enum.EasingStyle.Linear), {
						Size = UDim2.fromScale(1, 1)
					})
					sizetween:Play()
					countdowntween:Play()
					table.insert(self.tweens, countdowntween)
					table.insert(self.tweens, sizetween)
					return countdown
				end
			else
				bedwars.ClickHold.startClick = oldclickhold
				bedwars.ClickHold.showProgress = oldshowprogress
				oldclickhold = nil
				oldshowprogress = nil
			end
		end,
		Tooltip = 'Use/Consume items quicker.'
	})
	Value = FastConsume:CreateSlider({
		Name = 'Multiplier',
		Min = 0,
		Max = 100
	})
end)

run(function()
	local FastDrop
	FastDrop = vape.Categories.Inventory:CreateModule({
		Name = 'Fast Drop',
		Function = function(callback)
			if callback then
				repeat
					if entitylib.isAlive and (not store.inventory.opened) and (inputService:IsKeyDown(Enum.KeyCode.H) or inputService:IsKeyDown(Enum.KeyCode.Backspace)) and inputService:GetFocusedTextBox() == nil then
						task.spawn(bedwars.ItemDropController.dropItemInHand)
						task.wait()
					else
						task.wait(0.1)
					end
				until not FastDrop.Enabled
			end
		end,
		Tooltip = 'Drops items fast when you hold Q'
	})
end)

--[[
	Minigames
]]--

run(function()
	local BedPlates
	local Background
	local Color = {}
	local Reference = {}
	local Folder = Instance.new('Folder')
	Folder.Parent = vape.gui
	local function scanSide(self, start, tab)
		for _, side in sides do
			for i = 1, 15 do
				local block = getPlacedBlock(start + (side * i))
				if not block or block == self then
					break
				end
				if not block:GetAttribute('NoBreak') and not table.find(tab, block.Name) then
					table.insert(tab, block.Name)
				end
			end
		end
	end
	local function refreshAdornee(v)
		for _, obj in v.Frame:GetChildren() do
			if obj:IsA('ImageLabel') and obj.Name ~= 'Blur' then
				obj:Destroy()
			end
		end
		local start = v.Adornee.Position
		local alreadygot = {}
		scanSide(v.Adornee, start, alreadygot)
		scanSide(v.Adornee, start + Vector3.new(0, 0, 3), alreadygot)
		table.sort(alreadygot, function(a, b)
			return (bedwars.ItemMeta[a].block and bedwars.ItemMeta[a].block.health or 0) > (bedwars.ItemMeta[b].block and bedwars.ItemMeta[b].block.health or 0)
		end)
		v.Enabled = # alreadygot > 0
		for _, block in alreadygot do
			local blockimage = Instance.new('ImageLabel')
			blockimage.Size = UDim2.fromOffset(32, 32)
			blockimage.BackgroundTransparency = 1
			blockimage.Image = bedwars.getIcon({
				itemType = block
			}, true)
			blockimage.Parent = v.Frame
		end
	end
	local function Added(v)
		local billboard = Instance.new('BillboardGui')
		billboard.Parent = Folder
		billboard.Name = 'bed'
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
		billboard.Size = UDim2.fromOffset(36, 36)
		billboard.AlwaysOnTop = true
		billboard.ClipsDescendants = false
		billboard.Adornee = v
		local blur = addBlur(billboard)
		blur.Visible = Background.Enabled
		local frame = Instance.new('Frame')
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
		frame.BackgroundTransparency = 1 - (Background.Enabled and Color.Opacity or 0)
		frame.Parent = billboard
		local layout = Instance.new('UIListLayout')
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.Padding = UDim.new(0, 4)
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
			billboard.Size = UDim2.fromOffset(math.max(layout.AbsoluteContentSize.X + 4, 36), 36)
		end)
		layout.Parent = frame
		local corner = Instance.new('UICorner')
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = frame
		Reference[v] = billboard
		refreshAdornee(billboard)
	end
	local function refreshNear(data)
		data = data.blockRef.blockPosition * 3
		for i, v in Reference do
			if (data - i.Position).Magnitude <= 30 then
				refreshAdornee(v)
			end
		end
	end
	BedPlates = vape.Categories.Minigames:CreateModule({
		Name = 'Bed Plates',
		Function = function(callback)
			if callback then
				for _, v in collectionService:GetTagged('bed') do
					task.spawn(Added, v)
				end
				BedPlates:Clean(vapeEvents.PlaceBlockEvent.Event:Connect(refreshNear))
				BedPlates:Clean(vapeEvents.BreakBlockEvent.Event:Connect(refreshNear))
				BedPlates:Clean(collectionService:GetInstanceAddedSignal('bed'):Connect(Added))
				BedPlates:Clean(collectionService:GetInstanceRemovedSignal('bed'):Connect(function(v)
					if Reference[v] then
						Reference[v]:Destroy()
						Reference[v]:ClearAllChildren()
						Reference[v] = nil
					end
				end))
			else
				table.clear(Reference)
				Folder:ClearAllChildren()
			end
		end,
		Tooltip = 'Displays blocks over the bed'
	})
	Background = BedPlates:CreateToggle({
		Name = 'Background',
		Function = function(callback)
			if Color.Object then
				Color.Object.Visible = callback
			end
			for _, v in Reference do
				v.Frame.BackgroundTransparency = 1 - (callback and Color.Opacity or 0)
				v.Blur.Visible = callback
			end
		end,
		Default = true
	})
	Color = BedPlates:CreateColorSlider({
		Name = 'Background Color',
		DefaultValue = 0,
		DefaultOpacity = 0.5,
		Function = function(hue, sat, val, opacity)
			for _, v in Reference do
				v.Frame.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
				v.Frame.BackgroundTransparency = 1 - opacity
			end
		end,
		Darker = true
	})
end)

run(function()
	local Breaker
	local Range
	local BreakSpeed
	local UpdateRate
	local Custom
	local Bed
	local LuckyBlock
	local IronOre
	local Effect
	local CustomHealth = {}
	local Animation
	local SelfBreak
	local InstantBreak
	local LimitItem
	local customlist, parts = {}, {}
	local function customHealthbar(self, blockRef, health, maxHealth, changeHealth, block)
		if block:GetAttribute('NoHealthbar') then
			return
		end
		if not self.healthbarPart or not self.healthbarBlockRef or self.healthbarBlockRef.blockPosition ~= blockRef.blockPosition then
			self.healthbarMaid:DoCleaning()
			self.healthbarBlockRef = blockRef
			local create = bedwars.Roact.createElement
			local percent = math.clamp(health / maxHealth, 0, 1)
			local cleanCheck = true
			local part = Instance.new('Part')
			part.Size = Vector3.one
			part.CFrame = CFrame.new(bedwars.BlockController:getWorldPosition(blockRef.blockPosition))
			part.Transparency = 1
			part.Anchored = true
			part.CanCollide = false
			part.Parent = workspace
			self.healthbarPart = part
			bedwars.QueryUtil:setQueryIgnored(self.healthbarPart, true)
			local mounted = bedwars.Roact.mount(create('BillboardGui', {
				Size = UDim2.fromOffset(249, 102),
				StudsOffset = Vector3.new(0, 2.5, 0),
				Adornee = part,
				MaxDistance = 40,
				AlwaysOnTop = true
			}, {
				create('Frame', {
					Size = UDim2.fromOffset(160, 50),
					Position = UDim2.fromOffset(44, 32),
					BackgroundColor3 = Color3.new(),
					BackgroundTransparency = 0.5
				}, {
					create('UICorner', {
						CornerRadius = UDim.new(0, 5)
					}),
					create('ImageLabel', {
						Size = UDim2.new(1, 89, 1, 52),
						Position = UDim2.fromOffset(- 48, - 31),
						BackgroundTransparency = 1,
						Image = getcustomasset('newvape/assets/new/blur.png'),
						ScaleType = Enum.ScaleType.Slice,
						SliceCenter = Rect.new(52, 31, 261, 502)
					}),
					create('TextLabel', {
						Size = UDim2.fromOffset(145, 14),
						Position = UDim2.fromOffset(13, 12),
						BackgroundTransparency = 1,
						Text = bedwars.ItemMeta[block.Name].displayName or block.Name,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextColor3 = Color3.new(),
						TextScaled = true,
						Font = Enum.Font.Arial
					}),
					create('TextLabel', {
						Size = UDim2.fromOffset(145, 14),
						Position = UDim2.fromOffset(12, 11),
						BackgroundTransparency = 1,
						Text = bedwars.ItemMeta[block.Name].displayName or block.Name,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextColor3 = color.Dark(uipallet.Text, 0.16),
						TextScaled = true,
						Font = Enum.Font.Arial
					}),
					create('Frame', {
						Size = UDim2.fromOffset(138, 4),
						Position = UDim2.fromOffset(12, 32),
						BackgroundColor3 = uipallet.Main
					}, {
						create('UICorner', {
							CornerRadius = UDim.new(1, 0)
						}),
						create('Frame', {
							[bedwars.Roact.Ref] = self.healthbarProgressRef,
							Size = UDim2.fromScale(percent, 1),
							BackgroundColor3 = Color3.fromHSV(math.clamp(percent / 2.5, 0, 1), 0.89, 0.75)
						}, {
							create('UICorner', {
								CornerRadius = UDim.new(1, 0)
							})
						})
					})
				})
			}), part)
			self.healthbarMaid:GiveTask(function()
				cleanCheck = false
				self.healthbarBlockRef = nil
				bedwars.Roact.unmount(mounted)
				if self.healthbarPart then
					self.healthbarPart:Destroy()
				end
				self.healthbarPart = nil
			end)
			bedwars.RuntimeLib.Promise.delay(5):andThen(function()
				if cleanCheck then
					self.healthbarMaid:DoCleaning()
				end
			end)
		end
		local newpercent = math.clamp((health - changeHealth) / maxHealth, 0, 1)
		tweenService:Create(self.healthbarProgressRef:getValue(), TweenInfo.new(0.3), {
			Size = UDim2.fromScale(newpercent, 1),
			BackgroundColor3 = Color3.fromHSV(math.clamp(newpercent / 2.5, 0, 1), 0.89, 0.75)
		}):Play()
	end
	local hit = 0
	local function attemptBreak(tab, localPosition)
		if not tab then
			return
		end
		for _, v in tab do
			if (v.Position - localPosition).Magnitude < Range.Value and bedwars.BlockController:isBlockBreakable({
				blockPosition = v.Position / 3
			}, lplr) then
				if not SelfBreak.Enabled and v:GetAttribute('PlacedByUserId') == lplr.UserId then
					continue
				end
				if (v:GetAttribute('BedShieldEndTime') or 0) > workspace:GetServerTimeNow() then
					continue
				end
				if LimitItem.Enabled and not (store.hand.tool and bedwars.ItemMeta[store.hand.tool.Name].breakBlock) then
					continue
				end
				hit += 1
				local target, path, endpos = bedwars.breakBlock(v, Effect.Enabled, Animation.Enabled, CustomHealth.Enabled and customHealthbar or nil, InstantBreak.Enabled)
				if path then
					local currentnode = target
					for _, part in parts do
						part.Position = currentnode or Vector3.zero
						if currentnode then
							part.BoxHandleAdornment.Color3 = currentnode == endpos and Color3.new(1, 0.2, 0.2) or currentnode == target and Color3.new(0.2, 0.2, 1) or Color3.new(0.2, 1, 0.2)
						end
						currentnode = path[currentnode]
					end
				end
				task.wait(InstantBreak.Enabled and (store.damageBlockFail > tick() and 4.5 or 0) or BreakSpeed.Value)
				return true
			end
		end
		return false
	end
	Breaker = vape.Categories.Minigames:CreateModule({
		Name = 'Breaker',
		Function = function(callback)
			if callback then
				for _ = 1, 30 do
					local part = Instance.new('Part')
					part.Anchored = true
					part.CanQuery = false
					part.CanCollide = false
					part.Transparency = 1
					part.Parent = gameCamera
					local highlight = Instance.new('BoxHandleAdornment')
					highlight.Size = Vector3.one
					highlight.AlwaysOnTop = true
					highlight.ZIndex = 1
					highlight.Transparency = 0.5
					highlight.Adornee = part
					highlight.Parent = part
					table.insert(parts, part)
				end
				local beds = collection('bed', Breaker)
				local luckyblock = collection('LuckyBlock', Breaker)
				local ironores = collection('iron-ore', Breaker)
				customlist = collection('block', Breaker, function(tab, obj)
					if table.find(Custom.ListEnabled, obj.Name) then
						table.insert(tab, obj)
					end
				end)
				repeat
					task.wait(1 / UpdateRate.Value)
					if not Breaker.Enabled then
						break
					end
					if entitylib.isAlive then
						local localPosition = entitylib.character.RootPart.Position
						if attemptBreak(Bed.Enabled and beds, localPosition) then
							continue
						end
						if attemptBreak(customlist, localPosition) then
							continue
						end
						if attemptBreak(LuckyBlock.Enabled and luckyblock, localPosition) then
							continue
						end
						if attemptBreak(IronOre.Enabled and ironores, localPosition) then
							continue
						end
						for _, v in parts do
							v.Position = Vector3.zero
						end
					end
				until not Breaker.Enabled
			else
				for _, v in parts do
					v:ClearAllChildren()
					v:Destroy()
				end
				table.clear(parts)
			end
		end,
		Tooltip = 'Break blocks around you automatically'
	})
	Range = Breaker:CreateSlider({
		Name = 'Break range',
		Min = 1,
		Max = 30,
		Default = 30,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	BreakSpeed = Breaker:CreateSlider({
		Name = 'Break speed',
		Min = 0,
		Max = 0.3,
		Default = 0.25,
		Decimal = 100,
		Suffix = 'seconds'
	})
	UpdateRate = Breaker:CreateSlider({
		Name = 'Update rate',
		Min = 1,
		Max = 120,
		Default = 60,
		Suffix = 'hz'
	})
	Custom = Breaker:CreateTextList({
		Name = 'Custom',
		Function = function()
			if not customlist then
				return
			end
			table.clear(customlist)
			for _, obj in store.blocks do
				if table.find(Custom.ListEnabled, obj.Name) then
					table.insert(customlist, obj)
				end
			end
		end
	})
	Bed = Breaker:CreateToggle({
		Name = 'Break Bed',
		Default = true
	})
	LuckyBlock = Breaker:CreateToggle({
		Name = 'Break Lucky Block',
		Default = true
	})
	IronOre = Breaker:CreateToggle({
		Name = 'Break Iron Ore',
		Default = true
	})
	Effect = Breaker:CreateToggle({
		Name = 'Show Healthbar & Effects',
		Function = function(callback)
			if CustomHealth.Object then
				CustomHealth.Object.Visible = callback
			end
		end,
		Default = true
	})
	CustomHealth = Breaker:CreateToggle({
		Name = 'Custom Healthbar',
		Default = true,
		Darker = true
	})
	Animation = Breaker:CreateToggle({
		Name = 'Animation'
	})
	SelfBreak = Breaker:CreateToggle({
		Name = 'Self Break'
	})
	InstantBreak = Breaker:CreateToggle({
		Name = 'Instant Break'
	})
	LimitItem = Breaker:CreateToggle({
		Name = 'Limit to items',
		Tooltip = 'Only breaks when tools are held'
	})
end)

run(function()
	local ViewHistory
	ViewHistory = vape.Categories.Minigames:CreateModule({
		Name = 'ViewHistory',
		Tooltip = 'Allows you to see other peoples match histories like a AC Mod',
		Function = function(callback)
			if not callback then return end
			ViewHistory:Toggle()
			notif('ViewHistory', "Opening in 2 seconds. Bedwars problem not mines.",2.5)
			bedwars.MatchHistroyController:requestMatchHistory(lplr.Name):andThen(function(Data)
				if Data then
					bedwars.AppController:openApp({app = bedwars.MatchHistroyApp,appId = "MatchHistoryApp",},Data)
				end
			end)
		end
	})
end)

run(function() -- skidded from cv but better ig
    local HackerDetector
    
    local function Added(player, reason)
        if not store.FlaggedCheaters[player] then
            store.FlaggedCheaters[player] = true
            whitelist.customtags[player.Name] = {{ text = 'EXPLOITER', color = Color3.new(0, 1, 1)}}
            notif('HackerDetector', `{player.Name} flagged for {reason}ing`, 10, 'info')
        end
    end
    local function checkPoint(pos, params)
        for _, v in workspace:GetPartBoundsInRadius(pos, 0, params) do
            if v.CanCollide and (v:GetClosestPointOnSurface(pos) - pos).Magnitude <= 0 then
                return false
            end
        end
    
        return true
    end
    
    local overlap = OverlapParams.new()
    overlap.FilterDescendantsInstances = {workspace.Map}
    overlap.FilterType = Enum.RaycastFilterType.Include
	local flychgedkle = {}
    local Checks = {
        Killaura = function()
            local AttackData = {}
            local Strikes = {}
    
            HackerDetector:Clean(vapeEvents.EntityDamageEvent.Event:Connect(function(damageTable)
                if damageTable.damageType == 0 and damageTable.fromEntity then
                    local from = playersService:GetPlayerFromCharacter(damageTable.fromEntity)
    
                    if from and from ~= lplr then
                        local lastHit = (os.clock() - (AttackData[from] or 0))
                        if lastHit <= 0.26 then
                            Strikes[from] = (Strikes[from] or 0) + 1
    
                            task.delay(60, function()
                                pcall(function()
                                    Strikes[from] -= 1
                                end)
                            end)
    
                            if Strikes[from] > 2 then
                                Added(from, 'Killaura')
                            end
                        end
    
                        AttackData[from] = os.clock()
                    end
                end
            end))
        end,
        Reach = function()
            HackerDetector:Clean(vapeEvents.EntityDamageEvent.Event:Connect(function(damageTable)
                if damageTable.damageType == 0 and damageTable.fromEntity then
                    local player = playersService:GetPlayerFromCharacter(damageTable.fromEntity) 
                    if player and player ~= lplr then
                        local magnitude = (damageTable.fromEntity.PrimaryPart.Position - damageTable.entityInstance.PrimaryPart.Position).Magnitude
                        local held = (store.inventories[player] or {}).hand
                        local meta = held and bedwars.ItemMeta[held.tool.Name].sword or nil
                        local reach = math.floor(meta and meta.attackRange or 12.4) + 4
                        if magnitude > (reach + lplr:GetNetworkPing()) then
                            Added(player, 'Reach')
                        end
                    end
                end
            end))
        end,
        Invisible = function() end,
        HighJump = function() end,
        Phase = function() end,
		Fly = function()
			task.spawn(function()
				repeat
					for _, ent in playersService:GetPlayers() do
						if not store.FlaggedCheaters[ent] and ent ~= lplr then
							local char = ent.Character
							local root = char.HumanoidRootPart
							local hum = char and char:FindFirstChild("Humanoid")

							if hum and root then
								if hum.FloorMaterial ~= Enum.Material.Air then
									flychgedkle[ent] = nil
								else
									if not flychgedkle[ent] then
										flychgedkle[ent] = {
											StartTime = tick()
										}
									end
									local data = flychgedkle[ent]
									local timeInAir = tick() - data.StartTime
									if timeInAir > 2.45 then
										local vel = root.AssemblyLinearVelocity
										local horizontalSpeed = Vector2.new(vel.X, vel.Z).Magnitude
										if horizontalSpeed > 5 and vel.Y > -25 then
											Added(ent, 'Fly')
											flychgedkle[ent] = nil
										end
									end
								end
							end
						end
					end
					task.wait() 
				until not HackerDetector.Enabled
			end)
		end,
	}
    HackerDetector = vape.Categories.Minigames:CreateModule({
        Name = 'Hacker Detector',
        Function = function(callback)
            if callback then
                for i, v in Checks do
                    if HackerDetector.Options and HackerDetector.Options[i].Enabled then
                        task.spawn(v)
                    end
                end
    
                repeat
                    for _, v in entitylib.List do
                        if v.Player and v.Player ~= lplr and v.Health > 0 and not store.FlaggedCheaters[v.Player] then
                            if HackerDetector.Options.Invisible.Enabled and (v.RootPart.Position - v.Head.Position).Magnitude > 5 then
                                Added(v.Player, 'Invisible')
                            end
                            if HackerDetector.Options.HighJump.Enabled and v.RootPart.AssemblyLinearVelocity.Y > 80 then
                                Added(v.Player, 'HighJump')
                            end
                            if HackerDetector.Options.Phase.Enabled and not checkPoint(v.Head.Position, overlap) then
                                Added(v.Player, 'Phase')
                            end

                        end
                    end
                    task.wait(0.1)
                until not HackerDetector.Enabled
            else
				table.clear(flychgedkle)
			end
        end,
        Tooltip = 'Alerts for any possible cheaters.'
    })
    
    for i in Checks do
        HackerDetector:CreateToggle({
            Name = i,
            Default = true
        })
    end
end)

--[[
	Legit
]]--

run(function()
    local ArmorTrims
    local Color
    local Type
    
    ArmorTrims = vape.Legit:CreateModule({
        Name = 'Armor Trims',
        Function = function(callback)
            if callback then
                ArmorTrims:Clean(entitylib.Events.LocalAdded:Connect(function(ent)
    				task.delay(lplr:GetNetworkPing(), function()
                        if not ArmorTrims.Enabled then return end
    					lplr:SetAttribute('ArmorTrimType', Type.Value)
                        lplr:SetAttribute('ArmorTrimColor', Color3.fromHSV(Color.Hue, Color.Sat, Color.Value))
    				end)
    			end))
            end
        end
    })
    
    local list = {}
    for i = 1, 12 do
        table.insert(list, 'trim_'.. i)
    end
    Type = ArmorTrims:CreateDropdown({
        Name = 'Trim type',
        List = list,
        Default = list[1],
        Function = function(val)
            if ArmorTrims.Enabled and lplr.Character then
                lplr:SetAttribute('ArmorTrimType', val)
            end
        end
    })
    Color = ArmorTrims:CreateColorSlider({
        Name = 'Trim color',
        Function = function(hue, sat, val)
            if ArmorTrims.Enabled and lplr.Character then
                lplr:SetAttribute('ArmorTrimColor', Color3.fromHSV(hue, sat, val))
            end
        end
    })
end)

run(function()
	local BedBreakEffect
	local Mode
	local List
	local NameToId = {}
	BedBreakEffect = vape.Legit:CreateModule({
		Name = 'Bed Break Effect',
		Function = function(callback)
			if callback then
				BedBreakEffect:Clean(vapeEvents.BedwarsBedBreak.Event:Connect(function(data)
					firesignal(bedwars.Client:Get('BedBreakEffectTriggered').instance.OnClientEvent, {
						player = data.player,
						position = data.bedBlockPosition * 3,
						effectType = NameToId[List.Value],
						teamId = data.brokenBedTeam.id,
						centerBedPosition = data.bedBlockPosition * 3
					})
				end))
			end
		end,
		Tooltip = 'Custom bed break effects'
	})
	local BreakEffectName = {}
	for i, v in bedwars.BedBreakEffectMeta do
		table.insert(BreakEffectName, v.name)
		NameToId[v.name] = i
	end
	table.sort(BreakEffectName)
	List = BedBreakEffect:CreateDropdown({
		Name = 'Effect',
		List = BreakEffectName
	})
end)

run(function()
	vape.Legit:CreateModule({
		Name = 'Clean Kit',
		Function = function(callback)
			if callback then
				hookfunction(bedwars.WindWalkerController.spawnOrb, function()
					return
				end)
				local zephyreffect = lplr.PlayerGui:FindFirstChild('WindWalkerEffect', true)
				if zephyreffect then
					zephyreffect.Visible = callback
				end
			else
				restorefunction(bedwars.WindWalkerController.spawnOrb)
			end
		end,
		Tooltip = 'Removes zephyr status indicator'
	})
end)

run(function()
	local old
	local Image
	local Crosshair = vape.Legit:CreateModule({
		Name = 'Crosshair',
		Function = function(callback)
			if callback then
				old = debug.getconstant(bedwars.ViewmodelController.showCrosshair, 25)
				debug.setconstant(bedwars.ViewmodelController.showCrosshair, 25, Image.Value)
				debug.setconstant(bedwars.ViewmodelController.showCrosshair, 37, Image.Value)
			else
				debug.setconstant(bedwars.ViewmodelController.showCrosshair, 25, old)
				debug.setconstant(bedwars.ViewmodelController.showCrosshair, 37, old)
				old = nil
			end
			if bedwars.ViewmodelController.crosshair then
				bedwars.ViewmodelController:hideCrosshair()
				bedwars.ViewmodelController:showCrosshair()
			end
		end,
		Tooltip = 'Custom first person crosshair depending on the image choosen.'
	})
	Image = Crosshair:CreateTextBox({
		Name = 'Image',
		Placeholder = 'image id (roblox)',
		Function = function(enter)
			if enter and Crosshair.Enabled then
				Crosshair:Toggle()
				Crosshair:Toggle()
			end
		end
	})
end)

run(function()
	local DamageIndicator
	local FontOption
	local Color
	local Size
	local Anchor
	local Stroke
	local suc, tab = pcall(function()
		return debug.getupvalue(bedwars.DamageIndicator, 2)
	end)
	tab = suc and tab or {}
	local oldvalues, oldfont = {}
	DamageIndicator = vape.Legit:CreateModule({
		Name = 'Damage Indicator',
		Function = function(callback)
			if callback then
				oldvalues = table.clone(tab)
				oldfont = debug.getconstant(bedwars.DamageIndicator, 86)
				debug.setconstant(bedwars.DamageIndicator, 86, Enum.Font[FontOption.Value])
				debug.setconstant(bedwars.DamageIndicator, 119, Stroke.Enabled and 'Thickness' or 'Enabled')
				tab.strokeThickness = Stroke.Enabled and 1 or false
				tab.textSize = Size.Value
				tab.blowUpSize = Size.Value
				tab.blowUpDuration = 0
				tab.baseColor = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
				tab.blowUpCompleteDuration = 0
				tab.anchoredDuration = Anchor.Value
			else
				for i, v in oldvalues do
					tab[i] = v
				end
				debug.setconstant(bedwars.DamageIndicator, 86, oldfont)
				debug.setconstant(bedwars.DamageIndicator, 119, 'Thickness')
			end
		end,
		Tooltip = 'Customize the damage indicator'
	})
	local fontitems = {
		'GothamBlack'
	}
	for _, v in Enum.Font:GetEnumItems() do
		if v.Name ~= 'GothamBlack' then
			table.insert(fontitems, v.Name)
		end
	end
	FontOption = DamageIndicator:CreateDropdown({
		Name = 'Font',
		List = fontitems,
		Function = function(val)
			if DamageIndicator.Enabled then
				debug.setconstant(bedwars.DamageIndicator, 86, Enum.Font[val])
			end
		end
	})
	Color = DamageIndicator:CreateColorSlider({
		Name = 'Color',
		DefaultHue = 0,
		Function = function(hue, sat, val)
			if DamageIndicator.Enabled then
				tab.baseColor = Color3.fromHSV(hue, sat, val)
			end
		end
	})
	Size = DamageIndicator:CreateSlider({
		Name = 'Size',
		Min = 1,
		Max = 32,
		Default = 32,
		Function = function(val)
			if DamageIndicator.Enabled then
				tab.textSize = val
				tab.blowUpSize = val
			end
		end
	})
	Anchor = DamageIndicator:CreateSlider({
		Name = 'Anchor',
		Min = 0,
		Max = 1,
		Decimal = 10,
		Function = function(val)
			if DamageIndicator.Enabled then
				tab.anchoredDuration = val
			end
		end
	})
	Stroke = DamageIndicator:CreateToggle({
		Name = 'Stroke',
		Function = function(callback)
			if DamageIndicator.Enabled then
				debug.setconstant(bedwars.DamageIndicator, 119, callback and 'Thickness' or 'Enabled')
				tab.strokeThickness = callback and 1 or false
			end
		end
	})
end)

run(function()
	local FOV
	local Value
	local old, old2
	FOV = vape.Legit:CreateModule({
		Name = 'FOV',
		Function = function(callback)
			if callback then
				old = bedwars.FovController.setFOV
				old2 = bedwars.FovController.getFOV
				bedwars.FovController.setFOV = function(self)
					return old(self, Value.Value)
				end
				bedwars.FovController.getFOV = function()
					return Value.Value
				end
			else
				bedwars.FovController.setFOV = old
				bedwars.FovController.getFOV = old2
			end
			bedwars.FovController:setFOV(bedwars.Store:getState().Settings.fov)
		end,
		Tooltip = 'Adjusts camera vision'
	})
	Value = FOV:CreateSlider({
		Name = 'FOV',
		Min = 30,
		Max = 120
	})
end)

run(function()
	local FPSBoost
	local Kill
	local Visualizer
	local effects, util = {}, {}
	FPSBoost = vape.Legit:CreateModule({
		Name = 'FPS Boost',
		Function = function(callback)
			if callback then
				if Kill.Enabled then
					for i, v in bedwars.KillEffectController.killEffects do
						if not i:find('Custom') then
							effects[i] = v
							bedwars.KillEffectController.killEffects[i] = {
								new = function()
									return {
										onKill = function()
										end,
										isPlayDefaultKillEffect = function()
											return true
										end
									}
								end
							}
						end
					end
				end
				if Visualizer.Enabled then
					for i, v in bedwars.VisualizerUtils do
						util[i] = v
						bedwars.VisualizerUtils[i] = function()
						end
					end
				end
				repeat
					task.wait()
				until store.matchState ~= 0
				if not bedwars.AppController then
					return
				end
				bedwars.NametagController.addGameNametag = function()
				end
				for _, v in bedwars.AppController:getOpenApps() do
					if tostring(v):find('Nametag') then
						bedwars.AppController:closeApp(tostring(v))
					end
				end
			else
				for i, v in effects do
					bedwars.KillEffectController.killEffects[i] = v
				end
				for i, v in util do
					bedwars.VisualizerUtils[i] = v
				end
				table.clear(effects)
				table.clear(util)
			end
		end,
		Tooltip = 'Improves the framerate by turning off certain effects'
	})
	Kill = FPSBoost:CreateToggle({
		Name = 'Kill Effects',
		Function = function()
			if FPSBoost.Enabled then
				FPSBoost:Toggle()
				FPSBoost:Toggle()
			end
		end,
		Default = true
	})
	Visualizer = FPSBoost:CreateToggle({
		Name = 'Visualizer',
		Function = function()
			if FPSBoost.Enabled then
				FPSBoost:Toggle()
				FPSBoost:Toggle()
			end
		end,
		Default = true
	})
end)

run(function()
	local HitColor
	local Color
	local done = {}
	HitColor = vape.Legit:CreateModule({
		Name = 'Hit Color',
		Function = function(callback)
			if callback then
				repeat
					for i, v in entitylib.List do
						local highlight = v.Character and v.Character:FindFirstChild('_DamageHighlight_')
						if highlight then
							if not table.find(done, highlight) then
								table.insert(done, highlight)
							end
							highlight.FillColor = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
							highlight.FillTransparency = Color.Opacity
						end
					end
					task.wait(0.1)
				until not HitColor.Enabled
			else
				for i, v in done do
					v.FillColor = Color3.new(1, 0, 0)
					v.FillTransparency = 0.4
				end
				table.clear(done)
			end
		end,
		Tooltip = 'Customize the hit highlight options'
	})
	Color = HitColor:CreateColorSlider({
		Name = 'Color',
		DefaultOpacity = 0.4
	})
end)

run(function()
	vape.Legit:CreateModule({
		Name = 'Hit Fix',
		Function = function(callback)
			debug.setconstant(bedwars.SwordController.swingSwordAtMouse, 23, callback and 'raycast' or 'Raycast')
			debug.setupvalue(bedwars.SwordController.swingSwordAtMouse, 4, callback and bedwars.QueryUtil or workspace)
		end,
		Tooltip = 'Changes the raycast function to the correct one'
	})
end)

run(function()
	local Interface
	local HotbarOpenInventory = require(lplr.PlayerScripts.TS.controllers.global.hotbar.ui['hotbar-open-inventory']).HotbarOpenInventory
	local HotbarHealthbar = require(lplr.PlayerScripts.TS.controllers.global.hotbar.ui.healthbar['hotbar-healthbar']).HotbarHealthbar
	local HotbarApp = getRoactRender(require(lplr.PlayerScripts.TS.controllers.global.hotbar.ui['hotbar-app']).HotbarApp.render)
	local old, new = {}, {}
	vape:Clean(function()
		for _, v in new do
			table.clear(v)
		end
		for _, v in old do
			table.clear(v)
		end
		table.clear(new)
		table.clear(old)
	end)
	local function modifyconstant(func, ind, val)
		if not func then
			return
		end
		if not old[func] then
			old[func] = {}
		end
		if not new[func] then
			new[func] = {}
		end
		if not old[func][ind] then
			old[func][ind] = debug.getconstant(func, ind)
		end
		if typeof(old[func][ind]) ~= typeof(val) then
			return
		end
		new[func][ind] = val
		if Interface.Enabled then
			if val then
				debug.setconstant(func, ind, val)
			else
				debug.setconstant(func, ind, old[func][ind])
				old[func][ind] = nil
			end
		end
	end
	Interface = vape.Legit:CreateModule({
		Name = 'Interface',
		Function = function(callback)
			for i, v in (callback and new or old) do
				for i2, v2 in v do
					debug.setconstant(i, i2, v2)
				end
			end
		end,
		Tooltip = 'Customize bedwars UI'
	})
	local fontitems = {
		'LuckiestGuy'
	}
	for _, v in Enum.Font:GetEnumItems() do
		if v.Name ~= 'LuckiestGuy' then
			table.insert(fontitems, v.Name)
		end
	end
	Interface:CreateDropdown({
		Name = 'Health Font',
		List = fontitems,
		Function = function(val)
			modifyconstant(HotbarHealthbar.render, 77, val)
		end
	})
	Interface:CreateColorSlider({
		Name = 'Health Color',
		Function = function(hue, sat, val)
			modifyconstant(HotbarHealthbar.render, 16, tonumber(Color3.fromHSV(hue, sat, val):ToHex(), 16))
			if Interface.Enabled then
				local hotbar = lplr.PlayerGui:FindFirstChild('hotbar')
				hotbar = hotbar and hotbar:FindFirstChild('HealthbarProgressWrapper', true)
				if hotbar then
					hotbar['1'].BackgroundColor3 = Color3.fromHSV(hue, sat, val)
				end
			end
		end
	})
	Interface:CreateColorSlider({
		Name = 'Hotbar Color',
		DefaultOpacity = 0.8,
		Function = function(hue, sat, val, opacity)
			local func = oldinvrender or HotbarOpenInventory.render
			modifyconstant(debug.getupvalue(HotbarApp, 23).render, 51, tonumber(Color3.fromHSV(hue, sat, val):ToHex(), 16))
			modifyconstant(debug.getupvalue(HotbarApp, 23).render, 58, tonumber(Color3.fromHSV(hue, sat, math.clamp(val > 0.5 and val - 0.2 or val + 0.2, 0, 1)):ToHex(), 16))
			modifyconstant(debug.getupvalue(HotbarApp, 23).render, 54, 1 - opacity)
			modifyconstant(debug.getupvalue(HotbarApp, 23).render, 55, math.clamp(1.2 - opacity, 0, 1))
			modifyconstant(func, 31, tonumber(Color3.fromHSV(hue, sat, val):ToHex(), 16))
			modifyconstant(func, 32, math.clamp(1.2 - opacity, 0, 1))
			modifyconstant(func, 34, tonumber(Color3.fromHSV(hue, sat, math.clamp(val > 0.5 and val - 0.2 or val + 0.2, 0, 1)):ToHex(), 16))
		end
	})
end)

run(function()
	local KillEffect
	local Mode
	local List
	local NameToId = {}
	local killeffects = {
		Gravity = function(_, _, char, _)
			char:BreakJoints()
			local highlight = char:FindFirstChildWhichIsA('Highlight')
			local nametag = char:FindFirstChild('Nametag', true)
			if highlight then
				highlight:Destroy()
			end
			if nametag then
				nametag:Destroy()
			end
			task.spawn(function()
				local partvelo = {}
				for _, v in char:GetDescendants() do
					if v:IsA('BasePart') then
						partvelo[v.Name] = v.Velocity
					end
				end
				char.Archivable = true
				local clone = char:Clone()
				clone.Humanoid.Health = 100
				clone.Parent = workspace
				game:GetService('Debris'):AddItem(clone, 30)
				char:Destroy()
				task.wait(0.01)
				clone.Humanoid:ChangeState(Enum.HumanoidStateType.Dead)
				clone:BreakJoints()
				task.wait(0.01)
				for _, v in clone:GetDescendants() do
					if v:IsA('BasePart') then
						local bodyforce = Instance.new('BodyForce')
						bodyforce.Force = Vector3.new(0, (workspace.Gravity - 10) * v:GetMass(), 0)
						bodyforce.Parent = v
						v.CanCollide = true
						v.Velocity = partvelo[v.Name] or Vector3.zero
					end
				end
			end)
		end,
		Lightning = function(_, _, char, _)
			char:BreakJoints()
			local highlight = char:FindFirstChildWhichIsA('Highlight')
			if highlight then
				highlight:Destroy()
			end
			local startpos = 1125
			local startcf = char.PrimaryPart.CFrame.p - Vector3.new(0, 8, 0)
			local newpos = Vector3.new((math.random(1, 10) - 5) * 2, startpos, (math.random(1, 10) - 5) * 2)
			for i = startpos - 75, 0, - 75 do
				local newpos2 = Vector3.new((math.random(1, 10) - 5) * 2, i, (math.random(1, 10) - 5) * 2)
				if i == 0 then
					newpos2 = Vector3.zero
				end
				local part = Instance.new('Part')
				part.Size = Vector3.new(1.5, 1.5, 77)
				part.Material = Enum.Material.SmoothPlastic
				part.Anchored = true
				part.Material = Enum.Material.Neon
				part.CanCollide = false
				part.CFrame = CFrame.new(startcf + newpos + ((newpos2 - newpos) * 0.5), startcf + newpos2)
				part.Parent = workspace
				local part2 = part:Clone()
				part2.Size = Vector3.new(3, 3, 78)
				part2.Color = Color3.new(0.7, 0.7, 0.7)
				part2.Transparency = 0.7
				part2.Material = Enum.Material.SmoothPlastic
				part2.Parent = workspace
				game:GetService('Debris'):AddItem(part, 0.5)
				game:GetService('Debris'):AddItem(part2, 0.5)
				bedwars.QueryUtil:setQueryIgnored(part, true)
				bedwars.QueryUtil:setQueryIgnored(part2, true)
				if i == 0 then
					local soundpart = Instance.new('Part')
					soundpart.Transparency = 1
					soundpart.Anchored = true
					soundpart.Size = Vector3.zero
					soundpart.Position = startcf
					soundpart.Parent = workspace
					bedwars.QueryUtil:setQueryIgnored(soundpart, true)
					local sound = Instance.new('Sound')
					sound.SoundId = 'rbxassetid://6993372814'
					sound.Volume = 2
					sound.Pitch = 0.5 + (math.random(1, 3) / 10)
					sound.Parent = soundpart
					sound:Play()
					sound.Ended:Connect(function()
						soundpart:Destroy()
					end)
				end
				newpos = newpos2
			end
		end,
		Delete = function(_, _, char, _)
			char:Destroy()
		end
	}
	KillEffect = vape.Legit:CreateModule({
		Name = 'Kill Effect',
		Function = function(callback)
			if callback then
				for i, v in killeffects do
					bedwars.KillEffectController.killEffects['Custom' .. i] = {
						new = function()
							return {
								onKill = v,
								isPlayDefaultKillEffect = function()
									return false
								end
							}
						end
					}
				end
				KillEffect:Clean(lplr:GetAttributeChangedSignal('KillEffectType'):Connect(function()
					lplr:SetAttribute('KillEffectType', Mode.Value == 'Bedwars' and NameToId[List.Value] or 'Custom' .. Mode.Value)
				end))
				lplr:SetAttribute('KillEffectType', Mode.Value == 'Bedwars' and NameToId[List.Value] or 'Custom' .. Mode.Value)
			else
				for i in killeffects do
					bedwars.KillEffectController.killEffects['Custom' .. i] = nil
				end
				lplr:SetAttribute('KillEffectType', 'default')
			end
		end,
		Tooltip = 'Custom final kill effects'
	})
	local modes = {
		'Bedwars'
	}
	for i in killeffects do
		table.insert(modes, i)
	end
	Mode = KillEffect:CreateDropdown({
		Name = 'Mode',
		List = modes,
		Function = function(val)
			List.Object.Visible = val == 'Bedwars'
			if KillEffect.Enabled then
				lplr:SetAttribute('KillEffectType', val == 'Bedwars' and NameToId[List.Value] or 'Custom' .. val)
			end
		end
	})
	local KillEffectName = {}
	for i, v in bedwars.KillEffectMeta do
		table.insert(KillEffectName, v.name)
		NameToId[v.name] = i
	end
	table.sort(KillEffectName)
	List = KillEffect:CreateDropdown({
		Name = 'Bedwars',
		List = KillEffectName,
		Function = function(val)
			if KillEffect.Enabled then
				lplr:SetAttribute('KillEffectType', NameToId[val])
			end
		end,
		Darker = true
	})
end)

run(function()
	local ReachDisplay
	local label
	ReachDisplay = vape.Legit:CreateModule({
		Name = 'Reach Display',
		Function = function(callback)
			if callback then
				repeat
					label.Text = (store.attackReachUpdate > tick() and store.attackReach or '0.00') .. ' studs'
					task.wait(0.4)
				until not ReachDisplay.Enabled
			end
		end,
		Size = UDim2.fromOffset(100, 41)
	})
	ReachDisplay:CreateFont({
		Name = 'Font',
		Blacklist = 'Gotham',
		Function = function(val)
			label.FontFace = val
		end
	})
	ReachDisplay:CreateColorSlider({
		Name = 'Color',
		DefaultValue = 0,
		DefaultOpacity = 0.5,
		Function = function(hue, sat, val, opacity)
			label.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
			label.BackgroundTransparency = 1 - opacity
		end
	})
	label = Instance.new('TextLabel')
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 0.5
	label.TextSize = 15
	label.Font = Enum.Font.Gotham
	label.Text = '0.00 studs'
	label.TextColor3 = Color3.new(1, 1, 1)
	label.BackgroundColor3 = Color3.new()
	label.Parent = ReachDisplay.Children
	local corner = Instance.new('UICorner')
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = label
end)

run(function()
	local SongBeats
	local List
	local FOV
	local FOVValue = {}
	local Volume
	local alreadypicked = {}
	local beattick = tick()
	local oldfov, songobj, songbpm, songtween
	local function choosesong()
		local list = List.ListEnabled
		if # alreadypicked >= # list then
			table.clear(alreadypicked)
		end
		if # list <= 0 then
			notif('SongBeats', 'no songs', 10)
			SongBeats:Toggle()
			return
		end
		local chosensong = list[math.random(1, # list)]
		if # list > 1 and table.find(alreadypicked, chosensong) then
			repeat
				task.wait()
				chosensong = list[math.random(1, # list)]
			until not table.find(alreadypicked, chosensong) or not SongBeats.Enabled
		end
		if not SongBeats.Enabled then
			return
		end
		local split = chosensong:split('/')
		if not isfile(split[1]) then
			notif('SongBeats', 'Missing song (' .. split[1] .. ')', 10)
			SongBeats:Toggle()
			return
		end
		songobj.SoundId = assetfunction(split[1])
		repeat
			task.wait()
		until songobj.IsLoaded or not SongBeats.Enabled
		if SongBeats.Enabled then
			beattick = tick() + (tonumber(split[3]) or 0)
			songbpm = 60 / (tonumber(split[2]) or 50)
			songobj:Play()
		end
	end
	SongBeats = vape.Legit:CreateModule({
		Name = 'Song Beats',
		Function = function(callback)
			if callback then
				songobj = Instance.new('Sound')
				songobj.Volume = Volume.Value / 100
				songobj.Parent = workspace
				repeat
					if not songobj.Playing then
						choosesong()
					end
					if beattick < tick() and SongBeats.Enabled and FOV.Enabled then
						beattick = tick() + songbpm
						oldfov = math.min(bedwars.FovController:getFOV() * (bedwars.SprintController.sprinting and 1.1 or 1), 120)
						gameCamera.FieldOfView = oldfov - FOVValue.Value
						songtween = tweenService:Create(gameCamera, TweenInfo.new(math.min(songbpm, 0.2), Enum.EasingStyle.Linear), {
							FieldOfView = oldfov
						})
						songtween:Play()
					end
					task.wait()
				until not SongBeats.Enabled
			else
				if songobj then
					songobj:Destroy()
				end
				if songtween then
					songtween:Cancel()
				end
				if oldfov then
					gameCamera.FieldOfView = oldfov
				end
				table.clear(alreadypicked)
			end
		end,
		Tooltip = 'Built in mp3 player'
	})
	List = SongBeats:CreateTextList({
		Name = 'Songs',
		Placeholder = 'filepath/bpm/start'
	})
	FOV = SongBeats:CreateToggle({
		Name = 'Beat FOV',
		Function = function(callback)
			if FOVValue.Object then
				FOVValue.Object.Visible = callback
			end
			if SongBeats.Enabled then
				SongBeats:Toggle()
				SongBeats:Toggle()
			end
		end,
		Default = true
	})
	FOVValue = SongBeats:CreateSlider({
		Name = 'Adjustment',
		Min = 1,
		Max = 30,
		Default = 5,
		Darker = true
	})
	Volume = SongBeats:CreateSlider({
		Name = 'Volume',
		Function = function(val)
			if songobj then
				songobj.Volume = val / 100
			end
		end,
		Min = 1,
		Max = 100,
		Default = 100,
		Suffix = '%'
	})
end)

run(function()
	local SoundChanger
	local List
	local soundlist = {}
	local old
	SoundChanger = vape.Legit:CreateModule({
		Name = 'Sound Changer',
		Function = function(callback)
			if callback then
				old = bedwars.SoundManager.playSound
				bedwars.SoundManager.playSound = function(self, id, ...)
					if soundlist[id] then
						id = soundlist[id]
					end
					return old(self, id, ...)
				end
			else
				bedwars.SoundManager.playSound = old
				old = nil
			end
		end,
		Tooltip = 'Change ingame sounds to custom ones.'
	})
	List = SoundChanger:CreateTextList({
		Name = 'Sounds',
		Placeholder = '(DAMAGE_1/ben.mp3)',
		Function = function()
			table.clear(soundlist)
			for _, entry in List.ListEnabled do
				local split = entry:split('/')
				local id = bedwars.SoundList[split[1]]
				if id and # split > 1 then
					soundlist[id] = split[2]:find('rbxasset') and split[2] or isfile(split[2]) and assetfunction(split[2]) or ''
				end
			end
		end
	})
end)

run(function()
	local UICleanup
	local OpenInv
	local KillFeed
	local OldTabList
	local HotbarApp = getRoactRender(require(lplr.PlayerScripts.TS.controllers.global.hotbar.ui['hotbar-app']).HotbarApp.render)
	local HotbarOpenInventory = require(lplr.PlayerScripts.TS.controllers.global.hotbar.ui['hotbar-open-inventory']).HotbarOpenInventory
	local old, new = {}, {}
	local oldkillfeed
	vape:Clean(function()
		for _, v in new do
			table.clear(v)
		end
		for _, v in old do
			table.clear(v)
		end
		table.clear(new)
		table.clear(old)
	end)
	local function modifyconstant(func, ind, val)
		if not old[func] then
			old[func] = {}
		end
		if not new[func] then
			new[func] = {}
		end
		if not old[func][ind] then
			local typing = type(old[func][ind])
			if typing == 'function' or typing == 'userdata' then
				return
			end
			old[func][ind] = debug.getconstant(func, ind)
		end
		if typeof(old[func][ind]) ~= typeof(val) and val ~= nil then
			return
		end
		new[func][ind] = val
		if UICleanup.Enabled then
			if val then
				debug.setconstant(func, ind, val)
			else
				debug.setconstant(func, ind, old[func][ind])
				old[func][ind] = nil
			end
		end
	end
	UICleanup = vape.Legit:CreateModule({
		Name = 'UI Cleanup',
		Function = function(callback)
			for i, v in (callback and new or old) do
				for i2, v2 in v do
					debug.setconstant(i, i2, v2)
				end
			end
			if callback then
				if OpenInv.Enabled then
					oldinvrender = HotbarOpenInventory.render
					HotbarOpenInventory.render = function()
						return bedwars.Roact.createElement('TextButton', {
							Visible = false
						}, {})
					end
				end
				if KillFeed.Enabled then
					oldkillfeed = bedwars.KillFeedController.addToKillFeed
					bedwars.KillFeedController.addToKillFeed = function()
					end
				end
				if OldTabList.Enabled then
					starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, true)
				end
			else
				if oldinvrender then
					HotbarOpenInventory.render = oldinvrender
					oldinvrender = nil
				end
				if KillFeed.Enabled then
					bedwars.KillFeedController.addToKillFeed = oldkillfeed
					oldkillfeed = nil
				end
				if OldTabList.Enabled then
					starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
				end
			end
		end,
		Tooltip = 'Cleans up the UI for kits & main'
	})
	UICleanup:CreateToggle({
		Name = 'Resize Health',
		Function = function(callback)
			modifyconstant(HotbarApp, 60, callback and 1 or nil)
			modifyconstant(debug.getupvalue(HotbarApp, 15).render, 30, callback and 1 or nil)
			modifyconstant(debug.getupvalue(HotbarApp, 23).tweenPosition, 16, callback and 0 or nil)
		end,
		Default = true
	})
	UICleanup:CreateToggle({
		Name = 'No Hotbar Numbers',
		Function = function(callback)
			local func = oldinvrender or HotbarOpenInventory.render
			modifyconstant(debug.getupvalue(HotbarApp, 23).render, 90, callback and 0 or nil)
			modifyconstant(func, 71, callback and 0 or nil)
		end,
		Default = true
	})
	OpenInv = UICleanup:CreateToggle({
		Name = 'No Inventory Button',
		Function = function(callback)
			modifyconstant(HotbarApp, 78, callback and 0 or nil)
			if UICleanup.Enabled then
				if callback then
					oldinvrender = HotbarOpenInventory.render
					HotbarOpenInventory.render = function()
						return bedwars.Roact.createElement('TextButton', {
							Visible = false
						}, {})
					end
				else
					HotbarOpenInventory.render = oldinvrender
					oldinvrender = nil
				end
			end
		end,
		Default = true
	})
	KillFeed = UICleanup:CreateToggle({
		Name = 'No Kill Feed',
		Function = function(callback)
			if UICleanup.Enabled then
				if callback then
					oldkillfeed = bedwars.KillFeedController.addToKillFeed
					bedwars.KillFeedController.addToKillFeed = function()
					end
				else
					bedwars.KillFeedController.addToKillFeed = oldkillfeed
					oldkillfeed = nil
				end
			end
		end,
		Default = true
	})
	OldTabList = UICleanup:CreateToggle({
		Name = 'Old Player List',
		Function = function(callback)
			if UICleanup.Enabled then
				starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, callback)
			end
		end,
		Default = true
	})
	UICleanup:CreateToggle({
		Name = 'Fix Queue Card',
		Function = function(callback)
			modifyconstant(bedwars.QueueCard.render, 15, callback and 0.1 or nil)
		end,
		Default = true
	})
end)

run(function()
	local WinEffect
	local List
	local NameToId = {}
	WinEffect = vape.Legit:CreateModule({
		Name = 'Win Effect',
		Function = function(callback)
			if callback then
				WinEffect:Clean(vapeEvents.MatchEndEvent.Event:Connect(function()
					for i, v in getconnections(bedwars.Client:Get('WinEffectTriggered').instance.OnClientEvent) do
						if v.Function then
							v.Function({
								winEffectType = NameToId[List.Value],
								winningPlayer = lplr
							})
						end
					end
				end))
			end
		end,
		Tooltip = 'Allows you to select any clientside win effect'
	})
	local WinEffectName = {}
	for i, v in bedwars.WinEffectMeta do
		table.insert(WinEffectName, v.name)
		NameToId[v.name] = i
	end
	table.sort(WinEffectName)
	List = WinEffect:CreateDropdown({
		Name = 'Effects',
		List = WinEffectName
	})
end)

run(function()
	local Optimize
	local savedEffects = {}
	
	local function applyOptimizations()
		pcall(function()
			settings():GetService("RenderSettings").QualityLevel = Enum.QualityLevel.Level01
			settings():GetService("RenderSettings").MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level01
		end)
		
		pcall(function()
			lightingService.GlobalShadows = false
			lightingService.FogEnd = 9e9
			lightingService.Brightness = 0
			
			for _, effect in {lightingService:FindFirstChildOfClass("Atmosphere"),
							  lightingService:FindFirstChildOfClass("BlurEffect"),
							  lightingService:FindFirstChildOfClass("BloomEffect"),
							  lightingService:FindFirstChildOfClass("ColorCorrectionEffect"),
							  lightingService:FindFirstChildOfClass("SunRaysEffect")} do
				if effect then
					savedEffects[effect] = effect.Enabled
					effect.Enabled = false
				end
			end
		end)

		task.spawn(function()
			for _, obj in workspace:GetDescendants() do
				if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
					if obj.Enabled then
						savedEffects[obj] = true
						obj.Enabled = false
					end
				end
			end
		end)
		
		pcall(function()
			workspace.Terrain.Decoration = false
			workspace.Terrain.WaterReflectance = 0
			workspace.Terrain.WaterTransparency = 0
		end)
	end
	
	local function restoreOptimizations()
		pcall(function()
			settings():GetService("RenderSettings").QualityLevel = Enum.QualityLevel.Automatic
		end)
		
		for effect, wasEnabled in pairs(savedEffects) do
			if effect and effect.Parent then
				effect.Enabled = wasEnabled
			end
		end
		table.clear(savedEffects)
	end
	
	Optimize = vape.Legit:CreateModule({
		Name = 'Optimize',
		Function = function(callback)
			if callback then
				applyOptimizations()
			else
				restoreOptimizations()
			end
		end,
		Tooltip = 'Maximum FPS optimization - All features remain functional'
	})
end)

run(function()
	local PotatoMode
	local originalProperties = {}
	local blockMonitorConnections = {}
	local processedBlocks = {}
	
	local blockColors = {
		["clay_white"] = Color3.fromRGB(255, 255, 255),
		["wool_white"] = Color3.fromRGB(255, 255, 255),
		["wool_red"] = Color3.fromRGB(255, 50, 50),
		["wool_green"] = Color3.fromRGB(50, 255, 50),
		["grass"] = Color3.fromRGB(50, 255, 50),
		["moss_block"] = Color3.fromRGB(50, 255, 50),
		["wool_blue"] = Color3.fromRGB(50, 100, 255),
		["wool_yellow"] = Color3.fromRGB(255, 255, 50),
		["wool_orange"] = Color3.fromRGB(255, 150, 50),
		["clay_orange"] = Color3.fromRGB(255, 150, 50),
		["wool_purple"] = Color3.fromRGB(180, 50, 255),
		["clay_light_brown"] = Color3.fromRGB(200, 170, 120),
		["wool_pink"] = Color3.fromRGB(255, 100, 200),
		["wool_black"] = Color3.fromRGB(50, 50, 50),
		["wool_cyan"] = Color3.fromRGB(50, 255, 255),
		["wool_magenta"] = Color3.fromRGB(255, 50, 150),
		["wool_lime"] = Color3.fromRGB(150, 255, 50),
		["wool_brown"] = Color3.fromRGB(150, 75, 0),
		["wood_plank_spruce"] = Color3.fromRGB(222, 184, 135),
		["wool_light_blue"] = Color3.fromRGB(100, 200, 255),
		["wool_gray"] = Color3.fromRGB(150, 150, 150),
		["clay"] = Color3.fromRGB(220, 180, 140),
		["wood"] = Color3.fromRGB(180, 140, 100),
		["stone"] = Color3.fromRGB(150, 150, 150),
		["andesite"] = Color3.fromRGB(150, 150, 150),
		["cobblestone"] = Color3.fromRGB(150, 150, 150),
		["obsidian"] = Color3.fromRGB(50, 30, 80),
		["bedrock"] = Color3.fromRGB(80, 80, 80),
		["tnt"] = Color3.fromRGB(255, 50, 50),
		["sandstone"] = Color3.fromRGB(220, 200, 150),
		["sand"] = Color3.fromRGB(220, 200, 150),
		["wool"] = Color3.fromRGB(200, 200, 200),
		["bed"] = Color3.fromRGB(200, 50, 50),
		["concrete"] = Color3.fromRGB(180, 180, 180),
	}
	
	local cachedColors = {}
	
	local function getBlockColor(blockName)
		if cachedColors[blockName] then
			return cachedColors[blockName]
		end
		
		if blockColors[blockName] then
			cachedColors[blockName] = blockColors[blockName]
			return blockColors[blockName]
		end
		
		local lowerName = blockName:lower()
		
		if blockColors[lowerName] then
			cachedColors[blockName] = blockColors[lowerName]
			return blockColors[lowerName]
		end
		
		if lowerName:find("wool", 1, true) then 
			for key, color in pairs(blockColors) do
				if key:find("wool", 1, true) and lowerName:find(key, 1, true) then
					cachedColors[blockName] = color
					return color
				end
			end
			cachedColors[blockName] = blockColors["wool"]
			return blockColors["wool"]
		end
		
		for name, color in pairs(blockColors) do
			if lowerName:find(name, 1, true) then
				cachedColors[blockName] = color
				return color
			end
		end
		
		local defaultColor = Color3.fromRGB(150, 150, 150)
		cachedColors[blockName] = defaultColor
		return defaultColor
	end
	
	local function cleanupDeadReferences()
		for block, _ in pairs(originalProperties) do
			if not block or not block.Parent then
				originalProperties[block] = nil
				processedBlocks[block] = nil
			end
		end
	end
	
	local function simplifyBlock(block)
		if not block or not block.Parent or processedBlocks[block] then return end
		
		if not originalProperties[block] then
			originalProperties[block] = {
				Material = block.Material,
				Color = block.Color,
				TextureID = block:IsA("MeshPart") and block.TextureID or nil,
				Textures = {}
			}
			
			for _, child in block:GetChildren() do
				if child:IsA("Texture") or child:IsA("Decal") then
					table.insert(originalProperties[block].Textures, {
						Class = child.ClassName,
						Texture = child.Texture,
						StudsPerTileU = child.StudsPerTileU,
						StudsPerTileV = child.StudsPerTileV,
						Face = child.Face,
						Transparency = child.Transparency,
						Color3 = child:IsA("Decal") and child.Color3 or nil
					})
				end
			end
		end
		
		block.Material = Enum.Material.SmoothPlastic
		block.Color = getBlockColor(block.Name)
		
		for _, child in block:GetChildren() do
			if child:IsA("Texture") or child:IsA("Decal") then
				child:Destroy()
			end
		end
		
		if block:IsA("MeshPart") and block.TextureID ~= "" then
			block.TextureID = ""
		end
		
		processedBlocks[block] = true
	end
	
	local function restoreBlock(block)
		if not block or not block.Parent then 
			originalProperties[block] = nil
			processedBlocks[block] = nil
			return 
		end
		
		local props = originalProperties[block]
		if not props then return end
		
		block.Material = props.Material or Enum.Material.Plastic
		block.Color = props.Color or Color3.fromRGB(255, 255, 255)
		
		if props.TextureID and block:IsA("MeshPart") then
			block.TextureID = props.TextureID
		end
		
		for _, textureProps in props.Textures do
			local newTexture
			if textureProps.Class == "Texture" then
				newTexture = Instance.new("Texture")
				newTexture.StudsPerTileU = textureProps.StudsPerTileU or 1
				newTexture.StudsPerTileV = textureProps.StudsPerTileV or 1
			else
				newTexture = Instance.new("Decal")
				newTexture.Color3 = textureProps.Color3 or Color3.fromRGB(255, 255, 255)
			end
			
			newTexture.Texture = textureProps.Texture or ""
			newTexture.Face = textureProps.Face or Enum.NormalId.Front
			newTexture.Transparency = textureProps.Transparency or 0
			newTexture.Parent = block
		end
		
		originalProperties[block] = nil
		processedBlocks[block] = nil
	end
	
	local function isTargetBlock(obj)
		if not obj:IsA("BasePart") then return false end
		
		local name = obj.Name
		
		if blockColors[name] then return true end
		
		local lowerName = name:lower()
		return lowerName:find("wool", 1, true) or 
		       lowerName:find("clay", 1, true) or
		       lowerName:find("wood", 1, true) or 
		       lowerName:find("stone", 1, true) or 
		       lowerName:find("glass", 1, true) or
		       lowerName:find("plank", 1, true) or 
		       lowerName:find("bed", 1, true) or 
		       lowerName:find("obsidian", 1, true) or
		       lowerName:find("sand", 1, true) or 
		       lowerName:find("end", 1, true) or 
		       lowerName:find("tnt", 1, true) or
		       lowerName:find("barrier", 1, true) or 
		       lowerName:find("magic", 1, true) or 
		       lowerName:find("concrete", 1, true) or
		       lowerName:find("_block", 1, true) or 
		       obj:IsA("Seat")
	end
	
	local function processExistingBlocks(simplify)
		local descendants = workspace:GetDescendants()
		
		task.spawn(function()
			for i, obj in descendants do
				if isTargetBlock(obj) then
					if simplify then
						simplifyBlock(obj)
					else
						restoreBlock(obj)
					end
				end
			end
			
			if not simplify then
				cleanupDeadReferences()
			end
		end)
	end
	
	local function setupBlockMonitor(simplify)
		for _, conn in blockMonitorConnections do
			conn:Disconnect()
		end
		table.clear(blockMonitorConnections)
		
		if not simplify then return end
		
		local mainConn = workspace.DescendantAdded:Connect(function(descendant)
			if isTargetBlock(descendant) then
				task.defer(function()
					if descendant and descendant.Parent then
						simplifyBlock(descendant)
					end
				end)
			end
		end)
		
		table.insert(blockMonitorConnections, mainConn)
		
		local lastCleanup = 0
		local cleanupConn = runService.Heartbeat:Connect(function()
			local now = tick()
			if now - lastCleanup >= 5 then
				lastCleanup = now
				cleanupDeadReferences()
			end
		end)
		
		table.insert(blockMonitorConnections, cleanupConn)
	end
	
	PotatoMode = vape.Legit:CreateModule({
		Name = 'PotatoMode',
		Function = function(callback)
			if callback then
				processExistingBlocks(true)
				setupBlockMonitor(true)
			else
				processExistingBlocks(false)
				for _, conn in blockMonitorConnections do
					conn:Disconnect()
				end
				table.clear(blockMonitorConnections)
				table.clear(cachedColors)
				cleanupDeadReferences()
			end
		end,
		Tooltip = 'Removes block textures but keeps colors'
	})
end)

--[[
	Kits
]]--

run(function()
	local aim = 0.158
	local tnt = 0.0045
	local aunchself = 0.395
	local defaultaim = 0.4
	local defaulttnt = 0.2
	local defaultself = 0.4
	local A
	local T
	local L
	local C
	local AJ
	local AS
	local Speed = vape.Modules.Speed
	local Fly = vape.Modules.Fly
	local function setCannonSpeeds(blocksFolder, aimDur, tntDur, selfDur)
		for _, v in ipairs(blocksFolder:GetChildren()) do
			if v:IsA("BasePart") and v.Name == "cannon" then
				local AimPrompt = v:FindFirstChild("AimPrompt")
				local FirePrompt = v:FindFirstChild("FirePrompt")
				local LaunchSelfPrompt = v:FindFirstChild("LaunchSelfPrompt")
				if AimPrompt and FirePrompt and LaunchSelfPrompt then
					AimPrompt.HoldDuration = aimDur
					FirePrompt.HoldDuration = tntDur
					LaunchSelfPrompt.HoldDuration = selfDur
				end
			end
		end
	end
	BetterDavey = vape.Categories.Kits:CreateModule({
		Name = "Better Davey",
		Tooltip = "Allows you to edit your cannon speed.",
		Function = function(callback)
			local worldFolder = getWorldFolder()
			if not worldFolder then
				return
			end
			local blocks = worldFolder:WaitForChild("Blocks")
			if callback then
				setCannonSpeeds(blocks, aim, tnt, aunchself)
				local function onLaunchTriggered(child)
					local humanoid = entitylib.character.Humanoid
					if not humanoid then
						return
					end
					if Speed.Enabled and Fly.Enabled then
						Fly:Toggle(false)
						task.wait(0.025)
						Speed:Toggle(false)
					elseif Speed.Enabled then
						Speed:Toggle(false)
					elseif Fly.Enabled then
						Fly:Toggle(false)
					end
					if AS.Enabled then
						local pickaxe = getPickaxeSlot()
						if hotbarSwitch(pickaxe) or store.hand.tool.Name:lower():find("pickaxe") then
							task.spawn(bedwars.breakBlock, child, false, nil, true)
							task.spawn(bedwars.breakBlock, child, false, nil, true)
						end
					else
						task.spawn(bedwars.breakBlock, child, false, nil, true)
						task.spawn(bedwars.breakBlock, child, false, nil, true)
					end
					if AJ.Enabled then
						if humanoid:GetState() ~= Enum.HumanoidStateType.Jumping then
							humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
						end
					end
				end
				local function setupCannon(child)
					if not (child:IsA("BasePart") and child.Name == "cannon" and BetterDavey.Enabled) then
						return
					end
					local AimPrompt = child:WaitForChild("AimPrompt")
					local FirePrompt = child:WaitForChild("FirePrompt")
					local LaunchSelfPrompt = child:WaitForChild("LaunchSelfPrompt")
					AimPrompt.HoldDuration = aim
					FirePrompt.HoldDuration = tnt
					LaunchSelfPrompt.HoldDuration = aunchself
					BetterDavey:Clean(LaunchSelfPrompt.Triggered:Connect(function()
						onLaunchTriggered(child)
					end))
				end
				BetterDavey:Clean(blocks.ChildAdded:Connect(setupCannon))
				for _, child in blocks:GetChildren() do
					setupCannon(child)
				end
			else
				setCannonSpeeds(blocks, defaultaim, defaulttnt, defaultself)
			end
		end
	})
	AJ = BetterDavey:CreateToggle({
		Name = "Auto-Jump",
		Default = true,
		Visible = true
	})
	AS = BetterDavey:CreateToggle({
		Name = "Auto-Switch",
		Default = false,
		Visible = true
	})
	A = BetterDavey:CreateSlider({
		Name = "Aim",
		Visible = false,
		Min = 0,
		Max = 1,
		Default = aim,
		Decimal = 10,
		Function = function(v)
			aim = v
			local worldFolder = getWorldFolder()
			if not worldFolder then
				return
			end
			local blocks = worldFolder:WaitForChild("Blocks")
			setCannonSpeeds(blocks, aim, tnt, aunchself)
		end
	})
	T = BetterDavey:CreateSlider({
		Name = "Tnt",
		Visible = false,
		Min = 0,
		Max = 1,
		Default = tnt,
		Decimal = 10,
		Function = function(v)
			tnt = v
			local worldFolder = getWorldFolder()
			if not worldFolder then
				return
			end
			local blocks = worldFolder:WaitForChild("Blocks")
			setCannonSpeeds(blocks, aim, tnt, aunchself)
		end
	})
	L = BetterDavey:CreateSlider({
		Name = "Launch Self",
		Visible = false,
		Min = 0,
		Max = 1,
		Default = aunchself,
		Decimal = 10,
		Function = function(v)
			aunchself = v
			local worldFolder = getWorldFolder()
			if not worldFolder then
				return
			end
			local blocks = worldFolder:WaitForChild("Blocks")
			setCannonSpeeds(blocks, aim, tnt, aunchself)
		end
	})
	C = BetterDavey:CreateToggle({
		Name = "Customize",
		Default = false,
		Visible = true,
		Function = function(v)
			A.Object.Visible = v
			T.Object.Visible = v
			L.Object.Visible = v
			if not v then
				aim = 0.158
				tnt = 0.0045
				aunchself = 0.395
			end
		end
	})
end)

run(function()
	local AutoKit
	local Legit
	local Toggles = {}
	local function kitCollection(id, func, range, specific)
		local objs = type(id) == 'table' and id or collection(id, AutoKit)
		repeat
			if entitylib.isAlive then
				local localPosition = entitylib.character.RootPart.Position
				for _, v in objs do
					if InfiniteFly.Enabled or not AutoKit.Enabled then
						break
					end
					local part = not v:IsA('Model') and v or v.PrimaryPart
					if part and (part.Position - localPosition).Magnitude <= (not Legit.Enabled and specific and math.huge or range) then
						func(v)
					end
				end
			end
			task.wait(0.1)
		until not AutoKit.Enabled
	end
	local AutoKitFunctions = {
		blood_assassin = function()
			local hitPlayers = {}
			AutoKit:Clean(vapeEvents.EntityDamageEvent.Event:Connect(function(damageTable)
				if not entitylib.isAlive then
					return
				end
				local attacker = playersService:GetPlayerFromCharacter(damageTable.fromEntity)
				local victim = playersService:GetPlayerFromCharacter(damageTable.entityInstance)
				if attacker == lplr and victim and victim ~= lplr then
					hitPlayers[victim] = true
					local storeState = bedwars.Store:getState()
					local activeContract = storeState.Kit.activeContract
					local availableContracts = storeState.Kit.availableContracts or {}
					if not activeContract then
						for _, contract in availableContracts do
							if contract.target == victim then
								task.wait(Legit.Enabled and lplr:GetNetworkPing() or 0)
								bedwars.Client:Get('BloodAssassinSelectContract'):SendToServer({
									contractId = contract.id
								})
								table.clear(hitPlayers)
								break
							end
						end
					end
				end
			end))
			AutoKit:Clean(function()
				table.clear(hitPlayers)
			end)
		end,
		battery = function()
			repeat
				if entitylib.isAlive then
					local localPosition = entitylib.character.RootPart.Position
					for i, v in bedwars.BatteryEffectsController.liveBatteries do
						if (v.position - localPosition).Magnitude <= Legit.Enabled and 10 or 18 then
							local BatteryInfo = bedwars.BatteryEffectsController:getBatteryInfo(i)
							if not BatteryInfo or BatteryInfo.activateTime >= workspace:GetServerTimeNow() or BatteryInfo.consumeTime + (Legit.Enabled and 0.5 or 0.25) - lplr:GetNetworkPing() >= workspace:GetServerTimeNow() then
								continue
							end
							BatteryInfo.consumeTime = workspace:GetServerTimeNow()
							bedwars.Client:Get(remotes.ConsumeBattery):SendToServer({
								batteryId = i
							})
						end
					end
				end
				task.wait(0.1)
			until not AutoKit.Enabled
		end,
		beekeeper = function()
			local pickup = false
			kitCollection('bee', function(v)
				if Legit.Enabled then
					repeat
						task.wait(0.08)
					until store.hand.tool and store.hand.tool.Name:lower():find("net")
					pickup = true
				else
					pickup = true
				end
				repeat
					task.wait(0.02)
				until pickup
				task.wait(Legit.Enabled and lplr:GetNetworkPing() + 0.1 or lplr:GetNetworkPing())
				if bedwars.Client:Get(remotes.BeePickup):SendToServer({
					beeId = v:GetAttribute('BeeId')
				}) and pickup then
					bedwars.GameAnimationUtil:playAnimation(lplr, bedwars.AnimationType.NET_CATCH)
					bedwars.SoundManager:playSound(bedwars.SoundList.BEE_NET_SWING)
					pickup = false
				end
			end, Legit.Enabled and 8 or 18, false)
		end,
		block_kicker = function()
			local old = bedwars.BlockKickerKitController.getKickBlockProjectileOriginPosition
			bedwars.BlockKickerKitController.getKickBlockProjectileOriginPosition = function(...)
				local origin, dir = select(2, ...)
				local plr = entitylib.EntityMouse({
					Part = 'RootPart',
					Range = Legit.Enabled and 75 or 1000,
					Origin = origin,
					Players = true,
					Wallcheck = Legit.Enabled
				})
				if plr then
					local calc = prediction.SolveTrajectory(origin, 100, 20, plr.RootPart.Position, plr.RootPart.Velocity, workspace.Gravity, plr.HipHeight, plr.Jumping and 42.6 or nil)
					if calc then
						for i, v in debug.getstack(2) do
							if v == dir then
								debug.setstack(2, i, CFrame.lookAt(origin, calc).LookVector)
							end
						end
					end
				end
				return old(...)
			end
			AutoKit:Clean(function()
				bedwars.BlockKickerKitController.getKickBlockProjectileOriginPosition = old
			end)
		end,
		cat = function()
			local old = bedwars.CatController.leap
			bedwars.CatController.leap = function(...)
				vapeEvents.CatPounce:Fire()
				return old(...)
			end
			AutoKit:Clean(function()
				bedwars.CatController.leap = old
			end)
		end,
		davey = function()
			local old = bedwars.CannonHandController.launchSelf
			bedwars.CannonHandController.launchSelf = function(...)
				local res = {
					old(...)
				}
				local self, block = ...
				if block:GetAttribute('PlacedByUserId') == lplr.UserId and (block.Position - entitylib.character.RootPart.Position).Magnitude < 30 then
					if Legit.Enabled then
						local pickaxe = getPickaxeSlot()
						if not hotbarSwitch(pickaxe) or not store.hand.tool.Name:find('pickaxe') then return unpack(res) end
					end
					for i = 1, 2 do
						task.delay(0.05, bedwars.breakBlock, block, false, nil, true)
					end
				end
				return unpack(res)
			end
			AutoKit:Clean(function()
				bedwars.CannonHandController.launchSelf = old
			end)
		end,
		dragon_slayer = function()
			kitCollection('KaliyahPunchInteraction', function(v)
				bedwars.DragonSlayerController:deleteEmblem(v)
				bedwars.DragonSlayerController:playPunchAnimation(Vector3.zero)
				bedwars.Client:Get(remotes.KaliyahPunch):SendToServer({
					target = v
				})
			end, Legit.Enabled and 10 or 18, true)
		end,
		farmer_cletus = function()
			kitCollection('HarvestableCrop', function(v)
				if bedwars.Client:Get(remotes.HarvestCrop):CallServer({
					position = bedwars.BlockController:getBlockPosition(v.Position)
				}) then
					bedwars.GameAnimationUtil:playAnimation(lplr.Character, bedwars.AnimationType.PUNCH)
					bedwars.SoundManager:playSound(bedwars.SoundList.CROP_HARVEST)
				end
			end, Legit.Enabled and 8 or 12, false)
		end,
		fisherman = function()
			local old = bedwars.FishingMinigameController.startMinigame
			bedwars.FishingMinigameController.startMinigame = function(_, _, result)
				local D = lplr:GetNetworkPing()
				D = Legit.Enabled and D + 8 - math.random() or lplr:GetNetworkPing()
				task.delay(D, function()
					result({
						win = true
					})
				end)
			end
			AutoKit:Clean(function()
				bedwars.FishingMinigameController.startMinigame = old
			end)
		end,
		gingerbread_man = function()
			local old = bedwars.LaunchPadController.attemptLaunch
			bedwars.LaunchPadController.attemptLaunch = function(...)
				local res = {
					old(...)
				}
				local self, block = ...
				if (workspace:GetServerTimeNow() - self.lastLaunch) < 0.4 then
					if block:GetAttribute('PlacedByUserId') == lplr.UserId and (block.Position - entitylib.character.RootPart.Position).Magnitude < 30 then
						if Legit.Enabled then
							local pickaxe = getPickaxeSlot()
							if not hotbarSwitch(pickaxe) or not store.hand.tool.Name:find('pickaxe') then return unpack(res) end
						end
						task.delay(0.05, bedwars.breakBlock, block, false, nil, true)
					end
				end
				return unpack(res)
			end
			AutoKit:Clean(function()
				bedwars.LaunchPadController.attemptLaunch = old
			end)
		end,
		hannah = function()
			kitCollection('HannahExecuteInteraction', function(v)
				local billboard = bedwars.Client:Get(remotes.HannahKill):CallServer({
					user = lplr,
					victimEntity = v
				}) and v:FindFirstChild('Hannah Execution Icon')
				if billboard then
					billboard:Destroy()
				end
			end, Legit.Enabled and 15 or 30, true)
		end,
		jailor = function()
			kitCollection('jailor_soul', function(v)
				bedwars.JailorController:collectEntity(lplr, v, 'JailorSoul')
			end, Legit.Enabled and 12 or 20, false)
		end,
		grim_reaper = function()
			kitCollection(bedwars.GrimReaperController.soulsByPosition, function(v)
				if entitylib.isAlive and lplr.Character:GetAttribute('Health') <= (lplr.Character:GetAttribute('MaxHealth') / 4) and (not lplr.Character:GetAttribute('GrimReaperChannel')) then
					bedwars.Client:Get(remotes.ConsumeSoul):CallServer({
						secret = v:GetAttribute('GrimReaperSoulSecret')
					})
				end
			end, Legit.Enabled and 45 or 120, false)
		end,
		melody = function()
			repeat
				local mag, hp, ent = Legit.Enabled and 15 or 30, math.huge
				if entitylib.isAlive then
					local localPosition = entitylib.character.RootPart.Position
					for _, v in entitylib.List do
						if v.Player and v.Player:GetAttribute('Team') == lplr:GetAttribute('Team') then
							local newmag = (localPosition - v.RootPart.Position).Magnitude
							if newmag <= mag and v.Health < hp and v.Health < v.MaxHealth then
								mag, hp, ent = newmag, v.Health, v
							end
						end
					end
				end
				if ent and getItem('guitar') then
					bedwars.Client:Get(remotes.GuitarHeal):SendToServer({
						healTarget = ent.Character
					})
				end
				task.wait(0.1)
			until not AutoKit.Enabled
		end,
		metal_detector = function()
			kitCollection('hidden-metal', function(v)
				bedwars.Client:Get(remotes.PickupMetal):SendToServer({
					id = v:GetAttribute('Id')
				})
			end, Legit.Enabled and 10 or 20, false)
		end,
		miner = function()
			kitCollection('petrified-player', function(v)
				bedwars.Client:Get(remotes.MinerDig):SendToServer({
					petrifyId = v:GetAttribute('PetrifyId')
				})
			end, 6, true)
		end,
		pinata = function()
			notif('AutoKit', 'please note lucia now has a range check now.', 6, "warning")
			kitCollection(lplr.Name .. ':pinata', function(v)
				if getItem('candy') then
					bedwars.Client:Get('DepositCoins'):CallServer(v)
				end
			end, 6, true)
		end,
		spirit_assassin = function()
			kitCollection('EvelynnSoul', function(v)
				bedwars.SpiritAssassinController:useSpirit(lplr, v)
			end, 120, true)
		end,
		star_collector = function()
			kitCollection('stars', function(v)
				bedwars.StarCollectorController:collectEntity(lplr, v, v.Name)
			end, 20, false)
		end,
		summoner = function()
			repeat
				local plr = entitylib.EntityPosition({
					Range = Legit.Enabled and 21.4 or 31,
					Part = 'RootPart',
					Players = true,
					NPCs = true,
					Sort = sortmethods.Health,
					Wallcheck = Legit.Enabled
				})
				if plr then
					local localPosition = entitylib.character.RootPart.Position
					local shootDir = CFrame.lookAt(localPosition, plr.RootPart.Position).LookVector
					localPosition += shootDir * math.max((localPosition - plr.RootPart.Position).Magnitude - 16, 0)
                    local active = false
					if Legit.Enabled then
						for _, v in workspace:QueryDescendants('#Summoner_SummonCircle') do
							local pivot = v:FindFirstChild('Pivot')
							if pivot and math.floor(pivot.Position.X) == math.floor(entitylib.character.RootPart.Position.X) and math.floor(pivot.Position.Z) == math.floor(entitylib.character.RootPart.Position.Z) then
								active = true
								break
							end
						end
						if active then
							task.wait()
							continue
						end
						task.wait(lplr:GetNetworkPing())
						bedwars.SummonerClawController:clawAttack(lplr, localPosition, shootDir, store.hand.tool.Name or 'summoner_claw_1')
					end
					bedwars.Client:Get(remotes.SummonerClawAttack):SendToServer({
						position = localPosition,
						direction = shootDir,
						clientTime = workspace:GetServerTimeNow()
					})
				end
				task.wait(0.1)
			until not AutoKit.Enabled
		end,
		void_dragon = function()
			local oldflap = bedwars.VoidDragonController.flapWings
			local flapped
			bedwars.VoidDragonController.flapWings = function(self)
				if not flapped and bedwars.Client:Get(remotes.DragonFly):CallServer() then
					local modifier = bedwars.SprintController:getMovementStatusModifier():addModifier({
						blockSprint = true,
						constantSpeedMultiplier = 2
					})
					self.SpeedMaid:GiveTask(modifier)
					self.SpeedMaid:GiveTask(function()
						flapped = false
					end)
					flapped = true
				end
			end
			AutoKit:Clean(function()
				bedwars.VoidDragonController.flapWings = oldflap
			end)
			repeat
				if bedwars.VoidDragonController.inDragonForm then
					local plr = entitylib.EntityPosition({
						Range = Legit.Enabled and 12 or 21,
						Part = 'RootPart',
						Players = true,
						Wallcheck = Legit.Enabled
					})
					if plr then
						bedwars.Client:Get(remotes.DragonBreath):SendToServer({
							player = lplr,
							targetPoint = plr.RootPart.Position
						})
					end
				end
				task.wait(0.1)
			until not AutoKit.Enabled
		end,
		warlock = function()
			local lastTarget
			repeat
				if store.hand.tool and store.hand.tool.Name == 'warlock_staff' then
					local plr = entitylib.EntityPosition({
						Range = Legit.Enabled and 15 or 30,
						Part = 'RootPart',
						Players = true,
						NPCs = true,
						Wallcheck = Legit.Enabled
					})
					if plr and plr.Character ~= lastTarget then
						if not bedwars.Client:Get(remotes.WarlockTarget):CallServer({
							target = plr.Character
						}) then
							plr = nil
						end
					end
					lastTarget = plr and plr.Character
				else
					lastTarget = nil
				end
				task.wait(0.1)
			until not AutoKit.Enabled
		end,
		wizard = function()
			repeat
				local ability = lplr:GetAttribute('WizardAbility')
				if ability and bedwars.AbilityController:canUseAbility(ability) then
					local plr = entitylib.EntityPosition({
						Range = 50,
						Part = 'RootPart',
						Players = true,
						Sort = sortmethods.Health,
						Wallcheck = Legit.Enabled
					})
					if plr then
						bedwars.AbilityController:useAbility(ability, newproxy(true), {
							target = plr.RootPart.Position
						})
					end
				end
				task.wait(0.1)
			until not AutoKit.Enabled
		end
	}
	AutoKit = vape.Categories.Kits:CreateModule({
		Name = 'Auto Kit',
		Function = function(callback)
			if callback then
				repeat
					task.wait()
				until store.equippedKit ~= '' and store.matchState ~= 0 or (not AutoKit.Enabled)
				if AutoKit.Enabled and AutoKitFunctions[store.equippedKit] then
					AutoKitFunctions[store.equippedKit]()
				end
			end
		end,
		Tooltip = 'Automatically uses kit abilities.'
	})
	Legit = AutoKit:CreateToggle({
		Name = 'Legit'
	})
end)

run(function()
	local KitESP
	local Background
	local Color = {}
	local Reference = {}
	local Folder = Instance.new('Folder')
	Folder.Parent = vape.gui
	local ESPKits = {
		alchemist = {
			'alchemist_ingedients',
			'wild_flower'
		},
		beekeeper = {
			'bee',
			'bee'
		},
		bigman = {
			'treeOrb',
			'natures_essence_1'
		},
		ghost_catcher = {
			'ghost',
			'ghost_orb'
		},
		metal_detector = {
			'hidden-metal',
			'iron'
		},
		sheep_herder = {
			'SheepModel',
			'purple_hay_bale'
		},
		sorcerer = {
			'alchemy_crystal',
			'wild_flower'
		},
		star_collector = {
			'stars',
			'crit_star'
		}
	}
	local function Added(v, icon)
		local billboard = Instance.new('BillboardGui')
		billboard.Parent = Folder
		billboard.Name = icon
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
		billboard.Size = UDim2.fromOffset(36, 36)
		billboard.AlwaysOnTop = true
		billboard.ClipsDescendants = false
		billboard.Adornee = v
		local blur = addBlur(billboard)
		blur.Visible = Background.Enabled
		local image = Instance.new('ImageLabel')
		image.Size = UDim2.fromOffset(36, 36)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.BackgroundColor3 = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
		image.BackgroundTransparency = 1 - (Background.Enabled and Color.Opacity or 0)
		image.BorderSizePixel = 0
		image.Image = bedwars.getIcon({
			itemType = icon
		}, true)
		image.Parent = billboard
		local uicorner = Instance.new('UICorner')
		uicorner.CornerRadius = UDim.new(0, 4)
		uicorner.Parent = image
		Reference[v] = billboard
	end
	local function addKit(tag, icon)
		KitESP:Clean(collectionService:GetInstanceAddedSignal(tag):Connect(function(v)
			Added(v.PrimaryPart, icon)
		end))
		KitESP:Clean(collectionService:GetInstanceRemovedSignal(tag):Connect(function(v)
			if Reference[v.PrimaryPart] then
				Reference[v.PrimaryPart]:Destroy()
				Reference[v.PrimaryPart] = nil
			end
		end))
		for _, v in collectionService:GetTagged(tag) do
			Added(v.PrimaryPart, icon)
		end
	end
	KitESP = vape.Categories.Kits:CreateModule({
		Name = 'Kit ESP',
		Function = function(callback)
			if callback then
				repeat
					task.wait()
				until store.equippedKit ~= '' or (not KitESP.Enabled)
				local kit = KitESP.Enabled and ESPKits[store.equippedKit] or nil
				if kit then
					addKit(kit[1], kit[2])
				end
			else
				Folder:ClearAllChildren()
				table.clear(Reference)
			end
		end,
		Tooltip = 'ESP for certain kit related objects'
	})
	Background = KitESP:CreateToggle({
		Name = 'Background',
		Function = function(callback)
			if Color.Object then
				Color.Object.Visible = callback
			end
			for _, v in Reference do
				v.ImageLabel.BackgroundTransparency = 1 - (callback and Color.Opacity or 0)
				v.Blur.Visible = callback
			end
		end,
		Default = true
	})
	Color = KitESP:CreateColorSlider({
		Name = 'Background Color',
		DefaultValue = 0,
		DefaultOpacity = 0.5,
		Function = function(hue, sat, val, opacity)
			for _, v in Reference do
				v.ImageLabel.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
				v.ImageLabel.BackgroundTransparency = 1 - opacity
			end
		end,
		Darker = true
	})
end)

run(function()
	local AutoDavey
	local AutoBreak
	local AutoJump
	local AutoSwitch

	local old = nil

	AutoDavey = vape.Categories.Kits:CreateModule({
		Name = 'Auto Davey',
		Tooltip = 'Automatically breaks cannon/jump on launch',
		Function = function(callback)
			if callback then
				old = clonefunction(bedwars.CannonHandController.launchSelf)
				hookfunction(bedwars.CannonHandController.launchSelf, function(...)
					local res = {old(...)}
					local cannon = select(2, ...)
					local yes = false
					if AutoBreak.Enabled then
						if (cannon.Position - entitylib.character.RootPart.Position).Magnitude <= 30 then
							task.delay(0.05, function()
								for i = 1, 2 do
									task.spawn(bedwars.breakBlock, cannon, false, nil, true, nil, AutoSwitch.Enabled or false)
								end
							end)
						end
					end

					if AutoJump.Enabled then
						lplr.Character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
					end

					return unpack(res)
				end)
			else
				local suc, res = pcall(function()
					restorefunction(bedwars.CannonHandController.launchSelf)
				end)
				if not suc then
					bedwars.CannonHandController.launchSelf = old
				end
				old = nil
			end
		end
	})

    AutoJump = AutoDavey:CreateToggle({Name = 'Jump on impact'})
    AutoBreak = AutoDavey:CreateToggle({Name = 'Break on impact'})
    AutoSwitch = AutoDavey:CreateToggle({Name = 'Legit switch'})
end)

run(function()
	local AutoGingerbread
	local Range
	local Delay
	local AutoBreak
	local AutoJump
	local Switch
	local OnlyMines
	local SuccessfullyO
	local AutoPlace
	local PlaceMode
	local PlaceLegit
	local AutoSwitch

	local old
	local launched = false

	local function isFirstPerson()
		if not (lplr.Character and lplr.Character:FindFirstChild("Head")) then
			return false
		end
		return (lplr.Character.Head.Position - gameCamera.CFrame.Position).Magnitude < 2
	end


	local function canUseGumdrop(block)
		if not entitylib.isAlive then return false end
		if typeof(block) ~= 'Instance' then return false end
		if not block:IsA('BasePart') then return false end
		if store.equippedKit ~= 'gingerbread_man' then return false end
		if OnlyMines.Enabled and block:GetAttribute('PlacedByUserId') ~= lplr.UserId then return false end

		return (block.Position - entitylib.character.RootPart.Position).Magnitude <= Range.Value
	end

	AutoGingerbread = vape.Categories.Kits:CreateModule({
		Name = 'Auto Gingerbread Man',
		Tooltip = 'Automatically handles Gingerbread Man launch pads.',
		Function = function(callback)
			if callback then
				old = clonefunction(bedwars.LaunchPadController.attemptLaunch)
				hookfunction(bedwars.LaunchPadController.attemptLaunch, function(...)
					local res = {old(...)}
					local controller, block = ...
					local lastLaunch = controller and controller.lastLaunch or 0

					if not SuccessfullyO.Enabled or (controller and controller.lastLaunch and (controller.lastLaunch ~= lastLaunch or workspace:GetServerTimeNow() - controller.lastLaunch < 0.5)) then
						if AutoBreak.Enabled and canUseGumdrop(block) then
							task.delay(Delay.Value, bedwars.breakBlock, block, false, nil, true, nil, AutoSwitch.Enabled)
						end
						if AutoJump.Enabled and entitylib.isAlive then
							lplr.Character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
						end
						launched = true
						return unpack(res)
					end
				end)
				AutoGingerbread:Clean(lplr.Character.Humanoid.StateChanged:Connect(function(old, new)
					if new == Enum.HumanoidStateType.Landed and AutoPlace.Enabled then
						task.delay(Delay.Value + lplr:GetNetworkPing() + 0.05, function()
							if not launched then return end
							launched = false
							if PlaceMode.Value == 'First Person' and isFirstPerson() then
								task.spawn(function()
									if PlaceLegit.Enabled then
										local slot = getItemSlot('gumdrop_bounce_pad')
										if not hotbarSwitch(slot) or not store.hand.tool.Name:find('gumdrop_bounce_pad') then return end
									end
								end)
								local pos = entitylib.character.RootPart.Position
								pos = pos - Vector3.new(0, (entitylib.character.HipHeight + (entitylib.character.RootPart.Size.Y / 2)) - 3, 0)
								local rounded = Vector3.new(math.round(pos.X / 3) * 3, math.round(pos.Y / 3) * 3, math.round(pos.Z / 3) * 3)
								task.spawn(bedwars.placeBlock, rounded,'gumdrop_bounce_pad', false)
							elseif PlaceMode.Value == 'Third Person' and not isFirstPerson() then
								task.spawn(function()
									if PlaceLegit.Enabled then
										local slot = getItemSlot('gumdrop_bounce_pad')
										if not hotbarSwitch(slot) or not store.hand.tool.Name:find('gumdrop_bounce_pad') then return end
									end
								end)
								local pos = entitylib.character.RootPart.Position
								pos = pos - Vector3.new(0, (entitylib.character.HipHeight + (entitylib.character.RootPart.Size.Y / 2)) - 3, 0)
								local rounded = Vector3.new(math.round(pos.X / 3) * 3, math.round(pos.Y / 3) * 3, math.round(pos.Z / 3) * 3)
								task.spawn(bedwars.placeBlock, rounded,'gumdrop_bounce_pad', false)
							elseif PlaceMode.Value == 'Both' then
								task.spawn(function()
									if PlaceLegit.Enabled then
										local slot = getItemSlot('gumdrop_bounce_pad')
										if not hotbarSwitch(slot) or not store.hand.tool.Name:find('gumdrop_bounce_pad') then return end
									end
								end)
								local pos = entitylib.character.RootPart.Position
								pos = pos - Vector3.new(0, (entitylib.character.HipHeight + (entitylib.character.RootPart.Size.Y / 2)) - 3, 0)
								local rounded = Vector3.new(math.round(pos.X / 3) * 3, math.round(pos.Y / 3) * 3, math.round(pos.Z / 3) * 3)
								task.spawn(bedwars.placeBlock, rounded,'gumdrop_bounce_pad', false)
							end
						end)
					end
				end))
			else
				local suc, res = pcall(function()
					restorefunction(bedwars.LaunchPadController.attemptLaunch)
				end)
				if not suc then
					bedwars.LaunchPadController.attemptLaunch = old
				end
				old = nil
			end
		end
	})
   	AutoBreak = AutoGingerbread:CreateToggle({
    	Name = 'Break launch pad',
    	Default = true,
    	Function = function(call)
    		pcall(function()
    			Range.Object.Visible = call
    			Delay.Object.Visible = call
    			AutoSwitch.Object.Visible = call
    			OnlyMines.Object.Visible = call
    		end)
    	end
    })
    AutoJump = AutoGingerbread:CreateToggle({Name = 'Jump after launch', Visible = AutoBreak.Enabled})
    AutoSwitch = AutoGingerbread:CreateToggle({
    	Name = 'Legit switch',
    	Darker = true,
		Visible = AutoBreak.Enabled
    })
    OnlyMines = AutoGingerbread:CreateToggle({
    	Name = 'Own pads only',
    	Default = true,
    	Darker = true, 
		Visible = AutoBreak.Enabled
    })
	AutoPlace = AutoGingerbread:CreateToggle({
    	Name = 'Auto Place',
    	Default = false,
    	Function = function(call)
    		pcall(function()
    			PlaceMode.Object.Visible = call
				PlaceLegit.Object.Visible = call
    		end)
    	end
    })
	PlaceMode = AutoGingerbread:CreateDropdown({
		Name = 'Place Mode',
		List = {'First Person', 'Third Person', 'Both'},
		Default = 'First Person',
		Visible = AutoPlace.Enabled,		
		Darker = true,
	})
	PlaceLegit = AutoGingerbread:CreateToggle({
		Name = 'Switch to Gumdrop',
		Tooltip = 'Switches to gumdrop to place',
		Default = false,
		Darker = true,
		Visible = AutoPlace.Enabled
	})

    SuccessfullyO = AutoGingerbread:CreateToggle({
    	Name = 'Successful launch only',
    	Default = true
    })
    Range = AutoGingerbread:CreateSlider({
    	Name = 'Range',
    	Min = 1,
    	Max = 30,
    	Default = 30,
    	Darker = true,
		Visible = AutoBreak.Enabled,
    	Suffix = function(val)
    		return val <= 1 and 'stud' or 'studs'
    	end
    })
    Delay = AutoGingerbread:CreateSlider({
    	Name = 'Break delay',
    	Min = 0,
    	Max = 1,
    	Default = 0.05,
    	Decimal = 100,
    	Darker = true,
		Visible = AutoBreak.Enabled,
    	Suffix = function(val)
    		return val == 1 and 'sec' or 'secs'
    	end
    })
end)

run(function()
	local AutoWhisper
	local AutoHeal
	local HP
	local AutoFly
	local YLevel
	local UpdateRate

	local lowestpoint = math.huge

	AutoWhisper = vape.Categories.Kits:CreateModule({
		Name = 'Auto Whisper',
		Tooltip = 'Automatically uses whisper abilities',
		Function = function(callback)
			if callback then
				lowestpoint = math.huge
				repeat task.wait() until store.matchState ~= 0 or not AutoWhisper.Enabled
				for _, block in store.blocks do
					local p = (block.Position.Y - (block.Size.Y / 2)) - 50
					if p < lowestpoint then
						lowest = p
					end
				end
				repeat
					local liftR = AutoFly.Enabled and (workspace:GetServerTimeNow() - lplr:GetAttribute('OwlLiftReadyTime') or 0) > 0
					local healR = AutoHeal.Enabled and (workspace:GetServerTimeNow() - lplr:GetAttribute('OwlHealReadyTime') or 0) > 0
					
					if liftR or healR then
						for _, owls in collectionService:GetTagged('Owl') do
							if v:GetAttribute('Owner') == lplr.UserId then
								local plr = playersService:GetPlayerByUserId(owls:GetAttribute('Target'))
								if plr then
									if liftR and plr.Character.HumanoidRootPart.Velocity <= -10 then
										if plr.Character.HumanoidRootPart.Position.Y < lowestpoint then
											if bedwars.AbilityController:canUseAbility('OWL_LIFT') then
												bedwars.AbilityController:useAbility('OWL_LIFT')
											end
										end
									end
									if healR and (HP.Value >= 100 or (plr.Character:GetAttribute('Health') / plr.Character:GetAttribute('MaxHealth')) <= (HP.Value / 100)) then
										if bedwars.AbilityController:canUseAbility('OWL_HEAL') then
											bedwars.AbilityController:useAbility('OWL_HEAL')
										end
									end
								end
							end
						end
					end
					task.wait((1/UpdateRate.Value))					
				until not AutoWhisper.Enabled
			else
				lowestpoint = math.huge
			end
		end
	})
	AutoHeal = AutoWhisper:CreateToggle({
		Name = 'Auto Heal',
		Tooltip = 'Automatically will heal people under the thresold',
		Default = true,
		Function = function(callback)
			if HP then HP.Object.Visible = callback end
		end
	})
	HP = AutoWhisper:CreateSlider({
		Name = 'Health',
		Min = 0,
		Max = 99,
		Default = 99,
		Decimal = 100,
		Darker = true,
		Visible = AutoHeal.Enabled
	})
	AutoFly = AutoWhisper:CreateToggle({
		Name = 'Auto Fly',
		Tooltip = 'Automatically will fly people under the the YLevel',
		Default = true,
		Function = function(callback)
			if YLevel then YLevel.Object.Visible = callback end
		end
	})
	YLevel = AutoWhisper:CreateSlider({
		Name = 'Y-Level',
		Min = 0,
		Max = 100,
		Default = 100,
		Decimal = 10,
		Darker = true,
		Visible = AutoFly.Enabled
	})
	UpdateRate = AutoWhisper:CreateSlider({
		Name = 'Update Rate',
		Min = 0,
		Max = 120,
		Default = 60,
	})
end)

run(function()
	local OwlAura
	local Targets
	local Range
	local Delay
	local UpdateRate

	local function projMeta()
		local meta = bedwars.ProjectileMeta.owl_projectile
		if meta then
			return meta
		end
		return {}
	end

	OwlAura = vape.Categories.Kits:CreateModule({
		Name = 'Owl Aura',
		Function = function(callback)
			if callback then
				repeat task.wait() until store.matchState ~= 0 or not OwlAura.Enabled
				local owls = collection('Owl', OwlAura, function(self, obj)
					task.delay(lplr:GetNetworkPing() + 1.05, function()
						if obj and obj.Parent and obj:GetAttribute('Owner') == lplr.UserId then
							table.insert(self, obj)
						end
					end)
				end)
				repeat
					if entitylib.isAlive then
						local myOwl = owls[1]
						if myOwl then
							local og = myOwl.Part.Position
							local ent = entitylib.EntityPosition({
								Origin = og,
								Range = Range.Value,
								Part = 'RootPart',
								Players = Targets.Players.Enabled,
								NPCs = Targets.NPCs.Enabled,
								Wallcheck = Targets.Wallcheck.Enabled,
								Sort = sortmethods.Angle
							})
							if ent then
								local meta = projMeta()
								local calc = prediction.SolveTrajectory(og, meta.launchVelocity, meta.gravitationalAcceleration, plr.RootPart.Position, plr.RootPart.Velocity, workspace.Gravity, plr.HipHeight, plr.Jumping and 42.6 or nil)
								local dir = CFrame.lookAt(og, calc and calc or Vector3.zero).LookVector * meta.launchVelocity
								task.wait(Delay.Value - lplr:GetNetworkPing())
								bedwars.Client:Get('OwlAimming'):SendToServer({
									owl = myOwl.Part,
									starting = true
								})
								bedwars.Client:Get('OwlFireProjectile'):SendToServer({
									ProjectileRefId = httpService:GenerateGUID(false),
									direction = dir,
									fromPosition = og,
									initialVelocity = dir,
								})
								task.wait(lplr:GetNetworkPing())
								bedwars.Client:Get('OwlAimming'):SendToServer({
									owl = myOwl.Part,
									starting = false
								})
							end
						end
					end
					task.wait(1/UpdateRate.Value)
				until not OwlAura.Enabled
			else
				bedwars.Client:Get('OwlAimming'):SendToServer({
					owl = myOwl.Part,
					starting = false
				})
			end
		end,
		Tooltip = 'Automatically shoots your bird with the whisper kit'
	})
	Targets = OwlAura:CreateTargets({Players = true})
	Range = OwlAura:CreateSlider({
		Name = 'Range',
		Min = 0,
		Max = 75,
		Default = 30,
		Suffix = function(val)
			return val <= 0 and 'stud' or 'studs'
		end,
	})
	Delay = OwlAura:CreateSlider({
		Name = 'Delay',
		Min = 0,
		Max = 2,
		Default = 0.1,
		Decimal = 100,
		Suffix = 's'
	})
	UpdateRate = OwlAura:CreateSlider({
		Name = 'Update Rate',
		Min = 0,
		Max = 120,
		Default = 60,
	})
end)

run(function()
	local InfiniteVulcan
	InfiniteVulcan = vape.Categories.Kits:CreateModule({
		Name = 'Infinite Vulcan',
		Tooltip = 'When you hold you can spam a million bullets',
		Function = function(callback)
			repeat task.wait() until store.matchState ~= 0 or not InfiniteVulcan.Enabled
			if callback then
				vape:CreateNotification('Infinite Vulcan', 'Vulcan is now uncapped!', 8)
				InfiniteVulcan:Clean(runService.RenderStepped:Connect(function()
					bedwars.TurretCameraController.nextSendAim = -1
					bedwars.AutoTurretController.lastShotTime = 0
					bedwars.CameraTurretFireController.nextAllowedShot = -1
				end))
			else
				vape:CreateNotification('Infinite Vulcan', 'Vulcan is now back to normal.', 6)
				bedwars.TurretCameraController.nextSendAim = -1
				bedwars.AutoTurretController.lastShotTime = 0
				bedwars.CameraTurretFireController.nextAllowedShot = -1
			end
		end
	})
end)

run(function()
	local InfiniteKrystal
	local old
	InfiniteKrystal = vape.Categories.Kits:CreateModule({
		Name = 'Infinite Krystal',
		Tooltip = 'Gives you max momentum forever',
		Function = function(callback)
			repeat task.wait() until store.matchState ~= 0 or not InfiniteKrystal.Enabled
			if callback then
				old = clonefunction(bedwars.GlacialSkaterController.updateMomentum)
				InfiniteKrystal:Clean(runService.RenderStepped:Connect(function()
					bedwars.GlacialSkaterController.momentum = 100
					bedwars.GlacialSkaterController.lastMomentumReport = 100
					bedwars.GlacialSkaterController:updateMomentum(100,'newValue')
				end))
				hookfunction(bedwars.GlacialSkaterController.updateMomentum, function(self, ...)
					self.momentum = 100
					self.lastMomentumReport = 100
					local res = {old(self, ...)}
					return unpack(res)
				end)
			else
				local suc, res = pcall(function()
					restorefunction(bedwars.GlacialSkaterController.updateMomentum)
				end)
				if not suc then
					bedwars.GlacialSkaterController.updateMomentum = old
				end
				old = nil
				bedwars.GlacialSkaterController:updateMomentum(0,'newValue')
			end
		end
	})
end)

run(function()
	local KrystalDisabler
	local old
	KrystalDisabler = vape.Categories.Kits:CreateModule({
		Name = 'Krystal Disabler',
		Tooltip = 'Disables the AntiCheat completely',
		Function = function(callback)
			repeat task.wait() until store.matchState ~= 0 or not KrystalDisabler.Enabled
			if callback then
				vape:CreateNotification('Krystal Disabler', 'Turning off this module may cause crash... still looking into why? cant find why tho js be careful', 20, 'warning')
				old = clonefunction(bedwars.GlacialSkaterController.updateMomentum)
				hookfunction(bedwars.GlacialSkaterController.updateMomentum, function(self, ...)
					self.momentum = 9e9
					self.lastMomentumReport = 9e9
					bedwars.Client:Get("MomentumUpdate"):SendToServer({
						momentumValue = 9e9
					})
				end)
				bedwars.GlacialSkaterController:updateMomentum()
			else
				local suc, res = pcall(function()
					restorefunction(bedwars.GlacialSkaterController.updateMomentum)
				end)
				if not suc then
					bedwars.GlacialSkaterController.updateMomentum = old
				end
				old = nil
			end
		end
	})
end)

run(function()
	local VulcanAimbot
	local Range
	local Targets
	local UpdateRate
 
	VulcanAimbot = vape.Categories.Kits:CreateModule({
		Name = 'Vulcan Aimbot',
		Tooltip = 'Aims the Turret for you',
		Function = function(callback)
			if callback then
				repeat
					local turret = bedwars.Store:getState().Game.selectedTurret
					if turret then
                        local origin = turret.Rotate.Position
                        local ent = entitylib.EntityMouse({
                            Range = Range.Value,
                            Origin = origin,
                            Wallcheck = Targets.Walls.Enabled or nil,
                            Part = 'RootPart',
                            Players = Targets.Players.Enabled,
                            NPCs = Targets.NPCs.Enabled,
							Sort = sortmethods.Distance
                        })
                        if ent then
                            local pos = prediction.SolveTrajectory(origin, 320, 10, ent.RootPart.Position, ent.RootPart.Velocity, workspace.Gravity, ent.HipHeight, nil, store.airRay)
                            if pos then
                                local delta = pos - origin
                                bedwars.TurretCameraController.angleX = math.atan2(-delta.X, -delta.Z)
                                bedwars.TurretCameraController.angleY = math.clamp(math.atan2(delta.Y, math.sqrt(delta.X^2 + delta.Z^2)), -0.8, 0.8)
								bedwars.Client:Get('AimTurret'):SendToServer({
									turretBlockPos = bedwars.BlockController:getBlockPosition(turret.Position),
									angleX = math.atan2(-delta.X, -delta.Z),
									angleY = math.clamp(math.atan2(delta.Y, math.sqrt(delta.X^2 + delta.Z^2)), -0.8, 0.8)
								})
							end
						end
					end
					task.wait(1/UpdateRate.Value)
				until not VulcanAimbot.Enabled
			end
		end
	})
	Targets = VulcanAimbot:CreateTargets({Players=true,Wallcheck=true})
	Range = VulcanAimbot:CreateSlider({
		Name = 'Range',
		Min = 0,
		Max = 75,
		Default = 25,
		Suffix = function(val)
			return val <= 0 and 'stud' or 'studs'
		end,
	})
	UpdateRate = VulcanAimbot:CreateSlider({
		Name = 'Update Rate',
		Min = 0,
		Max = 120,
		Default = 60,
	})
end)

run(function()
	local FishermanSpy
	local IgnoreTeammates

	local FishNames = {
		fish_iron = "Iron Fish",
		fish_diamond = "Diamond Fish",
		fish_emerald = "Emerald Fish",
		fish_special = "Special Fish",
		fish_gold = "Gold Fish",
	}	
	
	FishermanSpy = vape.Categories.Kits:CreateModule({
		Name = "Fisherman Spy",
		Tooltip = 'Notifies whenever a fisher has caught something',
		Function = function(callback)
			if callback then
				bedwars.Client:WaitFor('FishCaught'):andThen(function(rbx)
					FishermanSpy:Clean(rbx:Connect(function(tbl)
						local char = tbl.catchingPlayer.Character
						local fish = tbl.dropData.fishModel
						local plrName = char.Name
						local str = plrName:sub(1, 1):upper()..plrName:sub(2) or 'Roblox'
						local strfish = FishNames[tostring(fish)] or 'Nil Fish'
						if IgnoreTeammates.Enabled then
							local currentTeam = lplr.Team
							local currentplr = playersService:GetPlayerFromCharacter(char)
							if currentplr.Team == currentTeam then
								return
							end
						end
						notif("FishermanSpy",`{str} has caught an {strfish}`,12)
					end))
				end)
			end
		end
	})
	IgnoreTeammates = FishermanSpy:CreateToggle({Name='Ignore Teammates',Default=true})
end)
