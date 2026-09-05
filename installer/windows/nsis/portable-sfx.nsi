Unicode true
RequestExecutionLevel user
CRCCheck force
SetCompressor /FINAL /SOLID lzma
SetCompressorDictSize 64

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"

!ifndef PRODUCT_VERSION
  !error "PRODUCT_VERSION is required"
!endif
!ifndef PAYLOAD_DIR
  !error "PAYLOAD_DIR is required"
!endif
!ifndef OUTPUT_FILE
  !error "OUTPUT_FILE is required"
!endif
!ifndef ICON_FILE
  !error "ICON_FILE is required"
!endif

!define PRODUCT_NAME "DB Browser for SQLCipher"
!define APP_FILE "DB Browser for SQLCipher.exe"

Name "${PRODUCT_NAME} ${PRODUCT_VERSION} portable"
Caption "Extract ${PRODUCT_NAME} ${PRODUCT_VERSION}"
OutFile "${OUTPUT_FILE}"
Icon "${ICON_FILE}"
InstallDir "$EXEDIR\${PRODUCT_NAME}-${PRODUCT_VERSION}"
ShowInstDetails show
BrandingText "${PRODUCT_NAME} portable"

VIProductVersion "${PRODUCT_VERSION}.0"
VIAddVersionKey /LANG=1033 "ProductName" "${PRODUCT_NAME} portable"
VIAddVersionKey /LANG=1033 "FileDescription" "${PRODUCT_NAME} portable self-extractor"
VIAddVersionKey /LANG=1033 "FileVersion" "${PRODUCT_VERSION}"
VIAddVersionKey /LANG=1033 "ProductVersion" "${PRODUCT_VERSION}"
VIAddVersionKey /LANG=1033 "CompanyName" "DB Browser for SQLite Team"
VIAddVersionKey /LANG=1033 "LegalCopyright" "DB Browser for SQLite Team"

!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!define MUI_PAGE_CUSTOMFUNCTION_LEAVE ValidateDirectoryPage
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_FILE}"
!define MUI_FINISHPAGE_RUN_TEXT "Run ${PRODUCT_NAME}"
!define MUI_FINISHPAGE_RUN_NOTCHECKED
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_LANGUAGE "English"

Var StagingDir
Var StagingCreated
Var ExtractionCode
Var ParentDir
Var ValidationMessage
Var ValidationCode
Var TargetExisted

!macro RejectPathTree BASE_PATH
  StrLen $2 "${BASE_PATH}"
  StrCpy $3 "$INSTDIR" $2
  ${If} $3 == "${BASE_PATH}"
    ${If} "$INSTDIR" == "${BASE_PATH}"
      Goto target_forbidden
    ${EndIf}
    StrCpy $4 "$INSTDIR" 1 $2
    ${If} $4 == "\"
      Goto target_forbidden
    ${EndIf}
  ${EndIf}
!macroend

Function ValidateTarget
  StrCpy $ValidationMessage ""
  StrCpy $ValidationCode "0"
  StrCpy $TargetExisted "0"

  IfFileExists "$INSTDIR\." normalize_existing_target normalize_new_target

normalize_existing_target:
  GetFullPathName $0 "$INSTDIR"
  StrCmp $0 "" target_invalid
  StrCpy $INSTDIR "$0"
  Goto target_normalized

normalize_new_target:
  ${GetParent} "$INSTDIR" $5
  ${GetFileName} "$INSTDIR" $6
  StrCmp $5 "" target_invalid
  StrCmp $6 "" target_invalid
  StrCmp $6 "." target_invalid
  StrCmp $6 ".." target_invalid
  GetFullPathName $0 "$5"
  StrCmp $0 "" target_invalid
  StrCpy $INSTDIR "$0\$6"

target_normalized:

  ${GetRoot} "$INSTDIR" $1
  StrCmp $1 "" target_invalid
  StrCmp "$INSTDIR" "$1" target_root

  !insertmacro RejectPathTree "$WINDIR"
  !insertmacro RejectPathTree "$SYSDIR"
  !insertmacro RejectPathTree "$PROGRAMFILES"
  !insertmacro RejectPathTree "$COMMONFILES"
  ${If} ${RunningX64}
    !insertmacro RejectPathTree "$PROGRAMFILES64"
    !insertmacro RejectPathTree "$COMMONFILES64"
  ${EndIf}

  IfFileExists "$INSTDIR\." target_directory
  IfFileExists "$INSTDIR" target_file target_valid

target_directory:
  StrCpy $TargetExisted "1"
  ClearErrors
  FindFirst $0 $1 "$INSTDIR\*"
  IfErrors target_valid

