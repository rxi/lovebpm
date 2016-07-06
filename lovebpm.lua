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
  self.lastSourceTime = 0
  self.time = 0
  self.totalTime = 0
  return self
end


function lovebpm.detectBpm(filename, opts)
  -- Init options table
  local default = { minbpm = 75, maxbpm = 300 }
  opts = opts or {}
  for k, v in pairs(default) do
    opts[k] = opts[k] or v
  end

  -- Load data
  local data = filename
  if type(data) == "string" then
    data = love.sound.newSoundData(data)
  else
    data = filename
  end
  local channels = data:getChannels()
  local samplerate = data:getSampleRate()
  data:getSample( data:getSampleCount() * 2 - 1)

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


function Track:setBpm(n)
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
  if self.source then
    self.source:stop()
    self.lastSourceTime = 0
    self.time = 0
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

  -- Get source time and apply offset
  local sourceTime = self.source:tell("seconds")
  sourceTime = sourceTime + self.offset

  -- If the source time is the same as the last time and the source is playing,
  -- we use the frame's delta time to guess how much time has passed, this
  -- assures the timing values (eg, the subbeat on :getBeat()) are updated each
  -- frame, even when the time being returned by the :tell() function is updated
  -- at a lower rate than the framerate
  local time
  if sourceTime == self.lastSourceTime and self.source:isPlaying() then
    local dt = love.timer.getDelta()
    time = self.time + dt * self.pitch
  else
    -- If the the current source time is earlier than the last time (which may
    -- have had frame-delta-time added to it), the last time is reused to give
    -- us a delta time of 0 instead of a negative value
    if sourceTime < self.time then
      time = self.time
    else
      time = sourceTime
    end
  end
  self.lastSourceTime = sourceTime
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
  -- Set last beat
  self.lastBeat = beat

  return self
end


return lovebpm
