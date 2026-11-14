-- CI helper: prints the centre "x y" of the first MacroForMac UI element with the given
-- accessibility role whose value or name contains the given text (text optional).
--   osascript scripts/ci/find.applescript AXCheckBox
--   osascript scripts/ci/find.applescript AXStaticText "Example: Select All & Copy"
on run argv
	set theRole to item 1 of argv
	set theText to ""
	if (count of argv) > 1 then set theText to item 2 of argv
	tell application "System Events" to tell process "MacroForMac"
		set frontmost to true
		set els to entire contents of window 1
	end tell
	repeat with e in els
		set e to contents of e
		set r to ""
		set t to ""
		tell application "System Events"
			try
				set r to role of e
			end try
			try
				set t to t & (value of e as text)
			end try
			try
				set t to t & (name of e as text)
			end try
		end tell
		if r is theRole and (theText is "" or t contains theText) then
			tell application "System Events"
				set p to position of e
				set s to size of e
			end tell
			set x to round ((item 1 of p) + (item 1 of s) / 2)
			set y to round ((item 2 of p) + (item 2 of s) / 2)
			return (x as text) & " " & (y as text)
		end if
	end repeat
	error "Not found: " & theRole & " " & theText
end run
