tell application "Finder"
	set root to container of (path to me) as alias
	set blocksFolder to folder "blocks" of root as alias
	set configFile to file "config.txt" of root as alias
	-- set scriptPath to POSIX path of (file "fuzzy_match.pl" of root as alias)
	set scriptPath to POSIX path of (path to me) & "Contents/Resources/fuzzy_match.pl"
end tell

-- Reading config.txt and fuzzy matching to blocks/*.key
set scriptOutput to do shell script "/usr/bin/perl " & quoted form of scriptPath & " " & quoted form of (POSIX path of blocksFolder) & " " & quoted form of (POSIX path of configFile)
set matchesLine to paragraph 1 of scriptOutput

if length of matchesLine > 8 then -- MATCHES: has 8 characters
	set matchesText to text 9 thru -1 of matchesLine
else
	set matchesText to ""
end if

-- Parsing file list
set AppleScript's text item delimiters to "|"
set fileItems to text items of text 7 thru -1 of paragraph 2 of scriptOutput -- FILES
set AppleScript's text item delimiters to return
set fileListPrompt to fileItems as text
set AppleScript's text item delimiters to ""


-- System dialog
set dialogText to "Assembling the presentation from:" & return & return & fileListPrompt
if length of matchesText > 0 then
	-- Parsing inexact matches
	set AppleScript's text item delimiters to "|"
	set matchItems to text items of matchesText
	set AppleScript's text item delimiters to return
	set matchesPrompt to matchItems as text
	set AppleScript's text item delimiters to ""
	
	set dialogText to dialogText & return & return & "Corrected names:" & return & matchesPrompt
end if

tell application "System Events"
	activate
	display dialog dialogText buttons {"Cancel", "Assemble presentation"} default button "Assemble presentation"
end tell


-- Actually assemble presentation
if (count of fileItems) > 0 then
	tell application "Keynote Creator Studio"
		activate
		
		set targetDoc to make new document
		set savePath to (root as text) & "Presentation.key"
		save targetDoc in file savePath
		
		repeat with safeFileName in fileItems
			set filePath to (blocksFolder as text) & safeFileName & ".key"
			set sourceDoc to open file filePath
			move slides of sourceDoc to end of slides of targetDoc
			close sourceDoc saving no
		end repeat
		
		delete slide 1 of targetDoc
		save targetDoc
		
		display dialog "Assembly Complete!" buttons {"Done"} default button 1
	end tell
end if