If (Form event code:C388=On Clicked:K2:4)
	
	SANE SET SCAN OPTION(Form:C1466.scanner.name; "source"; "ADF Front")
	
	Form:C1466.options.source:=SANE Get scan option(Form:C1466.scanner.name; "source")
	
End if 