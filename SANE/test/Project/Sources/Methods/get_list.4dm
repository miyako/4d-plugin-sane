//%attributes = {"invisible":true}
C_TEXT:C284(<>DEFAULT_SCANNER)

If (<>DEFAULT_SCANNER="")
	
	ARRAY TEXT:C222($scanners; 0)
	SANE SCANNERS LIST($scanners)
	
	If (Size of array:C274($scanners)#0)
		$json:=$scanners{0}
		ARRAY OBJECT:C1221($scannerInfos; 0)
		JSON PARSE ARRAY:C1219($json; $scannerInfos)
		<>DEFAULT_SCANNER:=$scanners{1}
	End if 
	
End if 

POST OUTSIDE CALL:C329(-1)