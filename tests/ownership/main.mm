#include "4DPluginAPI.h"
#include "PrivateTypes.h"
#include "EntryPoints.h"
#include "C_TEXT.h"
#include "ARRAY_TEXT.h"
#include "C_BLOB.h"
#include "C_LONGINT.h"
#include "4DPlugin-JSON.h"
#include "sane.h"
#include "png.h"
#include "jpeglib.h"
#import <objc/runtime.h>
#include <map>
#include <set>
#include <stdexcept>
#include <type_traits>
#include <cstring>
#include <iostream>

extern "C" CFURLRef CFURLCreateWithFileSystemPath(CFAllocatorRef, CFStringRef,
                                                CFURLPathStyle, Boolean) {
    throw std::runtime_error("path operations prohibited");
}
extern "C" CFStringRef CFURLCopyFileSystemPath(CFURLRef, CFURLPathStyle) {
    throw std::runtime_error("path operations prohibited");
}
extern "C" int setenv(const char*, const char*, int) {
    throw std::runtime_error("environment operations prohibited");
}
extern "C" void CGContextScaleCTM(CGContextRef, CGFloat, CGFloat) {
    throw std::runtime_error("drawing operations prohibited");
}
extern "C" void CGContextTranslateCTM(CGContextRef, CGFloat, CGFloat) {
    throw std::runtime_error("drawing operations prohibited");
}

