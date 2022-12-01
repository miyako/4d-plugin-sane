//%attributes = {"invisible":true}
get_list

ARRAY TEXT:C222($options; 0)
SANE SCAN OPTION VALUES(<>DEFAULT_SCANNER; $options)

If (Size of array:C274($options)#0)
	$json:=$options{0}
	ARRAY OBJECT:C1221($optionInfos; 0)
	JSON PARSE ARRAY:C1219($json; $optionInfos)
	
	If (-1#Find in array:C230($options; "mode"))
		$mode:=SANE Get scan option(<>DEFAULT_SCANNER; "mode")
		SANE SET SCAN OPTION(<>DEFAULT_SCANNER; "mode"; "Gray")
		$mode:=SANE Get scan option(<>DEFAULT_SCANNER; "mode")
	End if 
	
	If (-1#Find in array:C230($options; "resolution"))
		$resolution:=SANE Get scan option(<>DEFAULT_SCANNER; "resolution")
		SANE SET SCAN OPTION(<>DEFAULT_SCANNER; "resolution"; "600")
		$resolution:=SANE Get scan option(<>DEFAULT_SCANNER; "resolution")
	End if 
	
End if 