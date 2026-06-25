local input = {}
local acuteAccentPending = false

local accentedVowels = {
  [hs.keycodes.map.a] = { lower = "á", upper = "Á" },
  [hs.keycodes.map.e] = { lower = "é", upper = "É" },
  [hs.keycodes.map.i] = { lower = "í", upper = "Í" },
  [hs.keycodes.map.o] = { lower = "ó", upper = "Ó" },
  [hs.keycodes.map.u] = { lower = "ú", upper = "Ú" },
}

local function sendTextAfterRelease(text)
  hs.timer.doAfter(0.01, function()
    hs.eventtap.keyStrokes(text)
  end)
end

local function startAcuteAccentMode()
  acuteAccentPending = true

  hs.timer.doAfter(2, function()
    acuteAccentPending = false
  end)
end

hs.eventtap
  .new({ hs.eventtap.event.types.keyDown }, function(event)
    if not acuteAccentPending then
      return false
    end

    acuteAccentPending = false

    local accented = accentedVowels[event:getKeyCode()]
    if not accented then
      return false
    end

    local output = event:getFlags().shift and accented.upper or accented.lower
    hs.timer.doAfter(0, function()
      hs.eventtap.keyStrokes(output)
    end)

    return true
  end)
  :start()

hs.hotkey.bind({ "ctrl", "alt" }, "n", function() end, function()
  sendTextAfterRelease("ñ")
end)

hs.hotkey.bind({ "ctrl", "alt", "shift" }, "n", function() end, function()
  sendTextAfterRelease("Ñ")
end)

hs.hotkey.bind({ "ctrl", "alt" }, "e", function() end, function()
  startAcuteAccentMode()
end)

return input
