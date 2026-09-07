-- 16-bar electronic sketch: 140 BPM, 4/4, A minor.
local project = 0
local bars, qn_per_bar = 16, 4
local song_qn = bars * qn_per_bar

local function add_note(take, qn, duration, pitch, velocity, channel)
  local start_ppq = reaper.MIDI_GetPPQPosFromProjQN(take, qn)
  local end_ppq = reaper.MIDI_GetPPQPosFromProjQN(take, qn + duration)
  assert(reaper.MIDI_InsertNote(take, false, false, start_ppq, end_ppq,
    channel or 0, pitch, velocity, true))
end

local function make_track(index, name, fx_name, volume)
  reaper.InsertTrackAtIndex(index, true)
  local track = assert(reaper.GetTrack(project, index))
  assert(reaper.GetSetMediaTrackInfo_String(track, 'P_NAME', name, true))
  reaper.SetMediaTrackInfo_Value(track, 'D_VOL', volume)
  local fx = reaper.TrackFX_AddByName(track, fx_name, false, -1)
  assert(fx >= 0, 'Could not add ' .. fx_name .. ' to ' .. name)
  local item = assert(reaper.CreateNewMIDIItemInProj(track, 0, song_qn, true))
  local take = assert(reaper.GetActiveTake(item))
  assert(reaper.GetSetMediaItemTakeInfo_String(take, 'P_NAME', name .. ' — 16 bars', true))
  return track, take, fx
end

