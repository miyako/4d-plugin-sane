//%attributes = {}
C_TEXT:C284(<>DEFAULT_SCANNER)
If (<>DEFAULT_SCANNER="")
	ARRAY TEXT:C222($scannerNames; 0)
	$scanners:=SANE Scanners list($scannerNames)
	If ($scanners.length#0)
		<>DEFAULT_SCANNER:=$scanners[0].name
	End if 
End if 

SANE SET SCAN OPTION(<>DEFAULT_SCANNER; "mode"; "Color")
SANE SET SCAN OPTION(<>DEFAULT_SCANNER; "resolution"; "300")
SANE SET SCAN OPTION(<>DEFAULT_SCANNER; "depth"; "16")
SANE SET SCAN OPTION(<>DEFAULT_SCANNER; "source"; "ADF Duplex")

$images:=SANE Scan(<>DEFAULT_SCANNER; Scanner image type PNG)





