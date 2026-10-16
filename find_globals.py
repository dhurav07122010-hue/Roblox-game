import re

with open("GameplayManager.server.luau", "r", encoding="utf-8") as f:
    code = f.read()

# Find all Service names used with : or .
services_used = set(re.findall(r'([A-Z][a-zA-Z0-9]+):(?:FindFirstChild|WaitForChild|GetChildren|GetDescendants|GetService|Connect|Clone)', code))
print("Service/instance patterns called with methods:", services_used)

# Find all local declarations
locals_declared = set(re.findall(r'local\s+([a-zA-Z0-9_]+)', code))
print("Locals declared:", len(locals_declared))

for s in services_used:
    if s not in locals_declared and s not in ["Instance", "Vector3", "CFrame", "Color3", "UDim2", "Enum", "task", "math", "string", "table", "pcall", "pairs", "ipairs", "tonumber", "tostring", "print", "warn", "error"]:
        print(f"UNDECLARED GLOBAL: {s}")
