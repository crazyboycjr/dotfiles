function getPidOfFrontmostApp()
  local frontmostApp = hs.application.frontmostApplication()
  print('frontmostApp', frontmostApp)
  print('frontmostApp pid', frontmostApp:pid())
  if frontmostApp then
	return frontmostApp:pid()
  else
	return 0
  end
end

alacrittyPid = 0 -- a pid
hs.hotkey.bind({}, "F1", nil, function()
  print('alacrittyPid:', alacrittyPid)
  if alacrittyPid == 0 or hs.application.find(alacrittyPid) == nil then
	app = hs.application.open("io.alacritty", 1, 1)
    print('newly opened alacritty object: ', app)
	alacrittyPid = app:pid()
	app:setFrontmost(true)
	app:activate(true)
  else
  	local app = hs.application.find(alacrittyPid)
	assert(app, "impossible")
	assert(app:pid() == alacrittyPid)
	print('found object:', app)
	local frontmostPid = getPidOfFrontmostApp()
	if frontmostPid == app:pid() then
	  -- both approaches to hide the window do not work
	  print("hiding ", app:pid())
      -- hs.eventtap.keyStroke({'cmd'}, 'h')
      hs.eventtap.keyStroke({}, 'j')
	  app:hide()
	else
      hs.application.launchOrFocus("io.alacritty")
	  -- TODO(cjr): remove these below
      app:setFrontmost(true)
      app:activate(true)
	end
  end
  -- local alacritty = hs.application.find('alacritty')
  -- print('alacritty object', alacritty)
  -- print('isFrontmost', alacritty:isFrontmost())
  -- print('bundleID', alacritty:bundleID())
  -- print('path', alacritty:path())
  -- print('pid', alacritty:pid())
  -- local pid = alacritty:pid()
  -- local app = hs.application.applicationForPID(pid)
  -- print('app', app)
  -- local frontmostApp = hs.application.frontmostApplication()
  -- print('frontmostApp', frontmostApp:pid())
  -- local win = alacritty:focusedWindow()
  -- if win ~= nil then
  --   print('fullscreen', win:isFullScreen())
  -- end
  -- local mainWindow = alacritty:mainWindow()
  -- print('mainWindow:', mainWindow)
  -- -- for k, v in pairs(hs.application.runningApplications()) do
  -- --   print(k, v, v:name())
  -- -- end
  -- if alacritty and alacritty:isFrontmost() then
  --   alacritty:hide()
  -- else
  --   hs.application.launchOrFocus("/Applications/Alacritty.app")
  -- end
end)


hs.hotkey.bind({}, "F3", function()
  local app = hs.application.find('safari')
  assert(app ~= nil, "safari app not found")
  app:hide()
  -- local win = app:mainWindow()
  -- assert(win ~= nil, "alacritty has no windows, weird")
end)
