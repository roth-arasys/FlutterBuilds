-- FlutterBuilds - UI wrapper around mount.sh.
-- Registers itself as a hidden login item on first run, then either mounts silently
-- (fresh start) or offers the maintenance actions when volumes are already up.

set scriptPath to POSIX path of (path to resource "mount.sh")
set appPath to POSIX path of (path to me)
if appPath ends with "/" then set appPath to text 1 thru -2 of appPath

-- Autostart: register once. Needs Automation consent for System Events on first run.
try
	tell application "System Events"
		if not (exists login item "FlutterBuilds") then
			make new login item at end with properties {path:appPath, hidden:true}
		end if
	end tell
end try

-- "mount" output ends in "(apfs, local, ...)", so match the path followed by a space.
set checkMount to do shell script "mount | grep 'CloudStorage.*/build ' || true"

if checkMount is "" then
	-- Fresh start: nothing is attached, so this is the only moment the image can be
	-- compacted. boot therefore runs the full clean sequence and then mounts.
	do shell script quoted form of scriptPath & " boot"
else
	-- choose from list provides a real Cancel button and honours the Escape key, so the
	-- app can always be dismissed without performing an action.
	set opts to {"Remount New  -  neue Projekte einbinden", "Clean  -  verwaiste Volumes löschen, Image verkleinern, neu einbinden", "Unmount All  -  alle Volumes trennen"}
	set picked to (choose from list opts with title "FlutterBuilds" with prompt ¬
		"FlutterBuilds ist aktiv. Was möchtest du tun?" default items {item 1 of opts} ¬
		OK button name "Ausführen" cancel button name "Abbrechen")
	if picked is false then return
	set choice to item 1 of picked
	if choice starts with "Unmount All" then
		do shell script quoted form of scriptPath & " unmount"
		display notification "Alle Volumes getrennt." with title "FlutterBuilds"
	else if choice starts with "Clean" then
		do shell script quoted form of scriptPath & " clean"
		display notification "Clean abgeschlossen." with title "FlutterBuilds"
	else
		do shell script quoted form of scriptPath & " mount"
		display notification "Mounts aktualisiert." with title "FlutterBuilds"
	end if
end if
