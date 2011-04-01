#NoTrayIcon
#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_Au3Check_Parameters=-q -d -w 1 -w 2 -w 3 -w 4 -w 5 -w 6
#AutoIt3Wrapper_icon=md5hash.ico
#AutoIt3Wrapper_outfile=..\..\App\md5hash\md5hash.exe
#AutoIt3Wrapper_Compression=4
#AutoIt3Wrapper_Res_Comment=Create file checksums.
#AutoIt3Wrapper_Res_Description=md5hash
#AutoIt3Wrapper_Res_Fileversion=1.0.3.5
#AutoIt3Wrapper_Res_LegalCopyright=Erik Pilsits
#AutoIt3Wrapper_Res_Language=1033
#AutoIt3Wrapper_Res_requestedExecutionLevel=asInvoker
#AutoIt3Wrapper_Run_Obfuscator=y
#Obfuscator_Parameters=/so
#EndRegion ;**** Directives created by AutoIt3Wrapper_GUI ****

#cs
	MD5
	SHA1
	SHA224
	SHA256
	SHA384
	SHA512
	CRC16
	CRC32
	ADLER32
	MD2
	MD4
#ce

Opt("GUIOnEventMode", 1)
Opt("GUIResizeMode", 802) ; $GUI_DOCKALL

#include <Misc.au3>
#include <GuiConstantsEx.au3>
#include <WindowsConstants.au3>
#include <EditConstants.au3>
#include <GuiMenu.au3>
#include <GuiListView.au3>
#include <ListViewConstants.au3>
#include <hashthread.au3>
#include <_MemoryDll.au3>

If Not _Singleton("md5hashSingleton", 1) Then
	; second+ instance
	If $CmdLine[0] > 0 Then _MultiInstance()

	Exit
EndIf

; extract hash DLL if it does not exist or it is a newer version
If (Not FileExists(@ScriptDir & "\hash.dll")) Or (_VersionCompare("1.0.0.6", FileGetVersion(@ScriptDir & "\hash.dll")) > 0) Then _
	FileInstall(".\hash.dll", @ScriptDir & "\hash.dll", 1)
Global $hashDLL = MemoryDllOpen($__HashDllCode)
Global Const $WM_DROPFILES = 0x233

Global $version = FileGetVersion(@ScriptFullPath)
Global $MasterQueue[1] = [0], $gLVParam = 9999
Global $LastHashedList = -1 ; initial state: non-array
Global $LastTwoHashes[2][2]
Global $IsRunning = False
Global $aAlgo[11] = ["MD5", "SHA1", "SHA224", "SHA256", "SHA384", "SHA512", "CRC16", "CRC32", "ADLER32", "MD2", "MD4"] ; array of algorithms

; read INI settings
Global $datadir
If FileExists(@ScriptDir & "\..\..\md5hash.exe") Then
	; PortableApps install
	$datadir = @ScriptDir & "\..\..\Data"
Else
	; normal install
	$datadir = @ScriptDir
EndIf
If Not FileExists($datadir) Then DirCreate($datadir)
Global $inifile = $datadir & "\md5hash.ini"
Global $curAlgo = Number(IniRead($inifile, "md5hash", "algorithm", 0)) ; index into aAlgo array; 0 = MD5
Global $upperHash = Number(IniRead($inifile, "md5hash", "upper", 0)) ; uppercase
Global $historyMax = Number(IniRead($inifile, "md5hash", "history", 500)) ; history depth
Global $folderDepth = Number(IniRead($inifile, "md5hash", "folderdepth", 1)) ; folder recurse depth
Global $largeWarning = Number(IniRead($inifile, "md5hash", "largewarning", 1)) ; warn on large hash
Global $iDepth = 1 ; folder recursion counter
Global $miniGui = 28, $fullGui = 40, $GuiHeight, $GuiWidth = 274
Global $GuiBorder = _WinAPI_GetSystemMetrics($SM_CYCAPTION) + _WinAPI_GetSystemMetrics($SM_CYFRAME) - (_WinAPI_GetSystemMetrics($SM_CYBORDER) * 2)
Global $gui_x = Number(IniRead($inifile, "md5hash", "x", -1)) ; gui position
Global $gui_y = Number(IniRead($inifile, "md5hash", "y", Int(@DesktopHeight / 4)))
Global $sess_x = Number(IniRead($inifile, "md5hash", "sess_x", -1)) ; session gui
Global $sess_y = Number(IniRead($inifile, "md5hash", "sess_y", $gui_y + $fullGui + 40)) ; session gui
Global $guiFullMode = Number(IniRead($inifile, "md5hash", "fullmode", 1))
If $guiFullMode Then
	$GuiHeight = $fullGui
Else
	$GuiHeight = $miniGui