namespace {
using Text = std::basic_string<PA_Unichar>;
std::map<PA_Unichar*, Text> strings;
std::map<PA_Handle, size_t> handles;
std::set<PA_Picture> pictures;
std::map<void*, int> refs;
std::map<void*, std::vector<PA_Variable>> elements;
std::map<void*, Text> parsed;
PA_Variable property = {};
int failureCommand = 0, commandMode = 0, invalidInspections = 0;
bool failProperty = false, failResize = false, missingProperty = false;
bool failNewHandle = false;
bool failStringRead = false, failPicture = false, failElement = false;
int failCreateAfter = -1;
int checks = 0, failures = 0, starts = 0, readStep = 0;
std::string fixture = "ASCII";
Text lastJson;

void check(bool ok, const std::string& name) {
    ++checks;
    if (!ok) { ++failures; std::cerr << "FAIL " << name << "\n"; }
    else std::cout << "PASS " << name << "\n";
}
void require(bool ok) {
    if (!ok) throw std::runtime_error("invalid ownership or unexpected synthetic operation");
}
PA_Unistring make(const PA_Unichar* p) {
    Text text(p ? p : reinterpret_cast<const PA_Unichar*>(u""));
    PA_Unistring s = {};
    s.fLength = static_cast<PA_long32>(text.size());
    s.fString = new PA_Unichar[text.size() + 1];
    std::copy(text.begin(), text.end(), s.fString);
    s.fString[text.size()] = 0;
    strings.emplace(s.fString, text);
    return s;
}
void dispose(PA_Unistring s) {
    if (s.fString) { require(strings.erase(s.fString) == 1); delete[] s.fString; }
}
void clear(PA_Variable& v);
void release(void* p) {
    if (!p) return;
    require(refs.count(p) && refs[p] > 0);
    if (--refs[p] == 0) {
        if (elements.count(p)) {
            for (auto& v : elements[p]) clear(v);
            elements.erase(p);
        }
        parsed.erase(p); refs.erase(p); delete static_cast<int*>(p);
    }
}
void* reference() { void* p = new int(0); refs[p] = 1; return p; }
void clear(PA_Variable& v) {
    switch (PA_GetVariableKind(v)) {
        case eVK_Unistring: dispose(v.uValue.fString); break;
        case eVK_Picture:
            if (v.uValue.fPicture) {
                require(pictures.erase(v.uValue.fPicture) == 1);
                delete static_cast<int*>(v.uValue.fPicture);
            }
            break;
        case eVK_Object: release(v.uValue.fObject); break;
        case eVK_Collection: release(v.uValue.fCollection); break;
        case eVK_Blob:
            if (v.uValue.fBlob.fHandle) {
                auto h = v.uValue.fBlob.fHandle;
                require(handles.erase(h) == 1); free(*h); delete h;
            }
            break;
        case eVK_ArrayUnicode:
            if (v.uValue.fArray.fData) {
                auto h = v.uValue.fArray.fData;
                auto p = reinterpret_cast<PA_Unistring*>(*h);
                require(handles.at(h) >= (v.uValue.fArray.fNbElements + 1) * sizeof(*p));
                for (int i = 0; i <= v.uValue.fArray.fNbElements; ++i) dispose(p[i]);
                free(*h); handles.erase(h); delete h;
            }
            break;
        default: break;
    }
    v = {}; v.fType = eVK_Undefined;
}
PA_Variable copy(PA_Variable v) {
    if (PA_GetVariableKind(v) == eVK_Unistring)
        v.uValue.fString = make(v.uValue.fString.fString);
    if (v.fType == eVK_Object && v.uValue.fObject) ++refs.at(v.uValue.fObject);
    if (v.fType == eVK_Collection && v.uValue.fCollection) ++refs.at(v.uValue.fCollection);
    if (v.fType == eVK_Picture && v.uValue.fPicture) {
        v.uValue.fPicture = new int(0); pictures.insert(v.uValue.fPicture);
    }
    return v;
}
void engine(short selector, EngineBlock* eb) {
    eb->fError = eER_NoErr;
    switch (selector) {
        case EX_YIELD_ABSOLUTE: break;
        case EX_CREATE_UNISTRING:
            if (failCreateAfter == 0) {
                eb->fUniString1 = {}; eb->fError = -1; break;
            }
            if (failCreateAfter > 0) --failCreateAfter;
            eb->fUniString1 = make(reinterpret_cast<PA_Unichar*>(eb->fHandle)); break;
        case EX_DISPOSE_UNISTRING: dispose(eb->fUniString1); break;
        case EX_SET_UNISTRING: {
            auto s = make(reinterpret_cast<PA_Unichar*>(eb->fHandle));
            dispose(eb->fUniString1); eb->fUniString1 = s; break;
        }
        case EX_CLEAR_VARIABLE: {
            auto v = static_cast<PA_Variable*>(eb->fPtr1);
            if ((failProperty || failureCommand) && v->fType == 0) ++invalidInspections;
            clear(*v); break;
        }
        case EX_VARIABLE_TO_STRING: {
            auto v = reinterpret_cast<PA_Variable*>(eb->fHandle);
            if (failStringRead) { eb->fError = -1; eb->fUniString1 = {}; break; }
            if (failProperty || failureCommand || PA_GetVariableKind(*v) != eVK_Unistring) {
                ++invalidInspections; eb->fUniString1 = {}; break;
            }
            require(strings.count(v->uValue.fString.fString));
            eb->fUniString1 = v->uValue.fString; break;
        }
        case EX_HANDLE_MANAGER: {
            auto h = eb->fHandle;
            switch (eb->fParam1) {
                case 1:
                    if (failNewHandle) { eb->fHandle = nullptr; eb->fError = -1; break; }
                    h = new char*;
                    *h = static_cast<char*>(calloc(1, std::max<sLONG_PTR>(1, eb->fParam2)));
                    handles[h] = eb->fParam2; eb->fHandle = h; break;
                case 2:
                    require(handles.erase(h) == 1); free(*h); delete h; break;
                case 3: {
                    if (failResize) { eb->fError = -1; eb->fParam3 = 0; break; }
                    size_t old = handles.at(h);
                    *h = static_cast<char*>(realloc(*h, std::max<sLONG_PTR>(1, eb->fParam2)));
                    if (static_cast<size_t>(eb->fParam2) > old)
                        memset(*h + old, 0, eb->fParam2 - old);
                    handles[h] = eb->fParam2; eb->fParam3 = 1; break;
                }
                case 4: eb->fParam2 = handles.at(h); break;
                case 5: eb->fParam3 = reinterpret_cast<sLONG_PTR>(*h); break;
                case 6: break;
                default: throw std::runtime_error("unexpected handle operation");
            }
            break;
        }
        case EX_CREATE_PICTURE:
            if (failPicture) { eb->fError = -1; eb->fPicture = nullptr; break; }
            if (eb->fParam1) require(eb->fParam1 == 3 && !memcmp(eb->fPtr1, "PNG", 3));
            eb->fPicture = new int(0); pictures.insert(eb->fPicture); break;
        case EX_DISPOSE_PICTURE:
            require(pictures.erase(eb->fPicture) == 1);
            delete static_cast<int*>(eb->fPicture); break;
        case EX_DUPLICATE_PICTURE:
            require(pictures.count(eb->fPicture) && eb->fParam1 == 1);
            eb->fPicture = new int(0); pictures.insert(eb->fPicture); break;
        case EX_GET_OBJ_VALUE:
            if (failProperty) {
                memset(eb->fPtr2, 0, sizeof(PA_Variable)); eb->fError = -1;
            } else if (eb->fShort == eVK_Collection && eb->fLongint == -1) {
                PA_SetLongintVariable(static_cast<PA_Variable*>(eb->fPtr2),
                                     elements[eb->fPtr1].size());
            } else *static_cast<PA_Variable*>(eb->fPtr2) = copy(property);
            break;
        case EX_SET_OBJ_VALUE:
            if (failElement) { eb->fError = -1; break; }
            if (eb->fShort == eVK_Collection) {
                auto& vs = elements[eb->fPtr1];
                require(eb->fLongint == vs.size());
                vs.push_back(copy(*static_cast<PA_Variable*>(eb->fPtr2)));
            } else {
                clear(property); property = copy(*static_cast<PA_Variable*>(eb->fPtr2));
            }
            break;
        case EX_COPY_VARIABLE:
            *static_cast<PA_Variable*>(eb->fPtr2) = copy(*static_cast<PA_Variable*>(eb->fPtr1));
            break;
        case EX_EXECUTE_COMMAND_BY_ID: {
            auto result = static_cast<PA_Variable*>(eb->fPtr2);
            if (failureCommand == eb->fParam1) {
                memset(result, 0, sizeof(*result)); eb->fError = -1; break;
            }
            auto args = static_cast<PA_Variable**>(eb->fPtr1);
            switch (eb->fParam1) {
                case 1231: PA_SetBooleanVariable(result, !missingProperty); break;
                case 1472: PA_SetCollectionVariable(result, reference()); break;
                case 1218:
                    lastJson = args[0]->uValue.fString.fString;
                    if (commandMode == 1) *result = copy(property);
                    else {
                        auto p = reference(); parsed[p] = lastJson;
                        PA_SetCollectionVariable(result, p);
                    }
                    break;
                case 1217:
                    if (commandMode == 1) *result = copy(property);
                    else {
                        auto s = make(reinterpret_cast<const PA_Unichar*>(u"{\"ok\":true}"));
                        PA_SetStringVariable(result, &s);
                    }
                    break;
                default: throw std::runtime_error("unexpected command ID");
            }
            break;
        }
        // No real process scheduling: worker threads contain only memory stubs.
        case EX_CURRENT_PROCESS_NUMBER: eb->fParam1 = 1; break;
        case EX_PUT_PROCESS_TO_SLEEP: break;
        case EX_GET_PROCESS_INFO:
            eb->fUString[0] = '$'; eb->fUString[1] = 'x';
            eb->fUString[2] = 'x'; eb->fUString[3] = 0;
            eb->fParam2 = 0; eb->fParam3 = 0; break;
        default: throw std::runtime_error("unexpected engine selector " + std::to_string(selector));
    }
}
void reset() {
    clear(property);
    // Measure leaks first, then isolate baseline cases without hiding findings.
    for (auto& s : strings) delete[] s.first;
    strings.clear();
    for (auto p : pictures) delete static_cast<int*>(p);
    pictures.clear();
    for (auto p : refs) delete static_cast<int*>(p.first);
    refs.clear(); elements.clear(); parsed.clear();
    require(handles.empty());
}
void balance(const std::string& name) {
    clear(property);
    check(strings.empty() && pictures.empty() && refs.empty() && handles.empty(), name);
    reset();
}
Text text(const char* s) {
    NSString* str = [NSString stringWithUTF8String:s];
    Text out([str length], 0);
    if (!out.empty()) [str getCharacters:&out[0] range:NSMakeRange(0, out.size())];
    return out;
}
void dispatch(int command, std::initializer_list<void*> args, void* result = nullptr) {
    std::vector<uint8_t*> p;
    for (auto arg : args) p.push_back(static_cast<uint8_t*>(arg));
    PluginBlock block = {};
    block.fParameters = p.data(); block.fResult = result;
    FourDPackex(command, block.fParameters, nullptr, result);
}
void denyAppleBoundary(id, SEL, ...) { throw std::runtime_error("external Apple boundary denied"); }
void deny(Class cls, const char* selector, bool classMethod = false) {
    auto m = classMethod ? class_getClassMethod(cls, sel_registerName(selector)) :
                          class_getInstanceMethod(cls, sel_registerName(selector));
    require(m != nullptr);
    method_setImplementation(m, reinterpret_cast<IMP>(denyAppleBoundary));
}
NSTimeInterval syntheticTime(id, SEL) { return 100; }
}

