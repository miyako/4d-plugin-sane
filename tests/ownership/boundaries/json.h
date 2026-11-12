#ifndef OWNERSHIP_JSON_H
#define OWNERSHIP_JSON_H
#include <map>
#include <string>
#include <vector>
#include <sstream>

// In-memory serialization boundary; no vendored binary or external input.
namespace Json {
enum ValueType { nullValue, intValue, uintValue, realValue, stringValue,
                 booleanValue, arrayValue, objectValue };
class Value {
    ValueType type = nullValue;
    std::string scalar;
    std::map<std::string, Value> fields;
    std::vector<Value> items;
    static std::string quote(const std::string& s) {
        std::string out = "\"";
        for (char c : s) {
            if (c == '"' || c == '\\') out += '\\';
            out += c;
        }
        return out + "\"";
    }
public:
    Value(ValueType t = nullValue) : type(t) {}
    Value(const char* s) : type(stringValue), scalar(s) {}
    Value(const std::string& s) : type(stringValue), scalar(s) {}
    Value(int n) : type(intValue), scalar(std::to_string(n)) {}
    Value(bool b) : type(booleanValue), scalar(b ? "true" : "false") {}
    Value& operator[](const char* key) { type = objectValue; return fields[key]; }
    void append(const Value& v) { type = arrayValue; items.push_back(v); }
    std::string dump() const {
        if (type == stringValue) return quote(scalar);
        if (type == nullValue) return "null";
        if (type != arrayValue && type != objectValue) return scalar;
        std::string out = type == arrayValue ? "[" : "{";
        bool first = true;
        if (type == arrayValue) for (const auto& v : items) {
            if (!first) out += ",";
            first = false; out += v.dump();
        }
        else for (const auto& v : fields) {
            if (!first) out += ",";
            first = false; out += quote(v.first) + ":" + v.second.dump();
        }
        return out + (type == arrayValue ? "]" : "}");
    }
};
using StreamWriterBuilder = Value;
inline std::string writeString(const StreamWriterBuilder&, const Value& value) {
    return value.dump();
}
}
#endif
