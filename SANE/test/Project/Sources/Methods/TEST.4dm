//%attributes = {}
//ARRAY TEXT($scannerNames; 0)
//$scanners:=SANE Scanners list($scannerNames)

$images:=SANE Scan("fujitsu:fi-6130dj:13865"; Scanner image type PNG)




ARRAY TEXT:C222($options; 0)
SANE SCAN OPTION VALUES("fujitsu:fi-6130dj:13865"; $options)