// Every SANE entry point used by the complete plugin resolves here, never libsane.
extern "C" SANE_Status sane_init(SANE_Int* v, SANE_Auth_Callback) { *v = 1; return SANE_STATUS_GOOD; }
extern "C" void sane_exit() {}
extern "C" SANE_Status sane_get_devices(const SANE_Device*** out, SANE_Bool) {
    static SANE_Device device;
    static const SANE_Device* list[] = {&device, nullptr};
    device = {fixture.c_str(), "synthetic vendor", "synthetic model", "fixture"};
    *out = list; return SANE_STATUS_GOOD;
}
extern "C" SANE_Status sane_open(SANE_String_Const name, SANE_Handle* h) {
    require(std::string(name) == fixture); *h = reinterpret_cast<void*>(1); return SANE_STATUS_GOOD;
}
extern "C" void sane_close(SANE_Handle h) { require(h == reinterpret_cast<void*>(1)); }
extern "C" const SANE_Option_Descriptor* sane_get_option_descriptor(SANE_Handle, SANE_Int i) {
    static SANE_Option_Descriptor option;
    if (i > 1) return nullptr;
    option = {}; option.name = i ? fixture.c_str() : "count";
    option.title = "title"; option.desc = "description";
    option.type = SANE_TYPE_STRING; option.size = 32;
    option.cap = SANE_CAP_SOFT_SELECT | SANE_CAP_SOFT_DETECT;
    return &option;
}
extern "C" SANE_Status sane_control_option(SANE_Handle, SANE_Int, SANE_Action action, void* value, SANE_Int*) {
    if (action == SANE_ACTION_GET_VALUE) std::strcpy(static_cast<char*>(value), fixture.c_str());
    else require(std::string(static_cast<char*>(value)) == fixture);
    return SANE_STATUS_GOOD;
}
extern "C" SANE_Status sane_start(SANE_Handle) {
    readStep = 0; return starts++ == 0 ? SANE_STATUS_GOOD : SANE_STATUS_NO_DOCS;
}
extern "C" SANE_Status sane_set_io_mode(SANE_Handle, SANE_Bool) { return SANE_STATUS_GOOD; }
extern "C" SANE_Status sane_get_parameters(SANE_Handle, SANE_Parameters* p) {
    *p = {SANE_FRAME_GRAY, SANE_TRUE, 1, 1, 1, 8}; return SANE_STATUS_GOOD;
}
extern "C" SANE_Status sane_read(SANE_Handle, SANE_Byte* buf, SANE_Int, SANE_Int* len) {
    *len = readStep++ == 0 ? 1 : 0; buf[0] = 127;
    return *len ? SANE_STATUS_GOOD : SANE_STATUS_EOF;
}
extern "C" void sane_cancel(SANE_Handle) {}

