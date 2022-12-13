//%attributes = {"invisible":true}
C_PICTURE:C286($image; <>SCAN_IMAGE)

set_option_gray

$images:=SANE Scan(<>DEFAULT_SCANNER; Scanner image type PNG)

For each ($image; $images)
	<>SCAN_IMAGE:=<>SCAN_IMAGE+$image
End for each 

POST OUTSIDE CALL:C329(-1)