-- Static active-XML portability gate for the 3.3.5a parser.
-- This file is intentionally not listed in the addon TOC.

local addonRoot = assert(arg[1], "usage: lua StaticPortabilityCheck.lua <addon-root> [toc-file]")
local tocFile = arg[2] or "DialogueUI-Ascension.toc"

local function Fail(message)
    io.stderr:write("StaticPortabilityCheck: FAIL: "..message.."\n")
    os.exit(1)
end

local function ReadFile(path)
    local file, openError = io.open(path, "rb")
    if not file then
        Fail("cannot open "..path..": "..tostring(openError))
    end
    local content = file:read("*a")
    file:close()
    return content
end

local function Trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Normalize(path)
    path = path:gsub("/", "\\")
    local prefix = path:match("^%a:\\") or ""
    local body = prefix ~= "" and path:sub(#prefix + 1) or path
    local parts = {}
    for part in body:gmatch("[^\\]+") do
        if part == ".." then
            parts[#parts] = nil
        elseif part ~= "." and part ~= "" then
            parts[#parts + 1] = part
        end
    end
    return prefix..table.concat(parts, "\\")
end

local function Directory(path)
    return path:match("^(.*)\\[^\\]+$") or "."
end

local function IsAbsolute(path)
    return path:match("^%a:[\\/]") ~= nil
end

local function Join(base, path)
    if IsAbsolute(path) then
        return Normalize(path)
    end
    return Normalize(base.."\\"..path)
end

local forbiddenAttributes = {
    "mixin",
    "method",
    "relativeKey",
    "useParentLevel",
    "textureSubLevel",
}

local activeXML = {}
local activeXMLOrder = {}

local function AddXML(path)
    path = Normalize(path)
    local key = path:lower()
    if activeXML[key] then
        return
    end
    activeXML[key] = true
    activeXMLOrder[#activeXMLOrder + 1] = path

    local content = ReadFile(path)
    local withoutComments = content:gsub("<!%-%-.-%-%->", "")
    for includeFile in withoutComments:gmatch("<[Ii]nclude%s+[^>]-[Ff]ile%s*=%s*\"([^\"]+)\"[^>]*/?>") do
        AddXML(Join(Directory(path), includeFile))
    end
end

local tocPath = Join(addonRoot, tocFile)
for line in ReadFile(tocPath):gmatch("[^\r\n]+") do
    line = Trim(line)
    if line ~= "" and line:sub(1, 1) ~= "#" and line:lower():match("%.xml$") then
        AddXML(Join(addonRoot, line))
    end
end

if #activeXMLOrder == 0 then
    Fail("no active XML files were discovered from "..tocPath)
end

local violations = {}
for _, path in ipairs(activeXMLOrder) do
    local content = ReadFile(path):gsub("<!%-%-.-%-%->", "")
    local position = 1
    while true do
        local first, last, tag = content:find("(<[%a/][^>]*>)", position)
        if not first then
            break
        end
        for _, attribute in ipairs(forbiddenAttributes) do
            if tag:find("%s"..attribute.."%s*=", 1) then
                local prefix = content:sub(1, first)
                local _, lineNumber = prefix:gsub("\n", "\n")
                violations[#violations + 1] = path..":"..tostring(lineNumber + 1)..": "..attribute
            end
        end
        position = last + 1
    end
end

if #violations > 0 then
    local outputLimit = 30
    for index, violation in ipairs(violations) do
        if index > outputLimit then
            break
        end
        io.stderr:write(violation.."\n")
    end
    if #violations > outputLimit then
        io.stderr:write("...and "..tostring(#violations - outputLimit).." more\n")
    end
    Fail(tostring(#violations).." unsupported XML attribute(s) remain in active files")
end

print("StaticPortabilityCheck: PASS ("..tostring(#activeXMLOrder).." active XML files)")
