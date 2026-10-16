--!strict
-- ==============================================================================
-- Steal An Anime Egg: Clean-Up Script (Old Shop & Coin System Removal)
-- Run this in Roblox Studio Command Bar (View -> Command Bar) to permanently
-- remove the old Shop GUI, obsolete remotes, and legacy coin trash in Edit Mode!
-- ==============================================================================

local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

print("----------------------------------------------------------------------")
print("[Clean-up] Removing old Shop GUI, Remotes, and Coin System...")
print("----------------------------------------------------------------------")

-- 1. Remove old ShopsGui from StarterGui
local shopsGui = StarterGui:FindFirstChild("ShopsGui")
if shopsGui then
	shopsGui:Destroy()
	print("[-] Removed StarterGui.ShopsGui")
else
	print("[=] StarterGui.ShopsGui already absent")
end

-- 2. Remove old ShopInteractionController from StarterPlayerScripts
local spScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
if spScripts then
	local controller = spScripts:FindFirstChild("ShopInteractionController")
	if controller then
		controller:Destroy()
		print("[-] Removed StarterPlayerScripts.ShopInteractionController")
	end
end

-- 3. Remove obsolete shop remotes from ReplicatedStorage
for _, name in ipairs({"BuySpeedUpgrade", "EquipTrail", "GetShopState", "ShopStateChanged"}) do
	local r = ReplicatedStorage:FindFirstChild(name)
	if r then
		r:Destroy()
		print("[-] Removed ReplicatedStorage." .. name)
	end
end

-- 4. Remove legacy coin trash from ServerStorage
local trash = ServerStorage:FindFirstChild("RoCodeTrash")
if trash then
	trash:Destroy()
	print("[-] Removed ServerStorage.RoCodeTrash")
end

print("----------------------------------------------------------------------")
print("[Clean-up] SUCCESS! Clean slate ready for new shop systems.")
print("Note: Physical kiosks Workspace.Spawn.Speed and Workspace.Spawn.Trails preserved.")
print("----------------------------------------------------------------------")
