tell application "Finder"
	set root to container of (path to me) as alias
	set blocksFolder to folder "blocks" of root as alias
	set scriptPath to POSIX path of (path to me) & "Contents/Resources/fuzzy_match.pl"
	
	try
		set decksFolder to folder "decks" of root as alias
	on error
		tell application "System Events"
			activate
			display dialog "No decks/ folder found. Please create a decks/ folder with .txt config files." buttons {"OK"} default button 1
		end tell
		return
	end try
end tell

-- Ensure outputs/ and .manifests/ exist
set outputsPath to POSIX path of (root as text) & "outputs/"
set manifestsPath to outputsPath & ".manifests/"
do shell script "mkdir -p " & quoted form of manifestsPath

-- List all .txt configs in decks/
tell application "Finder"
	set configFiles to every file of decksFolder whose name extension is "txt"
end tell

if (count of configFiles) is 0 then
	tell application "System Events"
		activate
		display dialog "No deck configs (.txt) found in the decks/ folder." buttons {"OK"} default button 1
	end tell
	return
end if

-- Check staleness for each config
set staleDecks to {}
set staleDeckNames to {}
set freshDeckNames to {}

repeat with configFile in configFiles
	set configPath to POSIX path of (configFile as alias)
	set configName to text 1 thru -5 of (name of configFile as text) -- strip .txt
	
	set scriptOutput to do shell script "/usr/bin/perl " & quoted form of scriptPath & " --check " & quoted form of manifestsPath & " " & quoted form of (POSIX path of blocksFolder) & " " & quoted form of configPath
	
	-- Parse STATUS line
	set statusLine to paragraph 1 of scriptOutput
	set deckStatus to text 8 thru -1 of statusLine -- after "STATUS:"
	
	-- Parse MATCHES line
	set matchesLine to paragraph 2 of scriptOutput
	if length of matchesLine > 8 then
		set matchesText to text 9 thru -1 of matchesLine
	else
		set matchesText to ""
	end if
	
	-- Parse FILES line
	set filesLine to paragraph 3 of scriptOutput
	if length of filesLine > 6 then
		set filesText to text 7 thru -1 of filesLine
	else
		set filesText to ""
	end if
	
	if deckStatus is "STALE" then
		set end of staleDecks to {deckName:configName, deckConfig:configPath, deckFiles:filesText, deckMatches:matchesText}
		set end of staleDeckNames to configName
	else
		set end of freshDeckNames to configName
	end if
end repeat

if (count of staleDecks) is 0 then
	tell application "System Events"
		activate
		display dialog "All decks are up-to-date. Nothing to rebuild." buttons {"OK"} default button 1
	end tell
	return
end if

-- Build info text for corrections
set infoText to ""
repeat with deck in staleDecks
	set theMatches to deckMatches of deck
	if length of theMatches > 0 then
		set AppleScript's text item delimiters to "|"
		set matchItems to text items of theMatches
		set AppleScript's text item delimiters to return & "    "
		set matchesPrompt to matchItems as text
		set AppleScript's text item delimiters to ""
		set infoText to infoText & "Corrections in " & (deckName of deck) & ":" & return & "    " & matchesPrompt & return
	end if
end repeat

-- Build prompt
set promptText to "Select stale decks to rebuild:"
if (count of freshDeckNames) > 0 then
	set AppleScript's text item delimiters to ", "
	set freshList to freshDeckNames as text
	set AppleScript's text item delimiters to ""
	set promptText to promptText & return & "(Up-to-date: " & freshList & ")"
end if
if length of infoText > 0 then
	set promptText to promptText & return & return & infoText
end if

-- Show selection dialog with all stale decks pre-selected
tell application "System Events"
	activate
end tell
set selectedNames to choose from list staleDeckNames with prompt promptText with title "KeynoteBuilder" default items staleDeckNames with multiple selections allowed

if selectedNames is false then return

-- Filter staleDecks to only selected ones
set decksToRebuild to {}
repeat with deck in staleDecks
	if staleDeckNames contains (deckName of deck) then
		repeat with sel in selectedNames
			if (sel as text) is (deckName of deck) then
				set end of decksToRebuild to contents of deck
				exit repeat
			end if
		end repeat
	end if
end repeat

set deckCount to count of decksToRebuild

-- Assemble each selected deck
repeat with i from 1 to deckCount
	set deck to item i of decksToRebuild
	
	-- Parse file list OUTSIDE Keynote tell block
	set theFiles to deckFiles of deck
	set theName to deckName of deck
	set theConfig to deckConfig of deck
	
	set AppleScript's text item delimiters to "|"
	set fileItems to text items of theFiles
	set AppleScript's text item delimiters to ""
	
	if (count of fileItems) > 0 then
		tell application "Keynote Creator Studio"
			activate
			
			set targetDoc to make new document
			set savePath to outputsPath & theName & ".key"
			save targetDoc in POSIX file savePath
			
			repeat with safeFileName in fileItems
				set filePath to (blocksFolder as text) & safeFileName & ".key"
				set sourceDoc to open file filePath
				move slides of sourceDoc to end of slides of targetDoc
				close sourceDoc saving no
			end repeat
			
			delete slide 1 of targetDoc
			save targetDoc
			
			-- Close this deck if it's not the last one
			if i < deckCount then
				close targetDoc saving yes
			end if
		end tell
		
		-- Write manifest after successful build
		do shell script "/usr/bin/perl " & quoted form of scriptPath & " --write-manifest " & quoted form of manifestsPath & " " & quoted form of (POSIX path of blocksFolder) & " " & quoted form of theConfig
	end if
end repeat

tell application "System Events"
	activate
	display dialog "Assembly Complete! Built " & deckCount & " deck(s)." buttons {"Done"} default button 1
end tell
