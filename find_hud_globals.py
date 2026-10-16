import re

with open("StatsHUDController.client.luau", "r", encoding="utf-8") as f:
    code = f.read()

services_used = set(re.findall(r'([A-Z][a-zA-Z0-9]+):(?:FindFirstChild|WaitForChild|GetChildren|GetDescendants|GetService|Connect|Clone)', code))
locals_declared = set(re.findall(r'local\s+([a-zA-Z0-9_]+)', code))

for s in services_used:
    if s not in locals_declared and s not in ["Instance", "Vector3", "CFrame", "Color3", "UDim2", "Enum", "task", "math", "string", "table", "pcall", "pairs", "ipairs", "tonumber", "tostring", "print", "warn", "error"]:
        print(f"UNDECLARED GLOBAL in StatsHUDController: {s}")
