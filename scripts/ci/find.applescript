-- CI helper: prints the centre "x y" of a MacroForMac UI element.
--   osascript find.applescript AXCheckBox                          -- first element with this role
--   osascript find.applescript AXStaticText "Example: Select All"  -- role + text in its value/name
--   osascript find.applescript AXButton "" "Shortcut"              -- role, on the same row as a label
on run argv
	set theRole to item 1 of argv
	set theText to ""
	set rowLabel to ""
	if (count of argv) > 1 then set theText to item 2 of argv
	if (count of argv) > 2 then set rowLabel to item 3 of argv

	tell application "System Events" to tell process "MacroForMac"
		set frontmost to true
		set els to entire contents of window 1
	end tell

	set rowY to missing value
	set rowX to missing value
	if rowLabel is not "" then
		repeat with e in els
			set e to contents of e
			if my roleOf(e) is "AXStaticText" and my textOf(e) is rowLabel then
				set c to my centreOf(e)
				set rowX to item 1 of c
				set rowY to item 2 of c
				exit repeat
			end if
		end repeat
		if rowY is missing value then error "Label not found: " & rowLabel
	end if

	repeat with e in els
		set e to contents of e
		if my roleOf(e) is theRole and (theText is "" or my textOf(e) contains theText) then
			set c to my centreOf(e)
			if rowY is missing value then return my format(c)
			if (item 1 of c) > rowX and ((item 2 of c) - rowY) < 10 and (rowY - (item 2 of c)) < 10 then
				return my format(c)
			end if
		end if
	end repeat
	error "Not found: " & theRole & " " & theText & " " & rowLabel
end run

on roleOf(e)
	tell application "System Events"
		try
			return role of e
		end try
	end tell
	return ""
end roleOf

on textOf(e)
	set t to ""
	tell application "System Events"
		try
			set v to value of e
			if v is not missing value then set t to (v as text)
		end try
		if t is "" then
			try
				set n to name of e
				if n is not missing value then set t to (n as text)
			end try
		end if
	end tell
	return t
end textOf

on centreOf(e)
	tell application "System Events"
		set p to position of e
		set s to size of e
	end tell
	return {round ((item 1 of p) + (item 1 of s) / 2), round ((item 2 of p) + (item 2 of s) / 2)}
end centreOf

on format(c)
	return ((item 1 of c) as text) & " " & ((item 2 of c) as text)
end format
