-- Junky bootstrap - paste into the Roblox Studio command bar.
-- Fetches and runs the full installer over HTTP (no giant paste).
-- Requires: Game Settings -> Security -> Allow HTTP Requests = ON.
local HttpService = game:GetService("HttpService")
local URL = "https://raw.githubusercontent.com/mkl48/Junky/master/dist/install.luau"

local ok, body = pcall(function()
	return HttpService:GetAsync(URL)
end)
if not ok then
	warn("[Junky] HTTP fetch failed (enable Allow HTTP Requests in Game Settings): " .. tostring(body))
	return
end

if loadstring then
	local fn, err = loadstring(body)
	if fn then
		fn()
		return
	end
	warn("[Junky] loadstring failed, trying ModuleScript fallback: " .. tostring(err))
end

local m = Instance.new("ModuleScript")
m.Name = "JunkyInstaller"
m.Source = body
m.Parent = game:GetService("ReplicatedStorage")
local okr, err = pcall(require, m)
m:Destroy()
if not okr then
	warn("[Junky] install failed: " .. tostring(err))
end