EndIf
Global $alwaysOnTop = Number(IniRead($inifile, "md5hash", "alwaysontop", 1))
If Not FileExists($inifile) Then
	; write defaults to INI if it doesn't exist
	IniWrite($inifile, "md5hash", "algorithm", $curAlgo)
	IniWrite($inifile, "md5hash", "upper", $upperHash)
	IniWrite($inifile, "md5hash", "history", $historyMax)
	IniWrite($inifile, "md5hash", "x", $gui_x)
	IniWrite($inifile, "md5hash", "y", $gui_y)
	IniWrite($inifile, "md5hash", "sess_x", $sess_x)
	IniWrite($inifile, "md5hash", "sess_y", $sess_y)
	IniWrite($inifile, "md5hash", "fullmode", $guiFullMode)
	IniWrite($inifile, "md5hash", "alwaysontop", $alwaysOnTop)
	IniWrite($inifile, "md5hash", "folderdepth", $folderDepth)
	IniWrite($inifile, "md5hash", "largewarning", $largeWarning)
EndIf

; create our GUI
Global $wm_recv = GUICreate("md5hashHiddenWM_COPYDATA") ; hidden window to receive WM_COPYDATA messages, and act as parent so we don't have a toolbar button
Global $gui = GUICreate("md5hash", $GuiWidth, $GuiHeight, $gui_x, $gui_y, BitOR($WS_CAPTION, $WS_SYSMENU, $WS_POPUP), $WS_EX_ACCEPTFILES, $wm_recv)
If $alwaysOnTop Then WinSetOnTop($gui, "", 1)
_GuiInBounds($gui) ; make sure gui is in bounds
Global $edit = GUICtrlCreateEdit("", 4, 4, 266, 20, BitOR($ES_READONLY, $ES_AUTOHSCROLL))
GUICtrlSetBkColor(-1, 0xFFFFFF)
Global $progress = GUICtrlCreateProgress(4, 28, 266, 8)
Global $hProgress = 0
If $guiFullMode Then $hProgress = GUICtrlGetHandle($progress)
Global $dummy = GUICtrlCreateDummy()
Global $dummy2 = GUICtrlCreateDummy()

; modify system menu
; NOTES:
; system uses ID values > 0xF000
; ID value in WM_SYSCOMMAND notification is BitAND'd with 0xFFF0 so user values CANNOT use the low 4 bits
; ie 0x00F0 is OK, but not 0x00F1 - 0x00FF

; hash algorithm submenu
; good for values of $m up to 3759
Global $hAlgo = _GUICtrlMenu_CreatePopup()
For $m = 0 To UBound($aAlgo) - 1
	_GUICtrlMenu_AddMenuItem($hAlgo, $aAlgo[$m], BitShift($m + 0x50, -4)) ; convert ordinal to command ID value
Next
_GUICtrlMenu_SetItemChecked($hAlgo, $curAlgo)

; options menu
Global Enum $idUpperHash = 0, $idAlwaysOnTop, $idProgress, $idWarning, $idFolderDepth, $idHistoryMax
Global $hOptions = _GUICtrlMenu_CreatePopup()
_GUICtrlMenu_AddMenuItem($hOptions, "UPPERCASE Hash", 0x200)
_GUICtrlMenu_SetItemChecked($hOptions, $idUpperHash, ($upperHash = 1)) ; upper hash checked state
_GUICtrlMenu_AddMenuItem($hOptions, "Always On Top", 0x210)
_GUICtrlMenu_SetItemChecked($hOptions, $idAlwaysOnTop, ($alwaysOnTop = 1)) ; always on top checked state
_GUICtrlMenu_AddMenuItem($hOptions, "Show Progress", 0x220)
_GUICtrlMenu_SetItemChecked($hOptions, $idProgress, ($guiFullMode = 1)) ; progress checked state
_GUICtrlMenu_AddMenuItem($hOptions, "Warn On Large Jobs", 0x230)
_GUICtrlMenu_SetItemChecked($hOptions, $idWarning, ($largeWarning = 1)) ; warning checked state
_GUICtrlMenu_AddMenuItem($hOptions, "Folder Search Depth:  " & $folderDepth, 0x240)
_GUICtrlMenu_AddMenuItem($hOptions, "Session History Max:  " & $historyMax, 0x250)

; main menu
Global $hMenu = _GUICtrlMenu_GetSystemMenu($gui)
_GUICtrlMenu_InsertMenuItem($hMenu, 0, "Select File...", 0x20)
_GUICtrlMenu_InsertMenuItem($hMenu, 1, "View Session...", 0x30)
_GUICtrlMenu_InsertMenuItem($hMenu, 2, "Rehash Current", 0x40)
_GUICtrlMenu_InsertMenuItem($hMenu, 3, "Compare Last Two Hashes", 0x50)
_GUICtrlMenu_InsertMenuItem($hMenu, 3, "Compare Current Hash With Another", 0x60) ;Mine
_GUICtrlMenu_InsertMenuItem($hMenu, 4, "")
_GUICtrlMenu_InsertMenuItem($hMenu, 5, "Hash Algorithm", 0, $hAlgo) ; create submenu
_GUICtrlMenu_InsertMenuItem($hMenu, 6, "Options", 0, $hOptions) ; options submenu
_GUICtrlMenu_InsertMenuItem($hMenu, 7, "")
_GUICtrlMenu_InsertMenuItem($hMenu, 8, "Help", 0x70)
_GUICtrlMenu_InsertMenuItem($hMenu, 9, "About...", 0x80)
_GUICtrlMenu_InsertMenuItem($hMenu, 10, "")

