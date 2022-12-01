//%attributes = {"invisible":true}
C_PICTURE:C286($image; <>SCAN_IMAGE)

set_option_gray

$image:=SANE Scan(<>DEFAULT_SCANNER; Scanner image type PNG)

<>SCAN_IMAGE:=<>SCAN_IMAGE+$image

POST OUTSIDE CALL:C329(-1)