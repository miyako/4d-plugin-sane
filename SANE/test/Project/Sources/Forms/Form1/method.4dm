$event:=Form event code:C388

Case of 
	: ($event=On Load:K2:1)
		
		SET TIMER:C645(-1)
		
		C_PICTURE:C286(<>SCAN_IMAGE)
		<>SCAN_IMAGE:=<>SCAN_IMAGE*0
		
	: ($event=On Timer:K2:25)
		
		SET TIMER:C645(0)
		
		HIDE PROCESS:C324(New process:C317("get_list"; 0; "$get_list"))
		
	: ($event=On Unload:K2:2)
		
End case 