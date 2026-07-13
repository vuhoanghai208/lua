-- Standalone Device Auto-Select Button Tester
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

print("--- [DEVICE TESTER] Starting Device Button Click Scan ---")

local foundCount = 0

for _, obj in ipairs(PlayerGui:GetDescendants()) do
    if obj:IsA("GuiButton") and (obj.Name == "Tablet" or obj.Name == "Phone" or obj.Name == "Desktop") then
        print(string.format("[FOUND] Name: %s | Path: %s | Visible: %s | Active: %s", 
            obj.Name, 
            obj:GetFullName(), 
            tostring(obj.Visible), 
            tostring(obj.Active)
        ))
        
        foundCount = foundCount + 1
        
        -- Click button
        print("[TEST CLICK] Attempting to click: " .. obj.Name)
        pcall(function()
            if firesignal then
                firesignal(obj.MouseButton1Click)
                firesignal(obj.Activated)
                print("[SUCCESS] Fired events via firesignal!")
            else
                local clicked = false
                local events = {"MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "Activated"}
                for _, evName in ipairs(events) do
                    local conn = obj[evName]
                    if conn then
                        for _, signal in ipairs(getconnections(conn)) do
                            signal:Fire()
                            clicked = true
                        end
                    end
                end
                if clicked then
                    print("[SUCCESS] Fired events via getconnections!")
                else
                    print("[WARN] No connections or firesignal found.")
                end
            end
        end)
    end
end

if foundCount == 0 then
    print("[WARN] No Tablet/Phone/Desktop buttons found in PlayerGui. Make sure the selection GUI is open.")
else
    print("[DEVICE TESTER] Finished scanning. Found " .. foundCount .. " buttons.")
end
