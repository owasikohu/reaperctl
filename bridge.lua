-- Load once through REAPER's Actions > ReaScript > Load, then Run.
local _, script_path = reaper.get_action_context()
local directory = os.getenv('REAPER_AGENT_DIR')
  or (assert(script_path:match('^(.*[/\\])')) .. '.reaper-agent')
reaper.RecursiveCreateDirectory(directory, 0)

local function quote(s)
  assert(utf8.len(s), 'JSON strings must be UTF-8')
  return '"' .. s:gsub('[%z\1-\31\\"]', function(c)
    if c == '"' or c == '\\' then return '\\' .. c end
    return string.format('\\u%04x', c:byte())
  end) .. '"'
end

local function json(value, seen)
  local kind = type(value)
  if kind == 'nil' then return 'null' end
  if kind == 'boolean' then return tostring(value) end
  if kind == 'string' then return quote(value) end
  if kind == 'number' then
    assert(value == value and value ~= math.huge and value ~= -math.huge,
      'JSON cannot encode NaN or infinity')
    return tostring(value)
  end
  assert(kind == 'table', 'JSON cannot encode ' .. kind)
  seen = seen or {}
  assert(not seen[value], 'JSON cannot encode a cycle')
  seen[value] = true
  local count, array = 0, true
  for k in pairs(value) do
    count = count + 1
    if type(k) ~= 'number' or k < 1 or k % 1 ~= 0 then array = false end
  end
  local parts = {}
  if array and count > 0 then
    for i = 1, count do
      assert(value[i] ~= nil, 'JSON arrays must be contiguous')
      parts[i] = json(value[i], seen)
    end
  else
    for k, v in pairs(value) do
      assert(type(k) == 'string', 'JSON object keys must be strings')
      parts[#parts + 1] = quote(k) .. ':' .. json(v, seen)
    end
    table.sort(parts)
  end
  seen[value] = nil
  if array and count > 0 then return '[' .. table.concat(parts, ',') .. ']' end
  return '{' .. table.concat(parts, ',') .. '}'
end

local function publish(path, body)
  local file = assert(io.open(path .. '.tmp', 'wb'))
  local ok, err = file:write(body)
  local closed, close_err = file:close()
  assert(ok, err)
  assert(closed, close_err)
  assert(os.rename(path .. '.tmp', path))
end

local function execute(path)
  local file = assert(io.open(path, 'rb'))
  local source = file:read('*a')
  file:close()
  local expires = tonumber(source:match('^%-%- expires: (%d+)\n'))
  assert(expires, 'Invalid request header')
  assert(os.time() < expires, 'Request expired before execution')
  local api = setmetatable({}, {__index = reaper})
  local function synchronous_only()
    error('Requests must finish synchronously; defer/runloop/atexit are unsupported')
  end
  api.defer, api.runloop, api.atexit = synchronous_only, synchronous_only, synchronous_only
  local env = setmetatable({reaper = api}, {__index = _G})
  env._G = env
  local chunk, err = load(source, '@' .. path, 't', env)
  assert(chunk, err)
  local result = chunk()
  return json(result)
end

local function poll()
  -- Refresh REAPER's directory cache; process one request per UI callback.
  reaper.EnumerateFiles(directory, -1)
  local index = 0
  while true do
    local name = reaper.EnumerateFiles(directory, index)
    if not name then break end
    local id = name:match('^request%-([a-f0-9]+)%.lua$')
    if id and #id == 32 then
      local pending = directory .. '/' .. name
      local running = directory .. '/running-' .. id .. '.lua'
      if os.rename(pending, running) then
        local ok, result = xpcall(function() return execute(running) end, debug.traceback)
        local body = '{"id":' .. quote(id) .. ',"ok":' .. tostring(ok)
        if ok then body = body .. ',"result":' .. result
        else
          -- Lua errors may contain arbitrary bytes. Keep error JSON valid.
          if not utf8.len(result) then result = 'Lua error contained invalid UTF-8' end
          body = body .. ',"error":' .. quote(result)
        end
        publish(directory .. '/response-' .. id .. '.json', body .. '}')
        os.remove(running)
        break
      end
    end
    index = index + 1
  end
end

local function loop()
  local ok, err = xpcall(poll, debug.traceback)
  if not ok then
    reaper.ShowConsoleMsg('ReaScript bridge stopped: ' .. tostring(err) .. '\n')
    return
  end
  reaper.defer(loop)
end
loop()
