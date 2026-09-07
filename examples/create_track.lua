local index = reaper.CountTracks(0)
reaper.Undo_BeginBlock()
local ok, err = xpcall(function()
  reaper.InsertTrackAtIndex(index, true)
  local track = assert(reaper.GetTrack(0, index), 'Track creation failed')
  assert(reaper.GetSetMediaTrackInfo_String(track, 'P_NAME', 'Agent Test', true))
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
end, debug.traceback)
reaper.Undo_EndBlock('Agent: create test track', -1)
if not ok then error(err) end
return {index = index, name = 'Agent Test', track_count = reaper.CountTracks(0)}
