--
-- lovebpm
--
-- Copyright (c) 2016 rxi
--
-- This library is free software; you can redistribute it and/or modify it
-- under the terms of the MIT license. See LICENSE for details.
--

local lovebpm = { _version = "0.0.0" }

local Track = {}
Track.__index = Track


function lovebpm.newTrack()
  local self = setmetatable({}, Track)
  self.source = nil
  self.offset = 0
  self.volume = 1
  self.pitch = 1
  self.looping = false
  self.listeners = {}
  self.period = 60 / 120
  self.lastBeat = nil
  self.lastUpdateTime = nil
  self.lastSourceTime = 0
  self.time = 0
  self.totalTime = 0
  self.dtMultiplier = 1
  return self
end


function lovebpm.detectBPM(filename, opts)
  -- Init options table
  opts = opts or {}
  local t = { minbpm = 75, maxbpm = 300 }
  for k, v in pairs(t) do
    t[k] = opts[k] or v
  end
  opts = t

  -- Load data
  local data = filename
  if type(data) == "string" then
    data = love.sound.newSoundData(data)
  else
    data = filename
  end
  local channels = data:getChannels()
  local samplerate = data:getSampleRate()

  -- Gets max amplitude over a number of samples at `n` seconds
  local function getAmplitude(n)
    local count = samplerate * channels / 200
    local at = n * channels * samplerate
    if at + count > data:getSampleCount() then
      return 0
    end
    local a = 0
    for i = 0, count - 1 do
      a = math.max(a, math.abs( data:getSample(at + i) ))
    end
    return a
  end

  -- Get track duration and init results table
  local dur = data:getDuration("seconds")
  local results = {}

  -- Get maximum allowed BPM
  local step = 8
  local n = (dur * opts.maxbpm / 60)
  n = math.floor(n / step) * step

  -- Fill table with BPMs and their average on-the-beat amplitude until the
  -- minimum allowed BPM is reached
  while true do
    local bpm = n / dur * 60
    if bpm < opts.minbpm then
      break
    end
    local acc = 0
    for i = 0, n - 1 do
      acc = acc + getAmplitude(dur / n * i)
    end
    -- Round BPM to 3 decimal places
    bpm = math.floor(bpm * 1000 + .5) / 1000
    -- Add result to table
    table.insert(results, { bpm = bpm, avg = acc / n })
    n = n - step
  end

  -- Sort table by greatest average on-the-beat amplitude. The one with the
  -- greatest average is assumed to be the correct bpm
  table.sort(results, function(a, b) return a.avg > b.avg end)
  return results[1].bpm
end


function Track:load(filename)
  -- Deinit old source
  self:stop()
  -- Init new source
  -- "static" mode is used here instead of "stream" as the time returned by
  -- :tell() seems to go out of sync after the first loop otherwise
  self.source = love.audio.newSource(filename, "static")
  self:setLooping(self.looping)
  self:setVolume(self.volume)
  self:setPitch(self.pitch)
  self.totalTime = self.source:getDuration("seconds")
  self:stop()
  return self
end


function Track:setBPM(n)
  self.period = 60 / n
  return self
end


function Track:setOffset(n)
  self.offset = n or 0
  return self
end


function Track:setVolume(volume)
  self.volume = volume or 1
  if self.source then
    self.source:setVolume(self.volume)
  end
  return self
end


function Track:setPitch(pitch)
  self.pitch = pitch or 1
  if self.source then
    self.source:setPitch(self.pitch)
  end
  return self
end


function Track:setLooping(loop)
  self.looping = loop
  if self.source then
    self.source:setLooping(self.looping)
  end
  return self
end


function Track:on(name, fn)
  self.listeners[name] = self.listeners[name] or {}
  table.insert(self.listeners[name], fn)
  return self
end


function Track:emit(name, ...)
  if self.listeners[name] then
    for i, fn in ipairs(self.listeners[name]) do
      fn(...)
    end
  end
  return self
end


function Track:play(restart)
  if not self.source then return self end
  if self.restart then
    self:stop()
  end
  self.source:play()
  return self
end


function Track:pause()
  if not self.source then return self end
  self.source:pause()
  return self
end


function Track:stop()
  self.lastBeat = nil
  self.time = 0
  self.lastUpdateTime = nil
  self.lastSourceTime = 0
  if self.source then
    self.source:stop()
  end
  return self
end


function Track:setTime(n)
  if not self.source then return end
  self.source:seek(n)
  self.time = n
  self.lastSourceTime = n
  self.lastBeat = self:getBeat() - 1
  return self
end


function Track:setBeat(n)
  return self:setTime(n * self.period)
end


function Track:getTotalTime()
  return self.totalTime
end


function Track:getTotalBeats()
  if not self.source then
    return 0
  end
  return math.floor(self:getTotalTime() / self.period + 0.5)
end


function Track:getTime()
  return self.time
end


function Track:getBeat(multiplier)
  multiplier = multiplier or 1
  local period = self.period * multiplier
  return math.floor(self.time / period), (self.time % period) / period
end


function Track:update()
  if not self.source then return self end

  -- Get delta time: getTime() is used for time-keeping as the value returned by
  -- :tell() is updated at a potentially lower rate than the framerate
  local t = love.timer.getTime()
  local dt = self.lastUpdateTime and (t - self.lastUpdateTime) or 0
  self.lastUpdateTime = t

  -- Set new time
  local time
  if self.source:isPlaying() then
    time = self.time + dt * self.dtMultiplier * self.pitch
  else
    time = self.time
  end

  -- Get source time and apply offset
  local sourceTime = self.source:tell("seconds")
  sourceTime = sourceTime + self.offset

  -- If the value returned by the :tell() function has updated we check to see
  -- if we are in sync within an allowed threshold -- if we're out of sync we
  -- adjust the dtMultiplier to resync gradually
  if sourceTime ~= self.lastSourceTime then
    local diff = time - sourceTime
    -- Check if the difference is beyond the threshold -- If the difference is
    -- too great we assume the track has looped and treat it as being within the
    -- threshold
    if math.abs(diff) > 0.01 and math.abs(diff) < self.totalTime / 2 then
      self.dtMultiplier = math.max(0, 1 - diff * 2)
    else
      self.dtMultiplier = 1
    end
    self.lastSourceTime = sourceTime
  end

  -- Assure time is within proper bounds in case the offset or added
  -- frame-delta-time made it overshoot
  time = time % self.totalTime

  -- Calculate deltatime and emit update event; set time
  if self.lastBeat then
    local t = time
    if t < self.time then
      t = t + self.totalTime
    end
    self:emit("update", t - self.time)
  else
    self:emit("update", 0)
  end
  self.time = time

  -- Current beat doesn't match last beat?
  local beat = self:getBeat()
  local last = self.lastBeat
  if beat ~= last then
    -- Last beat is set here as one of the event handlers can potentially set it
    -- by calling :setTime() or :setBeat()
    self.lastBeat = beat
    -- Assure that the `beat` event is done once for each beat, even in cases
    -- where more than one beat has passed since the last update, or the song
    -- has looped
    local total = self:getTotalBeats()
    local b = beat
    local x = 0
    if last then
      x = last + 1
      -- If the last beat is greater than the current beat then the song has
      -- reached the end: if we're looping then set the current beat to after
      -- the tracks's end so incrementing towards it still works.
      if x > b then
        if self.looping then
          self:emit("loop")
          b = b + total
        else
          self:emit("end")
          self:stop()
        end
      end
    end
    -- Emit beat event for each passed beat
    while x <= b do
      self:emit("beat", x % total)
      x = x + 1
    end
  end

  return self
end


return lovebpm