// Opaque PNG boundary emits a three-byte token, never a real encoded image.
struct png_struct_def { jmp_buf jump; void* io; png_rw_ptr write; };
struct png_info_def {};
extern "C" png_structp png_create_write_struct(png_const_charp, png_voidp, png_error_ptr, png_error_ptr) {
    return new png_struct_def();
}
extern "C" png_infop png_create_info_struct(png_const_structrp) { return new png_info_def(); }
extern "C" void png_destroy_write_struct(png_structpp p, png_infopp i) {
    if (i) { delete *i; *i = nullptr; } delete *p; *p = nullptr;
}
extern "C" jmp_buf* png_set_longjmp_fn(png_structrp p, png_longjmp_ptr, size_t) { return &p->jump; }
extern "C" void png_set_write_fn(png_structrp p, png_voidp io, png_rw_ptr w, png_flush_ptr) {
    p->io = io; p->write = w;
}
extern "C" png_voidp png_get_io_ptr(png_const_structrp p) { return p->io; }
extern "C" void png_set_IHDR(png_const_structrp, png_inforp, png_uint_32 w, png_uint_32 h,
                           int depth, int, int, int, int) { require(w == 1 && h == 1 && depth == 8); }
extern "C" void png_set_pHYs(png_const_structrp, png_inforp, png_uint_32, png_uint_32, int) {}
extern "C" void png_write_info(png_structrp, png_const_inforp) {}
extern "C" void png_write_row(png_structrp, png_const_bytep p) { require(p[0] == 127); }
extern "C" void png_write_end(png_structrp p, png_inforp) {
    unsigned char token[] = {'P', 'N', 'G'}; p->write(p, token, sizeof(token));
}
extern "C" jpeg_error_mgr* jpeg_std_error(jpeg_error_mgr*) { throw std::runtime_error("JPEG denied"); }
extern "C" void jpeg_CreateCompress(j_compress_ptr, int, size_t) { throw std::runtime_error("JPEG denied"); }
extern "C" void jpeg_destroy_compress(j_compress_ptr) { throw std::runtime_error("JPEG denied"); }
extern "C" void jpeg_set_defaults(j_compress_ptr) { throw std::runtime_error("JPEG denied"); }
extern "C" void jpeg_set_quality(j_compress_ptr, int, boolean) { throw std::runtime_error("JPEG denied"); }
extern "C" void jpeg_simple_progression(j_compress_ptr) { throw std::runtime_error("JPEG denied"); }
extern "C" void jpeg_start_compress(j_compress_ptr, boolean) { throw std::runtime_error("JPEG denied"); }
extern "C" JDIMENSION jpeg_write_scanlines(j_compress_ptr, JSAMPARRAY, JDIMENSION) { throw std::runtime_error("JPEG denied"); }
extern "C" void jpeg_finish_compress(j_compress_ptr) { throw std::runtime_error("JPEG denied"); }
extern "C" void jpeg_abort_compress(j_compress_ptr) { throw std::runtime_error("JPEG denied"); }