; listview right-click menu
Global Enum $idFIRST = 1000, $idSaveSession, $idSaveSelected, $idRemoveItems, $idClearSession, $idLAST
Global $hMenu2 = _GUICtrlMenu_CreatePopup()
_GUICtrlMenu_AddMenuItem($hMenu2, "Save Session...", $idSaveSession)
_GUICtrlMenu_AddMenuItem($hMenu2, "Save Selected Item(s)...", $idSaveSelected)
_GUICtrlMenu_AddMenuItem($hMenu2, "Remove Selected Item(s)", $idRemoveItems)
_GUICtrlMenu_AddMenuItem($hMenu2, "Clear Session", $idClearSession)

; messages
GUIRegisterMsg($WM_DROPFILES, "_MY_WM_DROPFILES")
GUIRegisterMsg($WM_SYSCOMMAND, "_MY_WM_SYSCOMMAND")
GUIRegisterMsg($WM_COMMAND, "_MY_WM_COMMAND")
GUIRegisterMsg($WM_NOTIFY, "_MY_WM_NOTIFY")
GUIRegisterMsg($WM_COPYDATA, "_MY_WM_COPYDATA")

; events
GUISetOnEvent($GUI_EVENT_CLOSE, "_Exit")
GUICtrlSetOnEvent($dummy, "_Dummy")
GUICtrlSetOnEvent($dummy2, "_Dummy2")

; session GUI
Global $sessionGui = GUICreate("md5hash Session History (Double-click an entry to copy, Right-click to save or clear)", 800, 500, $sess_x, $sess_y, -1, $WS_EX_TOOLWINDOW, $gui)
Global $hLV1 = _GUICtrlListView_Create($sessionGui, "Algorithm|Hash|File", 0, 0, 800, 500, BitOR($LVS_SHOWSELALWAYS, $LVS_REPORT), $WS_EX_CLIENTEDGE)
_GUICtrlListView_SetExtendedListViewStyle($hLV1, BitOR($LVS_EX_GRIDLINES, $LVS_EX_DOUBLEBUFFER, $LVS_EX_FULLROWSELECT), _
											BitOR($LVS_EX_GRIDLINES, $LVS_EX_DOUBLEBUFFER, $LVS_EX_FULLROWSELECT))
_GUICtrlListView_SetColumnWidth($hLV1, 0, 65)
_GUICtrlListView_SetColumnWidth($hLV1, 1, 280)
_GUICtrlListView_RegisterSortCallBack($hLV1, False)

;create compare menu . . . .
Global $compareView = GUICreate("Compare Hash Values", 600, 100)
$showComparisonHash =GUICtrlCreateLabel("$LastTwoHashes[0][0]", 5, 20, 580)
$compareHashVal = GUICtrlCreateInput("Hash to compare to", 10, 50, 580, 20)
$CompareButton = GUICtrlCreateButton("Compare", 225, 75, 100)

; events
GUICtrlSetOnEvent($compareButton, "_CompareButton")
GUISetOnEvent($GUI_EVENT_CLOSE, "_Exit")

GUISetState(@SW_SHOW, $gui)

If $CmdLine[0] > 0 Then
	; hash commandline list of files
	_HashCommandLine()
Else
	GUICtrlSetData($edit, "Drop any file...")
	GUICtrlSetTip($edit, "Drop two files to compare checksums.")
EndIf

While 1
	Sleep(1000)
WEnd

Func _HashCommandLine()
	Local $aFiles, $aCmdLine = $CmdLine
	_SearchArray($aCmdLine, $aFiles)
	If $aFiles[0] Then
		$MasterQueue[0] += 1
		_ArrayAdd($MasterQueue, $aFiles)
		_Action()
	EndIf
EndFunc

Func _Exit()
	Switch @GUI_WinHandle
		Case $sessionGui
			GUISetState(@SW_HIDE, $sessionGui)
		Case $compareView
			GuiSetState(@SW_HIDE, $compareView)
		Case $gui
			MemoryDllClose($hashDLL)
			MemoryDllExit()
			_GUICtrlListView_UnRegisterSortCallBack($hLV1)
			; save position (bounds checking done on startup)
			Local $guipos = WinGetPos($gui), $sesspos = WinGetPos($sessionGui)
			IniWrite($inifile, "md5hash", "x", $guipos[0])
			IniWrite($inifile, "md5hash", "y", $guipos[1])
			IniWrite($inifile, "md5hash", "sess_x", $sesspos[0])
			IniWrite($inifile, "md5hash", "sess_y", $sesspos[1])

			Exit
	EndSwitch
EndFunc

