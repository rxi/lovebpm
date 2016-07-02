
-- Add parent directory to package.path so require() can find the module
package.path = package.path .. ";../?.lua"


local lovebpm = require("lovebpm")


function love.load()
  love.audio.setVolume(.6)
  font = love.graphics.newFont(50)
  paused = false
  pulse = 0
  -- Init new Track object and start playing
  music = lovebpm.newTrack()
    :load("loop.ogg")
    :setBpm(127)
    :setLooping(true)
    :on("beat", function(n)
      local r, g, b = math.random(90), math.random(90), math.random(90)
      love.graphics.setBackgroundColor(r, g, b)
      pulse = 1
    end)
    :play()
end


function love.update(dt)
  music:update()
  pulse = math.max(0, pulse - dt)
end


function love.keypressed(k)
  if k == "space" then
    -- Toggle pause
    paused = not paused
    if paused then
      music:pause()
    else
      music:play()
    end
  end
end


function love.draw()
  local w, h = love.graphics.getDimensions()

  -- Draw circle
  local radius = 80 + pulse ^ 3 * 20
  love.graphics.setLineWidth(8)
  love.graphics.setColor(255, 255, 255, 255 * 0.3)
  love.graphics.circle("line", w / 2, h / 2, radius)

  -- Get current beat and subbeat with 4x multiplier
  local beat, subbeat = music:getBeat(4)

  -- Draw 4x subbeat progress arc
  local angle1 = -math.pi / 2
  local angle2 = math.pi * 2 * subbeat - math.pi / 2
  love.graphics.setColor(255, 255, 255)
  love.graphics.arc("line", "open", w / 2, h / 2, radius, angle1, angle2)

  -- Get current beat and subbeat
  local beat, subbeat = music:getBeat()

  -- Draw current beat number
  love.graphics.setFont(font)
  love.graphics.printf(beat, 0, h / 2 - 30, w, "center")
end
