local tracks = {}
for i = 0, reaper.CountTracks(0) - 1 do
  local track = reaper.GetTrack(0, i)
  local _, name = reaper.GetTrackName(track)
  tracks[#tracks + 1] = {index = i, name = name}
end
return {track_count = reaper.CountTracks(0), tempo = reaper.Master_GetTempo(), tracks = tracks}
