If (Form event code:C388=On Clicked:K2:4)
	
	SANE SET SCAN OPTION(Form:C1466.scanner.name; "mode"; "Color")
	SANE SET SCAN OPTION(Form:C1466.scanner.name; "resolution"; "300")
	SANE SET SCAN OPTION(Form:C1466.scanner.name; "depth"; "16")
	
	$images:=SANE Scan(Form:C1466.scanner.name; Scanner image type PNG)
	
	$targetFolder:=Folder:C1567(fk desktop folder:K87:19).folder("scaned documents")
	$targetFolder.create()
	$i:=1
	For each ($image; $images)
		WRITE PICTURE FILE:C680($targetFolder.file(String:C10($i)+".png").platformPath; $image)
		$i:=$i+1
	End for each 
	
End if 