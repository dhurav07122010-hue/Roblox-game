with open("GameplayConfig.luau", "r", encoding="utf-8") as f:
    config_code = f.read()

with open("PlayerData.server.luau", "r", encoding="utf-8") as f:
    playerdata_code = f.read()

with open("GameplayManager.server.luau", "r", encoding="utf-8") as f:
    gameplay_mgr_code = f.read()

with open("StatsHUDController.client.luau", "r", encoding="utf-8") as f:
    statshud_code = f.read()

apply_script = f'''--!strict
-- ==============================================================================
-- Steal An Anime Egg: Complete Gameplay Loop Setup Script
-- Run this in the Roblox Studio Command Bar (View -> Command Bar) to permanently
-- configure and install the entire gameplay loop in Edit Mode!
-- ==============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
local ServerStorage = game:GetService("ServerStorage")

print("----------------------------------------------------------------------")
print("[Steal An Anime Egg] Installing Complete Gameplay Loop...")
print("----------------------------------------------------------------------")

-- 1. Create or Update ReplicatedStorage.GameplayConfig (ModuleScript)
local gameplayConfig = ReplicatedStorage:FindFirstChild("GameplayConfig") :: ModuleScript?
if not gameplayConfig then
	gameplayConfig = Instance.new("ModuleScript")
	gameplayConfig.Name = "GameplayConfig"
	gameplayConfig.Parent = ReplicatedStorage
end
gameplayConfig.Source = [===[{config_code}]===]
print("[+] Configured ReplicatedStorage.GameplayConfig")

-- 2. Update ServerScriptService.PlayerData (Script)
local playerDataScript = ServerScriptService:FindFirstChild("PlayerData") :: Script?
if not playerDataScript then
	playerDataScript = Instance.new("Script")
	playerDataScript.Name = "PlayerData"
	playerDataScript.Parent = ServerScriptService
end
playerDataScript.Source = [===[{playerdata_code}]===]
print("[+] Configured ServerScriptService.PlayerData (Strength, Money, Pen Upgrade & Limits)")

-- 3. Create or Update ServerScriptService.GameplayManager (Script)
local gameplayManagerScript = ServerScriptService:FindFirstChild("GameplayManager") :: Script?
if not gameplayManagerScript then
	gameplayManagerScript = Instance.new("Script")
	gameplayManagerScript.Name = "GameplayManager"
	gameplayManagerScript.Parent = ServerScriptService
end
gameplayManagerScript.Source = [===[{gameplay_mgr_code}]===]
print("[+] Configured ServerScriptService.GameplayManager (Pens, Eggs, Dumbbells, Lee Income & Wandering)")

-- 4. Create or Update StarterPlayerScripts.StatsHUDController (LocalScript)
local statsHudScript = StarterPlayerScripts:FindFirstChild("StatsHUDController") :: LocalScript?
if not statsHudScript then
	statsHudScript = Instance.new("LocalScript")
	statsHudScript.Name = "StatsHUDController"
	statsHudScript.Parent = StarterPlayerScripts
end
statsHudScript.Source = [===[{statshud_code}]===]
print("[+] Configured StarterPlayerScripts.StatsHUDController (Bottom-Left Speed, Strength, Money HUD)")

-- 5. Clean up old ShopInteractionController if deprecated
local oldShopCtrl = StarterPlayerScripts:FindFirstChild("ShopInteractionController")
if oldShopCtrl and oldShopCtrl:IsA("LocalScript") then
	oldShopCtrl:Destroy()
	print("[-] Cleaned up deprecated ShopInteractionController")
end

-- 6. Clean up obsolete RoCodeTrash in ServerStorage
local trash = ServerStorage:FindFirstChild("RoCodeTrash")
if trash then
	trash:Destroy()
	print("[-] Removed obsolete ServerStorage.RoCodeTrash")
end

print("----------------------------------------------------------------------")
print("[Steal An Anime Egg] SUCCESS! Complete gameplay loop installed in Explorer.")
print("  - Pens 1..7: Automated assignment, egg platforms & 30-capacity grid.")
print("  - Dumbbells: Dumbel1, Dumbel2, Dumbel3 training interactions active.")
print("  - Eggs: Zone1 spawning & Night-transition reset.")
print("  - Hatching & Lee: Rock Lee hatched, non-colliding, wandering & 1,000 Money/sec.")
print("  - UI: Bottom-left live Speed, Strength, and Money counters active.")
print("----------------------------------------------------------------------")
'''

with open("ApplyGameplayLoop.luau", "w", encoding="utf-8") as f:
    f.write(apply_script)

print("ApplyGameplayLoop.luau generated successfully! Size:", len(apply_script), "bytes")