Func _GuiInBounds($gui)
	Local $x, $y, $guipos = WinGetPos($gui)
	If $guipos[0] < 5 Then
		$x = 5
	ElseIf ($guipos[0] + $guipos[2] + 10) > @DesktopWidth Then
		$x = @DesktopWidth - $guipos[2] - 10
	Else
		$x = $guipos[0]
	EndIf
	If $guipos[1] < 5 Then
		$y = 5
	ElseIf ($guipos[1] + $guipos[3] + 10) > @DesktopHeight Then
		$y = @DesktopHeight - $guipos[3] - 10
	Else
		$y = $guipos[1]
	EndIf
	WinMove($gui, "", $x, $y)
EndFunc

Func _Dummy()
	; handles system menu commands
	Local $command = GUICtrlRead($dummy)
	Switch $command
		Case 0x10 ; DROPFILES or COPYDATA message
			_Action()
		Case 0x20 ; Select File...
			_FileSelect()
		Case 0x30 ; View Session...
			_ViewSession()
		Case 0x40 ; Rehash Current
			_Rehash()
		Case 0x50 ; Compare Last Two Hashes
			_CompareLastTwoHashes()
		Case 0x60 ; Compare Current Hash to a Value
			_CompareCurrentHash()
		Case 0x70 ; Help
			ShellExecute(@ScriptDir & "\Readme.txt")
		Case 0x80 ; About...
			_About()
		Case 0x200 ; Uppercase Hash
			_ToggleUpper()
		Case 0x210 ; Always On TOp
			_ToggleAlwaysOnTop()
		Case 0x220 ; Show Progress
			_ToggleProgress()
		Case 0x230 ; Warn Large Jobs
			_ToggleWarning()
		Case 0x240 ; Folder Search Depth
			_SetFolderDepth()
		Case 0x250 ; Session History Max
			_SetHistoryMax()
		Case 0x500 To 0xEFF0 ; Hash Algorithm ->
			; convert command ID to ordinal
			$command = BitAND($command, 0xFFF0)
			_SwitchAlgorithm(BitShift($command, 4) - 0x50)
	EndSwitch
EndFunc

Func _Dummy2()
	; handles listview right-click commands
	Local $saveData, $savePath, $hFile
	Local $command = GUICtrlRead($dummy2)
	Switch $command
		Case $idSaveSession
			; save session data
			$savePath = FileSaveDialog("Save Session...", @ScriptDir, "Text File (*.txt)", 2 + 16, "md5hash_Session.txt", $hLV1)
			If Not @error And $savePath Then
				If StringRight($savePath, 4) <> ".txt" Then $savePath &= ".txt"
				$saveData = ""
				For $i = 0 To _GUICtrlListView_GetItemCount($hLV1) - 1
					$saveData &= StringReplace(_GUICtrlListView_GetItemTextString($hLV1, $i), "|", ",") & @CRLF
				Next
				$hFile = FileOpen($savePath, 2)
				FileWrite($hFile, StringTrimRight($saveData, 2)) ; remove last @CRLF
				FileClose($hFile)
			EndIf
		Case $idSaveSelected
			; save selected items
			$savePath = FileSaveDialog("Save Selected Item(s)...", @ScriptDir, "Text File (*.txt)", 2 + 16, "md5hash_Items.txt", $hLV1)
			If Not @error And $savePath Then
				If StringRight($savePath, 4) <> ".txt" Then $savePath &= ".txt"
				$saveData = ""
				Local $items = _GUICtrlListView_GetSelectedIndices($hLV1, True)
				For $i = 1 To $items[0]
					$saveData &= StringReplace(_GUICtrlListView_GetItemTextString($hLV1, $items[$i]), "|", ",") & @CRLF
				Next
				$hFile = FileOpen($savePath, 2)
				FileWrite($hFile, StringTrimRight($saveData, 2)) ; remove last @CRLF
				FileClose($hFile)
			EndIf
		Case $idRemoveItems
			; remove selected items
			_GUICtrlListView_DeleteItemsSelected($hLV1)
			_GUICtrlListView_SetColumnWidth($hLV1, 2, $LVSCW_AUTOSIZE_USEHEADER)
			If Not _GUICtrlListView_GetItemCount($hLV1) Then $gLVParam = 9999 ; reset sorting counter if nothing left
		Case $idClearSession
			; clear listview
			_GUICtrlListView_DeleteAllItems($hLV1)
			_GUICtrlListView_SetColumnWidth($hLV1, 2, $LVSCW_AUTOSIZE_USEHEADER)
			$gLVParam = 9999 ; reset sorting counter
	EndSwitch
EndFunc

