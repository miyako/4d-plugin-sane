//%attributes = {"invisible":true}
get_list

ARRAY TEXT:C222($options; 0)
SANE SCAN OPTION VALUES(<>DEFAULT_SCANNER; $options)

If (Size of array:C274($options)#0)
	$json:=$options{0}
	ARRAY OBJECT:C1221($optionInfos; 0)
	JSON PARSE ARRAY:C1219($json; $optionInfos)
	
	ARRAY TEXT:C222($values; 0)
	
	For ($i; 1; Size of array:C274($options))
		$value:=SANE Get scan option(<>DEFAULT_SCANNER; $options{$i})
		APPEND TO ARRAY:C911($values; $value)
	End for 
	
End if 