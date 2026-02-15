tell application "Finder"
  tell disk "JUST4ALL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {120, 120, 760, 520}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set position of item "JUST4ALL.app" to {180, 200}
    set position of item "Applications" to {520, 200}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
