-- ====================================================================================
-- ULTIMATE MM2 DECOMPILER & FULL STRUCTURE MAPPER (OPTIMIZED)
-- Tác giả: Antigravity AI Assistant
-- Chức năng:
--   1. Quét toàn diện cấu trúc game MM2: Workspace (Parts, Models), ReplicatedStorage,
--      PlayerGui, PlayerScripts, Backpack, ReplicatedFirst, Lighting,...
--   2. Thu thập Full Cấu Trúc (Parts, Remotes, Values, Scripts, Modules) & xuất ra
--      file sơ đồ tổng thể (MM2_Full_Structure_Tree.lua).
--   3. Dịch ngược (Decompile) toàn bộ ModuleScript, LocalScript & Script (nếu có thể)
--      với cơ chế Queue & Yield tự động chống Lag/Freeze/Crash game.
--   4. Quét bổ sung các module trong bộ nhớ (getloadedmodules / getscripts - kể cả Nil).
-- ====================================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterGui = game:GetService("StarterGui")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

print("====================================================================")
print("[MM2 DECOMPILER & STRUCTURE MAPPER] Khởi động quá trình quét...")
print("====================================================================")

-- Thư mục gốc trong workspace (được gom gọn vào copiler_game/MM2_Decompiled_Source)
local PARENT_FOLDER = "copiler_game"
local ROOT_FOLDER = PARENT_FOLDER .. "/MM2_Decompiled_Source"

if not makefolder or not writefile then
    error("[DECOMPILER] Executor của bạn không hỗ trợ hàm makefolder hoặc writefile!")
end

pcall(makefolder, PARENT_FOLDER)
pcall(makefolder, ROOT_FOLDER)

-- ====================================================================================
-- CẤU HÌNH VÀ TARGETS QUÉT
-- ====================================================================================
local SCAN_TARGETS = {
    { Name = "ReplicatedStorage",     Instance = ReplicatedStorage,               IncludeParts = true },
    { Name = "ReplicatedFirst",       Instance = ReplicatedFirst,                 IncludeParts = true },
    { Name = "PlayerGui",             Instance = LocalPlayer:WaitForChild("PlayerGui"), IncludeParts = true },
    { Name = "PlayerScripts",         Instance = LocalPlayer:WaitForChild("PlayerScripts"), IncludeParts = true },
    { Name = "Backpack_Weapons",      Instance = LocalPlayer:WaitForChild("Backpack"), IncludeParts = true },
    { Name = "StarterPlayerScripts",  Instance = StarterPlayer:WaitForChild("StarterPlayerScripts"), IncludeParts = true },
    { Name = "Workspace_Map_Parts",   Instance = Workspace,                       IncludeParts = true },
    { Name = "Lighting",              Instance = Lighting,                        IncludeParts = true },
}

-- Thêm Character nếu đang tồn tại
if LocalPlayer.Character then
    table.insert(SCAN_TARGETS, { Name = "LocalCharacter", Instance = LocalPlayer.Character, IncludeParts = true })
end

-- ====================================================================================
-- CÁC HÀM TIỆN ÍCH (UTILITIES)
-- ====================================================================================

-- Làm sạch tên file/folder an toàn trên Windows
local function sanitizeName(name)
    name = tostring(name or "Unnamed")
    name = name:gsub("[\\/:*?\"<>|]", "_")
    name = name:gsub("[\r\n\t]", " ")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then name = "Unnamed_Instance" end
    return name
end

-- Lấy tóm tắt thuộc tính quan trọng của đối tượng (dành cho Full Structure Tree)
local function getInstanceSummary(inst)
    local summary = {}
    
    -- Ghi nhận ClassName
    table.insert(summary, "Class: " .. inst.ClassName)
    
    -- Nếu là Part / MeshPart / Model
    if inst:IsA("BasePart") then
        local pos = inst.Position
        table.insert(summary, string.format("Pos:(%.1f, %.1f, %.1f)", pos.X, pos.Y, pos.Z))
        table.insert(summary, string.format("Size:(%.1f, %.1f, %.1f)", inst.Size.X, inst.Size.Y, inst.Size.Z))
        if inst.Transparency > 0 then
            table.insert(summary, string.format("Transparency:%.2f", inst.Transparency))
        end
    elseif inst:IsA("ValueBase") then
        local ok, val = pcall(function() return tostring(inst.Value) end)
        if ok then
            table.insert(summary, "Value: " .. val)
        end
    elseif inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst:IsA("BindableEvent") or inst:IsA("BindableFunction") then
        table.insert(summary, "[NETWORK EVENT/REMOTE]")
    end

    -- Lấy Attributes nếu có
    local okAttr, attrs = pcall(function() return inst:GetAttributes() end)
    if okAttr and attrs then
        for k, v in pairs(attrs) do
            table.insert(summary, string.format("@%s=%s", tostring(k), tostring(v)))
        end
    end

    return table.concat(summary, " | ")
