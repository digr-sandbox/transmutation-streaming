#include <stdlib.h>
#include <string.h>

typedef struct {
    int status_code;
    char* message;
} ApiResponse;

ApiResponse* create_response(int code, const char* msg) {
    ApiResponse* res = malloc(sizeof(ApiResponse));
    res->status_code = code;
    res->message = strdup(msg);
    return res;
}