local result
reaper.Undo_BeginBlock()
local ok, err = xpcall(function()
  -- Replace the current sketch so the requested project has exactly four tracks.
  for i = reaper.CountTracks(project) - 1, 0, -1 do
    reaper.DeleteTrack(reaper.GetTrack(project, i))
  end
  local _, marker_count, region_count = reaper.CountProjectMarkers(project)
  for i = marker_count + region_count - 1, 0, -1 do
    local _, is_region, _, _, _, index = reaper.EnumProjectMarkers3(project, i)
    reaper.DeleteProjectMarker(project, index, is_region)
  end

  reaper.SetTempoTimeSigMarker(project, -1, 0, -1, -1, 140, 4, 4, false)
  reaper.GetSetProjectInfo_String(project, 'PROJECT_TITLE', 'A Minor Circuit — 16 bars', true)
  reaper.AddProjectMarker2(project, true, 0,
    reaper.TimeMap2_QNToTime(project, 32), 'A — Pulse', -1, 0)
  reaper.AddProjectMarker2(project, true, reaper.TimeMap2_QNToTime(project, 32),
    reaper.TimeMap2_QNToTime(project, 64), 'B — Lift / Cadence', -1, 0)

  local drums_track, drums = make_track(0, 'Drums',
    'VSTi: SI-Drum Kit (Cakewalk)', 0.55)
  local bass_track, bass = make_track(1, 'Bass',
    'VSTi: SI-Bass Guitar (Cakewalk)', 0.42)
  local chords_track, chords = make_track(2, 'Chords',
    'VSTi: SI-Electric Piano (Cakewalk)', 0.34)
  local lead_track, lead = make_track(3, 'Lead',
    'VSTi: Vital (Vital Audio)', 0.22)

  -- GM drum pitches. Bars 1–8: restrained four-on-the-floor.
  for bar = 0, 7 do
    local q = bar * 4
    for beat = 0, 3 do
      add_note(drums, q + beat, 0.12, 36, beat == 0 and 108 or 96, 9)
      add_note(drums, q + beat + 0.5, 0.08, 42, 62, 9)
    end
    add_note(drums, q + 1, 0.12, 38, 105, 9)
    add_note(drums, q + 3, 0.12, 38, 108, 9)
    if bar == 7 then
      local toms = {41, 43, 45, 47}
      for step = 0, 3 do add_note(drums, q + 3 + step * 0.25, 0.08, toms[step+1], 78 + step * 8, 9) end
    end
  end

  -- Bars 9–16: open hats, syncopated kick and a denser snare pattern.
  for bar = 8, 15 do
    local q = bar * 4
    for beat = 0, 3 do
      add_note(drums, q + beat, 0.12, 36, 108, 9)
      add_note(drums, q + beat + 0.5, 0.16, 46, 70, 9)
    end
    add_note(drums, q + 0.75, 0.1, 36, 82, 9)
    add_note(drums, q + 1, 0.12, 38, 112, 9)
    add_note(drums, q + 2.5, 0.1, 36, 88, 9)
    add_note(drums, q + 3, 0.12, 38, 112, 9)
    if bar == 14 then
      local toms = {41, 43, 45, 47, 50, 47, 45, 43}
      for step = 0, 7 do add_note(drums, q + 2 + step * 0.25, 0.08, toms[step+1], 70 + step * 6, 9) end
    elseif bar == 15 then
      -- Final bar thins out and ends with one resolved downbeat gesture.
      -- Existing four-on-floor notes remain; omit extra fill.
    end
  end

  local progressions = {
    {45, 'Am'}, {41, 'F'}, {48, 'C'}, {43, 'G'},
    {45, 'Am'}, {41, 'F'}, {48, 'C'}, {43, 'G'},
    {45, 'Am'}, {43, 'G'}, {41, 'F'}, {40, 'E'},
    {45, 'Am'}, {43, 'G'}, {40, 'E'}, {45, 'Am'},
  }
  local voicings = {
    Am={57,60,64,67}, F={53,57,60,64}, C={55,60,64,67},
    G={55,59,62,67}, E={52,56,59,64},
  }
  for bar, chord in ipairs(progressions) do
    local q = (bar - 1) * 4
    local root, name = chord[1], chord[2]
    -- Bass changes from steady eighth-note pulses to an octave/syncopated figure.
    if bar <= 8 then
      for step = 0, 7 do add_note(bass, q + step * 0.5, 0.38, root, step == 0 and 100 or 78) end
    elseif bar < 15 then
      local rhythm = {{0,root},{0.75,root},{1.5,root+12},{2,root},{2.75,root+7},{3.5,root+12}}
      for i, event in ipairs(rhythm) do add_note(bass, q + event[1], 0.35, event[2], i == 1 and 105 or 86) end
    elseif bar == 15 then
      add_note(bass, q, 1.5, 40, 104); add_note(bass, q + 2, 1.5, 52, 92)
    else
      add_note(bass, q, 3.8, 45, 108)
    end
    -- Four-note chords; section B changes from sustained pads to rhythmic stabs.
    if bar <= 8 or bar >= 15 then
      local duration = bar == 16 and 3.8 or 3.6
      for _, pitch in ipairs(voicings[name]) do add_note(chords, q, duration, pitch, 68) end
    else
      for _, offset in ipairs({0, 1.5, 2.5}) do
        for _, pitch in ipairs(voicings[name]) do add_note(chords, q + offset, 0.65, pitch, 74) end
      end
    end
  end

  -- Lead: sparse answer in A, higher and busier variation in B, then E→A cadence.
  local melody = {
    {0,69,0.75},{1,72,0.75},{2,76,1.5},
    {4,69,0.75},{5,72,0.75},{6,77,1.5},
    {8,67,0.75},{9,72,0.75},{10,76,1.5},
    {12,67,0.75},{13,71,0.75},{14,74,1.5},
    {16,69,0.5},{16.75,72,0.5},{17.5,76,0.5},{18.25,81,1.25},
    {20,77,0.5},{20.75,76,0.5},{21.5,72,0.5},{22.25,69,1.25},
    {24,72,0.5},{24.75,76,0.5},{25.5,79,0.5},{26.25,76,1.25},
    {28,74,0.5},{28.75,71,0.5},{29.5,67,0.5},{30.25,71,1.25},
    {32,81,0.5},{32.75,79,0.5},{33.5,76,0.5},{34.25,72,0.5},{35,76,0.75},
    {36,79,0.5},{36.75,83,0.5},{37.5,79,0.5},{38.25,74,0.5},{39,71,0.75},
    {40,77,0.5},{40.75,81,0.5},{41.5,77,0.5},{42.25,72,0.5},{43,69,0.75},
    {44,68,0.5},{44.75,71,0.5},{45.5,76,0.5},{46.25,80,1.25},
    {48,81,0.75},{49,76,0.5},{49.75,72,0.5},{50.5,69,1.25},
    {52,79,0.75},{53,74,0.5},{53.75,71,0.5},{54.5,67,1.25},
    {56,68,0.75},{57,71,0.75},{58,76,1.5},
    {60,76,0.5},{60.75,72,0.5},{61.5,69,2.3},
  }
  for _, note in ipairs(melody) do add_note(lead, note[1], note[3], note[2], 82) end

  for _, take in ipairs({drums, bass, chords, lead}) do reaper.MIDI_Sort(take) end
  reaper.GetSet_LoopTimeRange(true, false, 0, reaper.TimeMap2_QNToTime(project, song_qn), false)
  reaper.SetEditCurPos(0, false, false)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  result = {title='A Minor Circuit', bpm=140, numerator=4, denominator=4,
    bars=16, length_seconds=reaper.TimeMap2_QNToTime(project, song_qn),
    tracks={'Drums','Bass','Chords','Lead'},
    instruments={drums='SI-Drum Kit', bass='SI-Bass Guitar',
      chords='SI-Electric Piano', lead='Vital'}}
end, debug.traceback)
reaper.Undo_EndBlock('Agent: create 16-bar electronic track', -1)
if not ok then error(err) end
return result