int main(int argc, char** argv) {
    @autoreleasepool {
        deny([NSBundle class], "bundleWithIdentifier:", true);
        method_setImplementation(class_getClassMethod([NSDate class],
                                 @selector(timeIntervalSinceReferenceDate)),
                                 reinterpret_cast<IMP>(syntheticTime));
        deny([NSURL class], "initWithString:");
        gCall4D = engine; property.fType = eVK_Undefined;
        if (argc == 2 && (std::string(argv[1]) == "--resize-failure" ||
                          std::string(argv[1]) == "--dispatcher-resize-failure")) {
            PA_Variable a = PA_CreateVariable(eVK_ArrayUnicode);
            uint8_t* args[] = {reinterpret_cast<uint8_t*>(&a)};
            ARRAY_TEXT t; t.setSize(9); failResize = true;
            bool reported = false;
            PA_CollectionRef result = nullptr;
            bool exported = std::string(argv[1]) == "--dispatcher-resize-failure";
            if (exported) {
                dispatch(1, {&a}, &result);
                reported = refs.count(result) && elements[result].empty();
            } else {
                try { t.toParamAtIndex(args, 1); }
                catch (const std::runtime_error& e) {
                    reported = std::string(e.what()).find("-1") != std::string::npos;
                }
            }
            failResize = false;
            check(reported && a.uValue.fArray.fNbElements == 0,
                  "resize error reported before insertion and preserves owner metadata");
            PA_ClearVariable(&a);
            if (result) PA_DisposeCollection(result);
            balance("resize failure owner balance");
            std::cout << "checks=" << checks << " failures=" << failures << "\n";
            return failures ? 1 : 0;
        }
        check(!std::is_copy_constructible<C_TEXT>::value &&
              !std::is_copy_assignable<C_TEXT>::value, "C_TEXT rejects shallow owner copies");
        check(!std::is_copy_constructible<ARRAY_TEXT>::value &&
              !std::is_copy_assignable<ARRAY_TEXT>::value, "ARRAY_TEXT rejects shallow owner copies");
        check(!std::is_copy_constructible<C_BLOB>::value &&
              !std::is_copy_assignable<C_BLOB>::value, "C_BLOB rejects shallow owner copies");
        PA_ObjectRef obj = reinterpret_cast<void*>(1);
        const char* values[] = {"", "ASCII", "\xc3\xa9", "\xf0\x9f\x98\x80"};
        for (const char* value : values) {
            std::string label = std::string("fixture=") + value + " ";
            ob_set_s(obj, "key", value); balance(label + "narrow setter balance");
            ob_set_s(obj, L"key", value);
            CUTF8String got;
            check(ob_get_a(obj, L"key", &got) &&
                  std::string(reinterpret_cast<const char*>(got.data()), got.size()) == value,
                  label + "property UTF8 content");
            balance(label + "property getter balance");
            PA_Unistring input = make(text(value).c_str());
            C_TEXT scalar; uint8_t* in[] = {reinterpret_cast<uint8_t*>(&input)};
            scalar.fromParamAtIndex(in, 1); dispose(input);
            PA_Unistring output = {}; PA_Unistring* result = &output;
            scalar.setReturn(reinterpret_cast<sLONG_PTR*>(&result));
            check(Text(output.fString, output.fLength) == text(value) && output.fString[output.fLength] == 0,
                  label + "scalar copied return");
            dispose(output); balance(label + "scalar balance");
            ARRAY_TEXT array; array.setSize(1); array.appendUTF8String(
                reinterpret_cast<const uint8_t*>(value), std::strlen(value));
            PA_Variable a = PA_CreateVariable(eVK_Undefined);
            uint8_t* args[] = {reinterpret_cast<uint8_t*>(&a)};
            array.toParamAtIndex(args, 1);
            auto first = PA_GetStringInArray(a, 1);
            check(Text(first.fString, first.fLength) == text(value) && first.fString[first.fLength] == 0,
                  label + "array content");
            ARRAY_TEXT copied; copied.fromParamAtIndex(args, 1);
            array.toParamAtIndex(args, 1);
            copied.toParamAtIndex(args, 1);
            PA_ClearVariable(&a); balance(label + "array reuse balance");
        }
        for (int kind : {eVK_Unistring, eVK_Object, eVK_Collection, eVK_Picture}) {
            property = PA_CreateVariable(static_cast<PA_VariableKind>(kind));
            if (kind == eVK_Object) PA_SetObjectVariable(&property, reference());
            if (kind == eVK_Collection) PA_SetCollectionVariable(&property, reference());
            CUTF8String got;
            ob_get_a(obj, L"key", &got); balance("getter text/mismatch kind=" + std::to_string(kind));
            property = PA_CreateVariable(static_cast<PA_VariableKind>(kind));
            if (kind == eVK_Object) PA_SetObjectVariable(&property, reference());
            if (kind == eVK_Collection) PA_SetCollectionVariable(&property, reference());
            ob_get_b(obj, L"key"); balance("getter bool/mismatch kind=" + std::to_string(kind));
            property = PA_CreateVariable(static_cast<PA_VariableKind>(kind));
            if (kind == eVK_Object) PA_SetObjectVariable(&property, reference());
            if (kind == eVK_Collection) PA_SetCollectionVariable(&property, reference());
            ob_get_n(obj, L"key"); balance("getter number/mismatch kind=" + std::to_string(kind));
            for (int getter = 0; getter < 2; ++getter) {
                property = PA_CreateVariable(static_cast<PA_VariableKind>(kind));
                if (kind == eVK_Object) PA_SetObjectVariable(&property, reference());
                if (kind == eVK_Collection) PA_SetCollectionVariable(&property, reference());
                if (getter == 0) {
                    auto p = ob_get_o(obj, L"key");
                    if (p) PA_DisposeObject(p);
                } else {
                    auto p = ob_get_c(obj, L"key");
                    if (p) PA_DisposeCollection(p);
                }
                balance("owned reference getter=" + std::to_string(getter) +
                        " kind=" + std::to_string(kind));
            }
        }
        for (int getter = 0; getter < 5; ++getter) {
            failProperty = true; invalidInspections = 0; bool reported = false;
            try {
                CUTF8String got;
                switch (getter) {
                    case 0: ob_get_a(obj, L"key", &got); break;
                    case 1: ob_get_b(obj, L"key"); break;
                    case 2: ob_get_n(obj, L"key"); break;
                    case 3: ob_get_o(obj, L"key"); break;
                    case 4: ob_get_c(obj, L"key"); break;
                }
            } catch (const std::runtime_error& e) {
                reported = std::string(e.what()).find("-1") != std::string::npos;
            }
            check(reported && invalidInspections == 0,
                  "failed property output not adopted getter=" + std::to_string(getter));
            failProperty = false; balance("failed property key balance");
        }
        for (int command : {1217, 1231}) {
            failureCommand = command; invalidInspections = 0; bool reported = false;
            try {
                CUTF8String got;
                if (command == 1217) ob_stringify(obj, &got);
                else ob_is_defined(obj, L"key");
            } catch (const std::runtime_error& e) {
                reported = std::string(e.what()).find("-1") != std::string::npos;
            }
            check(reported && invalidInspections == 0,
                  "failed method output not adopted command=" + std::to_string(command));
            failureCommand = 0; balance("failed method owner balance");
        }
        ob_set_a(obj, L"key", L"\u00e9\U0001f600");
        balance("wide setter balance");
        CUTF16String native = text("\xc3\xa9\xf0\x9f\x98\x80");
        ob_set_a(obj, L"key", &native);
        CUTF8String nativeGot;
        check(ob_get_a(obj, L"key", &nativeGot) &&
              nativeGot == CUTF8String(reinterpret_cast<const uint8_t*>("\xc3\xa9\xf0\x9f\x98\x80")),
              "native UTF16 setter exact units");
        balance("native UTF16 getter balance");
        ob_set_b(obj, L"key", true);
        check(ob_get_b(obj, L"key"), "boolean getter content"); balance("boolean balance");
        ob_set_n(obj, L"key", 2.5);
        check(ob_get_n(obj, L"key") == 2.5, "real getter content"); balance("real balance");
        ob_set_n(obj, "key", 2.5); balance("narrow real setter balance");
        ob_set_i(obj, L"key", 7); balance("integer setter balance");
        ob_set_0(obj, L"key"); balance("wide null setter balance");
        ob_set_0(obj, "key"); balance("narrow null setter balance");
        ob_set_o(obj, L"key", reference()); balance("wide object setter consuming balance");
        ob_set_o(obj, "key", reference()); balance("narrow object setter consuming balance");
        ob_set_c(obj, L"key", reference()); balance("collection setter consuming balance");
        auto picture = PA_CreatePicture(nullptr, 0);
        ob_set_p(obj, L"key", picture); balance("picture setter consuming balance");
        CUTF8String serialized;
        ob_stringify(obj, &serialized);
        check(serialized == CUTF8String(reinterpret_cast<const uint8_t*>("{\"ok\":true}")),
              "stringify exact UTF8 content"); balance("stringify result balance");
        missingProperty = true;
        check(!ob_is_defined(obj, L"key"), "missing property control");
        missingProperty = false; balance("missing property key balance");
        for (int kind : {eVK_Unistring, eVK_Object, eVK_Collection, eVK_Picture}) {
            property = PA_CreateVariable(static_cast<PA_VariableKind>(kind));
            if (kind == eVK_Object) PA_SetObjectVariable(&property, reference());
            if (kind == eVK_Collection) PA_SetCollectionVariable(&property, reference());
            commandMode = 1; ob_stringify(obj, &serialized); commandMode = 0;
            balance("stringify result/mismatch kind=" + std::to_string(kind));
        }
        {
            PA_Variable a = PA_CreateVariable(eVK_ArrayUnicode);
            PA_Unistring zero = make(text("zero").c_str());
            PA_SetStringInArray(a, 0, &zero);
            check(PA_GetStringInArray(a, 0).fString == zero.fString, "SDK accepts index zero transfer");
            PA_Unistring rejected = make(text("retained").c_str());
            PA_SetStringInArray(a, 1, &rejected);
            check(strings.count(rejected.fString) == 1, "SDK rejected index retains caller owner");
            dispose(rejected); PA_ClearVariable(&a); balance("SDK transfer/rejection balance");
        }
        {
            ARRAY_TEXT a;
            a.appendUTF16String(reinterpret_cast<const PA_Unichar*>(u"old"));
            a.setUTF16StringAtIndex(reinterpret_cast<const PA_Unichar*>(u"new"), 0);
            CUTF16String got; a.copyUTF16StringAtIndex(&got, 0);
            check(a.getSize() == 1 && got == text("new"), "array indexed pointer setter replaces");
            const uint8_t input[] = {'A', 0, 'B'};
            ARRAY_TEXT embedded; embedded.appendUTF8String(input, sizeof(input));
            embedded.copyUTF16StringAtIndex(&got, 0);
            check(got.size() == 3 && got[0] == 'A' && got[1] == 0 && got[2] == 'B',
                  "array conversion preserves explicit UTF8 units");
            CUTF8String back; embedded.copyUTF8StringAtIndex(&back, 0);
            check(back == CUTF8String(input, sizeof(input)), "array conversion explicit UTF8 roundtrip");
        }
        {
            C_BLOB b;
            const uint8_t bytes[] = {1, 2, 3};
            b.setBytes(bytes, sizeof(bytes));
            C_TEXT encoded; b.toHexText(&encoded);
            check(encoded.getUTF16Length() == 6, "blob hex helper content");
            b.fromHexText(&encoded); b.toB64Text(&encoded); b.fromB64Text(&encoded);
            check(b.getBytesLength() == 3 && !memcmp(b.getBytesPtr(), bytes, 3), "blob codecs reuse");
            PA_Handle h = PA_NewHandle(3); auto old = h;
            uint8_t* args[] = {reinterpret_cast<uint8_t*>(&h)};
            failNewHandle = true; bool reported = false;
            try { b.toParamAtIndex(args, 1); }
            catch (const std::runtime_error& e) { reported = std::string(e.what()).find("-1") != std::string::npos; }
            failNewHandle = false;
            check(reported && h == old && handles.count(h), "blob failed replacement preserves caller owner");
            if (handles.count(h)) PA_DisposeHandle(h);
            balance("blob failed replacement balance");
        }
        {
            C_BLOB b; CBytes bytes;
            const uint8_t data[] = {7, 8};
            b.setBytes(data, sizeof(data));
            PA_Handle h = nullptr; uint8_t* args[] = {reinterpret_cast<uint8_t*>(&h)};
            b.toParamAtIndex(args, 1);
            bytes.fromParamAtIndex(args, 1);
            check(bytes.getBytesLength() == sizeof(data) && !memcmp(bytes.getBytesPtr(), data, sizeof(data)),
                  "blob actual handle parameter roundtrip");
            PA_DisposeHandle(h); h = nullptr;
            bytes.fromParamAtIndex(args, 1);
            check(bytes.getBytesLength() == 0, "blob empty parameter clears reused buffer");
            sLONG_PTR returned = 0;
            b.setReturn(&returned); PA_DisposeHandle(reinterpret_cast<PA_Handle>(returned));
            balance("blob return owner balance");
            C_LONGINT n; sLONG_PTR input = 12, output = 0;
            uint8_t* ints[] = {reinterpret_cast<uint8_t*>(&input)};
            n.fromParamAtIndex(ints, 1); n.setIntValue(n.getIntValue() + 1);
            n.toParamAtIndex(ints, 1); n.setReturn(&output);
            check(input == 13 && output == 13, "integer wrapper parameter/return control");
        }
        for (int helper = 0; helper < 2; ++helper) {
            property = PA_CreateVariable(eVK_Unistring); failStringRead = true;
            bool reported = false;
            try {
                CUTF8String got;
                if (helper == 0) ob_get_a(obj, L"key", &got);
                else ob_stringify(obj, &got);
            } catch (const std::runtime_error& e) {
                reported = std::string(e.what()).find("-1") != std::string::npos;
            }
            failStringRead = false;
            check(reported, "failed string conversion reported helper=" + std::to_string(helper));
            balance("failed string conversion owner balance");
        }
        for (int point : {0, 1, 2}) {
            bool reported = false;
            failCreateAfter = point < 2 ? point : -1;
            failElement = point == 2;
            try { ob_set_s(obj, "key", "value"); }
            catch (const std::runtime_error& e) {
                reported = std::string(e.what()).find("-1") != std::string::npos;
            }
            failCreateAfter = -1; failElement = false;
            check(reported, "setter reports creation/property error point=" + std::to_string(point));
            balance("setter failed input/key balance");
        }
        {
            PA_Unistring raw = make(text("raw").c_str());
            property = {}; property.fType = 0; property.uValue.fString = raw;
            CUTF8String got;
            check(ob_get_a(obj, L"key", &got) &&
                  got == CUTF8String(reinterpret_cast<const uint8_t*>("raw")),
                  "successful raw kind zero normalizes as text");
            balance("successful raw kind zero balance");
        }
        {
            ARRAY_TEXT source; source.setSize(2);
            PA_Variable a = PA_CreateVariable(eVK_ArrayUnicode);
            uint8_t* args[] = {reinterpret_cast<uint8_t*>(&a)};
            failCreateAfter = 0; bool reported = false;
            try { source.toParamAtIndex(args, 1); }
            catch (const std::runtime_error& e) {
                reported = std::string(e.what()).find("-1") != std::string::npos;
            }
            failCreateAfter = -1;
            check(reported, "array string allocation failure reported");
            PA_ClearVariable(&a); balance("array partial output remains caller-cleanable");
            a = PA_CreateVariable(eVK_Longint);
            source.toParamAtIndex(args, 1);
            check(a.fType == eVK_Longint, "array rejects scalar destination without consuming");
            PA_ClearVariable(&a); balance("array rejected destination balance");
            a = {}; a.fType = eVK_ArrayUnicode;
            reported = false;
            try { source.toParamAtIndex(args, 1); }
            catch (const std::runtime_error&) { reported = true; }
            check(reported, "array null data explicitly rejected");
            balance("array null data has no leaked strings");
        }
        // Both actual exported array consumers, with only synthetic devices.
        for (const char* value : values) {
            fixture = value;
            PA_Variable a = PA_CreateVariable(eVK_Undefined);
            PA_CollectionRef result = nullptr;
            dispatch(1, {&a}, &result);
            auto name = PA_GetStringInArray(a, 1);
            check(Text(name.fString, name.fLength) == text(value), "dispatcher scanners exact name");
            check(refs.count(result) && parsed[result] == lastJson, "dispatcher scanners collection handoff");
            PA_ClearVariable(&a); PA_DisposeCollection(result); balance("dispatcher scanners balance");
            PA_Unistring id = make(text(value).c_str());
            a = PA_CreateVariable(eVK_Undefined); result = nullptr;
            dispatch(3, {&id, &a}, &result);
            name = PA_GetStringInArray(a, 1);
            check(Text(name.fString, name.fLength) == text(value), "dispatcher options exact name");
            PA_ClearVariable(&a); PA_DisposeCollection(result); dispose(id);
            balance("dispatcher options balance");
            id = make(text(value).c_str());
            PA_Unistring option = make(text(value).c_str());
            PA_Unistring output = {}; PA_Unistring* out = &output;
            dispatch(5, {&id, &option}, &out);
            check(Text(output.fString, output.fLength) == text(value), "dispatcher scalar exact option");
            PA_Unistring set = make(text(value).c_str());
            dispatch(4, {&id, &option, &set});
            dispose(set); dispose(output); dispose(option); dispose(id);
            balance("dispatcher scalar balance");
            id = make(text(value).c_str()); starts = 0;
            sLONG_PTR format = 2; result = nullptr;
            dispatch(2, {&id, &format}, &result);
            check(elements[result].size() == 1 &&
                  pictures.count(elements[result][0].uValue.fPicture), "dispatcher scan picture handoff");
            PA_DisposeCollection(result); dispose(id); balance("dispatcher scan picture balance");
        }
        fixture = "ASCII";
        for (int selector : {1, 3}) {
            for (int mode : {0, 1}) {
                PA_Unistring id = make(text(fixture.c_str()).c_str());
                PA_Variable a = PA_CreateVariable(eVK_Undefined);
                property = PA_CreateVariable(eVK_Picture);
                commandMode = mode;
                failureCommand = mode == 0 ? 1218 : 0;
                PA_CollectionRef result = nullptr;
                invalidInspections = 0;
                if (selector == 1) dispatch(selector, {&a}, &result);
                else dispatch(selector, {&id, &a}, &result);
                commandMode = 0; failureCommand = 0;
                check(refs.count(result) && invalidInspections == 0,
                      "dispatcher JSON failure/mismatch safe fallback selector=" + std::to_string(selector));
                PA_DisposeCollection(result); PA_ClearVariable(&a); dispose(id);
                balance("dispatcher JSON failure/mismatch owner balance");
            }
        }
        for (int error = 0; error < 2; ++error) {
            PA_Unistring id = make(text(fixture.c_str()).c_str());
            starts = 0; sLONG_PTR format = 2; PA_CollectionRef result = nullptr;
            failPicture = error == 0; failElement = error == 1;
            dispatch(2, {&id, &format}, &result);
            failPicture = false; failElement = false;
            check(refs.count(result) && elements[result].empty(),
                  "dispatcher picture error safe fallback=" + std::to_string(error));
            PA_DisposeCollection(result); dispose(id); balance("dispatcher picture error owner balance");
        }
        dispatch(kCloseProcess, {});
        balance("dispatcher close process copied-name balance");
        std::cout << "checks=" << checks << " failures=" << failures << "\n";
        return failures ? 1 : 0;
    }
}
