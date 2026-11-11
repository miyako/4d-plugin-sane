$event:=FORM Event:C1606

Case of 
	: ($event.code=On Load:K2:1)
		
		If (Form:C1466.scanner=Null:C1517)
			ARRAY TEXT:C222($scannerNames; 0)
			$scanners:=SANE Scanners list($scannerNames)
			If ($scanners.length#0)
				Form:C1466.scanner:=$scanners[0]
				Form:C1466.options:=New object:C1471
				Form:C1466.options.source:=SANE Get scan option(Form:C1466.scanner.name; "source")
				ARRAY TEXT:C222($options; 0)
				Form:C1466.option_values:=SANE Scan option values(Form:C1466.scanner.name; $options)
			End if 
		End if 
		
End case 