Func _Action()
	; get out of here?
	If $MasterQueue[0] <= 0 Then Return ; nothing to process
	If $IsRunning Then Return ; already running something (ie a DROPFILES or COPYDATA message was processed during another job and called this function)
	; check size and number of files, issue warning
	Local $aHashes = $MasterQueue[1], $bailOut = False
	If $largeWarning Then
		If $aHashes[0] > 500 Then
			If 7 = MsgBox(4 + 48, "Warning", "You are about to hash " & $aHashes[0] & " files." & @CRLF & _
							"This could take a long time." & @CRLF & @CRLF & "Continue?", 0, $gui) Then
				; set cancel job flag
				$bailOut = True
			EndIf
		Else
			Local $size = 0
			For $i = 1 To $aHashes[0]
				$size += FileGetSize($aHashes[$i])
			Next
			$size /= (1024 ^ 2)
			If $size > 1024 Then ; 1 GB
				If 7 = MsgBox(4 + 48, "Warning", "You are about to hash " & Round($size / 1024, 2) & " GB of data." & @CRLF & _
								"This could take a long time." & @CRLF & @CRLF & "Continue?", 0, $gui) Then
					; set cancel job flab
					$bailOut = True
				EndIf
			EndIf
		EndIf
		If $bailOut Then
			$MasterQueue[0] -= 1
			_ArrayDelete($MasterQueue, 1)
			_Action()
			Return
		EndIf
	EndIf
	; go for it
	$IsRunning = True
	GUISetCursor(15, 1, $gui) ; set waiting cursor
	Switch $aHashes[0]
		Case 1
			GUICtrlSetData($edit, "Calculating...")
			GUICtrlSetTip($edit, $aHashes[1])
			Local $hash = _HashFile($aHashes[1], $hProgress)
			If $hash <> "" Then
				GUICtrlSetData($edit, $hash)
				ClipPut($hash)
			Else
				GUICtrlSetData($edit, "Unable to open file.")
				GUICtrlSetTip($edit, "Unable to open file:" & @CRLF & $aHashes[1])
			EndIf
		Case 2
			; compare 2 files
			Local $aCompare[2]
			GUICtrlSetData($edit, "Comparing files...")
			GUICtrlSetTip($edit, "Comparing:" & @CRLF & $aHashes[1] & @CRLF & $aHashes[2])
			For $i = 1 To 2
				$aCompare[$i - 1] = _HashFile($aHashes[$i], $hProgress)
			Next
			If $aCompare[0] = $aCompare[1] Then
				GUICtrlSetData($edit, "Files are IDENTICAL.")
			Else
				GUICtrlSetData($edit, "Files are DIFFERENT.")
			EndIf
		Case Else
			; hash the whole list
			GUICtrlSetData($edit, "Hashing all files...")
			GUICtrlSetTip($edit, "Hashing all files...")
			For $i = 1 To $aHashes[0]
				_HashFile($aHashes[$i], $hProgress)
			Next
			GUICtrlSetData($edit, "Hashing all files...DONE")
			GUICtrlSetTip($edit, "Hashing all files...DONE")
	EndSwitch

	; decrement counter and remove processed list
	$LastHashedList = $MasterQueue[1] ; save last hashed list
	$MasterQueue[0] -= 1
	_ArrayDelete($MasterQueue, 1)
	$IsRunning = False ; reset flag
	GUISetCursor() ; reset cursor

	_Action() ; process next queued list, if it exists
EndFunc

