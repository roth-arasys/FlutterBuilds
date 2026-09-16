use AppleScript version "2.4"
use framework "Foundation"
use framework "AppKit"
use scripting additions

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
	-- Fresh start: nothing is attached. Silent boot with a failsafe error timeout.
	try
		do shell script quoted form of scriptPath & " boot"
	on error errMsg
		display alert "FlutterBuilds Fehler beim Start" message errMsg as critical giving up after 15
	end try
else
	-- Maintenance menu
	set opts to {"Remount New  -  neue Projekte einbinden", "Clean  -  verwaiste Volumes löschen, Image verkleinern, neu einbinden", "Unmount All  -  alle Volumes trennen"}
	tell me to activate
	set picked to (choose from list opts with title "FlutterBuilds" with prompt ¬
		"FlutterBuilds ist aktiv. Was möchtest du tun?" default items {item 1 of opts} ¬
		OK button name "Ausführen" cancel button name "Abbrechen")
	
	if picked is not false then
		set choice to item 1 of picked
		if choice starts with "Unmount All" then
			set {cmd, msg} to {"unmount", "Alle Volumes getrennt."}
		else if choice starts with "Clean" then
			set {cmd, msg} to {"clean", "Clean abgeschlossen."}
		else
			set {cmd, msg} to {"mount", "Mounts aktualisiert."}
		end if
		
		try
			do shell script quoted form of scriptPath & " " & cmd
			display notification msg with title "FlutterBuilds"
		on error errMsg
			display alert "FlutterBuilds Fehler" message errMsg as critical
		end try
	end if
end if

-- Native Cocoa exit: shuts down the application run loop immediately
current application's NSApp's terminate:me