target_find_loop:
  StrCmp $1 "." target_find_next
  StrCmp $1 ".." target_find_next
  FindClose $0
  Goto target_not_empty

target_find_next:
  ClearErrors
  FindNext $0 $1
  IfErrors target_find_done target_find_loop

target_find_done:
  FindClose $0
  Goto target_valid

target_invalid:
  StrCpy $ValidationMessage "Choose a valid extraction directory."
  StrCpy $ValidationCode "21"
  Return

target_root:
  StrCpy $ValidationMessage "A drive or network-share root cannot be used. Choose a new empty subdirectory."
  StrCpy $ValidationCode "22"
  Return

target_forbidden:
  StrCpy $ValidationMessage "Windows and Program Files locations cannot be used. Choose a user-writable directory."
  StrCpy $ValidationCode "23"
  Return

target_file:
  StrCpy $ValidationMessage "The selected path is an existing file. Choose a new empty directory."
  StrCpy $ValidationCode "24"
  Return

target_not_empty:
  StrCpy $ValidationMessage "The selected directory is not empty. Choose a new empty directory."
  StrCpy $ValidationCode "25"
  Return

target_valid:
  StrCpy $ValidationMessage ""
  StrCpy $ValidationCode "0"
FunctionEnd

Function ValidateDirectoryPage
  Call ValidateTarget
  StrCmp "$ValidationMessage" "" directory_valid
  MessageBox MB_OK|MB_ICONSTOP "$ValidationMessage"
  Abort

directory_valid:
FunctionEnd

Section "Extract" SEC_EXTRACT
  Call ValidateTarget
  StrCmp "$ValidationMessage" "" extraction_target_valid

  IfSilent silent_target_invalid interactive_target_invalid

interactive_target_invalid:
  MessageBox MB_OK|MB_ICONSTOP "$ValidationMessage"

silent_target_invalid:
  SetErrorLevel $ValidationCode
  Quit

extraction_target_valid:
  StrCpy $ExtractionCode "31"
  ${GetParent} "$INSTDIR" $ParentDir
  StrCmp $ParentDir "" extraction_failed

  StrCpy $ExtractionCode "32"
  ClearErrors
  CreateDirectory "$ParentDir"
  IfErrors extraction_failed

  StrCpy $StagingCreated "0"
  StrCpy $StagingDir "$INSTDIR.__sqlitebrowser_extracting"
  StrCpy $ExtractionCode "33"
  IfFileExists "$StagingDir\." extraction_failed
  StrCpy $ExtractionCode "34"
  IfFileExists "$StagingDir" extraction_failed

  StrCpy $ExtractionCode "35"
  ClearErrors
  CreateDirectory "$StagingDir"
  IfErrors extraction_failed
  StrCpy $StagingCreated "1"

  StrCpy $ExtractionCode "36"
  SetOutPath "$StagingDir"
  ClearErrors
  File /r "${PAYLOAD_DIR}\*.*"
  IfErrors extraction_failed

  StrCpy $ExtractionCode "37"
  ClearErrors
  FileOpen $0 "$StagingDir\.sqlitebrowser-extract-complete" w
  IfErrors extraction_failed
  FileWrite $0 "${PRODUCT_VERSION}$\r$\n"
  FileClose $0
  StrCpy $ExtractionCode "38"
  ClearErrors
  Delete "$StagingDir\.sqlitebrowser-extract-complete"
  IfErrors extraction_failed

  StrCmp "$TargetExisted" "1" 0 publish_staging
  StrCpy $ExtractionCode "39"
  ClearErrors
  RMDir "$INSTDIR"
  IfErrors extraction_failed

publish_staging:
  StrCpy $ExtractionCode "40"
  SetOutPath "$ParentDir"
  ClearErrors
  Rename "$StagingDir" "$INSTDIR"
  IfErrors extraction_failed
  StrCpy $StagingDir ""
  SetErrorLevel 0
  Goto extraction_done

extraction_failed:
  StrCmp "$ParentDir" "" cleanup_staging
  SetOutPath "$ParentDir"

cleanup_staging:
  StrCmp "$StagingCreated" "1" 0 +2
  RMDir /r "$StagingDir"
  IfSilent silent_extraction_failed interactive_extraction_failed

interactive_extraction_failed:
  MessageBox MB_OK|MB_ICONSTOP "Extraction failed. No existing target directory was overwritten."

silent_extraction_failed:
  SetErrorLevel $ExtractionCode
  Quit

extraction_done:
SectionEnd
