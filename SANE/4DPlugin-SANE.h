/* --------------------------------------------------------------------------------
 #
 #	4DPlugin-SANE.h
 #	source generated by 4D Plugin Wizard
 #	Project : SANE
 #	author : miyako
 #	2022/11/28
 #  
 # --------------------------------------------------------------------------------*/

#ifndef PLUGIN_SANE_H
#define PLUGIN_SANE_H

#include "4DPluginAPI.h"

#include "libusb.h"
#include "sane.h"
//#include "sanei.h"
#include "saneopts.h"
#include "png.h"
#include "tiff.h"
#include "jpeglib.h"

#include "C_TEXT.h"
#include "ARRAY_TEXT.h"
#include "C_BLOB.h"
#include "C_LONGINT.h"

#include "json.h"

#include "4DPlugin-JSON.h"

#define BUFFER_SIZE 8192
#define READ_TIMEOUT 30
#define DEFAULT_RESOLUTION 300
#define INCHES_PER_METER (100.0/2.54)

namespace SANE
{
    typedef enum
    {
        image_type_jpg = 0,
        image_type_tif = 1, /* not implemented */
        image_type_png = 2
    }image_type_t;
}

#include <thread>
#include <future>
#include <chrono>

#pragma mark -

void SANE_SCANNERS_LIST(PA_PluginParameters params);
void SANE_Scan(PA_PluginParameters params);
void SANE_SCAN_OPTION_VALUES(PA_PluginParameters params);
void SANE_SET_SCAN_OPTION(PA_PluginParameters params);
void SANE_Get_scan_option(PA_PluginParameters params);

#endif /* PLUGIN_SANE_H */
