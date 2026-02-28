tell application "Finder"
	set root to container of (path to me) as alias
	set scriptPath to POSIX path of (path to me) & "Contents/Resources/fuzzy_match.pl"
end tell

set rootHFS to root as text
set rootPOSIX to POSIX path of rootHFS

set blocksHFS to rootHFS & "blocks:"
set blocksPath to rootPOSIX & "blocks/"
set decksPath to rootPOSIX & "decks/"
set outputsPath to rootPOSIX & "outputs/"
set manifestsPath to outputsPath & ".manifests/"

-- Check staleness for all configs in one call
set checkOutput to do shell script "/usr/bin/perl " & quoted form of scriptPath & " --check-all " & quoted form of manifestsPath & " " & quoted form of outputsPath & " " & quoted form of blocksPath & " " & quoted form of decksPath

if checkOutput is "" then
	tell application "System Events"
		activate
		display dialog "No deck configs (.txt) found in the decks/ folder." buttons {"OK"} default button 1
	end tell
	return
end if

set parsedOutput to run script checkOutput
try
	set errorMessage to errMsg of parsedOutput
	tell application "System Events"
		activate
		display dialog errorMessage buttons {"OK"} default button 1
	end tell
	return
end try

set allDecks to parsedOutput

set staleDecks to {}
set staleDeckNames to {}
set freshDeckNames to {}

repeat with deck in allDecks
	if deckStatus of deck is "STALE" then
		set end of staleDecks to contents of deck
		set end of staleDeckNames to deckName of deck
	else
		set end of freshDeckNames to deckName of deck
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
	if (count of theMatches) > 0 then
		set AppleScript's text item delimiters to return & "    "
		set matchesPrompt to theMatches as text
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
set builtConfigs to {}

-- Assemble each selected deck
repeat with i from 1 to deckCount
	set deck to item i of decksToRebuild
	
	-- Parse file list OUTSIDE Keynote tell block
	set theFiles to deckFiles of deck
	set theName to deckName of deck
	set theConfig to decksPath & theName & ".txt"
	
	if (count of theFiles) > 0 then
		tell application "Keynote Creator Studio"
			activate
			
			set targetDoc to make new document
			set savePath to outputsPath & theName & ".key"
			save targetDoc in POSIX file savePath
			
			repeat with safeFileName in theFiles
				set filePath to blocksHFS & safeFileName & ".key"
				set sourceDoc to open file filePath
				move slides of sourceDoc to end of slides of targetDoc
				close sourceDoc saving no
			end repeat
			
			delete slide 1 of targetDoc
			save targetDoc
			
			-- Close this deck unless only one is built, then keep it open for inspection
			if deckCount > 1 then
				close targetDoc saving yes
			end if
		end tell
		
		-- Build config_path argument for --write-manifests
		set end of builtConfigs to quoted form of theConfig
	end if
end repeat

-- Write manifests for built decks (pass config paths, Perl will re-resolve and update them)
if (count of builtConfigs) > 0 then
	set AppleScript's text item delimiters to " "
	set configArgs to builtConfigs as text
	set AppleScript's text item delimiters to ""
	do shell script "/usr/bin/perl " & quoted form of scriptPath & " --write-manifests " & quoted form of manifestsPath & " " & quoted form of blocksPath & " " & configArgs
end if

tell application "System Events"
	activate
	display dialog "Assembly Complete! Built " & deckCount & " deck(s)." buttons {"Done"} default button 1
end tell