Func _FileSelect()
	Local $file = FileOpenDialog("Select a file...", @WorkingDir, "All files (*.*)", 3, "", $gui)
	If Not @error Then
		FileChangeDir(StringLeft($file, StringInStr($file, "\", 0, -1) - 1))
		_SingleFile($file)
	EndIf
EndFunc

Func _Rehash()
	If IsArray($LastHashedList) Then
		$MasterQueue[0] += 1
		_ArrayAdd($MasterQueue, $LastHashedList)
		_Action()
	EndIf
EndFunc

Func _CompareLastTwoHashes()
	If ($LastTwoHashes[0][0] <> "") And ($LastTwoHashes[1][0] <> "") Then
		GUICtrlSetTip($edit, "Comparing:" & @CRLF & $LastTwoHashes[0][1] & @CRLF & $LastTwoHashes[1][1])
		If $LastTwoHashes[0][0] = $LastTwoHashes[1][0] Then
			GUICtrlSetData($edit, "Files are IDENTICAL.")
		Else
			GUICtrlSetData($edit, "Files are DIFFERENT.")
		EndIf
	EndIf
EndFunc

Func _About()
	MsgBox(0 + 64, "About...", "md5hash" & @CRLF & "v" & $version & @CRLF & @CRLF & "by Erik Pilsits", 0, $gui)
EndFunc

Func _ViewSession()
	If Not BitAND(WinGetState($sessionGui), 2) Then ; not visible
		_GuiInBounds($sessionGui)
		GUISetState(@SW_SHOW, $sessionGui)
	EndIf
EndFunc

Func _SwitchAlgorithm($iAlgo)
	_GUICtrlMenu_SetItemChecked($hAlgo, $curAlgo, False) ; uncheck current menu item
	$curAlgo = $iAlgo ; set new algorithm
	_GUICtrlMenu_SetItemChecked($hAlgo, $curAlgo) ; check the menu item
	IniWrite($inifile, "md5hash", "algorithm", $curAlgo) ; write to INI
EndFunc

Func _ToggleUpper()
	$upperHash = Number(Not $upperHash)
	_GUICtrlMenu_SetItemChecked($hOptions, $idUpperHash, $upperHash)
	IniWrite($inifile, "md5hash", "upper", $upperHash)
EndFunc

Func _ToggleAlwaysOnTop()
	$alwaysOnTop = Number(Not $alwaysOnTop)
	_GUICtrlMenu_SetItemChecked($hOptions, $idAlwaysOnTop, $alwaysOnTop)
	IniWrite($inifile, "md5hash", "alwaysontop", $alwaysOnTop)
	WinSetOnTop($gui, "", $alwaysOnTop)
EndFunc

Func _ToggleProgress()
	$guiFullMode = Number(Not $guiFullMode)
	_GUICtrlMenu_SetItemChecked($hOptions, $idProgress, $guiFullMode)
	IniWrite($inifile, "md5hash", "fullmode", $guiFullMode)
	If $guiFullMode Then
		; expand GUI and enable progress updates
		WinMove($gui, "", Default, Default, Default, $fullGui + $GuiBorder)
		$hProgress = GUICtrlGetHandle($progress)
	Else
		; shrink GUI and disable progress updates
		WinMove($gui, "", Default, Default, Default, $miniGui + $GuiBorder)
		$hProgress = 0
	EndIf
EndFunc

Func _ToggleWarning()
	$largeWarning = Number(Not $largeWarning)
	_GUICtrlMenu_SetItemChecked($hOptions, $idWarning, $largeWarning)
	IniWrite($inifile, "md5hash", "largewarning", $largeWarning)
EndFunc

Func _SetFolderDepth()
	Local $depth = InputBox("Folder Depth", "Enter new folder depth:",  $folderDepth, " M", 275, 140, Default, Default, 0, $gui)
	If $depth <> "" Then
		; set new folder depth
		$folderDepth = Number(StringStripWS($depth, 8))
		IniWrite($inifile, "md5hash", "folderdepth", $folderDepth)
		_GUICtrlMenu_SetItemText($hOptions, $idFolderDepth, "Folder Search Depth:  " & $folderDepth)
	EndIf
EndFunc

Func _SetHistoryMax()
	Local $max = InputBox("Session History Max", "Enter the maximum session size:",  $historyMax, " M", 275, 140, Default, Default, 0, $gui)
	If $max <> "" Then
		; set new history max
		$historyMax = Number(StringStripWS($max, 8))
		IniWrite($inifile, "md5hash", "history", $historyMax)
		_GUICtrlMenu_SetItemText($hOptions, $idHistoryMax, "Session History Max:  " & $historyMax)
	EndIf
EndFunc

Func _SingleFile($file)
	Local $aFiles, $aHashes[2] = [1, $file]
	_SearchArray($aHashes, $aFiles)
	If $aFiles[0] Then
		$MasterQueue[0] += 1
		_ArrayAdd($MasterQueue, $aFiles)
		_Action()
	EndIf
EndFunc

Func _HashFile($file, $vhProgress = 0)
	; get hash
	; longest hash is 512 bits = 64 bytes = 128 hex characters + 1 for the terminating NULL
	Local $hashResult = "", $buff = DllStructCreate("wchar[129]")
	Local $hThread = MemoryDllCall($hashDLL, "ptr:cdecl", "HashFileThread", "str", $aAlgo[$curAlgo], "wstr", $file, "ptr", DllStructGetPtr($buff), "hwnd", $vhProgress)
	If $hThread[0] Then
		Local $wait
		While 1
			$wait = DllCall("kernel32.dll", "dword", "WaitForSingleObject", "ptr", $hThread[0], "dword", 0)
			If Not $wait[0] Then
				; thread is finished
				DllCall("kernel32.dll", "int", "CloseHandle", "ptr", $hThread[0])
				$hashResult = DllStructGetData($buff, 1)
				ExitLoop
			EndIf
			Sleep(100) ; keep GUI responsive and accept other messages
		WEnd
	EndIf

	; result
	If $upperHash Then $hashResult = StringUpper($hashResult)
	Local $lvVal = $hashResult ; lvVal = what is displayed in ListView
	If $hashResult = "" Then $lvVal = "Unable to open file."

	; update session listview
	; insert item
	_GUICtrlListView_InsertItem($hLV1, $aAlgo[$curAlgo], 0, -1, $gLVParam)
	$gLVParam += 1
	_GUICtrlListView_SetItemText($hLV1, 0, $lvVal, 1)
	_GUICtrlListView_SetItemText($hLV1, 0, $file, 2)
	Local $lvCount = _GUICtrlListView_GetItemCount($hLV1)
	If $lvCount > $historyMax Then ; keep history of last XXX files
		; delete last item
		_GUICtrlListView_DeleteItem($hLV1, $lvCount - 1)
	EndIf
	; create horizontal scrollbar if necessary (resize final column)
	_GUICtrlListView_SetColumnWidth($hLV1, 2, $LVSCW_AUTOSIZE_USEHEADER)
	; update last two hashes
	If $hashResult Then
		$LastTwoHashes[1][0] = $LastTwoHashes[0][0]
		$LastTwoHashes[1][1] = $LastTwoHashes[0][1]
		$LastTwoHashes[0][0] = $hashResult
		$LastTwoHashes[0][1] = $file
	EndIf

	Return $hashResult
EndFunc

Func _MY_WM_DROPFILES($hWnd, $Msg, $wParam, $lParam)
	#forceref $Msg, $lParam
	Switch $hWnd
		Case $gui
			WinActivate($gui)
			; string buffer for file path
			Local $tDrop = DllStructCreate("wchar[260]")
			; get file count
			Local $aRet = DllCall("shell32.dll", "int", "DragQueryFileW", _
										"ptr", $wParam, _
										"uint", -1, _
										"ptr", DllStructGetPtr($tDrop), _
										"int", DllStructGetSize($tDrop) _
										)
			Local $iCount = $aRet[0]

			Local $aHashes[$iCount + 1]
			$aHashes[0] = $iCount
			; get file paths
			For $i = 0 To $iCount - 1
				$aRet = DllCall("shell32.dll", "int", "DragQueryFileW", _
										"ptr", $wParam, _
										"uint", $i, _
										"ptr", DllStructGetPtr($tDrop), _
										"int", DllStructGetSize($tDrop) _
										)
				$aHashes[$i + 1] = DllStructGetData($tDrop, 1)
			Next
			; finalize
			DllCall("shell32.dll", "int", "DragFinish", "hwnd", $wParam)
			Local $aFiles
			_SearchArray($aHashes, $aFiles)
			If $aFiles[0] Then
				; add to queue and start
				$MasterQueue[0] += 1
				_ArrayAdd($MasterQueue, $aFiles)
				GUICtrlSendToDummy($dummy, 0x10) ; _Action
			EndIf

			Return 0
	EndSwitch

	Return $GUI_RUNDEFMSG
EndFunc

Func _MY_WM_SYSCOMMAND($hWnd, $Msg, $wParam, $lParam)
	#forceref $Msg, $lParam
	Switch $hWnd
		Case $gui
			; user-defined ID's should be less than 0xF000
			; must BitAND the wParam value with 0xFFF0 to get proper ID
			Local $ID = BitAND($wParam, 0xFFF0)
			If $ID < 0xF000 Then
				GUICtrlSendToDummy($dummy, $ID)
				Return 0
			EndIf
	EndSwitch

	Return $GUI_RUNDEFMSG
EndFunc

Func _MY_WM_COMMAND($hWnd, $Msg, $wParam, $lParam)
	#forceref $Msg, $lParam
	Switch $hWnd
		Case $gui
			Switch BitAND(BitShift($wParam, 16), 0xFFFF) ; hi word
				Case 0 ; originated from a menu
					Local $ID = BitAND($wParam, 0xFFFF) ; lo word
					Switch $ID
						Case $idFIRST To $idLAST
							; send control ID to dummy
							GUICtrlSendToDummy($dummy2, $ID)
							Return 0
					EndSwitch
			EndSwitch
	EndSwitch

	Return $GUI_RUNDEFMSG
EndFunc

Func _MY_WM_NOTIFY($hWnd, $iMsg, $iwParam, $ilParam)
	#forceref $iMsg, $iwParam
	Switch $hWnd
		Case $sessionGui
			Local $tNMHDR = DllStructCreate($tagNMHDR, $ilParam)
			Local $hWndFrom = DllStructGetData($tNMHDR, "hWndFrom")
			Local $iCode = DllStructGetData($tNMHDR, "Code")
			Local $tInfo
			Switch $hWndFrom
				Case $hLV1
					Switch $iCode
						Case $NM_DBLCLK ; dbl-click on listview
							$tInfo = DllStructCreate($tagNMITEMACTIVATE, $ilParam)
							If DllStructGetData($tInfo, "Index") >= 0 Then
								Local $text = _GUICtrlListView_GetItemText($hLV1, DllStructGetData($tInfo, "Index"), DllStructGetData($tInfo, "SubItem"))
								If $text Then ClipPut($text)
							EndIf
						Case $NM_RCLICK ; right-click on listview
							If _GUICtrlListView_GetItemCount($hLV1) Then
								_GUICtrlMenu_SetItemEnabled($hMenu2, $idSaveSession, True, False)
								_GUICtrlMenu_SetItemEnabled($hMenu2, $idClearSession, True, False)
							Else
								_GUICtrlMenu_SetItemEnabled($hMenu2, $idSaveSession, False, False)
								_GUICtrlMenu_SetItemEnabled($hMenu2, $idClearSession, False, False)
							EndIf
							If _GUICtrlListView_GetSelectedCount($hLV1) Then
								_GUICtrlMenu_SetItemEnabled($hMenu2, $idSaveSelected, True, False)
								_GUICtrlMenu_SetItemEnabled($hMenu2, $idRemoveItems, True, False)
							Else
								_GUICtrlMenu_SetItemEnabled($hMenu2, $idSaveSelected, False, False)
								_GUICtrlMenu_SetItemEnabled($hMenu2, $idRemoveItems, False, False)
							EndIf
							_GUICtrlMenu_TrackPopupMenu($hMenu2, $gui)
							_WinAPI_PostMessage($hLV1, 0, 0, 0)
						Case $LVN_COLUMNCLICK
							$tInfo = DllStructCreate($tagNMLISTVIEW, $ilParam)
							_GUICtrlListView_SortItems($hWndFrom, DllStructGetData($tInfo, "SubItem"))
					EndSwitch
			EndSwitch
	EndSwitch

    Return $GUI_RUNDEFMSG
EndFunc   ;==>WM_NOTIFY

Func _MultiInstance()
	Local $hwnd = WinWait("md5hashHiddenWM_COPYDATA", "", 5) ; find window to send to
	If $hwnd Then
		; create data string
		Local $szData = ""
		For $i = 1 To $CmdLine[0]
			$szData &= $CmdLine[$i] & "|"
		Next
		$szData = StringTrimRight($szData, 1) ; remove trailing "|"
		Local $data = DllStructCreate("wchar[" & StringLen($szData) + 1 & "]")
		DllStructSetData($data, 1, $szData)
		; COPYDATASTRUCT
		Local $MyCDS = DllStructCreate("long;dword;ptr")
		DllStructSetData($MyCDS, 1, 0) ; function identifier
		DllStructSetData($MyCDS, 2, DllStructGetSize($data)) ; size of passed data
		DllStructSetData($MyCDS, 3, DllStructGetPtr($data)) ; ptr to passed data
		; send the message
		DllCall("user32.dll", "int", "SendMessageW", "hwnd", $hwnd, "uint", $WM_COPYDATA, "hwnd", 0, "ptr", DllStructGetPtr($MyCDS))
	EndIf
EndFunc

Func _MY_WM_COPYDATA($hWnd, $Msg, $wParam, $lParam)
	#forceref $hWnd, $Msg, $wParam
	Local $MyCDS = DllStructCreate("long;dword;ptr", $lParam) ; create struct
	Local $data = DllStructCreate("wchar[" & DllStructGetData($MyCDS, 2) / 2 & "]", DllStructGetData($MyCDS, 3)) ; get data
	Local $aHashes = StringSplit(DllStructGetData($data, 1), "|")
	Local $aFiles
	_SearchArray($aHashes, $aFiles)
	If $aFiles[0] Then
		$MasterQueue[0] += 1
		_ArrayAdd($MasterQueue, $aFiles)
		GUICtrlSendToDummy($dummy, 0x10) ; _Action
	EndIf

	Return 1 ; return TRUE
EndFunc

Func _SearchArray(ByRef $aSrc, ByRef $aDest)
	Dim $aDest[1] = [0]
	For $i = 1 To $aSrc[0]
		If StringInStr(FileGetAttrib($aSrc[$i]), "D") Then
			; directory
			_RecurseFolder($aSrc[$i], $aDest)
		Else
			; file
			$aDest[0] += 1
			If $aDest[0] >= UBound($aDest) Then ReDim $aDest[UBound($aDest) * 2]
			$aDest[$aDest[0]] = $aSrc[$i]
		EndIf
	Next
	ReDim $aDest[$aDest[0] + 1]
EndFunc

Func _RecurseFolder($path, ByRef $aFiles)
	If $folderDepth >= 0 And $iDepth > $folderDepth Then Return

	Local $item, $search = FileFindFirstFile($path & "\*.*")
	If $search = -1 Then Return
	While 1
		$item = FileFindNextFile($search)
		If @error Then ExitLoop
		If @extended Then
			; directory
			$iDepth += 1
			_RecurseFolder($path & "\" & $item, $aFiles)
			$iDepth -= 1
		Else
			; file, add to array
			$aFiles[0] += 1
			If $aFiles[0] >= UBound($aFiles) Then ReDim $aFiles[UBound($aFiles) * 2]
			$aFiles[$aFiles[0]] = $path & "\" & $item
		EndIf
	WEnd
	FileClose($search)
EndFunc

Func _CompareCurrentHash()
	If $LastTwoHashes[0][0] == "" Then
		MsgBox (48, "Alert!", "You need to hash a file for this to work")
	Else
		GUICtrlSetData ($showComparisonHash, $LastTwoHashes[0][0])
		GUISetState(@SW_SHOW, $compareView)
	EndIf
EndFunc

Func _CompareButton ()
	If $LastTwoHashes[0][0] = GUICtrlRead($compareHashVal) Then ;= compares two calues case insensitively when used with strings
		MsgBox (1, "Same", "Same")
	Else
		MsgBox (1, "failure", "Not the same")
	EndIf
EndFunc