end

-- ====================================================================================
-- BƯỚC 1: INDEXING TOÀN BỘ CẤU TRÚC GAME & THU THẬP SCRIPTS (NON-BLOCKING)
-- ====================================================================================

local structureLines = {
    "-- ========================================================================",
    "-- MM2 FULL GAME STRUCTURE MAP (Parts, Models, Remotes, Modules, Scripts)",
    "-- Generated by Antigravity Decompiler",
    "-- ========================================================================",
    ""
}

local decompileQueue = {}
local stats = {
    TotalInstances = 0,
    Parts = 0,
    Models = 0,
    Remotes = 0,
    Values = 0,
    ModuleScripts = 0,
    LocalScripts = 0,
    Scripts = 0,
    DecompileSuccess = 0,
    DecompileFailed = 0
}

local frameStartTime = os.clock()

local function yieldIfFrameBusy()
    -- Giữ game mượt (dưới 25ms mỗi frame)
    if os.clock() - frameStartTime > 0.025 then
        task.wait()
        frameStartTime = os.clock()
    end
end

local function scanInstanceTree(instance, currentFolderPath, depth, treePrefix)
    stats.TotalInstances = stats.TotalInstances + 1
    yieldIfFrameBusy()

    local className = instance.ClassName
    local safeName = sanitizeName(instance.Name)
    local itemPath = currentFolderPath .. "/" .. safeName

    -- Phân loại thống kê
    if instance:IsA("BasePart") then
        stats.Parts = stats.Parts + 1
    elseif instance:IsA("Model") then
        stats.Models = stats.Models + 1
    elseif instance:IsA("RemoteEvent") or instance:IsA("RemoteFunction") then
        stats.Remotes = stats.Remotes + 1
    elseif instance:IsA("ValueBase") then
        stats.Values = stats.Values + 1
    elseif instance:IsA("ModuleScript") then
        stats.ModuleScripts = stats.ModuleScripts + 1
    elseif instance:IsA("LocalScript") then
        stats.LocalScripts = stats.LocalScripts + 1
    elseif instance:IsA("Script") then
        stats.Scripts = stats.Scripts + 1
    end

    -- Ghi nhận vào sơ đồ cây Full Structure
    local summary = getInstanceSummary(instance)
    table.insert(structureLines, string.format("%s[%s] %s  (%s)", treePrefix, className, instance.Name, summary))

    -- Kiểm tra nếu là Script hoặc ModuleScript -> thêm vào danh sách Decompile
    local isScript = instance:IsA("LocalScript") or instance:IsA("ModuleScript") or instance:IsA("Script")
    if isScript then
        table.insert(decompileQueue, {
            Instance = instance,
            FilePath = itemPath .. ".lua",
            FullName = instance:GetFullName(),
            ClassName = className
        })
    end

    -- Tạo folder nếu instance này có con hoặc là Folder/Model quan trọng chứa Scripts/Remotes
    local children = instance:GetChildren()
    if #children > 0 then
        -- Chỉ tạo folder trong file system nếu nó là Script có con hoặc chứa Script/Remote bên trong
        -- Để tránh tạo quá nhiều thư mục trống không cần thiết cho hàng nghìn Part rỗng
        local shouldCreateDir = isScript or instance:IsA("Folder") or instance:IsA("Model") or instance:IsA("ScreenGui") or instance:IsA("Service")
        if shouldCreateDir then
            pcall(makefolder, itemPath)
        end

        for i, child in ipairs(children) do
            local isLast = (i == #children)
            local childPrefix = treePrefix .. (isLast and "└── " or "├── ")
            local nextPrefix = treePrefix .. (isLast and "    " or "│   ")
            
            scanInstanceTree(child, (shouldCreateDir and itemPath or currentFolderPath), depth + 1, nextPrefix)
        end
    end
end

-- ====================================================================================
-- THỰC THI QUÉT CẤU TRÚC THEO TARGETS
-- ====================================================================================
print("[BƯỚC 1/3] Đang lập bản đồ toàn bộ cấu trúc game (Parts, Modules, Remotes)...")

for _, target in ipairs(SCAN_TARGETS) do
    if target.Instance then
        local targetDir = ROOT_FOLDER .. "/" .. target.Name
        pcall(makefolder, targetDir)
        
        table.insert(structureLines, "\n========================================================================")
        table.insert(structureLines, "TARGET: " .. target.Name .. " (" .. target.Instance:GetFullName() .. ")")
        table.insert(structureLines, "========================================================================")
        
        print(string.format(" -> Đang quét phân vùng: %s...", target.Name))
        scanInstanceTree(target.Instance, targetDir, 0, "")
    end
end

-- Quét bổ sung các Loaded Modules / Nil Instances (nếu executor hỗ trợ getloadedmodules)
if getloadedmodules and type(getloadedmodules) == "function" then
    print(" -> Đang quét bổ sung ModuleScripts trong bộ nhớ (getloadedmodules)...")
    local nilDir = ROOT_FOLDER .. "/_Loaded_Modules_Memory"
    pcall(makefolder, nilDir)
    
    table.insert(structureLines, "\n========================================================================")
    table.insert(structureLines, "TARGET: _Loaded_Modules_Memory (getloadedmodules)")
    table.insert(structureLines, "========================================================================")

    local ok, loadedModules = pcall(getloadedmodules)
    if ok and type(loadedModules) == "table" then
        for i, mod in ipairs(loadedModules) do
            if mod and typeof(mod) == "Instance" and mod:IsA("ModuleScript") then
                -- Kiểm tra xem đã nằm trong decompileQueue chưa
                local alreadyQueued = false
                for _, item in ipairs(decompileQueue) do
                    if item.Instance == mod then
                        alreadyQueued = true
                        break
                    end
                end
                
                if not alreadyQueued then
                    stats.ModuleScripts = stats.ModuleScripts + 1
                    local safeModName = sanitizeName(mod.Name)
                    local parentName = (mod.Parent and sanitizeName(mod.Parent.Name)) or "NilParent"
                    local fullPath = string.format("%s/%s__%s.lua", nilDir, parentName, safeModName)
                    
                    table.insert(structureLines, string.format("├── [ModuleScript (Memory)] %s (Parent: %s)", mod.Name, tostring(mod.Parent)))
                    table.insert(decompileQueue, {
                        Instance = mod,
                        FilePath = fullPath,
                        FullName = mod:GetFullName(),
                        ClassName = "ModuleScript (LoadedMemory)"
                    })
                end
            end
        end
    end
end

-- ====================================================================================
-- BƯỚC 2: XUẤT SƠ ĐỒ CẤU TRÚC GAME RA FILE (MM2_Full_Structure_Tree.lua)
-- ====================================================================================
print("[BƯỚC 2/3] Đang ghi file bản đồ cấu trúc game...")
local structureFilePath = ROOT_FOLDER .. "/MM2_Full_Structure_Tree.lua"
local writeStructureSuccess, err = pcall(function()
    writefile(structureFilePath, table.concat(structureLines, "\n"))
end)

if writeStructureSuccess then
    print("[+] Đã lưu toàn bộ bản đồ cấu trúc game tại: workspace/" .. structureFilePath)
else
    print("[-] Lỗi ghi file sơ đồ cấu trúc: " .. tostring(err))
end

-- ====================================================================================
-- BƯỚC 3: DỊCH NGƯỢC (DECOMPILE) TOÀN BỘ SCRIPTS / MODULES THEO QUEUE
-- ====================================================================================
print(string.format("[BƯỚC 3/3] Bắt đầu dịch ngược %d Scripts/Modules...", #decompileQueue))

for idx, item in ipairs(decompileQueue) do
    yieldIfFrameBusy()

    local inst = item.Instance
    local header = {
        "-- =====================================================================",
        "-- DECOMPILED BY ANTIGRAVITY MM2 TOOL",
        "-- FullPath: " .. item.FullName,
        "-- ClassName: " .. item.ClassName,
        "-- Parent: " .. tostring(inst.Parent),
        "-- =====================================================================",
        ""
    }

    -- Ghi chú thêm các con / siblings xung quanh script để tiện phân tích
    local siblingsInfo = {}
    if inst.Parent then
        for _, sib in ipairs(inst.Parent:GetChildren()) do
            if sib ~= inst then
                table.insert(siblingsInfo, string.format("--   * [%s] %s", sib.ClassName, sib.Name))
            end
        end
    end
    if #siblingsInfo > 0 then
        table.insert(header, "-- [SURROUNDING SIBLINGS IN PARENT]:")
        for _, line in ipairs(siblingsInfo) do
            table.insert(header, line)
        end
        table.insert(header, "")
    end

    -- Thực hiện Decompile
    local sourceCode = nil
    if decompile then
        local success, result = pcall(function()
            return decompile(inst)
        end)
        if success and result and result ~= "" then
            sourceCode = result
        end
    end

    -- Nếu decompile không ra hoặc executor fallback
    if not sourceCode then
        -- Thử getscriptbytecode hoặc ghi chú dump
        sourceCode = "-- [WARNING] Decompile thất bại hoặc Script bị bảo vệ bởi Roblox/Executor.\n"
        local okByte, bc = pcall(function()
            return getscriptbytecode and getscriptbytecode(inst)
        end)
        if okByte and bc and #bc > 0 then
            sourceCode = sourceCode .. "-- [INFO] Script Bytecode size: " .. tostring(#bc) .. " bytes.\n"
        end
    else
        stats.DecompileSuccess = stats.DecompileSuccess + 1
    end

    if not sourceCode or sourceCode == "" then
        stats.DecompileFailed = stats.DecompileFailed + 1
    end

    local finalContent = table.concat(header, "\n") .. "\n" .. (sourceCode or "")
    pcall(function()
        writefile(item.FilePath, finalContent)
    end)

    -- Hiển thị tiến độ mỗi 50 scripts
    if idx % 50 == 0 or idx == #decompileQueue then
        print(string.format(" -> Tiến độ dịch ngược: %d / %d (%.1f%%)", idx, #decompileQueue, (idx / #decompileQueue) * 100))
    end
end

-- ====================================================================================
-- BƯỚC 4: TỰ ĐỘNG ĐỒNG BỘ DỮ LIỆU LÊN PYTHON AI ANALYZER SERVER (http://127.0.0.1:5000)
-- ====================================================================================
print("[BƯỚC 4] Đang gửi sơ đồ cấu trúc game tới Python AI Analyzer Server...")
local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request
if httpRequest then
    local structurePayload = table.concat(structureLines, "\n")
    local okSync, syncErr = pcall(function()
        httpRequest({
            Url = "http://127.0.0.1:5000/api/upload_structure",
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode({
                content = structurePayload
            })
        })
    end)
    if okSync then
        print("[+] Đã đồng bộ thành công cấu trúc game lên Web AI Analyzer (http://127.0.0.1:5000)!")
    else
        print("[-] Không thể gửi dữ liệu tới server (Server có đang chạy không?): " .. tostring(syncErr))
    end
else
    print("[!] Executor không hỗ trợ HTTP Request tự động. Bạn có thể kéo thả file MM2_Full_Structure_Tree.lua lên Web App.")
end

-- ====================================================================================
-- TỔNG KẾT HOÀN THÀNH
-- ====================================================================================
print("====================================================================")
print("[MM2 DECOMPILER & STRUCTURE MAPPER] HOÀN TẤT TRỌN VẸN!")
print(string.format("  + Tổng số đối tượng đã quét  : %d", stats.TotalInstances))
print(string.format("  + Parts / MeshParts          : %d", stats.Parts))
print(string.format("  + Models                     : %d", stats.Models))
print(string.format("  + RemoteEvents / Functions   : %d", stats.Remotes))
print(string.format("  + Values (String, Int, Bool) : %d", stats.Values))
print(string.format("  + ModuleScripts quét được    : %d", stats.ModuleScripts))
print(string.format("  + LocalScripts quét được     : %d", stats.LocalScripts))
print(string.format("  + Dịch ngược thành công      : %d scripts", stats.DecompileSuccess))
print(" -> Toàn bộ mã nguồn đã lưu tại : workspace/" .. ROOT_FOLDER)
print(" -> Bản đồ cấu trúc tổng thể  : workspace/" .. structureFilePath)
print(" -> Giao diện AI Phân Tích    : http://127.0.0.1:5000")
print("====================================================================")


