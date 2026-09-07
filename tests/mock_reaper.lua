-- Real Lua VM, fake host. Python supplies a directory snapshot per tick.
local bridge, directory = arg[1], assert(os.getenv('REAPER_AGENT_DIR'))
local files, callback, tracks = {}, nil, {}
reaper = {
  get_action_context = function() return false, bridge end,
  RecursiveCreateDirectory = function() end,
  EnumerateFiles = function(_, index) return files[index + 1] end,
  defer = function(fn) callback = fn end,
  ShowConsoleMsg = function(message) io.stderr:write(message) end,
  GetAppVersion = function() return 'MOCK-7' end,
  CountTracks = function() return #tracks end,
  Master_GetTempo = function() return 170 end,
  GetTrack = function(_, index) return tracks[index + 1] end,
  GetTrackName = function(track) return true, track.name end,
  InsertTrackAtIndex = function(index) table.insert(tracks, index + 1, {name = ''}) end,
  GetSetMediaTrackInfo_String = function(track, _, value)
    track.name = value
    return true, value
  end,
  Undo_BeginBlock = function() end,
  Undo_EndBlock = function() end,
  TrackList_AdjustWindows = function() end,
  UpdateArrange = function() end,
}
dofile(bridge)
for line in io.lines() do
  files = {}
  for file in line:gmatch('[^|]+') do files[#files + 1] = file end
  assert(callback, 'Bridge stopped')()
  io.write('tick\n')
  io.flush()
end
