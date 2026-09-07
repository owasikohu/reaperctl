-- Traditional melody, C major, 8 bars. Run once to add a new track.
local phrases = {
  {{60,1},{62,1},{64,1},{65,1},{64,1},{62,1},{60,2}},
  {{64,1},{65,1},{67,1},{69,1},{67,1},{65,1},{64,2}},
  {{60,2},{60,2},{60,2},{60,2}},
  {{60,0.5},{60,0.5},{62,0.5},{62,0.5},{64,0.5},{64,0.5},
   {65,0.5},{65,0.5},{64,1},{62,1},{60,2}},
}
local index = reaper.CountTracks(0)
local result
reaper.Undo_BeginBlock()
local ok, err = xpcall(function()
  reaper.InsertTrackAtIndex(index, true)
  local track = assert(reaper.GetTrack(0, index))
  reaper.GetSetMediaTrackInfo_String(track, 'P_NAME', 'かえるの合唱', true)
  reaper.SetMediaTrackInfo_Value(track, 'D_VOL', 0.15)
  local fx = reaper.TrackFX_AddByName(track, 'ReaSynth (Cockos)', false, -1)
  assert(fx >= 0, 'ReaSynth unavailable; track was created without notes')
  local item = assert(reaper.CreateNewMIDIItemInProj(track, 0, 32, true))
  local take = assert(reaper.GetActiveTake(item))
  reaper.GetSetMediaItemTakeInfo_String(take, 'P_NAME', 'かえるの合唱 — C major', true)
  local beat, count = 0, 0
  for _, phrase in ipairs(phrases) do
    for _, note in ipairs(phrase) do
      local pitch, duration = note[1], note[2]
      local start_ppq = reaper.MIDI_GetPPQPosFromProjQN(take, beat)
      local end_ppq = reaper.MIDI_GetPPQPosFromProjQN(take, beat + duration * 0.85)
      assert(reaper.MIDI_InsertNote(take, false, false, start_ppq, end_ppq,
        0, pitch, 85, true))
      beat, count = beat + duration, count + 1
    end
  end
  reaper.MIDI_Sort(take)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  result = {track_index = index, name = 'かえるの合唱', notes = count,
    beats = beat, instrument = 'ReaSynth', start_seconds = 0,
    end_seconds = reaper.TimeMap2_QNToTime(0, beat)}
end, debug.traceback)
reaper.Undo_EndBlock('Agent: add frog song', -1)
if not ok then error(err) end
return result
